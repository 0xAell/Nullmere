//! Cairns over a store kept in memory: scattered on the land as the realm
//! opens, and what each holds found once by each player's scouts.

use realm::catalog::{Building as Kind, Goods, Item, Troops};
use realm::hex::Hex;
use realm::rows::{Building, Cairn, City, Find, March, Place, Report, Satchel, Stock, Troop};
use realm::rules::{self, Asked, Refusal};
use realm::store::{Mem, Seconds, Table};

const START: Seconds = 3_000_000;

/// A realm with Ada and Bryn, each with spearmen ready.
fn realm() -> (Mem, (u64, City), (u64, City)) {
    let mut db = Mem::new(START, 5);
    rules::open(&mut db, 7, 1, 48);
    let mut both = Vec::new();
    for name in ["Ada", "Bryn"] {
        let player = db.call(|db| rules::join(db, name)).unwrap().id;
        let city = rules::city_of(&db, player).unwrap();
        rules::keep_troop(&mut db, Troop { id: Troop::key(city.id, Troops::Spearmen as u8, 1), city: city.id, kind: Troops::Spearmen as u8, tier: 1, ready: 50, wounded: 0 });
        both.push((player, city));
    }
    (db, both[0].clone(), both[1].clone())
}

fn until(db: &mut Mem, moment: Seconds) {
    db.advance(moment, |db, timer| rules::fire(db, timer));
}

fn scouts() -> Vec<Asked> {
    vec![Asked { kind: Troops::Spearmen as u8, tier: 1, count: 1 }]
}

fn stock_at(db: &Mem, city: u64, moment: Seconds) -> Goods {
    rules::goods(&rules::grown(&Table::<Stock>::get(db, city).unwrap(), moment))
}

fn held(db: &Mem, player: u64, item: Item) -> u64 {
    Table::<Satchel>::by(db, 0, player).iter().filter(|row| row.item == item as u8).map(|row| row.count).sum()
}

#[test]
fn cairns_stand_on_open_ground_about_the_land() {
    let (db, _, _) = realm();
    let cairns = Table::<Cairn>::all(&db);
    // A radius of 48 has 7,057 hexes: one cairn tried for every 150.
    assert!(cairns.len() >= 40 && cairns.len() <= 47, "{} cairns", cairns.len());
    for cairn in &cairns {
        assert!((1..=rules::TOP_CAIRN).contains(&cairn.level));
        let place = Table::<Place>::get(&db, cairn.hex).unwrap();
        assert_eq!((place.kind, place.id), (Place::CAIRN, cairn.id));
        assert_eq!(rules::cairn_at(&db, Hex::unpacked(cairn.hex)).map(|found| found.id), Some(cairn.id));
    }
    // The higher stand nearer the lake: on the whole, nearer than the lowest.
    let mean = |level: u32| {
        let near: Vec<u32> = cairns.iter().filter(|cairn| cairn.level == level).map(|cairn| Hex::unpacked(cairn.hex).length()).collect();
        near.iter().sum::<u32>() as f64 / near.len().max(1) as f64
    };
    assert!(mean(1) > mean(4).min(mean(5)), "level ones lie out toward the mountains");

    // What each level holds.
    assert_eq!(rules::hoard_of(1), (Goods::of(2_000, 2_000, 2_000, 0), vec![Item::Tome]));
    assert_eq!(rules::hoard_of(3), (Goods::of(12_000, 12_000, 12_000, 0), vec![Item::Haste5, Item::Tome]));
    assert_eq!(rules::hoard_of(4), (Goods::of(20_000, 20_000, 20_000, 500), vec![Item::Haste5, Item::Tome]));
    assert_eq!(rules::hoard_of(5), (Goods::of(30_000, 30_000, 30_000, 1_000), vec![Item::Haste60, Item::GreatTome]));
}

