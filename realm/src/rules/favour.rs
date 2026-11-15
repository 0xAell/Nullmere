//! Favour: what a player earns by doing the day's work, day after day.
//! Each of the day's chests adds to it as it is opened. It rises through
//! ten levels, and at each every work the player sets going (a building
//! raised, soldiers trained, a study) is done a hundredth sooner.

use crate::catalog::{self, TOP_FAVOUR};
use crate::rows::{Db, Favour, Grace};
use crate::store::Table;

/// Writes the levels of favour out as rows, for clients to show, as the
/// realm opens.
pub fn write_graces(db: &mut impl Db) {
    for level in 0..=TOP_FAVOUR {
        db.insert(Grace { level: level as u64, points: catalog::favour_needs(level), sooner: level });
    }
}

/// The favour a player has: none, until they have earned some.
pub fn favour_of(db: &impl Db, player: u64) -> Favour {
    Table::<Favour>::get(db, player).unwrap_or(Favour { player, points: 0, level: 0 })
}

/// How long a work a player sets going takes, given how long it would
/// take one without favour: a hundredth less for each level, and never
/// less than a second.
pub(super) fn favoured(db: &impl Db, player: u64, seconds: i64) -> i64 {
    let level = favour_of(db, player).level.min(TOP_FAVOUR) as i64;
    (seconds * (100 - level) / 100).max(1.min(seconds))
}

/// A player earns favour, and rises a level where it has come to enough.
pub(super) fn earn_favour(db: &mut impl Db, player: u64, points: u64) {
    if points == 0 {
        return;
    }
    let mut row = favour_of(db, player);
    row.points = row.points.saturating_add(points);
    row.level = catalog::favour_level(row.points);
    if Table::<Favour>::get(db, player).is_some() {
        db.update(row);
    } else {
        db.insert(row);
    }
}
