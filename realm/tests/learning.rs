//! What an alliance learns together, over a store kept in memory: members
//! giving toward a topic's next level, only what it still needs taken,
//! the study on its timer, every member having it after, and none of it
//! for one who leaves or once the alliance ends.

use realm::catalog::{self, Building as Kind, Goods, Topic, TOP_ALLIANCE_STUDY};
use realm::rows::{Building, City, Learning, Report, Stock};
use realm::rules::{self, Refusal, TIMER_LEARNING};
use realm::store::{Mem, Seconds, Table};

const START: Seconds = 3_000_000;
const SEED: u64 = 7;
const RADIUS: u32 = 48;

fn wait(db: &mut Mem, seconds: Seconds) {
    let to = db.clock + seconds;
    db.advance(to, rules::fire);
}

/// A realm of players of these names, each with an Embassy and goods
/// enough; all but those named in `apart` in one alliance, founded by the
/// first.
fn allies(names: &[&str], apart: &[&str]) -> (Mem, Vec<u64>, Vec<City>, u64) {
    let mut db = Mem::new(START, 5);
    rules::open(&mut db, SEED, 1, RADIUS);
    let players: Vec<u64> = names.iter().map(|name| db.call(|db| rules::join(db, name)).unwrap().id).collect();
    let mut cities = Vec::new();
    for player in &players {
        let city = rules::city_of(&db, *player).unwrap();
        db.insert(Building { id: 0, city: city.id, kind: Kind::Embassy as u8, level: 1 });
        let mut stock = rules::grown(&Table::<Stock>::get(&db, city.id).unwrap(), db.clock);
        (stock.grain, stock.timber, stock.stone, stock.moonsalt) = (2_000_000, 2_000_000, 2_000_000, 1_000);
        db.update(stock);
        cities.push(city);
    }
    let alliance = db.call(|db| rules::found_alliance(db, players[0], "Keepers of the Mere", "MERE")).unwrap();
    for (name, player) in names.iter().zip(&players).skip(1) {
        if !apart.contains(name) {
            db.call(|db| rules::join_alliance(db, *player, alliance.id)).unwrap();
        }
    }
    wait(&mut db, 30);
    (db, players, cities, alliance.id)
}

fn goods_of(db: &Mem, city: &City) -> Goods {
    rules::goods(&rules::grown(&Table::<Stock>::get(db, city.id).unwrap(), db.clock))
}

fn hourly_grain(db: &Mem, city: &City) -> u64 {
    Table::<Stock>::get(db, city.id).unwrap().grain_hourly
}

