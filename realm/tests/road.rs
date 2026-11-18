//! The Barrow Road over a store kept in memory: its stages written as the
//! realm opens, walked with soldiers of the player's city, none lost, a
//! stage cleared once giving goods and every fifth an item, and the rest
//! between walks.

use realm::catalog::{self, Goods, Item, Troops};
use realm::rows::{City, Commander, Report, Road, Stage, Stock, Troop};
use realm::rules::{self, Asked, Refusal};
use realm::store::{Mem, Seconds, Table};

const START: Seconds = 3_000_000;

fn wait(db: &mut Mem, seconds: Seconds) {
    let to = db.clock + seconds;
    db.advance(to, |db, timer| rules::fire(db, timer));
}

/// A realm with one player, soldiers of these kinds and tiers ready in
/// their city, and their one commander.
fn walker(ready: &[(Troops, u32, u64)]) -> (Mem, u64, City, Commander) {
    let mut db = Mem::new(START, 5);
    rules::open(&mut db, 7, 1, 48);
    let player = db.call(|db| rules::join(db, "Ada")).unwrap().id;
    let city = rules::city_of(&db, player).unwrap();
    for (kind, tier, count) in ready {
        rules::keep_troop(&mut db, Troop { id: Troop::key(city.id, *kind as u8, *tier), city: city.id, kind: *kind as u8, tier: *tier, ready: *count, wounded: 0 });
    }
    let commander = rules::commanders_of(&db, player).remove(0);
    (db, player, city, commander)
}

fn asked(kind: Troops, tier: u32, count: u64) -> Vec<Asked> {
    vec![Asked { kind: kind as u8, tier, count }]
}

fn stock(db: &Mem, city: u64) -> Goods {
    let stock = Table::<Stock>::get(db, city).unwrap();
    Goods::of(stock.grain, stock.timber, stock.stone, stock.moonsalt)
}

fn last_report(db: &Mem, player: u64) -> Report {
    Table::<Report>::by(db, 0, player).into_iter().filter(|report| report.kind == Report::ROAD).max_by_key(|report| report.id).unwrap()
}

/// The kind that bests a host leaning on another.
fn counter(leaning: Troops) -> Troops {
    match leaning {
        Troops::Riders => Troops::Spearmen,
        Troops::Spearmen => Troops::Archers,
        _ => Troops::Riders,
    }
}

#[test]
fn the_road_s_stages_are_written_as_the_realm_opens_each_leaning_on_a_kind() {
    let (db, _, _, _) = walker(&[]);
    let stages = Table::<Stage>::all(&db);
    assert_eq!(stages.len() as u64, catalog::ROAD_STAGES);
    let first = Table::<Stage>::get(&db, 1).unwrap();
    assert_eq!((first.tier, first.spearmen, first.archers, first.riders, first.most), (1, 15, 0, 21, 36));
    assert_eq!((first.grain, first.timber, first.stone, first.moonsalt, first.item), (1_200, 1_200, 500, 0, 0));
    let fifth = Table::<Stage>::get(&db, 5).unwrap();
    assert_eq!((fifth.item, fifth.items), (Item::Haste60 as u8, 2));
    let last = Table::<Stage>::get(&db, catalog::ROAD_STAGES).unwrap();
    assert_eq!((last.tier, last.most, last.moonsalt, last.item, last.items), (5, 6_300, 1_200, Item::Summons as u8, 2));
    // The kind each host leans on turns from stage to stage.
    let leaning: Vec<Troops> = (1..=6).map(|stage| catalog::road_host(stage).0[0].kind).collect();
    assert_eq!(leaning, [Troops::Spearmen, Troops::Archers, Troops::Riders, Troops::Spearmen, Troops::Archers, Troops::Riders].map(counter_of));
    for stage in &stages {
        assert_eq!(stage.spearmen + stage.archers + stage.riders, stage.most, "stage {}", stage.id);
    }
}

/// The kind a counter bests.
fn counter_of(kind: Troops) -> Troops {
    match kind {
        Troops::Spearmen => Troops::Riders,
        Troops::Archers => Troops::Spearmen,
        _ => Troops::Archers,
    }
}

