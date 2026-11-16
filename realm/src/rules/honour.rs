//! Honour within an alliance, and the alliance's stores.
//!
//! A member earns honour by helping allies with their works, twenty a
//! help, up to a thousand of it from helping in a day of the realm; and
//! by giving goods toward what the alliance learns, one for every
//! thousand taken. Honour is the member's own and stays with them through
//! any alliance they are in. It buys hastes, peace and tomes from the stores
//! of whatever alliance they are in now, at prices the realm writes out
//! for clients to show.

use super::{asking, give, member_of, today, Refusal};
use crate::catalog::Item;
use crate::rows::{Db, Honour, Price};
use crate::store::Table;

/// Honour for each help given.
pub const HONOUR_A_HELP: u64 = 20;
/// The most honour earned from helping in one day of the realm.
pub const HONOUR_FROM_HELP_A_DAY: u64 = 1_000;
/// Goods given toward the alliance's learning for each honour.
pub const GOODS_AN_HONOUR: u64 = 1_000;
/// The most of one thing bought at once.
pub const MOST_BOUGHT: u64 = 100;

/// What the stores sell, and for how much honour each.
pub const PRICES: [(Item, u64); 6] =
    [(Item::Haste5, 100), (Item::Haste60, 1_000), (Item::Haste480, 6_000), (Item::Peace8, 5_000), (Item::Tome, 250), (Item::GreatTome, 2_000)];

/// Writes the stores' prices out as rows, for clients to show, as the
/// realm opens.
pub fn write_prices(db: &mut impl Db) {
    for (item, honour) in PRICES {
        db.insert(Price { item: item as u64, honour });
    }
}

/// A player's honour, and what of it they have earned from helping
/// today: none of that, if what is kept is of an earlier day.
pub fn honour_of(db: &impl Db, player: u64) -> Honour {
    let day = today(db);
    let mut row = Table::<Honour>::get(db, player).unwrap_or(Honour { player, honour: 0, day, from_help: 0 });
    if row.day != day {
        (row.day, row.from_help) = (day, 0);
    }
    row
}

fn keep(db: &mut impl Db, row: Honour) {
    if Table::<Honour>::get(db, row.player).is_some() {
        db.update(row);
    } else {
        db.insert(row);
    }
}

/// A player helped an ally with a work: honour for it, while today's
/// honour from helping lasts.
pub(super) fn honoured_for_help(db: &mut impl Db, player: u64) {
    let mut row = honour_of(db, player);
    let earned = HONOUR_A_HELP.min(HONOUR_FROM_HELP_A_DAY.saturating_sub(row.from_help));
    if earned == 0 {
        return;
    }
    row.honour += earned;
    row.from_help += earned;
    keep(db, row);
}

/// A player gave goods toward what their alliance learns: an honour for
/// every thousand taken.
pub(super) fn honoured_for_giving(db: &mut impl Db, player: u64, taken: u64) {
    let earned = taken / GOODS_AN_HONOUR;
    if earned == 0 {
        return;
    }
    let mut row = honour_of(db, player);
    row.honour += earned;
    keep(db, row);
}

/// The honour one of a thing costs in the stores, if they sell it.
pub fn price_of(item: Item) -> Option<u64> {
    PRICES.iter().find(|(sold, _)| *sold == item).map(|(_, honour)| *honour)
}

/// A member buys so many of a thing from their alliance's stores with
/// their honour: into their satchel. What honour they have left.
pub fn buy(db: &mut impl Db, player: u64, item: u8, count: u64) -> Result<u64, Refusal> {
    asking(db, player)?;
    member_of(db, player).ok_or(Refusal::NotAllied)?;
    let item = Item::of(item).ok_or(Refusal::NoSuchWare)?;
    let price = price_of(item).ok_or(Refusal::NoSuchWare)?;
    if count == 0 {
        return Err(Refusal::NothingAsked);
    }
    if count > MOST_BOUGHT {
        return Err(Refusal::TooMany(MOST_BOUGHT));
    }
    let mut row = honour_of(db, player);
    let cost = price * count;
    if row.honour < cost {
        return Err(Refusal::NotEnoughHonour(row.honour));
    }
    row.honour -= cost;
    let left = row.honour;
    keep(db, row);
    give(db, player, item, count);
    Ok(left)
}
