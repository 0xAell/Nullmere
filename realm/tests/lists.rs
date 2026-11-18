//! The Lists over a store kept in memory: bands set and the standing
//! entered at its foot, challenges up to ten places above, five a day,
//! places taken by winning and none lost, and the day's purse by place.

use realm::catalog::{self, Goods, Troops};
use realm::rows::{City, Commander, Entrant, Guard, Purse, Report, Stock, Troop};
use realm::rules::{self, Asked, Refusal};
use realm::store::{Mem, Seconds, Table};

const START: Seconds = 3_000_000;

fn wait(db: &mut Mem, seconds: Seconds) {
    let to = db.clock + seconds;
    db.advance(to, |db, timer| rules::fire(db, timer));
}

/// A realm of players of these names, each with a Keep at its tenth
/// level and soldiers of every kind ready, tier 1 and as many of tier 3.
fn realm(names: &[&str]) -> (Mem, Vec<u64>, Vec<City>) {
    let mut db = Mem::new(START, 5);
    rules::open(&mut db, 7, 1, 48);
    let players: Vec<u64> = names.iter().map(|name| db.call(|db| rules::join(db, name)).unwrap().id).collect();
    let mut cities = Vec::new();
    for player in &players {
        let mut city = rules::city_of(&db, *player).unwrap();
        city.keep = 10;
        db.update(city.clone());
        for kind in 1..=3u8 {
            for tier in [1, 3] {
                rules::keep_troop(&mut db, Troop { id: Troop::key(city.id, kind, tier), city: city.id, kind, tier, ready: 1_000, wounded: 0 });
            }
        }
        cities.push(city);
    }
    (db, players, cities)
}

fn band(kind: Troops, tier: u32, count: u64) -> Vec<Asked> {
    vec![Asked { kind: kind as u8, tier, count }]
}

fn place(db: &Mem, player: u64) -> u64 {
    Table::<Entrant>::get(db, player).unwrap().place
}

fn stock(db: &Mem, city: u64) -> Goods {
    let stock = Table::<Stock>::get(db, city).unwrap();
    Goods::of(stock.grain, stock.timber, stock.stone, stock.moonsalt)
}

fn told(db: &Mem, player: u64) -> Report {
    Table::<Report>::by(db, 0, player).into_iter().filter(|report| report.kind == Report::LISTS).max_by_key(|report| report.id).unwrap()
}

#[test]
fn the_purses_are_written_as_the_realm_opens() {
    let (db, _, _) = realm(&[]);
    let mut purses = Table::<Purse>::all(&db);
    purses.sort_by_key(|purse| purse.id);
    assert_eq!(purses.iter().map(|purse| (purse.first, purse.last, purse.grain, purse.honour)).collect::<Vec<_>>(),
               [(1, 1, 30_000, 300), (2, 3, 20_000, 200), (4, 10, 12_000, 120), (11, 50, 6_000, 60), (51, u64::MAX, 2_000, 20)]);
    assert_eq!(catalog::lists_purse(7), (Goods::of(12_000, 12_000, 12_000, 0), 120));
    assert_eq!(catalog::lists_purse(4_000), (Goods::of(2_000, 2_000, 2_000, 0), 20));
}

