//! The pedlar: each day of the realm he brings four of his twelve deals,
//! turning over three days, each a number of one item for goods. A player
//! takes each deal once a day it is offered, paying from their city's
//! stock, the item going into their satchel.

use super::{asking, city_of, give, goods, set_goods, settle, today, Refusal};
use crate::catalog::{self, Goods, Item};
use crate::rows::{Bought, Db, Deal};
use crate::store::Table;

/// Writes the pedlar's deals out as rows, for clients to show, as the
/// realm opens.
pub fn write_deals(db: &mut impl Db) {
    for (id, item, count, cost, slot) in catalog::pedlar_deals() {
        db.insert(Deal { id, item: item as u8, count, grain: cost.grain, timber: cost.timber, stone: cost.stone, moonsalt: cost.moonsalt, slot });
    }
}

/// A player takes one of the deals the pedlar offers today: its goods
/// from their city's stock, its items into their satchel, once a day.
pub fn buy_deal(db: &mut impl Db, player: u64, deal: u64) -> Result<Deal, Refusal> {
    asking(db, player)?;
    let city = city_of(db, player)?;
    let row = Table::<Deal>::get(db, deal).ok_or(Refusal::NoSuchDeal)?;
    let day = today(db);
    if row.slot != day % catalog::PEDLAR_DAYS {
        return Err(Refusal::NotOfferedToday);
    }
    let key = Bought::key(player, deal);
    let kept = Table::<Bought>::get(db, key);
    if kept.as_ref().is_some_and(|bought| bought.day == day) {
        return Err(Refusal::DealTaken);
    }
    let item = Item::of(row.item).ok_or(Refusal::NoSuchDeal)?;
    let cost = Goods::of(row.grain, row.timber, row.stone, row.moonsalt);
    let mut stock = settle(db, city.id)?;
    let short = goods(&stock).short_of(cost);
    if !short.is_none() {
        return Err(Refusal::CannotAfford(short));
    }
    let left = goods(&stock).minus(cost);
    set_goods(&mut stock, left);
    db.update(stock);
    give(db, player, item, row.count);
    let bought = Bought { key, player, deal, day };
    if kept.is_some() {
        db.update(bought);
    } else {
        db.insert(bought);
    }
    Ok(row)
}
