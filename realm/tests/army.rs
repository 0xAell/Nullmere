//! Troops over a store kept in memory: trained in batches on a timer,
//! counted by kind and tier.

use realm::catalog::{self, Building as Kind, Goods, Troops};
use realm::rows::{Building, City, Job, Soldier, Stock, Troop};
use realm::rules::{self, Refusal};
use realm::store::{Mem, Seconds, Table};

const START: Seconds = 2_000_000;

/// A realm with one rich player whose Keep stands at a level, with every
/// building that level opens, each at the Keep's level.
fn grown(keep: u32) -> (Mem, u64, City) {
    let mut db = Mem::new(START, 5);
    rules::open(&mut db, 7, 1, 48);
    let player = db.call(|db| rules::join(db, "Ada")).unwrap().id;
    let city = rules::city_of(&db, player).unwrap();
    for kind in Kind::ALL {
        if keep < kind.opens_at() {
            continue;
        }
        match rules::building_of(&db, city.id, kind) {
            Some(mut building) => {
                building.level = keep;
                db.update(building);
            }
            None => {
                db.insert(Building { id: 0, city: city.id, kind: kind as u8, level: keep });
            }
        }
    }
    let mut stock = Table::<Stock>::get(&db, city.id).unwrap();
    (stock.grain, stock.timber, stock.stone, stock.moonsalt, stock.holds) = (5_000_000, 5_000_000, 5_000_000, 100_000, 9_000_000);
    db.update(stock);
    let mut row = city.clone();
    row.keep = keep;
    db.update(row.clone());
    (db, player, row)
}

fn wait(db: &mut Mem, seconds: Seconds) {
    let to = db.clock + seconds;
    db.advance(to, |db, timer| rules::fire(db, timer));
}

fn goods(db: &Mem, city: u64) -> Goods {
    rules::goods(&rules::grown(&Table::<Stock>::get(db, city).unwrap(), db.clock))
}

#[test]
fn the_catalogue_of_troops_is_written_out() {
    let (db, _, _) = grown(2);
    let all = Table::<Soldier>::all(&db);
    assert_eq!(all.len(), 20);
    let spear = Table::<Soldier>::get(&db, Soldier::key(Troops::Spearmen as u8, 1)).unwrap();
    assert_eq!((spear.name.as_str(), spear.grain, spear.timber, spear.millis, spear.building, spear.needs_level), ("Spearmen", 50, 50, 8_000, Kind::Barracks as u8, 1));
    let rider = Table::<Soldier>::get(&db, Soldier::key(Troops::Riders as u8, 3)).unwrap();
    assert_eq!((rider.pace, rider.needs_level, rider.power), (35, 10, 3));
}

#[test]
fn a_batch_is_trained_on_a_timer_and_paid_for_at_once() {
    let (mut db, ada, city) = grown(2);
    let barracks = rules::building_of(&db, city.id, Kind::Barracks).unwrap();
    let before = goods(&db, city.id);
    let job = db.call(|db| rules::train(db, ada, barracks.id, 1, 40)).unwrap();
    assert_eq!((job.kind, job.subject, job.level, job.amount, job.ends - job.started), (Job::TRAIN, barracks.id, 1, 40, 40 * 8));
    let spent = before.minus(goods(&db, city.id));
    assert_eq!(spent, Goods::of(40 * 50, 40 * 50, 0, 0));
    assert!(Table::<Troop>::by(&db, 0, city.id).is_empty(), "none stand ready until the training is done");

    // While they train: no second batch there, and the Barracks can't be raised.
    assert_eq!(db.call(|db| rules::train(db, ada, barracks.id, 1, 10)), Err(Refusal::AlreadyTraining(Kind::Barracks)));
    let keep = rules::building_of(&db, city.id, Kind::Keep).unwrap();
    db.call(|db| rules::upgrade(db, ada, keep.id)).unwrap();
    wait(&mut db, catalog::seconds(Kind::Keep, 3));
    let refusal = db.call(|db| rules::upgrade(db, ada, barracks.id)).unwrap_err();
    assert_eq!(refusal, Refusal::BusyTraining(Kind::Barracks));
    assert_eq!(refusal.to_string(), "Your Barracks is training troops. Wait for them to finish.");

    // Done: forty spearmen stand ready, and the city is stronger by them.
    let power = rules::city_of(&db, ada).unwrap().power;
    wait(&mut db, 40 * 8);
    let troop = rules::troop(&db, city.id, Troops::Spearmen, 1);
    assert_eq!((troop.ready, troop.wounded), (40, 0));
    assert_eq!(rules::city_of(&db, ada).unwrap().power, power + 40);
    assert!(Table::<Job>::all(&db).is_empty());

    // A second batch joins the first.
    db.call(|db| rules::train(db, ada, barracks.id, 1, 25)).unwrap();
    wait(&mut db, 25 * 8);
    assert_eq!(rules::troop(&db, city.id, Troops::Spearmen, 1).ready, 65);
    assert_eq!(Table::<Troop>::by(&db, 0, city.id).len(), 1);
}

