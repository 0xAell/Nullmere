//! Marks on the map: an alliance's officers mark places for its members.
//!
//! An officer sets a mark at any hex of the realm with a few words, forty
//! characters at most, nothing unprintable: where to gather, what to take.
//! A mark set where the alliance has one already says the new words
//! instead. An alliance keeps ten marks at most; its officers clear them,
//! and when it ends they are gone. Only its members read them.

use super::{asking, officer, realm, Refusal};
use crate::hex::Hex;
use crate::rows::{Db, Mark};
use crate::store::Table;

/// How many marks an alliance keeps at once.
pub const MOST_MARKS: usize = 10;
/// The most characters a mark says.
pub const MARK_LONGEST: usize = 40;

/// An officer sets a mark of their alliance at a hex. The mark.
pub fn set_mark(db: &mut impl Db, player: u64, at: Hex, words: &str) -> Result<Mark, Refusal> {
    asking(db, player)?;
    let member = officer(db, player)?;
    let words = words.trim();
    if words.is_empty() {
        return Err(Refusal::NothingSaid);
    }
    if words.chars().count() > MARK_LONGEST || words.chars().any(char::is_control) {
        return Err(Refusal::MarkTooLong(MARK_LONGEST));
    }
    if at.length() > realm(db)?.radius {
        return Err(Refusal::BeyondTheRealm);
    }
    let now = db.now();
    let marks = Table::<Mark>::by(db, 0, member.alliance);
    if let Some(mut mark) = marks.iter().find(|mark| mark.hex == at.packed()).cloned() {
        mark.words = words.to_string();
        mark.setter = player;
        mark.at = now;
        db.update(mark.clone());
        return Ok(mark);
    }
    if marks.len() >= MOST_MARKS {
        return Err(Refusal::MarksAll(MOST_MARKS));
    }
    Ok(db.insert(Mark { id: 0, alliance: member.alliance, hex: at.packed(), words: words.to_string(), setter: player, at: now }))
}

/// An officer clears a mark of their alliance.
pub fn clear_mark(db: &mut impl Db, player: u64, mark: u64) -> Result<(), Refusal> {
    asking(db, player)?;
    let member = officer(db, player)?;
    Table::<Mark>::get(db, mark).filter(|mark| mark.alliance == member.alliance).ok_or(Refusal::NoSuchMark)?;
    Table::<Mark>::delete(db, mark);
    Ok(())
}

/// Every mark of an alliance cleared, as it ends.
pub(super) fn clear_marks(db: &mut impl Db, alliance: u64) {
    for mark in Table::<Mark>::by(db, 0, alliance) {
        Table::<Mark>::delete(db, mark.id);
    }
}
