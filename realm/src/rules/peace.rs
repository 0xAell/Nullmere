//! Keeping the peace in the realm's chat and on its roll.
//!
//! A player reports a line said in the realm's chat, or in their own
//! alliance's: the report keeps the line, who said it and the lines said
//! about it, for the realm's owner to read (complaints are private; the
//! database's owner reads them by SQL). The owner takes a line away (it
//! stands where it was, its words gone), bars a player from speaking for
//! so many hours, lets a report go, and forgets a player who asks it:
//! their name leaves the realm's roll, its chat, its letters and what the
//! alliance holds of them, their city is kept under the name they are
//! given, and their identity is let go (the module's part), so whoever
//! comes back with it joins anew.

use super::{asking, member_of, Refusal};
use crate::rows::{AllianceChat, Applicant, Bar, City, Complaint, Db, Letter, Petition, Player, Plea, Rally, RealmChat};
use crate::store::{Seconds, Table};

/// The lines kept with a report from before the line reported, and as
/// many from after.
pub const SAID_AROUND: usize = 3;
/// The most reports a player may have waiting on the owner at once.
pub const REPORTS_OPEN: usize = 20;
/// The longest a player is barred from speaking at once.
pub const LONGEST_BAR_HOURS: u64 = 24 * 365;

/// A line of chat as a report keeps it: who said it, and what.
fn as_kept(name: &str, words: &str) -> String {
    if words.is_empty() {
        format!("{name}: (taken away)")
    } else {
        format!("{name}: {words}")
    }
}

/// A player reports a line said in the realm's chat, or within their
/// alliance: kept for the realm's owner with the lines about it.
pub fn report_line(db: &mut impl Db, player: u64, line: u64, within_alliance: bool) -> Result<Complaint, Refusal> {
    asking(db, player)?;
    // The line, its speaker, its moment and the alliance it was said in,
    // and the lines said about it, the one reported marked.
    let (speaker, words, said, alliance, around) = if within_alliance {
        let member = member_of(db, player).ok_or(Refusal::NotAllied)?;
        let found = Table::<AllianceChat>::get(db, line).filter(|said| said.alliance == member.alliance).ok_or(Refusal::NoSuchLine)?;
        let mut all = Table::<AllianceChat>::by(db, 0, member.alliance);
        all.sort_by_key(|said| said.id);
        let at = all.iter().position(|said| said.id == line).unwrap_or(0);
        let around: Vec<String> = all[at.saturating_sub(SAID_AROUND)..(at + SAID_AROUND + 1).min(all.len())]
            .iter()
            .map(|said| (if said.id == line { "> " } else { "  " }).to_string() + &as_kept(&said.name, &said.words))
            .collect();
        (found.player, found.words, found.at, member.alliance, around.join("\n"))
    } else {
        let found = Table::<RealmChat>::get(db, line).ok_or(Refusal::NoSuchLine)?;
        let first = line.saturating_sub(SAID_AROUND as u64).max(1);
        let around: Vec<String> = (first..=line + SAID_AROUND as u64)
            .filter_map(|id| Table::<RealmChat>::get(db, id))
            .map(|said| (if said.id == line { "> " } else { "  " }).to_string() + &as_kept(&said.name, &said.words))
            .collect();
        (found.player, found.words, found.at, 0, around.join("\n"))
    };
    if words.is_empty() {
        return Err(Refusal::TakenAwayAlready);
    }
    if speaker == player {
        return Err(Refusal::OwnWords);
    }
    let open = Table::<Complaint>::by(db, 0, player);
    if open.iter().any(|complaint| complaint.line == line && complaint.alliance == alliance) {
        return Err(Refusal::ReportedAlready);
    }
    if open.len() >= REPORTS_OPEN {
        return Err(Refusal::TooManyReports(REPORTS_OPEN as u64));
    }
    let reported = db.now();
    Ok(db.insert(Complaint { id: 0, reporter: player, line, alliance, speaker, words, said, reported, around }))
}

/// The realm's owner takes a line away: it stands where it was, its words
/// gone, and every report of it is let go.
pub fn take_away(db: &mut impl Db, line: u64, within_alliance: bool) -> Result<(), Refusal> {
    let alliance = if within_alliance {
        let mut said = Table::<AllianceChat>::get(db, line).ok_or(Refusal::NoSuchLine)?;
        if said.words.is_empty() {
            return Err(Refusal::TakenAwayAlready);
        }
        said.words.clear();
        let alliance = said.alliance;
        db.update(said);
        alliance
    } else {
        let mut said = Table::<RealmChat>::get(db, line).ok_or(Refusal::NoSuchLine)?;
        if said.words.is_empty() {
            return Err(Refusal::TakenAwayAlready);
        }
        said.words.clear();
        db.update(said);
        0
    };
    for complaint in Table::<Complaint>::all(db) {
        if complaint.line == line && complaint.alliance == alliance {
            Table::<Complaint>::delete(db, complaint.id);
        }
    }
    Ok(())
}