#[test]
fn each_kind_trains_in_its_own_building_at_once() {
    let (mut db, ada, city) = grown(10);
    let ids: Vec<u64> = [Kind::Barracks, Kind::Range, Kind::Stable, Kind::Workshop].iter().map(|kind| rules::building_of(&db, city.id, *kind).unwrap().id).collect();
    for (index, id) in ids.iter().enumerate() {
        db.call(|db| rules::train(db, ada, *id, 1 + index as u32 % 3, 100)).unwrap();
    }
    assert_eq!(Table::<Job>::by(&db, 0, city.id).len(), 4, "four buildings, four batches under way");
    wait(&mut db, 100 * 30);
    let mut have: Vec<(u8, u32, u64)> = Table::<Troop>::by(&db, 0, city.id).iter().map(|t| (t.kind, t.tier, t.ready)).collect();
    have.sort();
    assert_eq!(have, vec![(1, 1, 100), (2, 2, 100), (3, 3, 100), (4, 1, 100)]);
    assert_eq!(rules::troop_power(&db, city.id), 100 + 200 + 300 + 100);
}

#[test]
fn what_cant_be_trained_is_refused_in_plain_words() {
    let (mut db, ada, city) = grown(5);
    let barracks = rules::building_of(&db, city.id, Kind::Barracks).unwrap();
    let farm = rules::building_of(&db, city.id, Kind::Farm).unwrap();
    let cases: Vec<(u64, u32, u64, Refusal, &str)> = vec![
        (farm.id, 1, 10, Refusal::TrainsNothing(Kind::Farm), "No troops are trained in a Farm."),
        (barracks.id, 0, 10, Refusal::NoSuchTroops, "There are no such troops."),
        (barracks.id, 6, 10, Refusal::NoSuchTroops, "There are no such troops."),
        (barracks.id, 3, 10, Refusal::NeedsOther(Kind::Barracks, 10), "Raise your Barracks to level 10 first."),
        (barracks.id, 1, 0, Refusal::NothingAsked, "Ask for at least one."),
        (barracks.id, 2, 211, Refusal::TooMany(210), "At most 210 at once."),
        (9_999, 1, 10, Refusal::NoSuchBuilding, "There is no such building."),
    ];
    for (building, tier, count, refusal, words) in cases {
        let got = db.call(|db| rules::train(db, ada, building, tier, count)).unwrap_err();
        assert_eq!(got, refusal);
        assert_eq!(got.to_string(), words);
    }
    let bryn = db.call(|db| rules::join(db, "Bryn")).unwrap().id;
    assert_eq!(db.call(|db| rules::train(db, bryn, barracks.id, 1, 10)), Err(Refusal::NotYours));
    assert_eq!(db.call(|db| rules::train(db, 77, barracks.id, 1, 10)), Err(Refusal::NotAPlayer));

    // Short of goods, they are told by how much; and a building still
    // being raised trains no one.
    let mut poor = Table::<Stock>::get(&db, city.id).unwrap();
    (poor.grain, poor.timber) = (1_000, 5_000);
    db.update(poor);
    let short = db.call(|db| rules::train(db, ada, barracks.id, 2, 100)).unwrap_err();
    assert_eq!(short.to_string(), "You need 9,000 grain and 5,000 timber more.");
    db.call(|db| rules::upgrade(db, ada, rules::building_of(db, city.id, Kind::Range).unwrap().id)).unwrap_err();
    let range = rules::building_of(&db, city.id, Kind::Range).unwrap();
    let mut rich = Table::<Stock>::get(&db, city.id).unwrap();
    (rich.grain, rich.timber) = (5_000_000, 5_000_000);
    db.update(rich);
    let keep = rules::building_of(&db, city.id, Kind::Keep).unwrap();
    let mut wall = rules::building_of(&db, city.id, Kind::Wall).unwrap();
    wall.level = 5;
    db.update(wall);
    db.call(|db| rules::upgrade(db, ada, keep.id)).unwrap();
    wait(&mut db, catalog::seconds(Kind::Keep, 6));
    db.call(|db| rules::upgrade(db, ada, range.id)).unwrap();
    assert_eq!(db.call(|db| rules::train(db, ada, range.id, 1, 10)), Err(Refusal::AlreadyRising(Kind::Range)));
    assert!(Table::<Troop>::by(&db, 0, city.id).is_empty());
}

#[test]
fn troops_are_kept_only_while_there_are_any() {
    let (mut db, _, city) = grown(2);
    let mut row = rules::troop(&db, city.id, Troops::Archers, 2);
    assert_eq!((row.ready, row.wounded), (0, 0));
    rules::keep_troop(&mut db, row.clone());
    assert!(Table::<Troop>::all(&db).is_empty(), "none, so no row");
    row.ready = 30;
    rules::keep_troop(&mut db, row.clone());
    assert_eq!(Table::<Troop>::get(&db, Troop::key(city.id, 2, 2)).unwrap().ready, 30);
    (row.ready, row.wounded) = (0, 12);
    rules::keep_troop(&mut db, row.clone());
    assert_eq!(rules::troop(&db, city.id, Troops::Archers, 2).wounded, 12, "the wounded are still theirs");
    row.wounded = 0;
    rules::keep_troop(&mut db, row);
    assert!(Table::<Troop>::all(&db).is_empty());
    assert_ne!(Troop::key(1, 2, 3), Troop::key(1, 3, 2));
    assert_ne!(Troop::key(1, 2, 3), Troop::key(2, 2, 3));
}

