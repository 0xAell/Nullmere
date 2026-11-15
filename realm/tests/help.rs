//! Help over a store kept in memory: asked of an alliance for a work
//! under way, given once by each ally, and what it takes off the work.

use realm::catalog::{self, Building as Kind};
use realm::rows::{Building, City, Helper, Job, Plea, Stock};
use realm::rules::{self, Refusal};
use realm::store::{Mem, Seconds, Table};

const START: Seconds = 3_000_000;

fn wait(db: &mut Mem, seconds: Seconds) {
    let to = db.clock + seconds;
    db.advance(to, |db, timer| rules::fire(db, timer));
}

/// A realm of players of these names, each with a Keep at its fifteenth
/// level, an Embassy at its first and goods enough; all but those named
/// in `apart` in one alliance, founded by the first.
fn allies(names: &[&str], apart: &[&str]) -> (Mem, Vec<u64>, Vec<City>) {
    let mut db = Mem::new(START, 5);
    rules::open(&mut db, 7, 1, 48);
    let players: Vec<u64> = names.iter().map(|name| db.call(|db| rules::join(db, name)).unwrap().id).collect();
    let mut cities = Vec::new();
    for player in &players {
        let mut city = rules::city_of(&db, *player).unwrap();
        city.keep = 15;
        db.update(city.clone());
        let mut keep = rules::building_of(&db, city.id, Kind::Keep).unwrap();
        keep.level = 15;
        db.update(keep);
        db.insert(Building { id: 0, city: city.id, kind: Kind::Embassy as u8, level: 1 });
        let mut stock = rules::grown(&Table::<Stock>::get(&db, city.id).unwrap(), db.clock);
        (stock.grain, stock.timber, stock.stone, stock.moonsalt) = (9_000_000, 9_000_000, 9_000_000, 900_000);
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
    (db, players, cities)
}

/// Has a player raise their Farm from a level: a work of some hours.
fn long_work(db: &mut Mem, player: u64, city: &City, level: u32) -> Job {
    let mut farm = rules::building_of(db, city.id, Kind::Farm).unwrap();
    farm.level = level;
    db.update(farm.clone());
    db.call(|db| rules::upgrade(db, player, farm.id)).unwrap()
}

#[test]
fn a_player_asks_their_alliances_help_with_a_work_of_their_own_once() {
    let (mut db, players, cities) = allies(&["Ada", "Bryn", "Cole"], &["Cole"]);
    let (ada, bryn, cole) = (players[0], players[1], players[2]);
    let job = long_work(&mut db, ada, &cities[0], 12);
    let theirs = long_work(&mut db, bryn, &cities[1], 12);

    assert_eq!(db.call(|db| rules::ask_help(db, cole, job.id)), Err(Refusal::NotAllied));
    assert_eq!(db.call(|db| rules::ask_help(db, ada, theirs.id)), Err(Refusal::NoSuchJob), "another's work is theirs to ask for");
    assert_eq!(db.call(|db| rules::ask_help(db, ada, 999_999)), Err(Refusal::NoSuchJob));

    let plea = db.call(|db| rules::ask_help(db, ada, job.id)).unwrap();
    assert_eq!((plea.job, plea.asker, plea.work, plea.helped, plea.most), (job.id, ada, Job::RAISE, 0, catalog::helps(1)));
    assert!(plea.name.contains("Ada"));
    assert_eq!(catalog::helps(1), 5);
    assert_eq!((catalog::helps(10), catalog::helps(40)), (14, 30), "more with a higher Embassy, thirty at most");
    wait(&mut db, 3);
    assert_eq!(db.call(|db| rules::ask_help(db, ada, job.id)), Err(Refusal::HelpAsked));
    assert_eq!(Refusal::HelpAsked.to_string(), "You have asked your alliance's help with that already.");
}

#[test]
fn each_ally_helps_once_and_a_help_takes_a_hundredth_or_a_minute_off_what_is_left() {
    let (mut db, players, cities) = allies(&["Ada", "Bryn", "Cole", "Dara"], &["Dara"]);
    let (ada, bryn, cole, dara) = (players[0], players[1], players[2], players[3]);
    let job = long_work(&mut db, ada, &cities[0], 14);
    db.call(|db| rules::ask_help(db, ada, job.id)).unwrap();
    let left = job.ends - db.clock;
    assert!(left > 100 * catalog::HELP_SECONDS, "long enough for a hundredth to be more than a minute: {left}");

    // Not one's own work, not one who is no ally, and not twice.
    assert_eq!(db.call(|db| rules::help(db, ada, job.id)), Err(Refusal::YourOwnWork));
    assert_eq!(db.call(|db| rules::help(db, dara, job.id)), Err(Refusal::NotAllied));
    db.call(|db| rules::help(db, bryn, job.id)).unwrap();
    let after = Table::<Job>::get(&db, job.id).unwrap();
    assert_eq!(after.ends, job.ends - left / 100, "a hundredth of what was left");
    wait(&mut db, 3);
    assert_eq!(db.call(|db| rules::help(db, bryn, job.id)), Err(Refusal::AlreadyHelped));
    assert_eq!(Table::<Plea>::get(&db, job.id).unwrap().helped, 1);

    // A second ally's help takes a hundredth of what is left now.
    let left = after.ends - db.clock;
    db.call(|db| rules::help(db, cole, job.id)).unwrap();
    let twice = Table::<Job>::get(&db, job.id).unwrap();
    assert_eq!(twice.ends, after.ends - left / 100);
    assert_eq!(Table::<Helper>::by(&db, 0, job.id).len(), 2);

    // The work ends when it now says, and the asking with it.
    let moment = twice.ends - 1;
    db.advance(moment, |db, timer| rules::fire(db, timer));
    assert!(Table::<Job>::get(&db, job.id).is_some());
    wait(&mut db, 1);
    assert!(Table::<Job>::get(&db, job.id).is_none());
    assert_eq!(rules::building_of(&db, cities[0].id, Kind::Farm).unwrap().level, 15);
    assert!(Table::<Plea>::get(&db, job.id).is_none());
    assert!(Table::<Helper>::all(&db).is_empty());
    assert_eq!(db.call(|db| rules::help(db, bryn, job.id)), Err(Refusal::NoSuchPlea));
}

#[test]
fn a_short_work_is_helped_by_a_minute_and_never_ends_before_now() {
    let (mut db, players, cities) = allies(&["Ada", "Bryn", "Cole"], &[]);
    let (ada, bryn, cole) = (players[0], players[1], players[2]);
    // A work with less than a hundred minutes left: a help is a minute.
    let job = long_work(&mut db, ada, &cities[0], 5);
    let left = job.ends - db.clock;
    assert!(left > 2 * catalog::HELP_SECONDS && left < 100 * catalog::HELP_SECONDS, "{left}");
    db.call(|db| rules::ask_help(db, ada, job.id)).unwrap();
    db.call(|db| rules::help(db, bryn, job.id)).unwrap();
    assert_eq!(Table::<Job>::get(&db, job.id).unwrap().ends, job.ends - catalog::HELP_SECONDS);

    // With less than a minute left it ends a second from now, not before.
    wait(&mut db, left - catalog::HELP_SECONDS - 20);
    db.call(|db| rules::help(db, cole, job.id)).unwrap();
    assert_eq!(Table::<Job>::get(&db, job.id).unwrap().ends, db.clock + 1);
    wait(&mut db, 1);
    assert!(Table::<Job>::get(&db, job.id).is_none());
}

#[test]
fn a_work_may_be_helped_only_so_many_times_and_helping_all_helps_what_one_may() {
    let (mut db, players, cities) = allies(&["Ada", "Bryn", "Cole", "Dara", "Edda", "Finn", "Gwen"], &[]);
    let ada = players[0];
    let job = long_work(&mut db, ada, &cities[0], 14);
    db.call(|db| rules::ask_help(db, ada, job.id)).unwrap();
    // Five may help with an Embassy at its first level; the sixth may not.
    for player in &players[1..6] {
        db.call(|db| rules::help(db, *player, job.id)).unwrap();
    }
    assert_eq!(db.call(|db| rules::help(db, players[6], job.id)), Err(Refusal::HelpedEnough));
    assert_eq!(Table::<Plea>::get(&db, job.id).unwrap().helped, 5);

    // Helping all: every work of the alliance's one may help with, and no other.
    let second = long_work(&mut db, players[1], &cities[1], 14);
    let third = long_work(&mut db, players[2], &cities[2], 14);
    db.call(|db| rules::ask_help(db, players[1], second.id)).unwrap();
    db.call(|db| rules::ask_help(db, players[2], third.id)).unwrap();
    wait(&mut db, 3);
    assert_eq!(db.call(|db| rules::help_all(db, players[1])), Ok(1), "the third's, not their own, and not the one that is full");
    assert_eq!(db.call(|db| rules::help_all(db, players[6])), Ok(2));
    wait(&mut db, 3);
    assert_eq!(db.call(|db| rules::help_all(db, players[6])), Ok(0), "nothing left to help with");
    assert_eq!(Table::<Plea>::get(&db, second.id).unwrap().helped, 1);
    assert_eq!(Table::<Plea>::get(&db, third.id).unwrap().helped, 2);
}
