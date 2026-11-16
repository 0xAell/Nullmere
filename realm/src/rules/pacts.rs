//! Envoys and pacts between alliances.
//!
//! An officer of an alliance sends another an envoy with the terms of a
//! pact: a truce, or passage, for some days, two weeks at most. An officer
//! of the other answers it within a day, or it is gone. A truce holds the
//! two alliances' members from attacking one another, and from rallying
//! against one another's cities, wardstones or gates; armies already on
//! their way turn home when they come up. Passage lets each alliance's
//! armies through the other's gates of the ridge. A pact ends when its
//! days are done; an officer of either may break it, and it ends a day
//! after. Both alliances' members are told of every envoy and pact.

use super::{asking, member_of, officer, realm, report, Refusal};
use crate::catalog;
use crate::rows::{Alliance, Db, Envoy, Member, Pact, Report};
use crate::store::{Seconds, Table};

/// The pacts that hold now between two alliances.
fn pacts_between(db: &impl Db, a: u64, b: u64) -> Vec<Pact> {
    let now = db.now();
    Table::<Pact>::by(db, 0, a)
        .into_iter()
        .filter(|pact| pact.second == b)
        .chain(Table::<Pact>::by(db, 0, b).into_iter().filter(|pact| pact.second == a))
        .filter(|pact| pact.ends > now)
        .collect()
}

/// Whether a pact of some terms holds now between two alliances.
pub fn pact_holds(db: &impl Db, a: u64, b: u64, terms: u8) -> bool {
    a != 0 && b != 0 && a != b && pacts_between(db, a, b).iter().any(|pact| pact.terms == terms)
}

/// Whether two players' alliances are at truce.
pub fn at_truce(db: &impl Db, a: u64, b: u64) -> bool {
    match (member_of(db, a), member_of(db, b)) {
        (Some(one), Some(other)) => pact_holds(db, one.alliance, other.alliance, Pact::TRUCE),
        _ => false,
    }
}

/// The alliances whose gates an alliance's armies may pass by a pact.
pub fn passage_for(db: &impl Db, alliance: u64) -> Vec<u64> {
    let now = db.now();
    let mut with: Vec<u64> = Table::<Pact>::by(db, 0, alliance)
        .into_iter()
        .filter(|pact| pact.terms == Pact::PASSAGE && pact.ends > now)
        .map(|pact| pact.second)
        .chain(Table::<Pact>::by(db, 1, alliance).into_iter().filter(|pact| pact.terms == Pact::PASSAGE && pact.ends > now).map(|pact| pact.first))
        .collect();
    with.sort();
    with.dedup();
    with
}

fn name_of(db: &impl Db, alliance: u64) -> String {
    Table::<Alliance>::get(db, alliance).map(|alliance| format!("[{}] {}", alliance.tag, alliance.name)).unwrap_or_else(|| "An alliance".into())
}

fn terms_words(terms: u8, days: u32) -> String {
    let span = if days == 1 { "a day".to_string() } else { format!("{days} days") };
    match terms {
        Pact::TRUCE => format!("a truce of {span}"),
        _ => format!("passage through one another's gates for {span}"),
    }
}

/// Tells every member of an alliance something of a pact with another.
fn tell(db: &mut impl Db, alliance: u64, other: u64, words: &str) {
    let now = db.now();
    for member in Table::<Member>::by(db, 0, alliance) {
        report(
            db,
            Report {
                id: 0,
                player: member.player,
                at: now,
                kind: Report::PACT,
                hex: 0,
                won: false,
                foe: other,
                rounds: 0,
                fought: 0,
                wounded: 0,
                dead: 0,
                stood: 0,
                fell: 0,
                grain: 0,
                timber: 0,
                stone: 0,
                moonsalt: 0,
                words: words.to_string(),
                read: false,
            },
        );
    }
}

/// Whether an envoy is still waiting on its answer.
fn waiting(db: &impl Db, envoy: &Envoy) -> bool {
    let pace = realm(db).map(|realm| realm.pace).unwrap_or(1);
    db.now() < envoy.sent_at + catalog::paced(catalog::ENVOY_WAITS, pace)
}

