//! Shutting a player out.
//!
//! A player shuts out another, a hundred at most: the letters of the one
//! shut out are no longer taken, they are told so when they write one, and
//! an officer's letter to the whole alliance passes them by; the client of
//! the one who shut them out leaves their sayings in the realm's chat and
//! the alliance's unshown. Nothing else is changed between them: an ally
//! stays an ally. They are let back in whenever their keeper likes, and
//! one who asks to be forgotten keeps no one shut out.

use super::{asking, Refusal};
use crate::rows::{Db, Player, Shun};
use crate::store::Table;

/// How many players one may shut out at once.
pub const MOST_SHUT_OUT: usize = 100;

/// Whether a player has shut out another.
pub fn shuts_out(db: &impl Db, player: u64, other: u64) -> bool {
    Table::<Shun>::get(db, Shun::key(player, other)).is_some()
}

/// A player shuts out another.
pub fn shut_out(db: &mut impl Db, player: u64, other: u64) -> Result<Shun, Refusal> {
    asking(db, player)?;
    if other == player {
        return Err(Refusal::OwnShun);
    }
    Table::<Player>::get(db, other).ok_or(Refusal::NoSuchPlayer)?;
    if shuts_out(db, player, other) {
        return Err(Refusal::ShutOutAlready);
    }
    if Table::<Shun>::by(db, 0, player).len() >= MOST_SHUT_OUT {
        return Err(Refusal::TooManyShutOut(MOST_SHUT_OUT));
    }
    let at = db.now();
    Ok(db.insert(Shun { key: Shun::key(player, other), player, shunned: other, at }))
}

/// A player lets back in one they shut out.
pub fn let_in(db: &mut impl Db, player: u64, other: u64) -> Result<(), Refusal> {
    asking(db, player)?;
    if !shuts_out(db, player, other) {
        return Err(Refusal::NotShutOut);
    }
    Table::<Shun>::delete(db, Shun::key(player, other));
    Ok(())
}

/// Everyone a player has shut out, let back in: as they are forgotten.
pub(super) fn let_all_in(db: &mut impl Db, player: u64) {
    for shun in Table::<Shun>::by(db, 0, player) {
        Table::<Shun>::delete(db, shun.key);
    }
}