#[test]
fn soldiers_that_best_a_stage_s_host_clear_it_and_none_are_lost() {
    let (mut db, ada, city, _) = walker(&[(Troops::Spearmen, 1, 36), (Troops::Archers, 1, 60)]);
    let before = stock(&db, city.id);
    assert_eq!(db.call(|db| rules::walk_road(db, ada, &asked(Troops::Spearmen, 1, 36), 0)), Ok((true, 1)));
    assert_eq!(rules::road_of(&db, ada).cleared, 1);
    assert_eq!(rules::troop(&db, city.id, Troops::Spearmen, 1).ready, 36, "none lost");
    let gained = stock(&db, city.id);
    assert_eq!((gained.grain - before.grain, gained.timber - before.timber, gained.stone - before.stone), (1_200, 1_200, 500));
    let told = last_report(&db, ada);
    assert_eq!((told.won, told.foe, told.fought, told.stood, told.fell, told.dead, told.grain), (true, 1, 36, 36, 36, 0, 1_200));
    assert_eq!(told.words, "Your soldiers cleared stage 1 of the Barrow Road: all 36 of its Unquiet fell, and none of yours were lost. It gave 1,200 grain, 1,200 timber and 500 stone.");

    // They rest a minute between walks.
    assert_eq!(db.call(|db| rules::walk_road(db, ada, &asked(Troops::Archers, 1, 36), 0)), Err(Refusal::RoadResting(60)));
    wait(&mut db, 61);
    // The second stage's host leans on spearmen: spearmen are turned back,
    // and lose no one; the stage stands as it stood.
    let walked = rules::road_of(&db, ada).walked;
    assert_eq!(db.call(|db| rules::walk_road(db, ada, &asked(Troops::Spearmen, 1, 36), 0)), Ok((false, 2)));
    assert_eq!(rules::troop(&db, city.id, Troops::Spearmen, 1).ready, 36);
    let road = rules::road_of(&db, ada);
    assert_eq!(road.cleared, 1);
    assert!(road.walked > walked, "a walk turned back is a walk");
    let told = last_report(&db, ada);
    assert!(!told.won);
    assert!(told.words.starts_with("Your soldiers were turned back at stage 2 of the Barrow Road: "), "{}", told.words);
    assert!(told.words.ends_with(" Unquiet still stood. None of yours were lost; its host leans on spearmen."), "{}", told.words);
    assert_eq!(told.grain, 0);
    wait(&mut db, 61);
    // No more than its host has may go; nor more than stand ready; nor none.
    assert_eq!(db.call(|db| rules::walk_road(db, ada, &[Asked { kind: 1, tier: 1, count: 36 }, Asked { kind: 2, tier: 1, count: 40 }, Asked { kind: 2, tier: 1, count: 9 }], 0)), Err(Refusal::RoadNarrow(84)));
    assert_eq!(db.call(|db| rules::walk_road(db, ada, &asked(Troops::Archers, 1, 70), 0)), Err(Refusal::NotEnoughTroops(Troops::Archers, 1, 60)));
    assert_eq!(db.call(|db| rules::walk_road(db, ada, &[], 0)), Err(Refusal::NothingAsked));
    assert_eq!(db.call(|db| rules::walk_road(db, ada, &asked(Troops::Archers, 1, 36), 999)), Err(Refusal::NoSuchCommander));
    assert_eq!(rules::road_of(&db, ada).cleared, 1, "nothing refused walked it");
}

#[test]
fn the_whole_road_is_walked_by_those_who_bring_what_bests_each_host_and_a_commander_sees_war() {
    let all: Vec<(Troops, u32, u64)> = [Troops::Spearmen, Troops::Archers, Troops::Riders].map(|kind| (kind, 5, 7_000)).to_vec();
    let (mut db, ada, _, commander) = walker(&all);
    let hastes = rules::held(&db, ada, Item::Haste60);
    for stage in 1..=catalog::ROAD_STAGES {
        let (host, most) = catalog::road_host(stage);
        let walked = db.call(|db| rules::walk_road(db, ada, &asked(counter(host[0].kind), 5, most), commander.id));
        assert_eq!(walked, Ok((true, stage)), "{}", last_report(&db, ada).words);
        wait(&mut db, 61);
        if stage == 5 {
            assert_eq!(rules::held(&db, ada, Item::Haste60), hastes + 2, "the fifth stage gives two hours' haste");
            let words = last_report(&db, ada).words;
            assert!(words.ends_with(&format!(", and 2 × An hour's haste. {} led them.", commander.name)), "{words}");
        }
    }
    let led = Table::<Commander>::get(&db, commander.id).unwrap();
    assert!(led.level > commander.level, "the commander who led them all has seen war: level {}", led.level);
    assert!(rules::held(&db, ada, Item::Summons) >= 3, "the twenty-fifth and the last give summons");
    assert_eq!(db.call(|db| rules::walk_road(db, ada, &asked(Troops::Spearmen, 5, 10), 0)), Err(Refusal::RoadWalked));
    assert_eq!(Table::<Road>::get(&db, ada).unwrap().cleared, catalog::ROAD_STAGES);
}

#[test]
fn a_commander_out_with_an_army_does_not_walk_the_road() {
    let (mut db, ada, _, commander) = walker(&[(Troops::Spearmen, 1, 36)]);
    let mut away = Table::<Commander>::get(&db, commander.id).unwrap();
    away.march = 77;
    db.update(away);
    assert_eq!(db.call(|db| rules::walk_road(db, ada, &asked(Troops::Spearmen, 1, 36), commander.id)), Err(Refusal::CommanderAway(commander.name.clone())));
    assert!(Table::<Road>::get(&db, ada).is_none());
}

#[test]
fn a_commander_held_prisoner_does_not_walk_the_road() {
    let (mut db, ada, _, commander) = walker(&[(Troops::Spearmen, 1, 36)]);
    let mut held = Table::<Commander>::get(&db, commander.id).unwrap();
    held.march = rules::HELD;
    db.update(held);
    assert_eq!(db.call(|db| rules::walk_road(db, ada, &asked(Troops::Spearmen, 1, 36), commander.id)), Err(Refusal::HeldPrisoner(commander.name.clone())));
}