#[test]
fn a_band_is_set_and_its_player_enters_at_the_foot_of_the_standing() {
    let (mut db, players, _) = realm(&["Ada", "Bryn", "Cole"]);
    let (ada, bryn) = (players[0], players[1]);
    let commander = rules::commanders_of(&db, ada).remove(0);
    let entered = db.call(|db| rules::enter_lists(db, ada, &band(Troops::Spearmen, 1, 300), commander.id)).unwrap();
    assert_eq!((entered.place, entered.leader), (1, commander.id));
    wait(&mut db, 1);
    assert_eq!(db.call(|db| rules::enter_lists(db, bryn, &band(Troops::Archers, 1, 200), 0)).unwrap().place, 2);
    // Set again, the band is the new one and the place is kept; the soldiers stay ready in the city.
    wait(&mut db, 1);
    db.call(|db| rules::enter_lists(db, ada, &[Asked { kind: 3, tier: 3, count: 500 }, Asked { kind: 1, tier: 1, count: 100 }], 0)).unwrap();
    let mut guards: Vec<(u8, u32, u64)> = Table::<Guard>::by(&db, 0, ada).into_iter().map(|guard| (guard.kind, guard.tier, guard.count)).collect();
    guards.sort();
    assert_eq!(guards, [(1, 1, 100), (3, 3, 500)]);
    assert_eq!((place(&db, ada), Table::<Entrant>::get(&db, ada).unwrap().leader), (1, 0));
    let city = rules::city_of(&db, ada).unwrap();
    assert_eq!(rules::troop(&db, city.id, Troops::Riders, 3).ready, 1_000);
    // No more than the Keep allows (200 a level), nor more than stand ready, nor none, nor under another's commander.
    let cole = players[2];
    wait(&mut db, 1);
    assert_eq!(db.call(|db| rules::enter_lists(db, cole, &band(Troops::Spearmen, 1, 2_001), 0)), Err(Refusal::NotEnoughTroops(Troops::Spearmen, 1, 1_000)));
    assert_eq!(db.call(|db| rules::enter_lists(db, cole, &[Asked { kind: 1, tier: 1, count: 1_000 }, Asked { kind: 2, tier: 1, count: 1_000 }, Asked { kind: 3, tier: 1, count: 1 }], 0)), Err(Refusal::BandTooBig(2_000)));
    assert_eq!(db.call(|db| rules::enter_lists(db, cole, &[], 0)), Err(Refusal::NothingAsked));
    assert_eq!(db.call(|db| rules::enter_lists(db, cole, &band(Troops::Spearmen, 1, 10), commander.id)), Err(Refusal::NoSuchCommander));
    assert!(Table::<Entrant>::get(&db, cole).is_none(), "nothing refused entered them");
}

#[test]
fn a_challenger_who_wins_takes_the_place_of_the_one_they_beat_and_none_are_lost() {
    let (mut db, players, cities) = realm(&["Ada", "Bryn", "Cole", "Dana"]);
    let (ada, bryn, cole, dana) = (players[0], players[1], players[2], players[3]);
    db.call(|db| rules::enter_lists(db, ada, &band(Troops::Spearmen, 1, 300), 0)).unwrap();
    db.call(|db| rules::enter_lists(db, bryn, &band(Troops::Spearmen, 1, 300), 0)).unwrap();
    db.call(|db| rules::enter_lists(db, cole, &band(Troops::Archers, 3, 1_000), 0)).unwrap();
    assert_eq!([place(&db, ada), place(&db, bryn), place(&db, cole)], [1, 2, 3]);

    // Cole's archers of the third tier beat Ada's spearmen: he takes the first place, she goes down to the third.
    assert_eq!(db.call(|db| rules::challenge(db, cole, ada)), Ok(true));
    assert_eq!([place(&db, ada), place(&db, bryn), place(&db, cole)], [3, 2, 1]);
    assert_eq!(rules::troop(&db, cities[2].id, Troops::Archers, 3).ready, 1_000, "none lost");
    let his = told(&db, cole);
    assert_eq!((his.won, his.foe, his.fought, his.stood, his.fell), (true, ada, 1_000, 300, 300));
    assert!(his.words.starts_with("You challenged Ada in the Lists and won: of your 1,000 soldiers "), "{}", his.words);
    assert!(his.words.ends_with(". You take their place, the 1st."), "{}", his.words);
    let hers = told(&db, ada);
    assert_eq!((hers.won, hers.foe), (false, cole));
    assert_eq!(hers.words, "Cole challenged you in the Lists and won. You go down to the 3rd place. None of yours were lost.");

    // Ada's spearmen against Bryn's, as many: one of them holds. Whoever loses keeps their place.
    wait(&mut db, 1);
    let won = db.call(|db| rules::challenge(db, ada, bryn)).unwrap();
    assert_eq!([place(&db, ada), place(&db, bryn)], if won { [2, 3] } else { [3, 2] });
    if !won {
        assert!(told(&db, bryn).words.ends_with("your band held. You keep your place, the 2nd."), "{}", told(&db, bryn).words);
    }

    // Only those above, and only those in the Lists; one not in them challenges no one.
    wait(&mut db, 1);
    assert_eq!(db.call(|db| rules::challenge(db, cole, ada)), Err(Refusal::NotAbove));
    assert_eq!(db.call(|db| rules::challenge(db, cole, cole)), Err(Refusal::NotAbove));
    assert_eq!(db.call(|db| rules::challenge(db, ada, dana)), Err(Refusal::NoSuchEntrant));
    assert_eq!(db.call(|db| rules::challenge(db, dana, ada)), Err(Refusal::NotInTheLists));
}

