//! The day's work over a store kept in memory: what counts toward each
//! deed, the marks they earn, the chests those open, and the day ending.

use realm::catalog::{self, Building as Kind, Deed, Goods, Topic, Troops};
use realm::hex::Hex;
use realm::land;
use realm::rows::{Barrow, Building, Chest, City, Daily, Duty, March, Site, Stock, Troop};
use realm::rules::{self, Asked, Refusal};
use realm::store::{Mem, Seconds, Table};

const START: Seconds = 3_000_000;

const SEED: u64 = 7;
const RADIUS: u32 = 48;

fn wait(db: &mut Mem, seconds: Seconds) {
    let to = db.clock + seconds;
    db.advance(to, |db, timer| rules::fire(db, timer));
}

fn joined() -> (Mem, u64, City) {
    let mut db = Mem::new(START, 5);
    rules::open(&mut db, SEED, 1, RADIUS);
    let player = db.call(|db| rules::join(db, "Ada")).unwrap().id;
    let city = rules::city_of(&db, player).unwrap();
    (db, player, city)
}

fn stock(db: &Mem, city: u64) -> Goods {
    rules::goods(&rules::grown(&Table::<Stock>::get(db, city).unwrap(), db.clock))
}

/// Fills a city's stock, so that nothing here is refused for want of goods.
fn provide(db: &mut Mem, city: u64) {
    let mut row = rules::grown(&Table::<Stock>::get(db, city).unwrap(), db.clock);
    (row.grain, row.timber, row.stone, row.moonsalt) = (500_000, 500_000, 500_000, 50_000);
    db.update(row);
}

/// Sets one of a city's buildings to a level, raising it from nothing
/// where the city has none; gives the building.
fn raise(db: &mut Mem, city: u64, kind: Kind, level: u32) -> Building {
    let building = match rules::building_of(db, city, kind) {
        Some(mut building) => {
            building.level = level;
            db.update(building.clone());
            building
        }
        None => db.insert(Building { id: 0, city, kind: kind as u8, level }),
    };
    if kind == Kind::Keep {
        let mut row = Table::<City>::get(db, city).unwrap();
        row.keep = level;
        db.update(row);
    }
    building
}

#[test]
fn the_deeds_and_chests_are_written_out_for_clients() {
    let (db, _, _) = joined();
    let duties = Table::<Duty>::all(&db);
    assert_eq!(duties.len(), Deed::ALL.len());
    assert_eq!(duties.iter().map(|duty| duty.marks).sum::<u32>(), 100, "all five deeds make a hundred marks");
    for duty in &duties {
        let deed = Deed::of(duty.deed as u8).unwrap();
        assert_eq!((duty.asks, duty.words.as_str()), (deed.asks(), deed.words().as_str()));
        assert!(duty.words.ends_with('.'));
    }
    let chests = Table::<Chest>::all(&db);
    assert_eq!(chests.iter().map(|chest| chest.marks).collect::<Vec<_>>(), vec![40, 70, 100]);
    assert!(chests.windows(2).all(|pair| pair[0].grain < pair[1].grain), "a chest that asks more holds more");
    // The last can be opened: it asks no more marks than a day can earn.
    assert!(chests.iter().all(|chest| chest.marks <= 100));
}

