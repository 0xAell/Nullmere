//! The pedlar over a store kept in memory: his deals written as the realm
//! opens, four offered each day turning over three, each taken once a day
//! for its goods, its items into the satchel.

use realm::catalog::{self, Goods, Item};
use realm::rows::{Deal, Stock};
use realm::rules::{self, Refusal};
use realm::store::{Mem, Seconds, Table};

const START: Seconds = 3_000_000;

fn wait(db: &mut Mem, seconds: Seconds) {
    let to = db.clock + seconds;
    db.advance(to, |db, timer| rules::fire(db, timer));
}

fn customer(grain: u64) -> (Mem, u64, u64) {
    let mut db = Mem::new(START, 5);
    rules::open(&mut db, 7, 1, 48);
    let player = db.call(|db| rules::join(db, "Ada")).unwrap().id;
    let city = rules::city_of(&db, player).unwrap();
    let mut stock = rules::grown(&Table::<Stock>::get(&db, city.id).unwrap(), db.clock);
    (stock.grain, stock.timber, stock.stone, stock.moonsalt) = (grain, 200_000, 200_000, 5_000);
    db.update(stock);
    (db, player, city.id)
}

fn stock(db: &Mem, city: u64) -> Goods {
    rules::goods(&rules::grown(&Table::<Stock>::get(db, city).unwrap(), db.clock))
}

/// The deals offered today.
fn today(db: &Mem) -> Vec<Deal> {
    let day = rules::today(db);
    let mut deals: Vec<Deal> = Table::<Deal>::all(db).into_iter().filter(|deal| deal.slot == day % catalog::PEDLAR_DAYS).collect();
    deals.sort_by_key(|deal| deal.id);
    deals
}

#[test]
fn the_pedlar_s_deals_are_written_and_four_are_offered_each_day() {
    let (mut db, _, _) = customer(200_000);
    assert_eq!(Table::<Deal>::all(&db).len(), 12);
    for _ in 0..catalog::PEDLAR_DAYS {
        assert_eq!(today(&db).len(), 4);
        wait(&mut db, catalog::DAY);
    }
    let first = Table::<Deal>::get(&db, 1).unwrap();
    assert_eq!((first.item, first.count, first.grain, first.timber, first.slot), (Item::Haste5 as u8, 6, 4_000, 4_000, 0));
}

#[test]
fn a_deal_offered_today_is_taken_once_for_its_goods() {
    let (mut db, ada, city) = customer(200_000);
    let deal = today(&db).remove(0);
    let item = Item::of(deal.item).unwrap();
    let (held, before) = (rules::held(&db, ada, item), stock(&db, city));
    assert_eq!(db.call(|db| rules::buy_deal(db, ada, deal.id)).map(|taken| taken.id), Ok(deal.id));
    assert_eq!(rules::held(&db, ada, item), held + deal.count);
    let after = stock(&db, city);
    assert!(before.timber - after.timber >= deal.timber && before.timber - after.timber < deal.timber + 100, "{before:?} {after:?}");
    wait(&mut db, 1);
    assert_eq!(db.call(|db| rules::buy_deal(db, ada, deal.id)), Err(Refusal::DealTaken));
    // One not offered today, and none at all.
    let elsewhere = Table::<Deal>::all(&db).into_iter().find(|other| other.slot != deal.slot).unwrap();
    assert_eq!(db.call(|db| rules::buy_deal(db, ada, elsewhere.id)), Err(Refusal::NotOfferedToday));
    assert_eq!(db.call(|db| rules::buy_deal(db, ada, 99)), Err(Refusal::NoSuchDeal));
    // The pedlar comes round to it again three days on, when it may be taken again.
    wait(&mut db, catalog::PEDLAR_DAYS as Seconds * catalog::DAY);
    assert_eq!(db.call(|db| rules::buy_deal(db, ada, deal.id)).map(|taken| taken.id), Ok(deal.id));
}

#[test]
fn a_deal_not_afforded_is_refused_and_takes_nothing() {
    let (mut db, ada, city) = customer(0);
    let deal = today(&db).into_iter().find(|deal| deal.grain > 0).unwrap();
    let before = stock(&db, city);
    assert!(matches!(db.call(|db| rules::buy_deal(db, ada, deal.id)), Err(Refusal::CannotAfford(_))));
    assert_eq!(stock(&db, city).timber, before.timber);
    assert_eq!(rules::held(&db, ada, Item::of(deal.item).unwrap()), 0);
}
