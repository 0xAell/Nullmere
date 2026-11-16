//! Prisoners over a store kept in memory: the commander keeping a city
//! taken when it falls, held from leading and keeping, ransomed into the
//! captor's city, let go, or gone free after three days.

use realm::catalog::{self, Troops};
use realm::hex::Hex;
use realm::rows::{City, Commander, Keeper, March, Prisoner, Report, Stock, Troop};
use realm::rules::{self, Asked, Refusal, HELD};
use realm::store::{Mem, Seconds, Table};

const START: Seconds = 3_000_000;
const SEED: u64 = 7;
const RADIUS: u32 = 48;

fn wait(db: &mut Mem, seconds: Seconds) {
    let to = db.clock + seconds;
    db.advance(to, rules::fire);
}

fn spears(count: u64) -> Vec<Asked> {
    vec![Asked { kind: Troops::Spearmen as u8, tier: 1, count }]
}

/// Ada, with an army enough to take any city here; and Bryn, whose city
/// is open to attack, held by a few, and kept by his commander at their
/// sixth level.
fn ada_and_bryn() -> (Mem, u64, u64, City, City, Commander) {
    let mut db = Mem::new(START, 5);
    rules::open(&mut db, SEED, 1, RADIUS);
    let ada = db.call(|db| rules::join(db, "Ada")).unwrap().id;
    let bryn = db.call(|db| rules::join(db, "Bryn")).unwrap().id;
    let (hers, his) = (rules::city_of(&db, ada).unwrap(), rules::city_of(&db, bryn).unwrap());
    for (city, ready) in [(&hers, 50_000), (&his, 200)] {
        let mut row = Table::<City>::get(&db, city.id).unwrap();
        (row.keep, row.shield) = (12, 0);
        db.update(row);
        rules::keep_troop(&mut db, Troop { id: Troop::key(city.id, Troops::Spearmen as u8, 1), city: city.id, kind: Troops::Spearmen as u8, tier: 1, ready, wounded: 0 });
        let mut stock = rules::grown(&Table::<Stock>::get(&db, city.id).unwrap(), db.clock);
        (stock.grain, stock.timber, stock.stone, stock.moonsalt) = (100_000, 100_000, 100_000, 0);
        db.update(stock);
    }
    let mut keeper = rules::commanders_of(&db, bryn).remove(0);
    keeper.level = 6;
    db.update(keeper.clone());
    db.call(|db| rules::keep_city(db, bryn, keeper.id)).unwrap();
    (db, ada, bryn, hers, his, keeper)
}

/// Ada's army takes Bryn's city by storm.
fn storm(db: &mut Mem, ada: u64, his: &City) {
    wait(db, 10);
    let mut row = Table::<City>::get(db, his.id).unwrap();
    row.shield = 0;
    db.update(row);
    let march = db.call(|db| rules::send(db, ada, Hex::unpacked(his.hex), March::ATTACK, &spears(5_000))).unwrap();
    let to = march.arrives + catalog::ASSAULT_SECONDS;
    db.advance(to, rules::fire);
}

fn goods_of(db: &Mem, city: &City) -> catalog::Goods {
    rules::goods(&rules::grown(&Table::<Stock>::get(db, city.id).unwrap(), db.clock))
}

fn said(db: &Mem, player: u64, kind: u8) -> Vec<String> {
    let mut all: Vec<Report> = Table::<Report>::by(db, 0, player).into_iter().filter(|report| report.kind == kind).collect();
    all.sort_by_key(|report| report.id);
    all.into_iter().map(|report| report.words).collect()
}

