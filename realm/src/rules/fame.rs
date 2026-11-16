//! Fame: what each player has struck down of other players' soldiers in
//! battles between cities, and lost of their own; the realm's rankings.

use crate::catalog;
use crate::rows::{Db, Fame};
use crate::store::Table;

/// A player's fame; none yet where they have fought no city.
pub fn fame_of(db: &impl Db, player: u64) -> Fame {
    Table::<Fame>::get(db, player).unwrap_or(Fame { player, kills: 0, felled: 0, dead: 0 })
}

/// Kill points for soldiers struck down, wounded or slain: so many of each
/// tier, each worth what its tier is.
pub fn kill_points(struck: impl IntoIterator<Item = (u32, u64)>) -> u64 {
    struck.into_iter().map(|(tier, count)| count * catalog::kill_points(tier)).sum()
}

/// Adds to a player's fame: kill points, soldiers struck down, and their
/// own soldiers dead.
pub(super) fn add_fame(db: &mut impl Db, player: u64, kills: u64, felled: u64, dead: u64) {
    if kills + felled + dead == 0 {
        return;
    }
    let kept = Table::<Fame>::get(db, player);
    let mut fame = kept.clone().unwrap_or(Fame { player, kills: 0, felled: 0, dead: 0 });
    fame.kills += kills;
    fame.felled += felled;
    fame.dead += dead;
    if kept.is_some() {
        db.update(fame);
    } else {
        db.insert(fame);
    }
}
