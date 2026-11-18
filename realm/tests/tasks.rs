//! A player's first tasks over a store kept in memory: what each asks,
//! when it is done, and what claiming it gives.

use realm::catalog::{self, Building as Kind, Goal, Goods, Item, Troops};
use realm::rows::{Building, City, Hunt, Progress, Stock, Task, Troop};
use realm::rules::{self, Refusal};
use realm::store::{Mem, Seconds, Table};

const START: Seconds = 3_000_000;

fn joined() -> (Mem, u64, City) {
    let mut db = Mem::new(START, 5);
    rules::open(&mut db, 7, 1, 48);
    let player = db.call(|db| rules::join(db, "Ada")).unwrap().id;
    let city = rules::city_of(&db, player).unwrap();
    (db, player, city)
}

fn stock(db: &Mem, city: u64) -> Goods {
    rules::goods(&rules::grown(&Table::<Stock>::get(db, city).unwrap(), db.clock))
}

/// Sets one of a city's buildings to a level, raising it from nothing
/// where the city has none.
fn raise(db: &mut Mem, city: u64, kind: Kind, level: u32) {
    match rules::building_of(db, city, kind) {
        Some(mut building) => {
            building.level = level;
            db.update(building);
        }
        None => {
            db.insert(Building { id: 0, city, kind: kind as u8, level });
        }
    }
    if kind == Kind::Keep {
        let mut row = Table::<City>::get(db, city).unwrap();
        row.keep = level;
        db.update(row);
    }
}

#[test]
fn the_tasks_are_written_out_in_their_order_and_in_plain_words() {
    let (db, player, _) = joined();
    let written = Table::<Task>::all(&db);
    let tasks = catalog::tasks();
    assert_eq!(written.len(), tasks.len());
    assert_eq!(written.len(), 40);
    for (index, task) in written.iter().enumerate() {
        let (goal, gives) = tasks[index];
        assert_eq!(task.step, index as u64 + 1);
        assert_eq!((task.goal, task.amount, task.level), goal.numbers());
        assert_eq!(task.words, goal.words());
        assert_eq!(Goods::of(task.grain, task.timber, task.stone, task.moonsalt), gives);
        assert!(!gives.is_none(), "every task gives something");
        // What it gives besides, hastes and tomes, written out as it is given.
        let items = catalog::task_items(task.step);
        let count = |item: Item| items.iter().filter(|(given, _)| *given == item).map(|(_, count)| count).sum::<u64>();
        assert_eq!((task.brief_hastes, task.hour_hastes, task.long_hastes, task.tomes),
                   (count(Item::Haste5), count(Item::Haste60), count(Item::Haste480), count(Item::Tome)), "step {}", task.step);
        assert!(items.iter().all(|(item, count)| *count > 0 && [Item::Haste5, Item::Haste60, Item::Haste480, Item::Tome].contains(item)));
    }
    // Hastes and tomes come with most of the tasks after the first, the
    // longer hastes as the Keep rises; none past the last.
    let giving = (1..=tasks.len() as u64).filter(|step| !catalog::task_items(*step).is_empty()).count();
    assert!(giving >= tasks.len() / 2, "{giving} of {} tasks give items", tasks.len());
    assert!(catalog::task_items(1).is_empty() && catalog::task_items(tasks.len() as u64 + 1).is_empty());
    assert_eq!(written[18].words, "Raise your Keep to level 5.");
    assert_eq!(written[18].long_hastes, 1);
    assert_eq!(written[0].words, "Raise your Keep to level 2.");
    assert_eq!(written[1].words, "Build a Barracks.");
    assert_eq!(Goal::Raised(Kind::Embassy, 1).words(), "Build an Embassy.");
    assert_eq!(Goal::Raised(Kind::Range, 1).words(), "Build an Archery Range.");
    assert_eq!(Goal::Found(1).words(), "Send a scout to find what a cairn holds.");
    assert_eq!(Goal::Found(3).words(), "Have your scouts find what 3 cairns hold.");
    assert_eq!(Goal::Raised(Kind::Farm, 2).words(), "Raise your Farm to level 2.");
    assert_eq!(Goal::Soldiers(1_500).words(), "Have 1,500 soldiers.");
    assert_eq!(Goal::Cleared(3).words(), "Clear a level 3 barrow of the Unquiet.");
    assert_eq!(Goal::Allied.words(), "Join an alliance, or found one.");
    assert_eq!(Goal::Power(5_000).words(), "Reach 5,000 power.");
    assert_eq!([Goal::Keep(2), Goal::Raised(Kind::Wall, 3), Goal::Soldiers(20), Goal::Cleared(1), Goal::Allied, Goal::Power(9)].map(Goal::numbers),
               [(1, 2, 0), (2, 12, 3), (3, 20, 0), (4, 1, 0), (5, 0, 0), (6, 9, 0)]);
    // Nothing a task asks is out of reach when it is set: what it names
    // is open at the Keep level the tasks before it have asked for.
    let mut keep = 1;
    for (goal, _) in &tasks {
        match goal {
            Goal::Keep(level) => {
                assert_eq!(*level, keep + 1, "the Keep is asked up a level at a time");
                keep = *level;
            }
            Goal::Raised(building, level) => {
                assert!(building.opens_at() <= keep, "{} at Keep {keep}", building.name());
                assert!(*level <= keep);
            }
            _ => {}
        }
    }
    // A new player is on the first.
    assert_eq!(Table::<Progress>::get(&db, player), Some(Progress { player, step: 1 }));
}