#[test]
fn five_challenges_a_day_and_none_further_than_ten_places_up() {
    let names = ["Ada", "Bryn", "Cole", "Dana", "Edda", "Finn", "Gwen", "Hal", "Ivo", "Jory", "Kit", "Lark"];
    let (mut db, players, _) = realm(&names);
    for player in &players {
        db.call(|db| rules::enter_lists(db, *player, &band(Troops::Spearmen, 1, 100), 0)).unwrap();
    }
    let (first, last) = (players[0], players[11]);
    assert_eq!((place(&db, first), place(&db, last)), (1, 12));
    assert_eq!(db.call(|db| rules::challenge(db, last, first)), Err(Refusal::TooFarAbove(catalog::LISTS_REACH)));
    // Lark's band, made strong, challenges the second place five times; then no more today.
    db.call(|db| rules::enter_lists(db, last, &band(Troops::Archers, 3, 1_000), 0)).unwrap();
    let mut tries = 0;
    while tries < catalog::LISTS_TRIES {
        wait(&mut db, 1);
        let above = *players.iter().find(|player| place(&db, **player) == place(&db, last) - 1).unwrap();
        db.call(|db| rules::challenge(db, last, above)).unwrap();
        tries += 1;
    }
    assert_eq!(place(&db, last), 7, "five won, five places up");
    wait(&mut db, 1);
    let above = *players.iter().find(|player| place(&db, **player) == 6).unwrap();
    assert_eq!(db.call(|db| rules::challenge(db, last, above)), Err(Refusal::NoChallengesLeft(catalog::LISTS_TRIES)));
    assert_eq!(rules::tilt_of(&db, last).tries, 5);
    // A new day of the realm, five more.
    wait(&mut db, catalog::DAY);
    assert_eq!(rules::tilt_of(&db, last).tries, 0);
    assert_eq!(db.call(|db| rules::challenge(db, last, above)), Ok(true));
}

#[test]
fn the_purse_of_a_place_is_claimed_once_a_day() {
    let (mut db, players, cities) = realm(&["Ada", "Bryn"]);
    let (ada, bryn) = (players[0], players[1]);
    assert_eq!(db.call(|db| rules::claim_purse(db, ada)), Err(Refusal::NotInTheLists));
    db.call(|db| rules::enter_lists(db, ada, &band(Troops::Spearmen, 1, 100), 0)).unwrap();
    db.call(|db| rules::enter_lists(db, bryn, &band(Troops::Spearmen, 1, 100), 0)).unwrap();
    wait(&mut db, 1);
    let before = (stock(&db, cities[0].id), rules::honour_of(&db, ada).honour);
    assert_eq!(db.call(|db| rules::claim_purse(db, ada)), Ok((Goods::of(30_000, 30_000, 30_000, 0), 300)));
    let after = stock(&db, cities[0].id);
    assert_eq!((after.grain - before.0.grain, after.stone - before.0.stone, rules::honour_of(&db, ada).honour - before.1), (30_000, 30_000, 300));
    assert_eq!(db.call(|db| rules::claim_purse(db, bryn)), Ok((Goods::of(20_000, 20_000, 20_000, 0), 200)));
    wait(&mut db, 1);
    assert_eq!(db.call(|db| rules::claim_purse(db, ada)), Err(Refusal::PurseClaimed));
    wait(&mut db, catalog::DAY);
    assert_eq!(db.call(|db| rules::claim_purse(db, ada)).map(|(_, honour)| honour), Ok(300));
}