#[test]
fn scouts_find_what_a_cairn_holds_once_for_each_player() {
    let (mut db, (ada, hers), (bryn, his)) = realm();
    let home = Hex::unpacked(hers.hex);
    let mut cairns = Table::<Cairn>::all(&db);
    cairns.sort_by_key(|cairn| (Hex::unpacked(cairn.hex).distance(home), cairn.id));
    let mut cairn = cairns[0].clone();
    // Made a fifth-level cairn, for the whole of a hoard.
    cairn.level = 5;
    db.update(cairn.clone());
    let at = Hex::unpacked(cairn.hex);

    // Without a Scout Camp, no scouts go out; nor to where no cairn stands.
    assert_eq!(db.call(|db| rules::send(db, ada, at, March::EXPLORE, &scouts())), Err(Refusal::NeedsOther(Kind::ScoutCamp, 1)));
    db.insert(Building { id: 0, city: hers.id, kind: Kind::ScoutCamp as u8, level: 1 });
    let refusal = db.call(|db| rules::send(db, ada, home, March::EXPLORE, &scouts())).unwrap_err();
    assert_eq!((refusal.clone(), refusal.to_string()), (Refusal::NoCairnThere, "No cairn stands there.".to_string()));

    let march = db.call(|db| rules::send(db, ada, at, March::EXPLORE, &scouts())).unwrap();
    assert_eq!((march.kind, march.state, march.soldiers, march.target), (March::EXPLORE, March::GOING, 1, cairn.id));
    // Not twice at once.
    let refusal = db.call(|db| rules::send(db, ada, at, March::EXPLORE, &scouts())).unwrap_err();
    assert_eq!((refusal.clone(), refusal.to_string()), (Refusal::ScoutsOnTheWay, "Your scouts are on their way to that cairn already.".to_string()));

    // There, they find the hoard: into Ada's city at once, the haste into her satchel.
    let before = stock_at(&db, hers.id, march.arrives);
    until(&mut db, march.arrives);
    assert_eq!(stock_at(&db, hers.id, march.arrives), before.plus(Goods::of(30_000, 30_000, 30_000, 1_000)));
    assert_eq!(held(&db, ada, Item::Haste60), 1);
    assert_eq!(held(&db, ada, Item::GreatTome), 1);
    assert!(rules::has_found(&db, ada, cairn.id));
    let found = Table::<Find>::by(&db, 0, ada);
    assert_eq!((found.len(), found[0].cairn, found[0].at), (1, cairn.id, march.arrives));
    let told = Table::<Report>::by(&db, 0, ada).pop().unwrap();
    assert_eq!((told.kind, told.won, told.foe, told.hex, told.grain, told.moonsalt), (Report::CAIRN, true, 5, cairn.hex, 30_000, 1_000));
    assert_eq!(
        told.words,
        "Your scouts found what the old folk laid in a cairn of level 5: 30,000 grain, 30,000 timber, 30,000 stone and 1,000 moonsalt, and an hour's haste and a great tome of war. It is in your city."
    );
    // The scouts come home whole.
    let back = Table::<March>::get(&db, march.id).unwrap();
    assert_eq!((back.state, back.soldiers), (March::RETURNING, 1));
    until(&mut db, back.arrives);
    assert!(Table::<March>::get(&db, march.id).is_none());

    // Found once: Ada's scouts are sent there no more.
    let refusal = db.call(|db| rules::send(db, ada, at, March::EXPLORE, &scouts())).unwrap_err();
    assert_eq!((refusal.clone(), refusal.to_string()), (Refusal::FoundAlready, "Your scouts have found what that cairn held already.".to_string()));

    // The cairn stands for Bryn's scouts to find as well.
    assert!(Table::<Cairn>::get(&db, cairn.id).is_some());
    db.insert(Building { id: 0, city: his.id, kind: Kind::ScoutCamp as u8, level: 1 });
    let his_march = db.call(|db| rules::send(db, bryn, at, March::EXPLORE, &scouts())).unwrap();
    until(&mut db, his_march.arrives);
    assert!(rules::has_found(&db, bryn, cairn.id));
    assert_eq!(held(&db, bryn, Item::Haste60), 1);
    assert_eq!(Table::<Find>::all(&db).len(), 2);
}
