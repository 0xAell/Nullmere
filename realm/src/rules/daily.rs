//! The day's work: five deeds, the same for every player, begun afresh
//! each day of the realm. A deed done earns marks, and marks open the
//! day's three chests.

use super::{asking, city_of, earn_favour, give, goods, realm, set_goods, settle, Refusal};
use crate::catalog::{self, Deed, Goods, Item};
use crate::rows::{Chest, Daily, Db, Duty};
use crate::store::Table;

/// Writes the deeds and the chests out as rows, for clients to show, as
/// the realm opens.
pub fn write_days(db: &mut impl Db) {
    for deed in Deed::ALL {
        db.insert(Duty { deed: deed as u64, asks: deed.asks(), marks: deed.marks(), words: deed.words() });
    }
    for (index, (marks, holds)) in catalog::chests().into_iter().enumerate() {
        let items = catalog::chest_items(index as u8 + 1);
        let count = |item: Item| items.iter().filter(|(held, _)| *held == item).map(|(_, count)| count).sum();
        db.insert(Chest {
            id: index as u64 + 1,
            marks,
            grain: holds.grain,
            timber: holds.timber,
            stone: holds.stone,
            moonsalt: holds.moonsalt,
            brief_hastes: count(Item::Haste5),
            hour_hastes: count(Item::Haste60),
            long_hastes: count(Item::Haste480),
            peaces: count(Item::Peace8),
        });
    }
}

/// Which day of the realm it is, counted from its opening. A day is as
/// long as the realm's pace makes it.
pub fn today(db: &impl Db) -> u64 {
    let Ok(realm) = realm(db) else { return 0 };
    let long = catalog::paced(catalog::DAY, realm.pace).max(1);
    ((db.now() - realm.opened).max(0) / long) as u64
}

/// What a player has done today: nothing, if what is kept is of an
/// earlier day.
pub fn daily_of(db: &impl Db, player: u64) -> Daily {
    let day = today(db);
    Table::<Daily>::get(db, player).filter(|row| row.day == day).unwrap_or(Daily { player, day, trained: 0, gathered: 0, cleared: 0, begun: 0, hastened: 0, opened: 0 })
}

/// How much of a deed a day's row counts.
fn done(row: &Daily, deed: Deed) -> u64 {
    match deed {
        Deed::Train => row.trained,
        Deed::Gather => row.gathered,
        Deed::Clear => row.cleared,
        Deed::Begin => row.begun,
        Deed::Hasten => row.hastened,
    }
}

/// The marks a day's row has earned: those of each deed done in full.
pub fn marks(row: &Daily) -> u32 {
    Deed::ALL.into_iter().filter(|deed| done(row, *deed) >= deed.asks()).map(Deed::marks).sum()
}

/// A player has done something toward a deed: it is counted to today.
pub(super) fn did(db: &mut impl Db, player: u64, deed: Deed, amount: u64) {
    let mut row = daily_of(db, player);
    let count = match deed {
        Deed::Train => &mut row.trained,
        Deed::Gather => &mut row.gathered,
        Deed::Clear => &mut row.cleared,
        Deed::Begin => &mut row.begun,
        Deed::Hasten => &mut row.hastened,
    };
    *count = count.saturating_add(amount);
    if Table::<Daily>::get(db, player).is_some() {
        db.update(row);
    } else {
        db.insert(row);
    }
}

/// A player opens one of the day's chests: if they have earned the marks
/// it asks and have not opened it today, what it holds goes into their
/// stock, though it overfill it, its hastes into their satchel, and they
/// rise in favour.
pub fn open_chest(db: &mut impl Db, player: u64, chest: u8) -> Result<Goods, Refusal> {
    asking(db, player)?;
    let city = city_of(db, player)?;
    let all = catalog::chests();
    let (asks, holds) = *all.get((chest as usize).wrapping_sub(1)).ok_or(Refusal::NoSuchChest)?;
    let mut row = daily_of(db, player);
    let bit = 1u8 << (chest - 1);
    if row.opened & bit != 0 {
        return Err(Refusal::ChestOpened);
    }
    if marks(&row) < asks {
        return Err(Refusal::ChestNotEarned(asks));
    }
    let mut stock = settle(db, city.id)?;
    let more = goods(&stock).plus(holds);
    set_goods(&mut stock, more);
    db.update(stock);
    row.opened |= bit;
    if Table::<Daily>::get(db, player).is_some() {
        db.update(row);
    } else {
        db.insert(row);
    }
    for (item, count) in catalog::chest_items(chest) {
        give(db, player, item, count);
    }
    earn_favour(db, player, catalog::chest_favour(chest));
    Ok(holds)
}