#[test]
fn a_deed_counts_only_when_done_in_full_and_each_earns_its_marks() {
    let (mut db, player, city) = joined();
    provide(&mut db, city.id);
    raise(&mut db, city.id, Kind::Keep, 6);
    let barracks = raise(&mut db, city.id, Kind::Barracks, 6);
    assert_eq!(rules::marks(&rules::daily_of(&db, player)), 0);

    // Training: short of fifty earns nothing; the rest of them does.
    let most = catalog::batch(barracks.level);
    let first = 30.min(most);
    db.call(|db| rules::train(db, player, barracks.id, 1, first)).unwrap();
    assert_eq!(rules::daily_of(&db, player).trained, first);
    assert_eq!(rules::marks(&rules::daily_of(&db, player)), 0, "thirty of fifty is not the deed done");
    wait(&mut db, 6 * 3_600);
    db.call(|db| rules::train(db, player, barracks.id, 1, 20)).unwrap();
    assert_eq!(rules::marks(&rules::daily_of(&db, player)), Deed::Train.marks());

    // Works begun: a building raised and a study taken up.
    let farm = rules::building_of(&db, city.id, Kind::Farm).unwrap();
    db.call(|db| rules::upgrade(db, player, farm.id)).unwrap();
    assert_eq!(rules::daily_of(&db, player).begun, 1);
    raise(&mut db, city.id, Kind::Academy, 1);
    let job = db.call(|db| rules::study(db, player, Topic::Tillage as u8)).unwrap();
    assert_eq!(rules::marks(&rules::daily_of(&db, player)), Deed::Train.marks() + Deed::Begin.marks());

    // Hastening one of them.
    db.call(|db| rules::speed_up(db, player, job.id)).unwrap();
    assert_eq!(rules::daily_of(&db, player).hastened, 1);
    assert_eq!(rules::marks(&rules::daily_of(&db, player)), 60);

    // A refusal counts for nothing.
    assert!(db.call(|db| rules::train(db, player, barracks.id, 1, 0)).is_err());
    assert_eq!(rules::daily_of(&db, player).trained, first + 20);
}

#[test]
fn chests_open_at_their_marks_once_a_day_and_give_what_they_hold() {
    let (mut db, player, city) = joined();
    provide(&mut db, city.id);
    raise(&mut db, city.id, Kind::Keep, 6);
    let barracks = raise(&mut db, city.id, Kind::Barracks, 10);
    assert_eq!(db.call(|db| rules::open_chest(db, player, 1)), Err(Refusal::ChestNotEarned(40)));
    assert_eq!(db.call(|db| rules::open_chest(db, player, 0)), Err(Refusal::NoSuchChest));
    assert_eq!(db.call(|db| rules::open_chest(db, player, 4)), Err(Refusal::NoSuchChest));
    assert_eq!(Refusal::ChestNotEarned(40).to_string(), "That chest opens at 40 marks of the day's work.");

    // Forty marks: fifty soldiers set to train, and two works begun.
    db.call(|db| rules::train(db, player, barracks.id, 1, 50)).unwrap();
    let farm = rules::building_of(&db, city.id, Kind::Farm).unwrap();
    db.call(|db| rules::upgrade(db, player, farm.id)).unwrap();
    raise(&mut db, city.id, Kind::Academy, 1);
    db.call(|db| rules::study(db, player, Topic::Tillage as u8)).unwrap();
    assert_eq!(rules::marks(&rules::daily_of(&db, player)), 40);

    let before = stock(&db, city.id);
    let held = db.call(|db| rules::open_chest(db, player, 1)).unwrap();
    assert_eq!(held, catalog::chests()[0].1);
    assert_eq!(stock(&db, city.id), before.plus(held), "what it holds goes into the stock, though it overfill it");
    assert_eq!(db.call(|db| rules::open_chest(db, player, 1)), Err(Refusal::ChestOpened));
    assert_eq!(db.call(|db| rules::open_chest(db, player, 2)), Err(Refusal::ChestNotEarned(70)));
    assert_eq!(Table::<Daily>::get(&db, player).unwrap().opened, 0b001);
}

#[test]
fn a_new_day_begins_the_work_afresh() {
    let (mut db, player, city) = joined();
    provide(&mut db, city.id);
    raise(&mut db, city.id, Kind::Keep, 6);
    let barracks = raise(&mut db, city.id, Kind::Barracks, 10);
    assert_eq!(rules::today(&db), 0, "the day the realm opened");
    db.call(|db| rules::train(db, player, barracks.id, 1, 50)).unwrap();
    assert_eq!(rules::daily_of(&db, player).trained, 50);

    // A day of the realm later what was done is yesterday's.
    wait(&mut db, catalog::DAY + 60);
    assert_eq!(rules::today(&db), 1);
    let fresh = rules::daily_of(&db, player);
    assert_eq!((fresh.day, fresh.trained, rules::marks(&fresh)), (1, 0, 0));
    assert_eq!(Table::<Daily>::get(&db, player).unwrap().day, 0, "the row is kept as it was until they do something");
    db.call(|db| rules::train(db, player, barracks.id, 1, 10)).unwrap();
    let kept = Table::<Daily>::get(&db, player).unwrap();
    assert_eq!((kept.day, kept.trained, kept.opened), (1, 10, 0));
}