#[test]
fn a_speedup_hastens_a_batch_of_troops_training() {
    let (mut db, ada, city) = grown(2);
    let barracks = rules::building_of(&db, city.id, Kind::Barracks).unwrap();
    let job = db.call(|db| rules::train(db, ada, barracks.id, 1, 40)).unwrap();
    wait(&mut db, 40);
    // Of the 280 seconds left, a quarter comes off; the troops stand ready at the new end.
    let left = job.ends - db.clock;
    let now = db.clock;
    let hastened = db.call(|db| rules::speed_up(db, ada, job.id)).unwrap();
    assert_eq!(hastened.kind, Job::TRAIN);
    assert_eq!(hastened.ends, now + left - left / 4);
    let to_end = hastened.ends - db.clock - 1;
    wait(&mut db, to_end);
    assert!(Table::<Troop>::by(&db, 0, city.id).iter().all(|row| row.ready == 0), "not yet, a second early");
    wait(&mut db, 1);
    assert_eq!(Table::<Troop>::by(&db, 0, city.id).iter().map(|row| row.ready).sum::<u64>(), 40);
}

#[test]
fn troops_ready_are_raised_to_a_higher_tier_for_what_it_costs_beyond() {
    let (mut db, ada, city) = grown(10);
    let barracks = rules::building_of(&db, city.id, Kind::Barracks).unwrap();
    db.call(|db| rules::train(db, ada, barracks.id, 1, 100)).unwrap();
    wait(&mut db, 100 * 8);

    // Refused: none of a tier she lacks, not downward, not past what the Barracks trains, not more than stand ready.
    assert_eq!(db.call(|db| rules::promote(db, ada, barracks.id, 2, 3, 10)), Err(Refusal::NotEnoughTroops(Troops::Spearmen, 2, 0)));
    let refusal = db.call(|db| rules::promote(db, ada, barracks.id, 1, 1, 10)).unwrap_err();
    assert_eq!((refusal.clone(), refusal.to_string()), (Refusal::OnlyHigher, "Troops are raised only to a higher tier.".to_string()));
    assert_eq!(db.call(|db| rules::promote(db, ada, barracks.id, 1, 4, 10)), Err(Refusal::NeedsOther(Kind::Barracks, 17)));
    assert_eq!(db.call(|db| rules::promote(db, ada, barracks.id, 1, 6, 10)), Err(Refusal::NoSuchTroops));
    assert_eq!(db.call(|db| rules::promote(db, ada, barracks.id, 1, 3, 101)), Err(Refusal::NotEnoughTroops(Troops::Spearmen, 1, 100)));
    assert_eq!(db.call(|db| rules::promote(db, ada, barracks.id, 1, 3, 0)), Err(Refusal::NothingAsked));

    // Raised: paid the third tier's cost beyond the first's, waited its time beyond, out of the ranks meanwhile.
    let before = goods(&db, city.id);
    let power = rules::city_of(&db, ada).unwrap().power;
    let job = db.call(|db| rules::promote(db, ada, barracks.id, 1, 3, 40)).unwrap();
    let (first, third) = (Troops::Spearmen.soldier(1), Troops::Spearmen.soldier(3));
    assert_eq!(before.minus(goods(&db, city.id)), third.cost.minus(first.cost).times(40));
    assert_eq!((job.kind, job.level, job.amount, job.ends - job.started), (Job::TRAIN, 3, 40, 40 * (30 - 8)));
    assert_eq!(rules::troop(&db, city.id, Troops::Spearmen, 1).ready, 60);
    assert_eq!(rules::troop(&db, city.id, Troops::Spearmen, 3).ready, 0);
    assert_eq!(rules::city_of(&db, ada).unwrap().power, power - 40, "out of the ranks, they count for nothing");
    assert_eq!(db.call(|db| rules::promote(db, ada, barracks.id, 1, 2, 10)), Err(Refusal::AlreadyTraining(Kind::Barracks)));
    assert_eq!(db.call(|db| rules::train(db, ada, barracks.id, 1, 10)), Err(Refusal::AlreadyTraining(Kind::Barracks)));

    // Done: they stand ready at the third tier, and the city is the stronger for it.
    wait(&mut db, 40 * 22);
    assert_eq!(rules::troop(&db, city.id, Troops::Spearmen, 3).ready, 40);
    assert_eq!(rules::troop(&db, city.id, Troops::Spearmen, 1).ready, 60);
    assert_eq!(rules::city_of(&db, ada).unwrap().power, power + 40 * (3 - 1));

    // Only in her own city, and only troops ready: not those out on the road.
    let bryn = db.call(|db| rules::join(db, "Bryn")).unwrap().id;
    assert_eq!(db.call(|db| rules::promote(db, bryn, barracks.id, 1, 2, 10)), Err(Refusal::NotYours));
}
