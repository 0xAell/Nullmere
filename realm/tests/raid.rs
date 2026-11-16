//! Armies against armies in the field, over a store kept in memory: an
//! army sent against another player's army gathering at a site, which it
//! drives off or is beaten by, and what each side is told.

use realm::catalog::{Building as Kind, Troops};
use realm::hex::Hex;
use realm::rows::{Building, City, Haul, March, Report, Site, Troop};
use realm::rules::{self, Asked, Refusal};
use realm::store::{Mem, Seconds, Table};

const START: Seconds = 3_000_000;

/// A realm with Ada and Bryn, each with so many spearmen ready.
fn realm(hers: u64, his: u64) -> (Mem, (u64, City), (u64, City)) {
    let mut db = Mem::new(START, 5);
    rules::open(&mut db, 7, 1, 48);
    let mut both = Vec::new();
    for (name, ready) in [("Ada", hers), ("Bryn", his)] {
        let player = db.call(|db| rules::join(db, name)).unwrap().id;
        let city = rules::city_of(&db, player).unwrap();
        rules::keep_troop(&mut db, Troop { id: Troop::key(city.id, Troops::Spearmen as u8, 1), city: city.id, kind: Troops::Spearmen as u8, tier: 1, ready, wounded: 0 });
        // A Hospital, so some of the fallen are carried home wounded.
        db.insert(Building { id: 0, city: city.id, kind: Kind::Hospital as u8, level: 5 });
        both.push((player, city));
    }
    (db, both[0].clone(), both[1].clone())
}

fn until(db: &mut Mem, moment: Seconds) {
    db.advance(moment, |db, timer| rules::fire(db, timer));
}

fn spearmen(count: u64) -> Vec<Asked> {
    vec![Asked { kind: Troops::Spearmen as u8, tier: 1, count }]
}

/// The site nearest a city, and Bryn's army sent to gather there and at
/// work when it is returned.
fn bryn_gathers(db: &mut Mem, bryn: u64, his: &City, soldiers: u64) -> (Site, March) {
    let home = Hex::unpacked(his.hex);
    let mut sites = Table::<Site>::all(db);
    sites.sort_by_key(|site| (Hex::unpacked(site.hex).distance(home), site.id));
    let site = sites[0].clone();
    let march = db.call(|db| rules::send(db, bryn, Hex::unpacked(site.hex), March::GATHER, &spearmen(soldiers))).unwrap();
    until(db, march.arrives);
    let working = Table::<March>::get(db, march.id).unwrap();
    assert_eq!(working.state, March::WORKING);
    (Table::<Site>::get(db, site.id).unwrap(), working)
}

#[test]
fn an_army_falls_on_gatherers_drives_them_off_and_carries_off_their_load() {
    let (mut db, (ada, hers), (bryn, his)) = realm(400, 30);
    let (site, gathering) = bryn_gathers(&mut db, bryn, &his, 30);
    let at = Hex::unpacked(site.hex);

    let raid = db.call(|db| rules::send(db, ada, at, March::RAID, &spearmen(400))).unwrap();
    assert_eq!((raid.kind, raid.target, raid.soldiers), (March::RAID, site.id, 400));
    // Sending it gives up her city's peace.
    assert!(Table::<City>::get(&db, hers.id).unwrap().shield <= db.clock);
    // The gatherers' work must still be under way when the raiders arrive.
    assert!(raid.arrives < gathering.arrives, "the raid arrives at {} and the gathering ends at {}", raid.arrives, gathering.arrives);
    until(&mut db, raid.arrives);

    // Driven off: the site free, what they had gathered off it, and its
    // gatherers on their way home.
    let site_now = Table::<Site>::get(&db, site.id).unwrap();
    assert_eq!(site_now.gatherer, 0);
    let gathered = site.left - site_now.left;
    assert!(gathered > 0, "they had gathered something by then");
    let driven = Table::<March>::get(&db, gathering.id);
    assert!(driven.as_ref().is_none_or(|march| march.state == March::RETURNING), "{driven:?}");
    // The raiders on their way home, bearing what the gatherers had gathered.
    let back = Table::<March>::get(&db, raid.id).unwrap();
    assert_eq!(back.state, March::RETURNING);
    let haul = Table::<Haul>::get(&db, raid.id).expect("they carry off the load");
    assert_eq!(haul.grain + haul.timber + haul.stone + haul.moonsalt, gathered);

    // Each is told.
    let hers_told = Table::<Report>::by(&db, 0, ada).into_iter().find(|report| report.kind == Report::FIELD).unwrap();
    assert!(hers_told.won);
    assert_eq!((hers_told.foe, hers_told.fought, hers_told.stood, hers_told.hex), (bryn, 400, 30, site.hex));
    assert!(hers_told.words.starts_with("Your army fell on Bryn's army gathering "), "{}", hers_told.words);
    assert!(hers_told.words.contains(" and drove it off. "), "{}", hers_told.words);
    let his_told = Table::<Report>::by(&db, 0, bryn).into_iter().find(|report| report.kind == Report::FIELD_DEFENCE).unwrap();
    assert!(!his_told.won);
    // His thirty all struck down, wounded or dead; hers as many as fell.
    assert_eq!((his_told.foe, his_told.fought, his_told.wounded + his_told.dead, his_told.stood), (ada, 30, 30, 400));
    assert_eq!(his_told.fell, hers_told.wounded + hers_told.dead);
    assert!(his_told.words.starts_with("Ada's army fell on your army gathering "), "{}", his_told.words);
    // Her kills count to her fame.
    let fame = rules::fame_of(&db, ada);
    assert_eq!(fame.felled, hers_told.fell);
    assert!(fame.kills > 0);

    // Home: her haul in her city, and his soldiers back with their wounded.
    until(&mut db, back.arrives);
    assert!(Table::<March>::get(&db, raid.id).is_none());
    if let Some(driven) = driven {
        until(&mut db, driven.arrives);
        assert!(Table::<March>::get(&db, driven.id).is_none());
    }
}