#[test]
fn the_commander_keeping_a_city_is_taken_when_it_falls_and_ransomed_home() {
    let (mut db, ada, bryn, hers, his, keeper) = ada_and_bryn();
    storm(&mut db, ada, &his);

    // Taken: held, keeping nothing, leading nothing.
    let held = Table::<Prisoner>::get(&db, keeper.id).unwrap();
    let ransom = catalog::ransom(6);
    assert_eq!(ransom, catalog::Goods::of(30_000, 30_000, 30_000, 0));
    assert_eq!((held.owner, held.captor, held.name.as_str(), held.grain, held.timber, held.stone), (bryn, ada, keeper.name.as_str(), 30_000, 30_000, 30_000));
    assert_eq!(held.freed_at, held.freed_at.max(db.clock), "in days to come");
    assert_eq!(Table::<Commander>::get(&db, keeper.id).unwrap().march, HELD);
    assert!(Table::<Keeper>::get(&db, bryn).is_none(), "keeping nothing now");
    assert_eq!(db.call(|db| rules::keep_city(db, bryn, keeper.id)), Ok(()));
    assert_eq!(rules::defence_of(&db, his.id, bryn), rules::mastery(&db, his.id), "a prisoner keeps no city");
    rules::keep_troop(&mut db, Troop { id: Troop::key(his.id, Troops::Spearmen as u8, 1), city: his.id, kind: Troops::Spearmen as u8, tier: 1, ready: 100, wounded: 0 });
    let site = Table::<realm::rows::Site>::all(&db).into_iter().next().unwrap();
    assert_eq!(db.call(|db| rules::send_led(db, bryn, Hex::unpacked(site.hex), March::GATHER, &spears(10), keeper.id)), Err(Refusal::CommanderAway(keeper.name.clone())));
    // Both are told, in the storm's reports and in words of their own.
    assert!(said(&db, ada, Report::ATTACK).last().unwrap().ends_with(&format!(" {}, who kept the city, is your prisoner.", keeper.name)));
    assert!(said(&db, bryn, Report::DEFENCE).last().unwrap().ends_with(&format!(" {}, who kept it, was taken prisoner.", keeper.name)));
    assert!(said(&db, bryn, Report::PRISONER)[0].contains("You may ransom them for 30,000 grain, 30,000 timber and 30,000 stone"), "{}", said(&db, bryn, Report::PRISONER)[0]);

    // Only their owner ransoms them, with goods enough; the ransom goes into the captor's city.
    wait(&mut db, 10);
    assert_eq!(db.call(|db| rules::ransom(db, ada, keeper.id)), Err(Refusal::NoSuchPrisoner));
    assert_eq!(Refusal::NoSuchPrisoner.to_string(), "There is no such prisoner of yours.");
    let mut stock = rules::grown(&Table::<Stock>::get(&db, his.id).unwrap(), db.clock);
    (stock.grain, stock.timber, stock.stone) = (10_000, 10_000, 10_000);
    db.update(stock);
    assert!(matches!(db.call(|db| rules::ransom(db, bryn, keeper.id)), Err(Refusal::CannotAfford(_))));
    let mut stock = rules::grown(&Table::<Stock>::get(&db, his.id).unwrap(), db.clock);
    (stock.grain, stock.timber, stock.stone) = (40_000, 40_000, 40_000);
    db.update(stock);
    let (before_his, before_hers) = (goods_of(&db, &his), goods_of(&db, &hers));
    db.call(|db| rules::ransom(db, bryn, keeper.id)).unwrap();
    assert_eq!(goods_of(&db, &his), before_his.minus(ransom));
    assert_eq!(goods_of(&db, &hers), before_hers.plus(ransom));
    assert!(Table::<Prisoner>::get(&db, keeper.id).is_none());
    assert_eq!(Table::<Commander>::get(&db, keeper.id).unwrap().march, 0, "home");
    assert!(said(&db, ada, Report::PRISONER).last().unwrap().starts_with("Bryn ransomed "));
    assert!(db.timers.values().all(|timer| timer.kind != rules::TIMER_PRISON), "the days held are called off");
}

#[test]
fn a_captor_lets_a_prisoner_go_and_one_held_three_days_goes_free() {
    let (mut db, ada, bryn, _, his, keeper) = ada_and_bryn();
    storm(&mut db, ada, &his);
    assert!(Table::<Prisoner>::get(&db, keeper.id).is_some());
    wait(&mut db, 10);
    assert_eq!(db.call(|db| rules::release_prisoner(db, bryn, keeper.id)), Err(Refusal::NoSuchPrisoner), "only the captor lets them go");
    db.call(|db| rules::release_prisoner(db, ada, keeper.id)).unwrap();
    assert_eq!(Table::<Commander>::get(&db, keeper.id).unwrap().march, 0);
    assert_eq!(said(&db, bryn, Report::PRISONER).last().unwrap(), &format!("Ada let {} go. They are home.", keeper.name));

    // Kept and taken again: held three days, then free of themselves.
    db.call(|db| rules::keep_city(db, bryn, keeper.id)).unwrap();
    wait(&mut db, 4 * 3_600 + 10);
    storm(&mut db, ada, &his);
    let held = Table::<Prisoner>::get(&db, keeper.id).unwrap();
    db.advance(held.freed_at - 1, rules::fire);
    assert!(Table::<Prisoner>::get(&db, keeper.id).is_some(), "not a moment early");
    db.advance(held.freed_at, rules::fire);
    assert!(Table::<Prisoner>::get(&db, keeper.id).is_none());
    assert_eq!(Table::<Commander>::get(&db, keeper.id).unwrap().march, 0);
    assert!(said(&db, bryn, Report::PRISONER).last().unwrap().ends_with("has gone free after three days held, and is home."));

    // A city kept by no one gives up no prisoner.
    wait(&mut db, 4 * 3_600 + 10);
    storm(&mut db, ada, &his);
    assert!(Table::<Prisoner>::all(&db).is_empty());
}
