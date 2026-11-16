//! Gifts within an alliance over a store kept in memory: as a member clears
//! a barrow, every other member is given goods, claimed within a day.

use realm::catalog::{Building as Kind, Goods};
use realm::rows::{Boon, Building, Stock};
use realm::rules::{self, Refusal};
use realm::store::{Mem, Seconds, Table};

const START: Seconds = 3_000_000;

fn wait(db: &mut Mem, seconds: Seconds) {
    let to = db.clock + seconds;
    db.advance(to, rules::fire);
}

/// Ada, Bryn and Cole in one alliance founded by Ada; Dara in none.
fn alliance() -> (Mem, [u64; 4]) {
    let mut db = Mem::new(START, 5);
    rules::open(&mut db, 7, 1, 48);
    let players = ["Ada", "Bryn", "Cole", "Dara"].map(|name| db.call(|db| rules::join(db, name)).unwrap().id);
    let city = rules::city_of(&db, players[0]).unwrap();
    db.insert(Building { id: 0, city: city.id, kind: Kind::Embassy as u8, level: 1 });
    let founded = db.call(|db| rules::found_alliance(db, players[0], "Keepers of the Mere", "MERE")).unwrap();
    for player in &players[1..3] {
        db.call(|db| rules::join_alliance(db, *player, founded.id)).unwrap();
    }
    wait(&mut db, 30);
    (db, players)
}

fn goods(db: &Mem, player: u64) -> Goods {
    let city = rules::city_of(db, player).unwrap();
    rules::goods(&rules::grown(&Table::<Stock>::get(db, city.id).unwrap(), db.clock))
}

#[test]
fn a_barrow_cleared_is_a_gift_to_every_other_member() {
    let (mut db, [ada, bryn, cole, dara]) = alliance();
    rules::give_boons(&mut db, ada, 4);
    let given = |db: &Mem, player: u64| Table::<Boon>::by(db, 0, player);
    assert!(given(&db, ada).is_empty(), "nothing to the one who cleared it");
    assert!(given(&db, dara).is_empty(), "nothing to one in no alliance");
    let bryns = given(&db, bryn);
    assert_eq!(bryns.len(), 1);
    assert_eq!((bryns[0].giver, bryns[0].level, bryns[0].grain, bryns[0].timber, bryns[0].stone), (ada, 4, 800, 800, 800));
    assert_eq!(bryns[0].expires, db.clock + rules::BOON_LASTS);
    assert_eq!(rules::boon_of(4), Goods::of(800, 800, 800, 0));

    // Claimed: the goods come into his city, and the gift is gone.
    rules::give_boons(&mut db, cole, 2);
    let before = goods(&db, bryn);
    wait(&mut db, 1);
    let came = db.call(|db| rules::claim_boons(db, bryn)).unwrap();
    assert_eq!(came, Goods::of(1_200, 1_200, 1_200, 0), "both gifts, Ada's and Cole's");
    let after = goods(&db, bryn);
    assert!(after.grain >= before.grain + 1_200 && after.stone >= before.stone + 1_200);
    assert!(given(&db, bryn).is_empty());
    wait(&mut db, 1);
    let refusal = db.call(|db| rules::claim_boons(db, bryn)).unwrap_err();
    assert_eq!((refusal.clone(), refusal.to_string()), (Refusal::NoBoons, "No gift is waiting on you.".to_string()));
    // One in no alliance, or with none waiting, claims nothing.
    assert_eq!(db.call(|db| rules::claim_boons(db, dara)), Err(Refusal::NoBoons));

    // Unclaimed, a gift is gone a day later.
    assert_eq!(given(&db, cole).len(), 1, "Ada's gift waits on Cole");
    wait(&mut db, rules::BOON_LASTS);
    assert!(given(&db, cole).is_empty(), "gone, unclaimed");
}

#[test]
fn no_more_than_fifty_gifts_wait_on_one_member() {
    let (mut db, [ada, bryn, _, _]) = alliance();
    for _ in 0..60 {
        rules::give_boons(&mut db, ada, 1);
    }
    let waiting = Table::<Boon>::by(&db, 0, bryn);
    assert_eq!(waiting.len(), rules::BOONS_KEPT);
    let oldest = waiting.iter().map(|boon| boon.id).min().unwrap();
    assert!(Table::<Boon>::all(&db).iter().all(|boon| boon.player != bryn || boon.id >= oldest), "the oldest gone first");
}
