//! Merits over a store kept in memory: the tiers written as the realm
//! opens, the deeds of the day's work kept on a player's record over all
//! their days, and a tier reached claimed once, in order.

use realm::catalog::{self, Building as Kind, Deed, Goods, Item};
use realm::rows::{Building, City, Merit, Stock};
use realm::rules::{self, Refusal};
use realm::store::{Mem, Seconds, Table};

const START: Seconds = 3_000_000;

fn wait(db: &mut Mem, seconds: Seconds) {
    let to = db.clock + seconds;
    db.advance(to, |db, timer| rules::fire(db, timer));
}

/// A player with goods enough and a Barracks of the sixth level.
fn trainer() -> (Mem, u64, City, Building) {
    let mut db = Mem::new(START, 5);
    rules::open(&mut db, 7, 1, 48);
    let player = db.call(|db| rules::join(db, "Ada")).unwrap().id;
    let mut city = rules::city_of(&db, player).unwrap();
    city.keep = 6;
    db.update(city.clone());
    let mut keep = rules::building_of(&db, city.id, Kind::Keep).unwrap();
    keep.level = 6;
    db.update(keep);
    let barracks = db.insert(Building { id: 0, city: city.id, kind: Kind::Barracks as u8, level: 6 });
    let mut stock = rules::grown(&Table::<Stock>::get(&db, city.id).unwrap(), db.clock);
    (stock.grain, stock.timber, stock.stone, stock.moonsalt) = (900_000, 900_000, 900_000, 50_000);
    db.update(stock);
    (db, player, city, barracks)
}

fn stock(db: &Mem, city: u64) -> Goods {
    rules::goods(&rules::grown(&Table::<Stock>::get(db, city).unwrap(), db.clock))
}

#[test]
fn the_tiers_of_merit_are_written_as_the_realm_opens() {
    let (db, _, _, _) = trainer();
    assert_eq!(Table::<Merit>::all(&db).len() as u32, 5 * catalog::MERIT_TIERS);
    let first = Table::<Merit>::get(&db, Merit::key(Deed::Train as u8, 1)).unwrap();
    assert_eq!((first.name.as_str(), first.words.as_str(), first.goal, first.grain, first.stone, first.item), ("Drillmaster", "soldiers set to train", 500, 5_000, 2_500, 0));
    let last = Table::<Merit>::get(&db, Merit::key(Deed::Clear as u8, 4)).unwrap();
    assert_eq!((last.goal, last.grain, last.item, last.items), (2_000, 150_000, Item::GreatTome as u8, 1));
}

#[test]
fn soldiers_trained_over_many_days_reach_a_merit_claimed_once_in_order() {
    let (mut db, ada, city, barracks) = trainer();
    let most = catalog::batch(barracks.level);
    // Trained in batches across days: the day's work begins afresh, the record does not.
    let mut trained = 0;
    while trained < 500 {
        let count = most.min(500 - trained);
        db.call(|db| rules::train(db, ada, barracks.id, 1, count)).unwrap();
        trained += count;
        wait(&mut db, catalog::DAY);
    }
    assert_eq!(rules::record_of(&db, ada, Deed::Train).done, 500);
    assert!(rules::daily_of(&db, ada).trained < 500, "the day's own count began afresh");
    // Not yet the second tier; the first claimed, then not again.
    let before = stock(&db, city.id);
    assert_eq!(db.call(|db| rules::claim_merit(db, ada, Deed::Train as u8)), Ok((1, Goods::of(5_000, 5_000, 2_500, 0))));
    let after = stock(&db, city.id);
    assert!(after.grain >= before.grain + 5_000 - 100 && after.stone >= before.stone + 2_500 - 100, "{before:?} {after:?}");
    wait(&mut db, 1);
    assert_eq!(db.call(|db| rules::claim_merit(db, ada, Deed::Train as u8)), Err(Refusal::MeritNotReached(500, 5_000)));
    assert_eq!(rules::record_of(&db, ada, Deed::Train).claimed, 1);
    // A deed done none of, and no such deed.
    assert_eq!(db.call(|db| rules::claim_merit(db, ada, Deed::Clear as u8)), Err(Refusal::MeritNotReached(0, 10)));
    assert_eq!(db.call(|db| rules::claim_merit(db, ada, 99)), Err(Refusal::NoSuchMerit));
}

#[test]
fn every_tier_claimed_and_none_after() {
    let (mut db, ada, _, _) = trainer();
    let mut record = rules::record_of(&db, ada, Deed::Hasten);
    record.done = 2_000;
    db.insert(record);
    let hastes = rules::held(&db, ada, Item::Haste60);
    for tier in 1..=catalog::MERIT_TIERS {
        assert_eq!(db.call(|db| rules::claim_merit(db, ada, Deed::Hasten as u8)).map(|(tier, _)| tier), Ok(tier));
        wait(&mut db, 1);
    }
    assert_eq!(rules::held(&db, ada, Item::Haste60), hastes + 1, "the second tier's hour of haste");
    assert_eq!(rules::held(&db, ada, Item::GreatTome), 1, "the fourth's great tome");
    assert_eq!(db.call(|db| rules::claim_merit(db, ada, Deed::Hasten as u8)), Err(Refusal::MeritsClaimed));
}