#[test]
fn a_first_place_passed_from_hand_to_hand_pays_its_purse_once_a_day() {
    let (mut db, players, _) = realm(&["Ada", "Bryn", "Cole"]);
    let (ada, bryn, cole) = (players[0], players[1], players[2]);
    for player in [ada, bryn, cole] {
        db.call(|db| rules::enter_lists(db, player, &band(Troops::Spearmen, 1, 100), 0)).unwrap();
        wait(&mut db, 1);
    }
    // Ada, first, claims the first place's purse, then sets a band of one to be beaten.
    assert_eq!(db.call(|db| rules::claim_purse(db, ada)).map(|(_, honour)| honour), Ok(300));
    wait(&mut db, 1);
    db.call(|db| rules::enter_lists(db, ada, &band(Troops::Spearmen, 1, 1), 0)).unwrap();
    wait(&mut db, 1);
    db.call(|db| rules::enter_lists(db, bryn, &band(Troops::Archers, 3, 1_000), 0)).unwrap();
    wait(&mut db, 1);
    assert_eq!(db.call(|db| rules::challenge(db, bryn, ada)), Ok(true));
    assert_eq!([place(&db, ada), place(&db, bryn)], [2, 1]);
    // Bryn holds the first place now, but was second as the day's challenge was fought: the second's purse.
    wait(&mut db, 1);
    assert_eq!(db.call(|db| rules::claim_purse(db, bryn)).map(|(_, honour)| honour), Ok(200));
    // Cole, never challenged today, by the place he holds.
    assert_eq!(db.call(|db| rules::claim_purse(db, cole)).map(|(_, honour)| honour), Ok(200));
    // The next day, Bryn's first place pays.
    wait(&mut db, catalog::DAY);
    assert_eq!(db.call(|db| rules::claim_purse(db, bryn)).map(|(_, honour)| honour), Ok(300));
}

#[test]
fn ten_places_up_may_be_challenged_and_no_further() {
    let names = ["Ada", "Bryn", "Cole", "Dana", "Edda", "Finn", "Gwen", "Hal", "Ivo", "Jory", "Kit", "Lark"];
    let (mut db, players, _) = realm(&names);
    for player in &players {
        db.call(|db| rules::enter_lists(db, *player, &band(Troops::Spearmen, 1, 100), 0)).unwrap();
    }
    // Kit, eleventh, may challenge Ada, first; Lark, twelfth, may not.
    assert!(db.call(|db| rules::challenge(db, players[10], players[0])).is_ok());
    wait(&mut db, 1);
    let first = *players.iter().find(|player| place(&db, **player) == 1).unwrap();
    let twelfth = *players.iter().find(|player| place(&db, **player) == 12).unwrap();
    assert_eq!(db.call(|db| rules::challenge(db, twelfth, first)), Err(Refusal::TooFarAbove(catalog::LISTS_REACH)));
}

#[test]
fn a_commander_held_prisoner_stands_under_no_band() {
    let (mut db, players, _) = realm(&["Ada"]);
    let ada = players[0];
    let commander = rules::commanders_of(&db, ada).remove(0);
    let mut held = Table::<Commander>::get(&db, commander.id).unwrap();
    held.march = rules::HELD;
    db.update(held);
    assert_eq!(db.call(|db| rules::enter_lists(db, ada, &band(Troops::Spearmen, 1, 100), commander.id)), Err(Refusal::HeldPrisoner(commander.name.clone())));
    // One out with an army may: the band is a likeness, kept as it was set.
    let mut away = Table::<Commander>::get(&db, commander.id).unwrap();
    away.march = 77;
    db.update(away);
    assert!(db.call(|db| rules::enter_lists(db, ada, &band(Troops::Spearmen, 1, 100), commander.id)).is_ok());
}

#[test]
fn a_player_forgotten_leaves_the_lists_and_those_below_come_up() {
    let (mut db, players, _) = realm(&["Ada", "Bryn", "Cole"]);
    for player in &players {
        db.call(|db| rules::enter_lists(db, *player, &band(Troops::Spearmen, 1, 100), 0)).unwrap();
    }
    db.call(|db| rules::forget(db, players[0])).unwrap();
    assert!(Table::<Entrant>::get(&db, players[0]).is_none());
    assert!(Table::<Guard>::by(&db, 0, players[0]).is_empty(), "their band gone");
    assert_eq!([place(&db, players[1]), place(&db, players[2])], [1, 2]);
    // And one entering after takes the place below them, with no gap and none twice.
    let dana = db.call(|db| rules::join(db, "Dana")).unwrap().id;
    let city = rules::city_of(&db, dana).unwrap();
    rules::keep_troop(&mut db, Troop { id: Troop::key(city.id, 1, 1), city: city.id, kind: 1, tier: 1, ready: 100, wounded: 0 });
    assert_eq!(db.call(|db| rules::enter_lists(db, dana, &band(Troops::Spearmen, 1, 100), 0)).unwrap().place, 3);
}