#[test]
fn a_day_is_as_long_as_the_realms_pace_makes_it() {
    let (mut db, _, _) = joined();
    db.call(|db| rules::repace(db, 60)).unwrap();
    wait(&mut db, catalog::DAY / 60 * 3 + 5);
    assert_eq!(rules::today(&db), 3);
}

#[test]
fn what_an_army_carries_home_counts_as_it_comes_home() {
    let (mut db, player, city) = joined();
    raise(&mut db, city.id, Kind::Keep, 8);
    rules::keep_troop(&mut db, Troop { id: Troop::key(city.id, Troops::Spearmen as u8, 1), city: city.id, kind: Troops::Spearmen as u8, tier: 1, ready: 2_000, wounded: 0 });

    // Out to the nearest timber a way leads to, and home with the load.
    let from = Hex::unpacked(city.hex);
    let mut sites: Vec<Site> = Table::<Site>::all(&db).into_iter().filter(|site| site.kind == Site::TIMBER).collect();
    sites.sort_by_key(|site| (Hex::unpacked(site.hex).distance(from), site.id));
    let site = sites.into_iter().find(|site| land::way(SEED, RADIUS, from, Hex::unpacked(site.hex)).is_some()).expect("a site within reach");
    let asked = vec![Asked { kind: Troops::Spearmen as u8, tier: 1, count: 2_000 }];
    db.call(|db| rules::send(db, player, Hex::unpacked(site.hex), March::GATHER, &asked)).unwrap();
    assert_eq!(rules::daily_of(&db, player).gathered, 0, "nothing counts until it is home");
    let before = stock(&db, city.id).timber;
    while !Table::<March>::by(&db, 0, player).is_empty() {
        wait(&mut db, 600);
    }
    let today = rules::today(&db);
    let brought = Table::<Daily>::get(&db, player).filter(|row| row.day == today).map(|row| row.gathered).unwrap_or(0);
    assert!(brought > 0, "what the army carried home is counted");
    assert!(stock(&db, city.id).timber >= before + brought, "and it is in the stock");
    assert_eq!(rules::marks(&rules::daily_of(&db, player)) >= Deed::Gather.marks(), brought >= Deed::Gather.asks());
}

#[test]
fn a_barrow_cleared_counts_and_one_that_beats_the_army_does_not() {
    let (mut db, player, city) = joined();
    raise(&mut db, city.id, Kind::Keep, 8);
    rules::keep_troop(&mut db, Troop { id: Troop::key(city.id, Troops::Spearmen as u8, 1), city: city.id, kind: Troops::Spearmen as u8, tier: 1, ready: 3_000, wounded: 0 });
    let from = Hex::unpacked(city.hex);
    let mut barrows = Table::<Barrow>::all(&db);
    barrows.sort_by_key(|barrow| (Hex::unpacked(barrow.hex).distance(from), barrow.id));
    let mut barrow = barrows.into_iter().find(|barrow| land::way(SEED, RADIUS, from, Hex::unpacked(barrow.hex)).is_some()).expect("a barrow within reach");
    barrow.level = 1;
    db.update(barrow.clone());

    // Ten spears against it are beaten: nothing is cleared.
    let few = vec![Asked { kind: Troops::Spearmen as u8, tier: 1, count: 10 }];
    db.call(|db| rules::send(db, player, Hex::unpacked(barrow.hex), March::HUNT, &few)).unwrap();
    while !Table::<March>::by(&db, 0, player).is_empty() {
        wait(&mut db, 600);
    }
    assert_eq!(rules::daily_of(&db, player).cleared, 0);

    // Two thousand clear it.
    let many = vec![Asked { kind: Troops::Spearmen as u8, tier: 1, count: 2_000 }];
    db.call(|db| rules::send(db, player, Hex::unpacked(barrow.hex), March::HUNT, &many)).unwrap();
    while !Table::<March>::by(&db, 0, player).is_empty() {
        wait(&mut db, 600);
    }
    assert!(Table::<Barrow>::get(&db, barrow.id).is_none(), "the barrow is gone");
    let done = rules::daily_of(&db, player);
    assert_eq!(done.cleared, 1);
    assert!(rules::marks(&done) >= Deed::Clear.marks());
}