#[test]
fn members_give_toward_a_topic_and_the_alliance_learns_it_for_every_member() {
    let (mut db, players, cities, mere) = allies(&["Ada", "Bryn", "Cole"], &["Cole"]);
    let (ada, bryn, cole) = (players[0], players[1], players[2]);
    let tillage = Topic::Tillage as u8;

    assert_eq!(db.call(|db| rules::give_to_learning(db, cole, tillage, Goods::of(10, 10, 10, 0))), Err(Refusal::NotAllied));
    assert_eq!(db.call(|db| rules::give_to_learning(db, ada, 99, Goods::of(10, 10, 10, 0))), Err(Refusal::NoSuchTopic));
    assert_eq!(db.call(|db| rules::give_to_learning(db, ada, tillage, Goods::of(0, 0, 0, 500))), Err(Refusal::NothingAsked), "moonsalt is not asked for");

    // Ada gives most of the first level; Bryn the rest, and only what is still needed is taken.
    let cost = catalog::alliance_study_cost(1);
    assert_eq!(cost, Goods::of(100_000, 100_000, 100_000, 0));
    let before = goods_of(&db, &cities[0]);
    let learning = db.call(|db| rules::give_to_learning(db, ada, tillage, Goods::of(60_000, 60_000, 60_000, 0))).unwrap();
    assert_eq!((learning.alliance, learning.level, learning.grain, learning.rises_at), (mere, 0, 60_000, 0));
    assert_eq!(goods_of(&db, &cities[0]), before.minus(Goods::of(60_000, 60_000, 60_000, 0)));
    let before = goods_of(&db, &cities[1]);
    let learning = db.call(|db| rules::give_to_learning(db, bryn, tillage, Goods::of(60_000, 60_000, 60_000, 0))).unwrap();
    assert_eq!(goods_of(&db, &cities[1]), before.minus(Goods::of(40_000, 40_000, 40_000, 0)), "only what was still needed");
    // Paid for, it is studied: two hours for the first level, and nothing more is given meanwhile.
    assert_eq!((learning.level, learning.grain, learning.rises_at), (0, 0, db.clock + catalog::alliance_study_seconds(1)));
    assert_eq!(db.timers.values().filter(|timer| timer.kind == TIMER_LEARNING).count(), 1);
    wait(&mut db, 3);
    assert_eq!(db.call(|db| rules::give_to_learning(db, ada, tillage, Goods::of(10, 10, 10, 0))), Err(Refusal::StudiedTogether));

    // Learnt: every member's farms bring in more, as one more level of Tillage in their own city; not the one outside.
    let grain = [hourly_grain(&db, &cities[0]), hourly_grain(&db, &cities[1]), hourly_grain(&db, &cities[2])];
    assert_eq!(rules::boost(&db, cities[0].id, Topic::Tillage), 0);
    wait(&mut db, catalog::alliance_study_seconds(1));
    let learnt = Table::<Learning>::get(&db, Learning::key(mere, tillage)).unwrap();
    assert_eq!((learnt.level, learnt.rises_at, learnt.timer), (1, 0, 0));
    for city in &cities[..2] {
        assert_eq!(rules::boost(&db, city.id, Topic::Tillage), Topic::Tillage.each());
    }
    assert_eq!(rules::boost(&db, cities[2].id, Topic::Tillage), 0);
    assert!(hourly_grain(&db, &cities[0]) > grain[0] && hourly_grain(&db, &cities[1]) > grain[1], "members' farms bring in more");
    assert_eq!(hourly_grain(&db, &cities[2]), grain[2]);
    for player in [ada, bryn] {
        let told: Vec<Report> = Table::<Report>::by(&db, 0, player).into_iter().filter(|report| report.kind == Report::LEARNING).collect();
        assert_eq!(told.len(), 1);
        assert_eq!(told[0].words, "Your alliance has learnt Tillage to level 1. Every member has it as their own.");
    }

    // The next level asks more, and goods it has enough of already are not taken.
    assert_eq!(catalog::alliance_study_cost(2), Goods::of(400_000, 400_000, 400_000, 0));
    db.call(|db| rules::give_to_learning(db, ada, tillage, Goods::of(400_000, 0, 0, 0))).unwrap();
    assert_eq!(db.call(|db| rules::give_to_learning(db, ada, tillage, Goods::of(10, 0, 0, 0))), Err(Refusal::NothingNeeded));

    // One who leaves has none of it.
    wait(&mut db, 10);
    db.call(|db| rules::leave_alliance(db, bryn)).unwrap();
    assert_eq!(rules::boost(&db, cities[1].id, Topic::Tillage), 0);
    assert_eq!(hourly_grain(&db, &cities[1]), grain[1]);

    // Five levels at most.
    let mut row = Table::<Learning>::get(&db, Learning::key(mere, tillage)).unwrap();
    row.level = TOP_ALLIANCE_STUDY;
    db.update(row);
    assert_eq!(db.call(|db| rules::give_to_learning(db, ada, tillage, Goods::of(10, 10, 10, 0))), Err(Refusal::LearntTogether));
}

#[test]
fn an_alliance_ended_forgets_what_it_learnt_and_its_study_with_it() {
    let (mut db, players, cities, mere) = allies(&["Ada"], &[]);
    let ada = players[0];
    let marching = Topic::Marching as u8;
    db.call(|db| rules::give_to_learning(db, ada, marching, catalog::alliance_study_cost(1))).unwrap();
    wait(&mut db, catalog::alliance_study_seconds(1));
    assert_eq!(rules::boost(&db, cities[0].id, Topic::Marching), Topic::Marching.each());
    db.call(|db| rules::give_to_learning(db, ada, Topic::Drill as u8, catalog::alliance_study_cost(1))).unwrap();
    wait(&mut db, 10);

    db.call(|db| rules::leave_alliance(db, ada)).unwrap();
    assert!(Table::<Learning>::by(&db, 0, mere).is_empty());
    assert!(db.timers.values().all(|timer| timer.kind != TIMER_LEARNING), "the study under way stops");
    assert_eq!(rules::boost(&db, cities[0].id, Topic::Marching), 0);
    wait(&mut db, catalog::alliance_study_seconds(1));
}
