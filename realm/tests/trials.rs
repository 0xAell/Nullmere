//! The realm's contests over a store kept in memory: when the Long Hunt,
//! the Harvest Moon and the Muster run, overlapping each week, what scores
//! in each, and what their prizes give.

use realm::catalog::{self, Building as Kind, Contest, Goods, Item, Troops};
use realm::hex::Hex;
use realm::land;
use realm::rows::{Barrow, Building, City, March, Prize, Site, Stock, Tally, Trial, Troop};
use realm::rules::{self, Asked, Refusal};
use realm::store::{Mem, Seconds, Table};

const START: Seconds = 3_000_000;
const SEED: u64 = 7;
const RADIUS: u32 = 48;

fn wait(db: &mut Mem, seconds: Seconds) {
    let to = db.clock + seconds;
    db.advance(to, |db, timer| rules::fire(db, timer));
}

/// A realm with one player whose Keep stands at its eighth level, with
/// soldiers enough for any low barrow.
fn armed() -> (Mem, u64, City) {
    let mut db = Mem::new(START, 5);
    rules::open(&mut db, SEED, 1, RADIUS);
    let player = db.call(|db| rules::join(db, "Ada")).unwrap().id;
    let mut city = rules::city_of(&db, player).unwrap();
    city.keep = 8;
    db.update(city.clone());
    let mut keep = rules::building_of(&db, city.id, Kind::Keep).unwrap();
    keep.level = 8;
    db.update(keep);
    rules::keep_troop(&mut db, Troop { id: Troop::key(city.id, Troops::Spearmen as u8, 1), city: city.id, kind: Troops::Spearmen as u8, tier: 1, ready: 6_000, wounded: 0 });
    (db, player, city)
}

fn stock(db: &Mem, city: u64) -> Goods {
    rules::goods(&rules::grown(&Table::<Stock>::get(db, city).unwrap(), db.clock))
}

/// Sends two thousand spears against the nearest barrow a way leads to,
/// set to a level, and waits until they are home.
fn clear(db: &mut Mem, player: u64, city: &City, level: u32) {
    let from = Hex::unpacked(city.hex);
    let mut barrows = Table::<Barrow>::all(db);
    barrows.sort_by_key(|barrow| (Hex::unpacked(barrow.hex).distance(from), barrow.id));
    let mut barrow = barrows.into_iter().find(|barrow| land::way(SEED, RADIUS, from, Hex::unpacked(barrow.hex)).is_some()).expect("a barrow within reach");
    barrow.level = level;
    db.update(barrow.clone());
    let asked = vec![Asked { kind: Troops::Spearmen as u8, tier: 1, count: 2_000 }];
    db.call(|db| rules::send(db, player, Hex::unpacked(barrow.hex), March::HUNT, &asked)).unwrap();
    while !Table::<March>::by(db, 0, player).is_empty() {
        wait(db, 300);
    }
    assert!(Table::<Barrow>::get(db, barrow.id).is_none(), "the barrow was cleared");
}

/// Gives a player so many points in the hunt's round as it now is.
fn score(db: &mut Mem, player: u64, points: u64) {
    let mut row = rules::tally_of(db, player, Contest::Hunt);
    row.points = points;
    if Table::<Tally>::get(db, row.id).is_some() {
        db.update(row);
    } else {
        db.insert(row);
    }
}

#[test]
fn the_contests_and_their_prizes_are_written_out_for_clients() {
    let (db, _, _) = armed();
    let trials = Table::<Trial>::all(&db);
    assert_eq!(
        trials.iter().map(|trial| (trial.id, trial.name.as_str(), trial.every, trial.lasts, trial.opens)).collect::<Vec<_>>(),
        vec![(1, "The Long Hunt", 7, 3, 0), (2, "The Harvest Moon", 7, 3, 2), (3, "The Call to Arms", 7, 3, 4)]
    );
    assert!(trials.iter().all(|trial| trial.words.ends_with('.')));
    let all = Table::<Prize>::all(&db);
    assert_eq!(all.len(), 9, "three prizes a contest");
    let prizes: Vec<Prize> = all.into_iter().filter(|prize| prize.trial == 1).collect();
    assert_eq!(prizes.iter().map(|prize| (prize.trial, prize.place, prize.points)).collect::<Vec<_>>(), vec![(1, 1, 100), (1, 2, 400), (1, 3, 1_000)]);
    assert!(prizes.windows(2).all(|pair| pair[0].grain < pair[1].grain), "a prize that asks more gives more");
    assert_eq!((prizes[0].brief_hastes, prizes[1].hour_hastes, prizes[2].long_hastes), (2, 1, 1));
}

