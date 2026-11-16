//! Items over a store kept in memory: what the day's chests hold, and
//! what using a haste does to a work.

use realm::catalog::{self, Building as Kind, Item, Topic};
use realm::rows::{Building, Chest, City, Job, Satchel, Stock, Ware};
use realm::rules::{self, Refusal};
use realm::store::{Mem, Seconds, Table};

const START: Seconds = 3_000_000;

fn wait(db: &mut Mem, seconds: Seconds) {
    let to = db.clock + seconds;
    db.advance(to, |db, timer| rules::fire(db, timer));
}

fn joined(name: &str, db: &mut Mem) -> (u64, City) {
    let player = db.call(|db| rules::join(db, name)).unwrap().id;
    let city = rules::city_of(db, player).unwrap();
    let mut row = rules::grown(&Table::<Stock>::get(db, city.id).unwrap(), db.clock);
    (row.grain, row.timber, row.stone, row.moonsalt) = (900_000, 900_000, 900_000, 90_000);
    db.update(row);
    raise(db, city.id, Kind::Keep, 6);
    (player, rules::city_of(db, player).unwrap())
}

fn realm() -> Mem {
    let mut db = Mem::new(START, 5);
    rules::open(&mut db, 7, 1, 48);
    db
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

/// Puts so many of an item in a player's satchel.
fn hand(db: &mut Mem, player: u64, item: Item, count: u64) {
    let id = Satchel::key(player, item as u8);
    if Table::<Satchel>::get(db, id).is_some() {
        db.update(Satchel { id, player, item: item as u8, count });
    } else {
        db.insert(Satchel { id, player, item: item as u8, count });
    }
}

#[test]
fn the_items_are_written_out_and_the_chests_say_what_they_hold() {
    let db = realm();
    let wares = Table::<Ware>::all(&db);
    assert_eq!(
        wares.iter().map(|ware| (ware.item, ware.seconds, ware.kind)).collect::<Vec<_>>(),
        vec![
            (1, 300, Ware::HASTE),
            (2, 3_600, Ware::HASTE),
            (3, 28_800, Ware::HASTE),
            (4, 28_800, Ware::PEACE),
            (5, 0, Ware::MATERIAL),
            (6, 0, Ware::MATERIAL),
            (7, 0, Ware::MATERIAL),
            (8, 0, Ware::MATERIAL)
        ]
    );
    assert_eq!(wares[0].name, "Five minutes' haste");
    assert_eq!(wares[1].words, "Takes 1 hour off a work under way in your city.");
    for chest in Table::<Chest>::all(&db) {
        let holds = catalog::chest_items(chest.id as u8);
        let of = |item: Item| holds.iter().filter(|(held, _)| *held == item).map(|(_, count)| *count).sum::<u64>();
        assert_eq!((chest.brief_hastes, chest.hour_hastes, chest.long_hastes, chest.peaces), (of(Item::Haste5), of(Item::Haste60), of(Item::Haste480), of(Item::Peace8)));
        assert!(chest.brief_hastes + chest.hour_hastes + chest.long_hastes > 0, "every chest holds some haste");
    }
    assert!(catalog::chest_items(0).is_empty() && catalog::chest_items(4).is_empty());
}

#[test]
fn a_chest_opened_puts_its_hastes_in_the_satchel() {
    let mut db = realm();
    let (player, city) = joined("Ada", &mut db);
    let barracks = raise(&mut db, city.id, Kind::Barracks, 10);
    raise(&mut db, city.id, Kind::Academy, 1);
    assert_eq!(rules::held(&db, player, Item::Haste5), 0);
    assert!(Table::<Satchel>::by(&db, 0, player).is_empty(), "an empty satchel has no rows");

    db.call(|db| rules::train(db, player, barracks.id, 1, 50)).unwrap();
    let farm = rules::building_of(&db, city.id, Kind::Farm).unwrap();
    db.call(|db| rules::upgrade(db, player, farm.id)).unwrap();
    db.call(|db| rules::study(db, player, Topic::Tillage as u8)).unwrap();
    db.call(|db| rules::open_chest(db, player, 1)).unwrap();
    assert_eq!((rules::held(&db, player, Item::Haste5), rules::held(&db, player, Item::Haste60)), (2, 0));
    // A chest refused gives nothing.
    assert!(db.call(|db| rules::open_chest(db, player, 1)).is_err());
    assert_eq!(rules::held(&db, player, Item::Haste5), 2);
}

#[test]
fn a_haste_takes_its_time_off_a_work_and_is_spent() {
    let mut db = realm();
    let (player, city) = joined("Ada", &mut db);
    hand(&mut db, player, Item::Haste5, 2);
    raise(&mut db, city.id, Kind::Keep, 15);
    let farm = raise(&mut db, city.id, Kind::Farm, 12);
    let job = db.call(|db| rules::upgrade(db, player, farm.id)).unwrap();
    let whole = job.ends - job.started;
    assert!(whole > 700, "long enough to take two hastes: {whole}");

    let hastened = db.call(|db| rules::use_item(db, player, Item::Haste5 as u8, job.id)).unwrap();
    assert_eq!(hastened.ends, job.ends - 300);
    assert_eq!(rules::held(&db, player, Item::Haste5), 1);
    assert_eq!(rules::daily_of(&db, player).hastened, 1, "it counts toward the day's work");

    // The work ends when it now says, not when it said.
    wait(&mut db, whole - 300 - 1);
    assert_eq!(rules::building_of(&db, city.id, Kind::Farm).unwrap().level, farm.level);
    wait(&mut db, 1);
    assert_eq!(rules::building_of(&db, city.id, Kind::Farm).unwrap().level, farm.level + 1);
    assert!(Table::<Job>::get(&db, job.id).is_none());
}

#[test]
fn a_haste_longer_than_what_is_left_ends_the_work_at_once() {
    let mut db = realm();
    let (player, city) = joined("Ada", &mut db);
    hand(&mut db, player, Item::Haste480, 1);
    let farm = rules::building_of(&db, city.id, Kind::Farm).unwrap();
    let job = db.call(|db| rules::upgrade(db, player, farm.id)).unwrap();
    assert!(job.ends - job.started < 28_800);
    let hastened = db.call(|db| rules::use_item(db, player, Item::Haste480 as u8, job.id)).unwrap();
    assert_eq!(hastened.ends, db.clock + 1);
    wait(&mut db, 1);
    assert_eq!(rules::building_of(&db, city.id, Kind::Farm).unwrap().level, farm.level + 1);
    assert_eq!(rules::held(&db, player, Item::Haste480), 0);
    assert!(Table::<Satchel>::by(&db, 0, player).is_empty(), "the last one used leaves no row");
}

#[test]
fn a_haste_is_refused_where_it_cannot_be_used_and_is_not_spent() {
    let mut db = realm();
    let (ada, city) = joined("Ada", &mut db);
    let (bryn, other) = joined("Bryn", &mut db);
    hand(&mut db, ada, Item::Haste5, 1);
    let farm = rules::building_of(&db, city.id, Kind::Farm).unwrap();
    let job = db.call(|db| rules::upgrade(db, ada, farm.id)).unwrap();
    let theirs = rules::building_of(&db, other.id, Kind::Farm).unwrap();
    let foreign = db.call(|db| rules::upgrade(db, bryn, theirs.id)).unwrap();

    assert_eq!(db.call(|db| rules::use_item(db, ada, 9, job.id)), Err(Refusal::NoSuchItem));
    assert_eq!(db.call(|db| rules::use_item(db, ada, Item::Haste60 as u8, job.id)), Err(Refusal::NoneLeft));
    assert_eq!(db.call(|db| rules::use_item(db, ada, Item::Haste5 as u8, foreign.id)), Err(Refusal::NoSuchJob), "another's work");
    assert_eq!(db.call(|db| rules::use_item(db, ada, Item::Haste5 as u8, 999_999)), Err(Refusal::NoSuchJob));
    assert_eq!(db.call(|db| rules::use_item(db, 77, Item::Haste5 as u8, job.id)), Err(Refusal::NotAPlayer));
    // Nearly done: there is nothing to hasten.
    let whole = job.ends - job.started;
    wait(&mut db, whole - 1);
    assert_eq!(db.call(|db| rules::use_item(db, ada, Item::Haste5 as u8, job.id)), Err(Refusal::NothingToSpeed));
    assert_eq!(rules::held(&db, ada, Item::Haste5), 1, "none of those spent it");
    assert_eq!(Refusal::NoneLeft.to_string(), "You have none of that left.");
}

#[test]
fn in_a_faster_realm_a_haste_takes_off_as_much_less_as_everything_takes_less() {
    let mut db = realm();
    let (player, city) = joined("Ada", &mut db);
    db.call(|db| rules::repace(db, 60)).unwrap();
    hand(&mut db, player, Item::Haste5, 1);
    raise(&mut db, city.id, Kind::Keep, 10);
    let wall = raise(&mut db, city.id, Kind::Wall, 9);
    let job = db.call(|db| rules::upgrade(db, player, wall.id)).unwrap();
    assert!(job.ends - job.started > 10, "long enough at this pace: {}", job.ends - job.started);
    let hastened = db.call(|db| rules::use_item(db, player, Item::Haste5 as u8, job.id)).unwrap();
    assert_eq!(hastened.ends, job.ends - 5, "five minutes are five seconds at sixty times the pace");
}