/// An officer sends another alliance an envoy with the terms of a pact.
pub fn send_envoy(db: &mut impl Db, player: u64, to: u64, terms: u8, days: u32) -> Result<Envoy, Refusal> {
    asking(db, player)?;
    let member = officer(db, player)?;
    if to == member.alliance {
        return Err(Refusal::OwnAlliance);
    }
    Table::<Alliance>::get(db, to).ok_or(Refusal::NoSuchAlliance)?;
    if !matches!(terms, Pact::TRUCE | Pact::PASSAGE) || !(1..=catalog::PACT_MOST_DAYS).contains(&days) {
        return Err(Refusal::NoSuchTerms(catalog::PACT_MOST_DAYS));
    }
    if pact_holds(db, member.alliance, to, terms) {
        return Err(Refusal::PactHolds);
    }
    let sent = Table::<Envoy>::by(db, 0, member.alliance).into_iter().any(|envoy| envoy.receiver == to && envoy.terms == terms && waiting(db, &envoy));
    if sent {
        return Err(Refusal::EnvoySent);
    }
    let name = name_of(db, member.alliance);
    let envoy = db.insert(Envoy { id: 0, sender: member.alliance, receiver: to, name: name.clone(), terms, days, sent_at: db.now() });
    let words = format!("An envoy of {name} has come offering {}. Your alliance's officers may accept it or turn it away within a day.", terms_words(terms, days));
    tell(db, to, member.alliance, &words);
    let words = format!("Your alliance's envoy has gone to {} offering {}.", name_of(db, to), terms_words(terms, days));
    tell(db, member.alliance, to, &words);
    Ok(envoy)
}

/// An officer of the alliance an envoy came to accepts its terms, and the
/// pact holds from now; or turns it away.
pub fn answer_envoy(db: &mut impl Db, player: u64, envoy: u64, accept: bool) -> Result<Option<Pact>, Refusal> {
    asking(db, player)?;
    let member = officer(db, player)?;
    let envoy = Table::<Envoy>::get(db, envoy).filter(|envoy| envoy.receiver == member.alliance).ok_or(Refusal::NoSuchEnvoy)?;
    Table::<Envoy>::delete(db, envoy.id);
    if !waiting(db, &envoy) || Table::<Alliance>::get(db, envoy.sender).is_none() {
        return Err(Refusal::NoSuchEnvoy);
    }
    let (ours, theirs) = (name_of(db, member.alliance), name_of(db, envoy.sender));
    if !accept {
        tell(db, envoy.sender, member.alliance, &format!("{ours} turned away your alliance's envoy and its offer of {}.", terms_words(envoy.terms, envoy.days)));
        return Ok(None);
    }
    let pace = realm(db)?.pace;
    let now = db.now();
    let ends: Seconds = now + catalog::paced(catalog::DAY * envoy.days as i64, pace);
    let pact = db.insert(Pact { id: 0, first: envoy.sender, second: member.alliance, terms: envoy.terms, began: now, ends });
    let made = terms_words(envoy.terms, envoy.days);
    tell(db, envoy.sender, member.alliance, &format!("{ours} accepted your alliance's envoy: {made} holds from now."));
    tell(db, member.alliance, envoy.sender, &format!("Your alliance accepted the envoy of {theirs}: {made} holds from now."));
    Ok(Some(pact))
}

/// An officer of either alliance breaks a pact: it holds a day more, and
/// then it is done.
pub fn break_pact(db: &mut impl Db, player: u64, pact: u64) -> Result<Pact, Refusal> {
    asking(db, player)?;
    let member = officer(db, player)?;
    let now = db.now();
    let mut pact = Table::<Pact>::get(db, pact).filter(|pact| (pact.first == member.alliance || pact.second == member.alliance) && pact.ends > now).ok_or(Refusal::NoSuchPact)?;
    let pace = realm(db)?.pace;
    let notice = now + catalog::paced(catalog::PACT_NOTICE, pace);
    if pact.ends > notice {
        pact.ends = notice;
        db.update(pact.clone());
    }
    let other = if pact.first == member.alliance { pact.second } else { pact.first };
    let ours = name_of(db, member.alliance);
    tell(db, other, member.alliance, &format!("{ours} has broken its pact with your alliance. It holds until a day from now."));
    tell(db, member.alliance, other, &format!("Your alliance has broken its pact with {}. It holds until a day from now.", name_of(db, other)));
    Ok(pact)
}

/// An alliance has ended: its envoys are gone, and its pacts with them.
pub(super) fn pacts_end(db: &mut impl Db, alliance: u64) {
    for envoy in Table::<Envoy>::by(db, 0, alliance).into_iter().chain(Table::<Envoy>::by(db, 1, alliance)) {
        Table::<Envoy>::delete(db, envoy.id);
    }
    for pact in Table::<Pact>::by(db, 0, alliance).into_iter().chain(Table::<Pact>::by(db, 1, alliance)) {
        Table::<Pact>::delete(db, pact.id);
    }
}