/// The realm's owner bars a player from speaking for so many hours, from
/// now; no hours lifts a bar. Until when they are barred.
pub fn bar(db: &mut impl Db, player: u64, hours: u64) -> Result<Seconds, Refusal> {
    Table::<Player>::get(db, player).ok_or(Refusal::NoSuchPlayer)?;
    if hours > LONGEST_BAR_HOURS {
        return Err(Refusal::BarTooLong(LONGEST_BAR_HOURS));
    }
    let now = db.now();
    let had = Table::<Bar>::get(db, player).is_some();
    if hours == 0 {
        if had {
            Table::<Bar>::delete(db, player);
        }
        return Ok(now);
    }
    let until = now + hours as Seconds * 3_600;
    if had {
        db.update(Bar { player, until });
    } else {
        db.insert(Bar { player, until });
    }
    Ok(until)
}

/// How long a player is still barred from speaking, if they are.
pub fn barred_for(db: &impl Db, player: u64) -> Option<Seconds> {
    let left = Table::<Bar>::get(db, player)?.until - db.now();
    (left > 0).then_some(left)
}

/// The realm's owner lets a report go.
pub fn dismiss(db: &mut impl Db, complaint: u64) -> Result<(), Refusal> {
    Table::<Complaint>::get(db, complaint).ok_or(Refusal::NoSuchComplaint)?;
    Table::<Complaint>::delete(db, complaint);
    Ok(())
}

/// The name a forgotten player is given: one no player may join under.
pub fn forgotten_name(player: u64) -> String {
    format!("Forgotten #{player}")
}

/// The realm's owner forgets a player who asks it: their name leaves the
/// roll, the chat, the letters they wrote and what alliances hold of
/// them, and their city is kept under the name they are given. The name.
/// Words others wrote of them are theirs, and stay.
pub fn forget(db: &mut impl Db, player: u64) -> Result<String, Refusal> {
    let mut row = Table::<Player>::get(db, player).ok_or(Refusal::NoSuchPlayer)?;
    let name = forgotten_name(player);
    if row.name == name {
        return Err(Refusal::ForgottenAlready);
    }
    let old = std::mem::replace(&mut row.name, name.clone());
    row.name_key = super::name_key(&name);
    super::forget_links(db, player);
    super::let_all_in(db, player);
    // Their identity is let go, so nothing will tell the realm they left.
    row.online = false;
    db.update(row);
    for mut city in Table::<City>::by(db, 0, player) {
        city.name = name.clone();
        db.update(city);
    }
    for mut said in Table::<RealmChat>::all(db).into_iter().filter(|said| said.player == player) {
        said.name = name.clone();
        db.update(said);
    }
    for mut said in Table::<AllianceChat>::all(db).into_iter().filter(|said| said.player == player) {
        said.name = name.clone();
        db.update(said);
    }
    for mut letter in Table::<Letter>::by(db, 0, player) {
        letter.name = name.clone();
        db.update(letter);
    }
    if let Some(mut applicant) = Table::<Applicant>::get(db, player) {
        applicant.name = name.clone();
        db.update(applicant);
    }
    for mut plea in Table::<Plea>::all(db).into_iter().filter(|plea| plea.asker == player) {
        plea.name = name.clone();
        db.update(plea);
    }
    for mut rally in Table::<Rally>::all(db).into_iter().filter(|rally| rally.caller == player) {
        rally.name = name.clone();
        db.update(rally);
    }
    if let Some(mut petition) = Table::<Petition>::get(db, player) {
        petition.name = name.clone();
        db.update(petition);
    }
    // Their reports go with them, and reports of their words name them
    // as they are named now.
    for complaint in Table::<Complaint>::by(db, 0, player) {
        Table::<Complaint>::delete(db, complaint.id);
    }
    for mut complaint in Table::<Complaint>::all(db) {
        let around = renamed(&complaint.around, &old, &name);
        if around != complaint.around {
            complaint.around = around;
            db.update(complaint);
        }
    }
    Ok(name)
}

/// A player leaves the realm for good, their own name typed to be sure
/// they mean it: out of their alliance, which its leader may leave only
/// as its last member, their asking to join one let go, and forgotten as
/// the realm's owner forgets a player who asks it. Their city stays where
/// it stands, under the name they are given. The name. Their devices are
/// let go by the module, which alone knows them.
pub fn leave_realm(db: &mut impl Db, player: u64, typed: &str) -> Result<String, Refusal> {
    let row = super::asking(db, player)?;
    let typed = super::tidy(typed);
    if super::name_key(&typed) != row.name_key || typed.to_lowercase() != row.name.to_lowercase() {
        return Err(Refusal::NotYourName);
    }
    if let Some(member) = super::member_of(db, player) {
        super::quit(db, &member)?;
    }
    if Table::<Applicant>::get(db, player).is_some() {
        Table::<Applicant>::delete(db, player);
    }
    forget(db, player)
}

/// The lines a report keeps, with every line a speaker of one name said
/// put under another: the name after its mark and its alliance's tag, if
/// it had one, never within the words.
fn renamed(around: &str, old: &str, name: &str) -> String {
    let lines: Vec<String> = around
        .lines()
        .map(|line| {
            let (mark, said) = (line.get(..2).unwrap_or(""), line.get(2..).unwrap_or(""));
            let (tag, rest) = match said.strip_prefix('[').and_then(|rest| rest.split_once("] ")) {
                Some((tag, rest)) => (format!("[{tag}] "), rest),
                None => (String::new(), said),
            };
            match rest.strip_prefix(old).and_then(|words| words.strip_prefix(": ")) {
                Some(words) => format!("{mark}{tag}{name}: {words}"),
                None => line.to_string(),
            }
        })
        .collect();
    lines.join("\n")
}