#[test]
fn an_army_too_weak_is_beaten_and_the_gatherers_work_on() {
    let (mut db, (ada, _), (bryn, his)) = realm(5, 300);
    let (site, gathering) = bryn_gathers(&mut db, bryn, &his, 300);
    let raid = db.call(|db| rules::send(db, ada, Hex::unpacked(site.hex), March::RAID, &spearmen(5))).unwrap();
    until(&mut db, raid.arrives);

    // Still at work, the fewer if any fell; the raiders gone or going home.
    let working = Table::<March>::get(&db, gathering.id).unwrap();
    assert_eq!(working.state, March::WORKING);
    assert_eq!(Table::<Site>::get(&db, site.id).unwrap().gatherer, gathering.id);
    assert!(Table::<March>::get(&db, raid.id).is_none_or(|march| march.state == March::RETURNING));
    assert!(Table::<Haul>::get(&db, raid.id).is_none(), "nothing carried off");
    let hers_told = Table::<Report>::by(&db, 0, ada).into_iter().find(|report| report.kind == Report::FIELD).unwrap();
    assert!(!hers_told.won);
    assert!(hers_told.words.contains(" and was beaten. "), "{}", hers_told.words);
    let his_told = Table::<Report>::by(&db, 0, bryn).into_iter().find(|report| report.kind == Report::FIELD_DEFENCE).unwrap();
    assert!(his_told.won);
    assert!(his_told.words.contains("and was beaten. Your army gathers on."), "{}", his_told.words);
    // The gathering ends in its time, and brings home what it gathered.
    until(&mut db, working.arrives);
    assert_eq!(Table::<March>::get(&db, gathering.id).unwrap().state, March::RETURNING);
}

#[test]
fn no_army_falls_on_no_one_nor_on_its_own_nor_an_allys() {
    let (mut db, (ada, hers), (bryn, his)) = realm(50, 50);
    let home = Hex::unpacked(his.hex);
    let mut sites = Table::<Site>::all(&db);
    sites.sort_by_key(|site| (Hex::unpacked(site.hex).distance(home), site.id));
    let empty = Hex::unpacked(sites[1].hex);
    let refusal = db.call(|db| rules::send(db, ada, empty, March::RAID, &spearmen(10))).unwrap_err();
    assert_eq!((refusal.clone(), refusal.to_string()), (Refusal::NoOneGathering, "No army is gathering there.".to_string()));

    let (site, _) = bryn_gathers(&mut db, bryn, &his, 10);
    let at = Hex::unpacked(site.hex);
    let refusal = db.call(|db| rules::send(db, bryn, at, March::RAID, &spearmen(10))).unwrap_err();
    assert_eq!((refusal.clone(), refusal.to_string()), (Refusal::OwnArmy, "That is your own army.".to_string()));

    // Allies: Ada founds an alliance, and Bryn joins it.
    db.insert(Building { id: 0, city: hers.id, kind: Kind::Embassy as u8, level: 1 });
    let mere = db.call(|db| rules::found_alliance(db, ada, "Keepers", "MERE")).unwrap().id;
    db.call(|db| rules::join_alliance(db, bryn, mere)).unwrap();
    let refusal = db.call(|db| rules::send(db, ada, at, March::RAID, &spearmen(10))).unwrap_err();
    assert_eq!((refusal.clone(), refusal.to_string()), (Refusal::AllysArmy, "That army is your ally's.".to_string()));
}

#[test]
fn raiders_who_find_the_site_left_come_home_and_fight_no_one() {
    let (mut db, (ada, _), (bryn, his)) = realm(50, 20);
    let (site, gathering) = bryn_gathers(&mut db, bryn, &his, 20);
    let raid = db.call(|db| rules::send(db, ada, Hex::unpacked(site.hex), March::RAID, &spearmen(50))).unwrap();
    // Bryn calls his army home before the raiders arrive.
    db.call(|db| rules::recall(db, bryn, gathering.id)).unwrap();
    until(&mut db, raid.arrives);
    let back = Table::<March>::get(&db, raid.id).unwrap();
    assert_eq!((back.state, back.soldiers), (March::RETURNING, 50));
    assert!(Table::<Report>::by(&db, 0, ada).iter().all(|report| report.kind != Report::FIELD), "no fight, no report of one");
}
