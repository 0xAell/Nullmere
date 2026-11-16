//! The rules at a realm's full size: a thousand players joining the
//! published map, and an army of each out gathering at once, their timers
//! run through to the end. Each step is held to a budget ten times what a
//! release build took here, so a rule that grows with the square of the
//! players fails it. Run in release, as `realm/check.sh` runs it:
//!
//!     cargo test --release --test scale -- --ignored

use realm::hex::Hex;
use realm::rows::{City, March, Site, Troop};
use realm::rules::{self, Asked};
use realm::store::{Mem, Table};
use std::time::{Duration, Instant};

/// A thousand players on the published map (radius 128), joined no faster
/// than the realm lets newcomers in.
fn thousand() -> (Mem, Vec<u64>, Duration) {
    let mut db = Mem::new(3_000_000, 5);
    rules::open(&mut db, 7, 1, 128);
    let mut players = Vec::new();
    let mut joining = Duration::ZERO;
    for n in 0..1000 {
        if n % 100 == 99 {
            let to = db.clock + 60;
            db.advance(to, rules::fire);
        }
        let started = Instant::now();
        players.push(db.call(|db| rules::join(db, &format!("Player {n:04}"))).unwrap().id);
        joining += started.elapsed();
    }
    (db, players, joining)
}

#[test]
#[ignore]
fn a_thousand_players_join_and_send_an_army_each_to_gather() {
    let (mut db, players, joining) = thousand();
    assert_eq!(Table::<City>::all(&db).len(), 1000, "a city for each");
    println!("SCALE 1,000 joins: {joining:?}");
    assert!(joining < Duration::from_secs(6), "a thousand joins took {joining:?}");

    // Fifty spearmen each, sent to the nearest site no one works.
    for &player in &players {
        let city = rules::city_of(&db, player).unwrap();
        rules::keep_troop(&mut db, Troop { id: Troop::key(city.id, 1, 1), city: city.id, kind: 1, tier: 1, ready: 50, wounded: 0 });
    }
    let sites = Table::<Site>::all(&db);
    let (mut sent, mut sending, mut slowest) = (0, Duration::ZERO, Duration::ZERO);
    for &player in &players {
        let home = Hex::unpacked(rules::city_of(&db, player).unwrap().hex);
        let mut near: Vec<&Site> = sites.iter().collect();
        near.sort_by_key(|site| Hex::unpacked(site.hex).distance(home));
        for site in near.iter().take(5) {
            let started = Instant::now();
            let ok = db.call(|db| rules::send(db, player, Hex::unpacked(site.hex), March::GATHER, &[Asked { kind: 1, tier: 1, count: 50 }])).is_ok();
            sending += started.elapsed();
            slowest = slowest.max(started.elapsed());
            if ok {
                sent += 1;
                break;
            }
        }
        let to = db.clock + 1;
        db.advance(to, rules::fire);
    }
    println!("SCALE {sent} armies sent: {sending:?}, the slowest {slowest:?}");
    assert!(sent > 900, "nearly everyone found a site to gather at: {sent}");
    assert!(sending < Duration::from_secs(13), "{sent} sends took {sending:?}");

    // Four hours: every army works its site and comes home.
    let started = Instant::now();
    let to = db.clock + 4 * 3_600;
    db.advance(to, rules::fire);
    let timers = started.elapsed();
    println!("SCALE four hours of {sent} armies' timers: {timers:?}");
    assert!(Table::<March>::all(&db).is_empty(), "every army is home");
    assert!(timers < Duration::from_secs(12), "their timers took {timers:?}");
}