#[test]
fn the_hunt_runs_the_first_three_days_of_every_seven() {
    let (mut db, _, _) = armed();
    let mut seen = Vec::new();
    for _ in 0..15 {
        seen.push(rules::round_of(&db, Contest::Hunt));
        wait(&mut db, catalog::DAY);
    }
    let running: Vec<bool> = seen.iter().map(|(_, on)| *on).collect();
    assert_eq!(running, [true, true, true, false, false, false, false, true, true, true, false, false, false, false, true]);
    assert_eq!(seen.iter().map(|(round, _)| *round).collect::<Vec<_>>(), [0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 2]);
}

#[test]
fn a_barrow_cleared_scores_ten_for_each_of_its_levels_while_the_hunt_runs_and_nothing_after() {
    let (mut db, player, city) = armed();
    assert_eq!(rules::tally_of(&db, player, Contest::Hunt).points, 0);
    clear(&mut db, player, &city, 1);
    assert_eq!(rules::tally_of(&db, player, Contest::Hunt).points, 10);
    clear(&mut db, player, &city, 2);
    assert_eq!(rules::tally_of(&db, player, Contest::Hunt).points, 30);

    // The fourth day: the hunt is over until it comes round again.
    wait(&mut db, 3 * catalog::DAY);
    assert_eq!(rules::round_of(&db, Contest::Hunt), (0, false));
    clear(&mut db, player, &city, 1);
    assert_eq!(rules::tally_of(&db, player, Contest::Hunt).points, 30, "what was scored is kept, and nothing is added");
}

#[test]
fn a_prize_is_claimed_once_a_round_for_the_points_it_asks() {
    let (mut db, player, city) = armed();
    assert_eq!(db.call(|db| rules::claim_prize(db, player, 1, 1)), Err(Refusal::PrizeNotEarned(100)));
    assert_eq!(Refusal::PrizeNotEarned(1_000).to_string(), "That prize is for 1,000 points.");
    for (contest, place) in [(1, 0), (1, 4), (4, 1), (0, 1), (1, 200)] {
        assert_eq!(db.call(|db| rules::claim_prize(db, player, contest, place)), Err(Refusal::NoSuchPrize), "{contest}/{place}");
    }

    score(&mut db, player, 450);
    let before = stock(&db, city.id);
    let first = db.call(|db| rules::claim_prize(db, player, 1, 1)).unwrap();
    let second = db.call(|db| rules::claim_prize(db, player, 1, 2)).unwrap();
    assert_eq!(stock(&db, city.id), before.plus(first).plus(second), "their goods are in the stock");
    assert_eq!((rules::held(&db, player, Item::Haste5), rules::held(&db, player, Item::Haste60), rules::held(&db, player, Item::Haste480)), (2, 1, 0), "and their hastes in the satchel");
    assert_eq!(db.call(|db| rules::claim_prize(db, player, 1, 1)), Err(Refusal::PrizeClaimed));
    assert_eq!(db.call(|db| rules::claim_prize(db, player, 1, 3)), Err(Refusal::PrizeNotEarned(1_000)));

    // After the hunt's days, and until it comes round again, what was earned can still be claimed.
    score(&mut db, player, 1_000);
    wait(&mut db, 5 * catalog::DAY);
    assert_eq!(rules::round_of(&db, Contest::Hunt), (0, false));
    db.call(|db| rules::claim_prize(db, player, 1, 3)).unwrap();
    assert_eq!(rules::held(&db, player, Item::Haste480), 1);
}

