//! Letters: one player writes to another, or an officer to their whole
//! alliance.
//!
//! A letter holds a thousand characters at most, lines and all, and
//! nothing unprintable; one may be written every two seconds, apart from
//! what is said. Each player keeps their last hundred letters received. Only
//! the one a letter is to marks it read or forgets it. None reaches one who
//! has shut its writer out (`shun`).

use super::{asking, officer, shown_name, shuts_out, Refusal};
use crate::catalog;
use crate::rows::{Db, Letter, Member, Pace, Player};
use crate::store::Table;

/// A letter's words, as they are kept: trimmed, not empty, not too long,
/// nothing unprintable but the ends of lines.
fn letter_words(words: &str) -> Result<String, Refusal> {
    let words = words.trim().to_string();
    if words.is_empty() {
        return Err(Refusal::NothingSaid);
    }
    if words.chars().count() > catalog::LETTER_LONGEST || words.chars().any(|c| super::unseen(c) && c != '\n') || super::piled(&words) {
        return Err(Refusal::LetterTooLong(catalog::LETTER_LONGEST));
    }
    Ok(words)
}

/// Holds a writer to one letter every two seconds, apart from what they say.
fn paced(db: &mut impl Db, player: u64) -> Result<(), Refusal> {
    let now = db.now();
    let mut pace = Table::<Pace>::get(db, player).ok_or(Refusal::NotAPlayer)?;
    if now - pace.wrote < catalog::SAID_EVERY {
        return Err(Refusal::SayingTooFast);
    }
    pace.wrote = now;
    db.update(pace);
    Ok(())
}

/// Delivers a letter, letting go the receiver's oldest beyond the hundred kept.
fn deliver(db: &mut impl Db, sender: u64, receiver: u64, name: &str, words: &str) -> Letter {
    let at = db.now();
    let letter = db.insert(Letter { id: 0, sender, receiver, name: name.to_string(), words: words.to_string(), at, read: false });
    let mut kept = Table::<Letter>::by(db, 1, receiver);
    kept.sort_by_key(|letter| letter.id);
    for old in kept.iter().take(kept.len().saturating_sub(catalog::LETTERS_KEPT)) {
        Table::<Letter>::delete(db, old.id);
    }
    letter
}

/// A player writes a letter to another.
pub fn send_letter(db: &mut impl Db, player: u64, to: u64, words: &str) -> Result<Letter, Refusal> {
    let writer = asking(db, player)?;
    let words = letter_words(words)?;
    if to == player {
        return Err(Refusal::OwnLetter);
    }
    Table::<Player>::get(db, to).ok_or(Refusal::NoSuchPlayer)?;
    if shuts_out(db, to, player) {
        return Err(Refusal::LettersShutOut);
    }
    paced(db, player)?;
    let name = shown_name(db, &writer);
    Ok(deliver(db, player, to, &name, &words))
}

/// An officer writes one letter to every other member of their alliance
/// but those who have shut them out. How many it went to.
pub fn send_alliance_letter(db: &mut impl Db, player: u64, words: &str) -> Result<usize, Refusal> {
    let writer = asking(db, player)?;
    let member = officer(db, player)?;
    let words = letter_words(words)?;
    paced(db, player)?;
    let name = shown_name(db, &writer);
    let to: Vec<u64> = Table::<Member>::by(db, 0, member.alliance).into_iter().map(|member| member.player).filter(|other| *other != player).collect();
    let to: Vec<u64> = to.into_iter().filter(|other| !shuts_out(db, *other, player)).collect();
    for receiver in &to {
        deliver(db, player, *receiver, &name, &words);
    }
    Ok(to.len())
}

/// The one a letter is to marks it read.
pub fn read_letter(db: &mut impl Db, player: u64, letter: u64) -> Result<(), Refusal> {
    asking(db, player)?;
    let mut letter = Table::<Letter>::get(db, letter).filter(|letter| letter.receiver == player).ok_or(Refusal::NoSuchLetter)?;
    if !letter.read {
        letter.read = true;
        db.update(letter);
    }
    Ok(())
}

/// The one a letter is to forgets it.
pub fn forget_letter(db: &mut impl Db, player: u64, letter: u64) -> Result<(), Refusal> {
    asking(db, player)?;
    let letter = Table::<Letter>::get(db, letter).filter(|letter| letter.receiver == player).ok_or(Refusal::NoSuchLetter)?;
    Table::<Letter>::delete(db, letter.id);
    Ok(())
}
