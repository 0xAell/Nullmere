//! The realm's milestones over a store kept in memory: written as the
//! realm opens, counted from every player's feats, reached at their goal,
//! and claimed by each player once.

use realm::catalog::{self, Building as Kind, Feat, Item};
use realm::rows::{Building, Claim, Milestone, Stock};
use realm::rules::{self, Refusal};
use realm::store::{Mem, Seconds, Table};

const START: Seconds = 3_000_000;

fn wait(db: &mut Mem, seconds: Seconds) {
    let to = db.clock + seconds;
    db.advance(to, rules::fire);
}

fn milestone(db: &Mem, id: u64) -> Milestone {
    Table::<Milestone>::get(db, id).unwrap()
}

#[test]
fn the_realms_feats_count_toward_its_milestones() {
    let mut db = Mem::new(START, 5);
    rules::open(&mut db, 7, 1, 48);
    let written: Vec<(u64, u8, u64, u64, Seconds)> = {
        let mut all = Table::<Milestone>::all(&db);
        all.sort_by_key(|row| row.id);
        all.iter().map(|row| (row.id, row.feat, row.goal, row.done, row.reached)).collect()
    };
    assert_eq!(written, catalog::milestones().iter().map(|(id, feat, goal, ..)| (*id, *feat as u8, *goal, 0, 0)).collect::<Vec<_>>());
    let first = milestone(&db, 1);
    assert_eq!((first.words.as_str(), first.grain, first.item, first.items), ("Fifty cities founded in the realm.", 20_000, Item::Haste60 as u8, 1));

    // Every city founded counts toward both milestones of cities.
    let ada = db.call(|db| rules::join(db, "Ada")).unwrap().id;
    let bryn = db.call(|db| rules::join(db, "Bryn")).unwrap().id;
    assert_eq!((milestone(&db, 1).done, milestone(&db, 5).done, milestone(&db, 3).done), (2, 2, 0));

    // An alliance founded counts toward its own.
    let city = rules::city_of(&db, ada).unwrap();
    db.insert(Building { id: 0, city: city.id, kind: Kind::Embassy as u8, level: 1 });
    db.call(|db| rules::found_alliance(db, ada, "Keepers of the Mere", "MERE")).unwrap();
    assert_eq!(milestone(&db, 2).done, 1);
    assert_eq!(milestone(&db, 2).reached, 0);

    // Not reached: nothing to claim.
    assert_eq!(db.call(|db| rules::claim_milestone(db, bryn, 2)), Err(Refusal::MilestoneNotReached));
    assert_eq!(db.call(|db| rules::claim_milestone(db, bryn, 99)), Err(Refusal::NoSuchMilestone));
    assert_eq!(Refusal::MilestoneNotReached.to_string(), "The realm has not reached that milestone yet.");
    assert_eq!(Refusal::NoSuchMilestone.to_string(), "The realm has no such milestone.");
}

#[test]
fn a_milestone_reached_is_claimed_by_every_player_once() {
    let mut db = Mem::new(START, 5);
    rules::open(&mut db, 7, 1, 48);
    let ada = db.call(|db| rules::join(db, "Ada")).unwrap().id;
    let bryn = db.call(|db| rules::join(db, "Bryn")).unwrap().id;
    // Nine alliances more of the ten the second milestone asks, then the tenth.
    for _ in 0..8 {
        rules::feat_done(&mut db, Feat::Allied);
    }
    assert_eq!((milestone(&db, 2).done, milestone(&db, 2).reached), (8, 0));
    wait(&mut db, 60);
    rules::feat_done(&mut db, Feat::Allied);
    rules::feat_done(&mut db, Feat::Allied);
    assert_eq!((milestone(&db, 2).done, milestone(&db, 2).reached), (10, db.clock));
    // Reached, it counts no more.
    rules::feat_done(&mut db, Feat::Allied);
    assert_eq!(milestone(&db, 2).done, 10);

    let city = rules::city_of(&db, ada).unwrap();
    let before = rules::grown(&Table::<Stock>::get(&db, city.id).unwrap(), db.clock);
    let gives = db.call(|db| rules::claim_milestone(db, ada, 2)).unwrap();
    assert_eq!(gives, catalog::Goods::of(20_000, 20_000, 20_000, 0));
    let after = rules::grown(&Table::<Stock>::get(&db, city.id).unwrap(), db.clock);
    assert_eq!(after.timber, before.timber + 20_000);
    assert_eq!(rules::held(&db, ada, Item::Haste60), 2);
    assert!(Table::<Claim>::get(&db, Claim::key(ada, 2)).is_some());
    assert_eq!(db.call(|db| rules::claim_milestone(db, ada, 2)), Err(Refusal::MilestoneClaimed));
    assert_eq!(Refusal::MilestoneClaimed.to_string(), "You have claimed what that milestone gave.");
    // Bryn claims it too.
    assert!(db.call(|db| rules::claim_milestone(db, bryn, 2)).is_ok());
}