#[test]
fn when_the_hunt_comes_round_again_it_begins_afresh() {
    let (mut db, player, city) = armed();
    score(&mut db, player, 450);
    db.call(|db| rules::claim_prize(db, player, 1, 1)).unwrap();
    wait(&mut db, 7 * catalog::DAY + 60);
    assert_eq!(rules::round_of(&db, Contest::Hunt), (1, true));
    let fresh = rules::tally_of(&db, player, Contest::Hunt);
    assert_eq!((fresh.round, fresh.points, fresh.claimed), (1, 0, 0));
    assert_eq!(db.call(|db| rules::claim_prize(db, player, 1, 2)), Err(Refusal::PrizeNotEarned(400)), "last round's points are last round's");
    clear(&mut db, player, &city, 1);
    let kept = Table::<Tally>::get(&db, Tally::key(player, Contest::Hunt as u8)).unwrap();
    assert_eq!((kept.round, kept.points, kept.claimed), (1, 10, 0));
}

#[test]
fn the_weeks_contests_overlap_and_the_harvest_and_the_muster_score_their_own() {
    let (mut db, player, city) = armed();
    // The days each runs, a week from the realm's opening: each opens on the last day of the one before.
    let mut days = Vec::new();
    for _ in 0..7 {
        days.push(Contest::ALL.map(|contest| rules::round_of(&db, contest).1));
        wait(&mut db, catalog::DAY);
    }
    assert_eq!(days.iter().map(|on| on[0]).collect::<Vec<_>>(), [true, true, true, false, false, false, false], "the hunt");
    assert_eq!(days.iter().map(|on| on[1]).collect::<Vec<_>>(), [false, false, true, true, true, false, false], "the harvest");
    assert_eq!(days.iter().map(|on| on[2]).collect::<Vec<_>>(), [false, false, false, false, true, true, true], "the muster");

    // The next week's third day: the harvest runs. An army gathers and comes home: a point for each hundred it carries.
    wait(&mut db, 2 * catalog::DAY);
    assert!(rules::round_of(&db, Contest::Harvest).1);
    let from = Hex::unpacked(city.hex);
    let mut sites = Table::<Site>::all(&db);
    sites.sort_by_key(|site| (Hex::unpacked(site.hex).distance(from), site.id));
    let site = sites.into_iter().find(|site| land::way(SEED, RADIUS, from, Hex::unpacked(site.hex)).is_some()).unwrap();
    let before = stock(&db, city.id);
    db.call(|db| rules::send(db, player, Hex::unpacked(site.hex), March::GATHER, &[Asked { kind: Troops::Spearmen as u8, tier: 1, count: 200 }])).unwrap();
    while !Table::<March>::by(&db, 0, player).is_empty() {
        wait(&mut db, 300);
    }
    let brought = stock(&db, city.id).parts().iter().sum::<u64>() - before.parts().iter().sum::<u64>();
    assert!(brought >= 100, "something was brought home: {brought}");
    let harvested = rules::tally_of(&db, player, Contest::Harvest).points;
    assert!(harvested >= brought / 100 - 1 && harvested <= brought / 100 + 1, "{harvested} points for {brought} goods");
    assert_eq!(rules::tally_of(&db, player, Contest::Arms).points, 0);

    // Two days on, the muster runs: soldiers set to training score their number times their tier.
    wait(&mut db, 2 * catalog::DAY);
    assert!(rules::round_of(&db, Contest::Arms).1);
    let barracks = db.insert(Building { id: 0, city: city.id, kind: Kind::Barracks as u8, level: 5 });
    let mut row = rules::grown(&Table::<Stock>::get(&db, city.id).unwrap(), db.clock);
    (row.grain, row.timber, row.stone) = (500_000, 500_000, 500_000);
    db.update(row);
    db.call(|db| rules::train(db, player, barracks.id, 1, 50)).unwrap();
    assert_eq!(rules::tally_of(&db, player, Contest::Arms).points, 50);
}
