//! A player's other devices: a code asked for on one of theirs, shown and
//! typed or read on another, brings that one into the realm as the same
//! player, their phone beside their Mac.

use super::{asking, Refusal};
use crate::rows::{Db, Link};
use crate::store::{Seconds, Table};

/// How long a code is good for, in seconds of the world's own clock: the
/// time to take a phone out and type it.
pub const LINK_SECONDS: Seconds = 600;

/// The letters a code is written in, five bits each: no 0, 1, I or O to
/// mistake for another.
const LETTERS: &[u8; 32] = b"23456789ABCDEFGHJKLMNPQRSTUVWXYZ";

/// How many letters a code is: fifty bits, past guessing in ten minutes.
pub const LINK_LETTERS: usize = 10;

/// A code's number as its letters.
pub fn link_letters(code: u64) -> String {
    (0..LINK_LETTERS).rev().map(|at| LETTERS[((code >> (5 * at)) & 31) as usize] as char).collect()
}

/// A code's number from its letters as typed: in either case, spaces and
/// dashes between them let be; none if they are not a code's.
pub fn link_code(typed: &str) -> Option<u64> {
    let mut code = 0u64;
    let mut count = 0;
    for letter in typed.chars().filter(|letter| !matches!(letter, ' ' | '-')) {
        let at = LETTERS.iter().position(|known| *known as char == letter.to_ascii_uppercase())?;
        count += 1;
        if count > LINK_LETTERS {
            return None;
        }
        code = (code << 5) | at as u64;
    }
    (count == LINK_LETTERS).then_some(code)
}

/// A player asks for a code to bring another device of theirs in: one at
/// a time, a new one in place of any they had.
pub fn offer_link(db: &mut impl Db, player: u64) -> Result<Link, Refusal> {
    asking(db, player)?;
    for old in Table::<Link>::by(db, 0, player) {
        Table::<Link>::delete(db, old.code);
    }
    let mut code = db.chance() & ((1 << (5 * LINK_LETTERS)) - 1);
    while Table::<Link>::get(db, code).is_some() {
        code = db.chance() & ((1 << (5 * LINK_LETTERS)) - 1);
    }
    let link = Link { code, player, letters: link_letters(code), expires: db.now() + LINK_SECONDS };
    db.insert(link.clone());
    Ok(link)
}

/// A device with no player of its own takes a code another device showed:
/// the player whose it is, once, while it is good.
pub fn take_link(db: &mut impl Db, typed: &str) -> Result<u64, Refusal> {
    let code = link_code(typed).ok_or(Refusal::NoSuchLink)?;
    let link = Table::<Link>::get(db, code).ok_or(Refusal::NoSuchLink)?;
    if db.now() > link.expires {
        return Err(Refusal::LinkTooOld);
    }
    Table::<Link>::delete(db, code);
    Ok(link.player)
}

/// A player's codes go with them when they are forgotten.
pub(super) fn forget_links(db: &mut impl Db, player: u64) {
    for old in Table::<Link>::by(db, 0, player) {
        Table::<Link>::delete(db, old.code);
    }
}