#[test]
fn a_task_is_claimed_once_it_is_done() {
    let (mut db, player, city) = joined();
    // Not done: nothing is given, and the refusal says what is asked.
    let before = stock(&db, city.id);
    assert_eq!(db.call(|db| rules::claim_task(db, player)), Err(Refusal::TaskNotDone("Raise your Keep to level 2.".into())));
    assert_eq!(Refusal::TaskNotDone("Raise your Keep to level 2.".into()).to_string(), "Not done yet: Raise your Keep to level 2.");
    assert_eq!(stock(&db, city.id), before);
    assert_eq!(rules::progress_of(&db, player).step, 1);

    // Done: what it gives is in the stock, and the next is set.
    raise(&mut db, city.id, Kind::Keep, 2);
    assert_eq!(db.call(|db| rules::claim_task(db, player)), Ok(Goods::of(1_000, 1_000, 0, 0)));
    assert_eq!(stock(&db, city.id), before.plus(Goods::of(1_000, 1_000, 0, 0)));
    assert_eq!(rules::progress_of(&db, player).step, 2);
    // Not twice: the next is not done.
    assert_eq!(db.call(|db| rules::claim_task(db, player)), Err(Refusal::TaskNotDone("Build a Barracks.".into())));

    // A Barracks being raised stands at level 0, and is not yet built.
    raise(&mut db, city.id, Kind::Barracks, 0);
    assert!(!rules::met(&db, player, Goal::Raised(Kind::Barracks, 1)));
    raise(&mut db, city.id, Kind::Barracks, 1);
    // Its two five minutes' hastes go into the satchel with its goods.
    assert_eq!(rules::held(&db, player, Item::Haste5), 0);
    assert!(db.call(|db| rules::claim_task(db, player)).is_ok());
    assert_eq!(rules::held(&db, player, Item::Haste5), 2);

    // Soldiers count wherever they are: ready, wounded, or out with an army.
    assert!(!rules::met(&db, player, Goal::Soldiers(20)));
    rules::keep_troop(&mut db, Troop { id: Troop::key(city.id, 1, 1), city: city.id, kind: Troops::Spearmen as u8, tier: 1, ready: 12, wounded: 8 });
    assert!(rules::met(&db, player, Goal::Soldiers(20)));
    assert!(!rules::met(&db, player, Goal::Soldiers(21)));
    assert!(db.call(|db| rules::claim_task(db, player)).is_ok());
    assert_eq!(rules::held(&db, player, Item::Haste5), 5, "three more, beside the two kept");

    // A barrow cleared, an alliance joined, power reached.
    assert!(!rules::met(&db, player, Goal::Cleared(1)));
    let mut hunt = Table::<Hunt>::get(&db, player).unwrap();
    hunt.cleared = 2;
    db.update(hunt);
    assert!(rules::met(&db, player, Goal::Cleared(1)) && rules::met(&db, player, Goal::Cleared(2)) && !rules::met(&db, player, Goal::Cleared(3)));
    assert!(!rules::met(&db, player, Goal::Allied));
    raise(&mut db, city.id, Kind::Embassy, 1);
    db.advance(START + 30, |db, timer| rules::fire(db, timer));
    db.call(|db| rules::found_alliance(db, player, "Keepers", "MERE")).unwrap();
    assert!(rules::met(&db, player, Goal::Allied));
    // A cairn's hoard found by the player's scouts.
    assert!(!rules::met(&db, player, Goal::Found(1)));
    db.insert(realm::rows::Find { id: realm::rows::Find::key(player, 1), player, cairn: 1, at: START });
    assert!(rules::met(&db, player, Goal::Found(1)) && !rules::met(&db, player, Goal::Found(2)));
    let power = rules::city_of(&db, player).unwrap().power;
    assert!(rules::met(&db, player, Goal::Power(power)) && !rules::met(&db, player, Goal::Power(power + 1)));
    // Someone with no city has done nothing.
    assert!(!rules::met(&db, 99, Goal::Keep(1)));
    assert_eq!(db.call(|db| rules::claim_task(db, 99)), Err(Refusal::NotAPlayer));
}

#[test]
fn the_last_task_claimed_leaves_none() {
    let (mut db, player, city) = joined();
    let last = catalog::tasks().len() as u64;
    db.update(Progress { player, step: last });
    let mut row = Table::<City>::get(&db, city.id).unwrap();
    row.power = 80_000;
    db.update(row);
    let before = stock(&db, city.id);
    assert_eq!(db.call(|db| rules::claim_task(db, player)), Ok(Goods::of(60_000, 60_000, 30_000, 2_000)));
    let after = stock(&db, city.id);
    assert_eq!(after, before.plus(Goods::of(60_000, 60_000, 30_000, 2_000)), "given in full, though it overfill what the city holds");
    assert!(after.grain > Table::<Stock>::get(&db, city.id).unwrap().holds.min(after.grain - 1));
    assert_eq!(rules::progress_of(&db, player).step, last + 1);
    assert_eq!((rules::held(&db, player, Item::Haste480), rules::held(&db, player, Item::Tome)), (2, 8), "two eight hours' hastes and eight tomes besides");
    db.advance(START + 30, |db, timer| rules::fire(db, timer));
    assert_eq!(db.call(|db| rules::claim_task(db, player)), Err(Refusal::NoTasksLeft));
    assert_eq!(Refusal::NoTasksLeft.to_string(), "You have done every task there is.");
}
