//! Favour over a store kept in memory: what earns it, the levels it
//! rises through, and what a level does.

use realm::catalog::{self, Building as Kind, Topic, TOP_FAVOUR};
use realm::rows::{Building, City, Favour, Grace, Stock};
use realm::rules::{self};
use realm::store::{Mem, Seconds, Table};

const START: Seconds = 3_000_000;

fn joined() -> (Mem, u64, City) {
    let mut db = Mem::new(START, 5);
    rules::open(&mut db, 7, 1, 48);
    let player = db.call(|db| rules::join(db, "Ada")).unwrap().id;
    let city = rules::city_of(&db, player).unwrap();
    (db, player, city)
}

/// Fills a city's stock, so that nothing here is refused for want of goods.
fn provide(db: &mut Mem, city: u64) {
    let mut row = rules::grown(&Table::<Stock>::get(db, city).unwrap(), db.clock);
    (row.grain, row.timber, row.stone, row.moonsalt) = (900_000, 900_000, 900_000, 90_000);
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

/// Gives a player so much favour outright.
fn favour(db: &mut Mem, player: u64, points: u64) {
    let row = Favour { player, points, level: catalog::favour_level(points) };
    if Table::<Favour>::get(db, player).is_some() {
        db.update(row);
    } else {
        db.insert(row);
    }
}

#[test]
fn the_levels_of_favour_are_written_out_and_each_asks_more_than_the_last() {
    let (db, player, _) = joined();
    let graces: Vec<Grace> = Table::<Grace>::all(&db);
    assert_eq!(graces.len() as u32, TOP_FAVOUR + 1);
    assert_eq!((graces[0].level, graces[0].points, graces[0].sooner), (0, 0, 0), "everyone begins without any");
    assert!(graces.windows(2).all(|pair| pair[0].points < pair[1].points && pair[0].sooner + 1 == pair[1].sooner));
    assert_eq!(graces.last().unwrap().sooner, 10, "a tenth sooner at the top");
    for grace in &graces {
        assert_eq!(catalog::favour_level(grace.points), grace.level as u32);
        if grace.points > 0 {
            assert_eq!(catalog::favour_level(grace.points - 1), grace.level as u32 - 1, "one short of a level is the level below");
        }
    }
    assert_eq!(catalog::favour_level(u64::MAX), TOP_FAVOUR);
    assert_eq!(rules::favour_of(&db, player), Favour { player, points: 0, level: 0 });
    assert!(Table::<Favour>::get(&db, player).is_none(), "no row until some is earned");
}

#[test]
fn favour_is_earned_by_opening_the_days_chests() {
    let (mut db, player, city) = joined();
    provide(&mut db, city.id);
    raise(&mut db, city.id, Kind::Keep, 6);
    let barracks = raise(&mut db, city.id, Kind::Barracks, 10);
    raise(&mut db, city.id, Kind::Academy, 1);

    // Forty marks: the first chest, and ten of favour.
    db.call(|db| rules::train(db, player, barracks.id, 1, 50)).unwrap();
    let farm = rules::building_of(&db, city.id, Kind::Farm).unwrap();
    db.call(|db| rules::upgrade(db, player, farm.id)).unwrap();
    let study = db.call(|db| rules::study(db, player, Topic::Tillage as u8)).unwrap();
    assert_eq!(rules::favour_of(&db, player).points, 0, "the work itself earns none");
    db.call(|db| rules::open_chest(db, player, 1)).unwrap();
    assert_eq!(rules::favour_of(&db, player), Favour { player, points: 10, level: 0 });
    // A chest refused earns nothing.
    assert!(db.call(|db| rules::open_chest(db, player, 1)).is_err());
    assert!(db.call(|db| rules::open_chest(db, player, 2)).is_err());
    assert_eq!(rules::favour_of(&db, player).points, 10);

    // Sixty marks is not seventy; a deed more is.
    db.call(|db| rules::speed_up(db, player, study.id)).unwrap();
    assert!(db.call(|db| rules::open_chest(db, player, 2)).is_err());
    assert_eq!([1, 2, 3].map(catalog::chest_favour), [10, 20, 40]);
    assert_eq!(catalog::chest_favour(0) + catalog::chest_favour(4), 0);
}

#[test]
fn enough_favour_is_a_level_and_a_level_hastens_every_work_by_a_hundredth() {
    let (mut db, player, city) = joined();
    provide(&mut db, city.id);
    raise(&mut db, city.id, Kind::Keep, 8);
    let barracks = raise(&mut db, city.id, Kind::Barracks, 10);
    raise(&mut db, city.id, Kind::Academy, 1);
    favour(&mut db, player, catalog::favour_needs(4));
    assert_eq!(rules::favour_of(&db, player).level, 4);

    // A building raised, soldiers trained and a study: each four hundredths sooner than written.
    let farm = rules::building_of(&db, city.id, Kind::Farm).unwrap();
    let job = db.call(|db| rules::upgrade(db, player, farm.id)).unwrap();
    assert_eq!(job.ends - job.started, catalog::seconds(Kind::Farm, farm.level + 1) * 96 / 100);
    let batch = db.call(|db| rules::train(db, player, barracks.id, 1, 40)).unwrap();
    let written = catalog::Troops::trained_by(Kind::Barracks).unwrap().soldier(1).seconds * 40;
    assert_eq!(batch.ends - batch.started, written * 96 / 100);
    let study = db.call(|db| rules::study(db, player, Topic::Tillage as u8)).unwrap();
    assert_eq!(study.ends - study.started, catalog::study_seconds(1) * 96 / 100);
}

#[test]
fn favour_stops_at_its_top_and_never_makes_a_work_take_no_time() {
    let (mut db, player, city) = joined();
    provide(&mut db, city.id);
    raise(&mut db, city.id, Kind::Keep, 8);
    favour(&mut db, player, 10_000_000);
    assert_eq!(rules::favour_of(&db, player).level, TOP_FAVOUR);
    let farm = rules::building_of(&db, city.id, Kind::Farm).unwrap();
    let job = db.call(|db| rules::upgrade(db, player, farm.id)).unwrap();
    assert_eq!(job.ends - job.started, catalog::seconds(Kind::Farm, farm.level + 1) * 90 / 100);

    // At a pace that makes a short work shorter than a second it still takes one.
    let (mut fast, player, city) = joined();
    provide(&mut fast, city.id);
    raise(&mut fast, city.id, Kind::Keep, 8);
    fast.call(|db| rules::repace(db, 100_000)).unwrap();
    favour(&mut fast, player, 10_000_000);
    let farm = rules::building_of(&fast, city.id, Kind::Farm).unwrap();
    let job = fast.call(|db| rules::upgrade(db, player, farm.id)).unwrap();
    assert!(job.ends - job.started >= 1);
}

#[test]
fn from_its_second_level_favour_lends_levels_of_studies_as_a_title_does() {
    let (mut db, player, city) = joined();
    let lent = |topic: Topic| (0..=TOP_FAVOUR).map(|level| catalog::favour_lends(level, topic)).collect::<Vec<_>>();
    assert_eq!(lent(Topic::Gathering), vec![0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 2]);
    assert_eq!(lent(Topic::Tillage), vec![0, 0, 0, 1, 1, 1, 1, 1, 1, 2, 2]);
    assert_eq!(lent(Topic::Forestry), lent(Topic::Tillage));
    assert_eq!(lent(Topic::Masonry), lent(Topic::Tillage));
    assert_eq!(lent(Topic::Marching), vec![0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2]);
    assert_eq!(lent(Topic::Storage), vec![0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1]);
    assert_eq!(lent(Topic::Shields), vec![0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 2]);
    assert_eq!(lent(Topic::Drill), vec![0; 11], "nothing of what is not named");
    assert_eq!(catalog::favour_lends(99, Topic::Shields), 2, "no more past the top");

    // Read wherever a study tells: a level of gathering is a tenth faster.
    assert_eq!(rules::boost(&db, city.id, Topic::Gathering), 0);
    favour(&mut db, player, catalog::favour_needs(2));
    assert_eq!(rules::boost(&db, city.id, Topic::Gathering), 10);
    favour(&mut db, player, catalog::favour_needs(TOP_FAVOUR));
    assert_eq!(rules::boost(&db, city.id, Topic::Marching), 10);
    assert_eq!(rules::boost(&db, city.id, Topic::Shields), 6);
    assert_eq!(rules::favour_lent(&db, city.id, Topic::Storage), 1);
}

#[test]
fn rising_a_level_of_favour_reckons_the_city_for_what_the_level_lends() {
    let (mut db, player, city) = joined();
    provide(&mut db, city.id);
    raise(&mut db, city.id, Kind::Keep, 6);
    let barracks = raise(&mut db, city.id, Kind::Barracks, 10);
    raise(&mut db, city.id, Kind::Academy, 1);
    // Ten short of the third level.
    favour(&mut db, player, catalog::favour_needs(3) - 10);
    db.call(|db| rules::train(db, player, barracks.id, 1, 50)).unwrap();
    let farm = rules::building_of(&db, city.id, Kind::Farm).unwrap();
    db.call(|db| rules::upgrade(db, player, farm.id)).unwrap();
    // A study begun is not yet learnt: it adds nothing to the Farm here.
    db.call(|db| rules::study(db, player, Topic::Tillage as u8)).unwrap();
    let before = Table::<Stock>::get(&db, city.id).unwrap();
    assert!(before.grain_hourly > 0);

    // The first chest's ten: the third level, and the Farm brings in a twentieth more.
    db.call(|db| rules::open_chest(db, player, 1)).unwrap();
    assert_eq!(rules::favour_of(&db, player).level, 3);
    let after = Table::<Stock>::get(&db, city.id).unwrap();
    assert_eq!(after.grain_hourly, before.grain_hourly * 105 / 100);
    assert_eq!(after.timber_hourly, before.timber_hourly * 105 / 100);
    assert_eq!(after.moonsalt_hourly, before.moonsalt_hourly, "nothing lent for the Saltworks");
}
