//! The holy sites over a store kept in memory: kept by the Unquiet as the
//! realm opens, shut to rallies until three days into the season, taken
//! by a rally and lending its alliance's cities a study's levels, guarded
//! a day once taken, and given back at the season's turn but by its
//! victor, and by an alliance that ends.

use realm::catalog::{self, Building as Kind, Holy, Troops, Unit};
use realm::hex::Hex;
use realm::land;
use realm::rows::{Building, City, March, Place, Rally, Report, Shrine, Stock, Troop};
use realm::rules::{self, Asked, Refusal};
use realm::store::{Mem, Seconds, Table};

const START: Seconds = 3_000_000;
const SEED: u64 = 7;
const RADIUS: u32 = 48;

fn wait(db: &mut Mem, seconds: Seconds) {
    let to = db.clock + seconds;
    db.advance(to, rules::fire);
}

fn until(db: &mut Mem, moment: Seconds) {
    db.advance(moment, rules::fire);
}

/// A realm of players of these names, each with a Keep at its eighth
/// level, an Embassy, spearmen of the top tier and goods; all but those
/// named in `apart` in one alliance, founded by the first.
fn allies(names: &[&str], apart: &[&str]) -> (Mem, Vec<u64>, Vec<City>, u64) {
    let mut db = Mem::new(START, 5);
    rules::open(&mut db, SEED, 1, RADIUS);
    let players: Vec<u64> = names.iter().map(|name| db.call(|db| rules::join(db, name)).unwrap().id).collect();
    let mut cities = Vec::new();
    for player in &players {
        let mut city = rules::city_of(&db, *player).unwrap();
        city.keep = 8;
        db.update(city.clone());
        let mut keep = rules::building_of(&db, city.id, Kind::Keep).unwrap();
        keep.level = 8;
        db.update(keep);
        db.insert(Building { id: 0, city: city.id, kind: Kind::Embassy as u8, level: 1 });
        rules::keep_troop(&mut db, Troop { id: Troop::key(city.id, Troops::Spearmen as u8, 5), city: city.id, kind: Troops::Spearmen as u8, tier: 5, ready: 60_000, wounded: 0 });
        let mut stock = rules::grown(&Table::<Stock>::get(&db, city.id).unwrap(), db.clock);
        (stock.grain, stock.timber, stock.stone, stock.moonsalt) = (500_000, 500_000, 500_000, 0);
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

fn spears(count: u64) -> Vec<Asked> {
    vec![Asked { kind: Troops::Spearmen as u8, tier: 5, count }]
}

/// The holy site of the outer land nearest a city that a way leads to,
/// every gate of the ridge barred.
fn shrine_near(db: &Mem, city: &City) -> Shrine {
    let from = Hex::unpacked(city.hex);
    let gates = land::gates(RADIUS);
    let mut near: Vec<Shrine> = Table::<Shrine>::all(db).into_iter().filter(|shrine| shrine.kind != Holy::Heartstone as u8).collect();
    near.sort_by_key(|shrine| (Hex::unpacked(shrine.hex).distance(from), shrine.id));
    near.into_iter().find(|shrine| land::way_by(SEED, RADIUS, from, Hex::unpacked(shrine.hex), |hex| gates.contains(&hex)).is_some()).expect("a holy site within reach")
}

/// As many spearmen of the top tier as take a holy site of a kind when
/// chance gives neither side anything.
fn enough(kind: Holy) -> u64 {
    let garrison = kind.garrison();
    (1..200)
        .map(|thousands| thousands * 1_000)
        .find(|count| rules::fight_sheltered(&[Unit { kind: Troops::Spearmen, tier: 5, count: *count }], &garrison, catalog::shrine_shelter(), || 10).won)
        .expect("some number is enough")
}

fn reports(db: &Mem, player: u64, kind: u8) -> Vec<Report> {
    let mut all: Vec<Report> = Table::<Report>::by(db, 0, player).into_iter().filter(|report| report.kind == kind).collect();
    all.sort_by_key(|report| report.id);
    all
}

fn rally_march(db: &Mem, player: u64) -> Option<March> {
    Table::<March>::by(db, 0, player).into_iter().find(|march| march.kind == March::RALLY)
}

/// A rally of two against a hex, called by the first and joined by the
/// second, fought out: the moment its fight ended.
fn rally_out(db: &mut Mem, caller: u64, joiner: u64, to: Hex, each: u64) -> Seconds {
    let rally = db.call(|db| rules::call_rally(db, caller, to, &spears(each), 0)).unwrap();
    db.call(|db| rules::join_rally(db, joiner, rally.id, &spears(each), 0)).unwrap();
    until(db, rally.sets_out);
    let last = [caller, joiner].iter().map(|player| rally_march(db, *player).unwrap().arrives).max().unwrap();
    until(db, last + catalog::ASSAULT_SECONDS);
    last + catalog::ASSAULT_SECONDS
}

#[test]
fn the_holy_sites_stand_kept_by_the_unquiet_and_open_three_days_into_the_season() {
    let (mut db, players, cities, _) = allies(&["Ada", "Bryn"], &[]);
    let ada = players[0];
    let shrines: Vec<Shrine> = Table::<Shrine>::all(&db);
    let spots = land::shrines(SEED, RADIUS);
    assert_eq!(shrines.len(), 13, "three of each outer kind and the Heartstone");
    assert_eq!(shrines.iter().map(|shrine| (shrine.hex, shrine.kind)).collect::<Vec<_>>(), spots.iter().map(|(hex, kind)| (hex.packed(), *kind as u8)).collect::<Vec<_>>());
    for kind in Holy::OUTER {
        let of_kind: Vec<&Shrine> = shrines.iter().filter(|shrine| shrine.kind == kind as u8).collect();
        assert_eq!(of_kind.len(), 3, "three of {}", kind.name());
        assert!(of_kind.iter().all(|shrine| Hex::unpacked(shrine.hex).length() >= land::outer_from(RADIUS)), "in the outer land");
    }
    let heart: Vec<&Shrine> = shrines.iter().filter(|shrine| shrine.kind == Holy::Heartstone as u8).collect();
    assert_eq!(heart.len(), 1);
    assert!(land::lakeland(RADIUS, Hex::unpacked(heart[0].hex)), "the Heartstone stands in the lake country");
    for shrine in &shrines {
        assert_eq!((shrine.holder, shrine.fighter), (0, 0), "the Unquiet keep every one");
        assert_eq!(Table::<Place>::get(&db, shrine.hex), Some(Place { hex: shrine.hex, kind: Place::SHRINE, id: shrine.id }));
        assert_eq!(rules::shrine_at(&db, Hex::unpacked(shrine.hex)).map(|found| found.id), Some(shrine.id));
        let hex = Hex::unpacked(shrine.hex);
        assert!(shrines.iter().all(|other| other.id == shrine.id || Hex::unpacked(other.hex).distance(hex) >= 3), "none crowds another");
    }
    // Nothing else stands on one or beside it.
    for shrine in &shrines {
        let hex = Hex::unpacked(shrine.hex);
        assert!(hex.within(1).iter().skip(1).all(|near| Table::<Place>::get(&db, near.packed()).is_none()), "nothing beside {:?}", hex);
    }

    // A rally against one waits three days into the season.
    let near = shrine_near(&db, &cities[0]);
    let opens = rules::shrines_open_at(&db);
    assert_eq!(opens, START + 3 * catalog::DAY);
    assert_eq!(db.call(|db| rules::call_rally(db, ada, Hex::unpacked(near.hex), &spears(100), 0)), Err(Refusal::ShrinesShut(opens - db.clock)));
    assert_eq!(Refusal::ShrinesShut(2 * catalog::DAY).to_string(), "The holy sites may be stormed in 2 days.");
    // And an army goes against one only in a rally.
    assert_eq!(db.call(|db| rules::send(db, ada, Hex::unpacked(near.hex), March::ATTACK, &spears(100))), Err(Refusal::NoCityThere));
    // What each lends, in a player's words.
    assert_eq!(Holy::Moonwell.words(), "Your alliance's armies gather 20% faster.");
    assert_eq!(Holy::Heartstone.words(), "Your alliance's Spearmen, Archers and Riders strike 9% harder.");
}

#[test]
fn a_rally_takes_a_holy_site_and_every_city_of_its_alliance_has_what_it_lends() {
    let (mut db, players, cities, mere) = allies(&["Ada", "Bryn", "Cole"], &["Cole"]);
    let (ada, bryn, cole) = (players[0], players[1], players[2]);
    let shrine = shrine_near(&db, &cities[0]);
    let kind = Holy::of(shrine.kind).unwrap();
    let (topic, levels) = kind.lends()[0];
    let each = enough(kind);
    assert!(each <= 30_000, "a rally of two can take one: {each}");
    let before: Vec<u64> = cities.iter().map(|city| rules::boost(&db, city.id, topic)).collect();

    let opens = rules::shrines_open_at(&db);
    until(&mut db, opens);
    let energy = rules::hunt_of(&db, ada).energy;
    let rally = db.call(|db| rules::call_rally(db, ada, Hex::unpacked(shrine.hex), &spears(each), 0)).unwrap();
    assert_eq!((rally.barrow, rally.city, rally.hex), (0, 0, shrine.hex), "a holy site's rally names neither barrow nor city");
    db.call(|db| rules::join_rally(db, bryn, rally.id, &spears(each), 0)).unwrap();
    assert_eq!(rules::hunt_of(&db, ada).energy, energy, "no energy taken");
    until(&mut db, rally.sets_out);
    let last = [ada, bryn].iter().map(|player| rally_march(&db, *player).unwrap().arrives).max().unwrap();
    until(&mut db, last);
    assert_eq!(Table::<Shrine>::get(&db, shrine.id).unwrap().fighter, rally_march(&db, ada).unwrap().id, "the rally is at the site");
    until(&mut db, last + catalog::ASSAULT_SECONDS);

    // Taken: the site is the alliance's, the rally done, its armies home-bound.
    let taken = Table::<Shrine>::get(&db, shrine.id).unwrap();
    assert_eq!((taken.holder, taken.holder_name.as_str(), taken.taken_at, taken.fighter), (mere, "[MERE] Keepers of the Mere", last + catalog::ASSAULT_SECONDS, 0));
    assert!(Table::<Rally>::get(&db, rally.id).is_none());
    for player in [ada, bryn] {
        let told = reports(&db, player, Report::SHRINE);
        assert_eq!(told.len(), 1);
        assert!(told[0].won);
        assert_eq!(told[0].foe, shrine.id);
        let begins = format!("Your alliance's rally took {}: 2 armies, ", kind.name());
        assert!(told[0].words.starts_with(&begins), "{}", told[0].words);
        assert!(told[0].words.contains(&kind.words()), "{}", told[0].words);
        assert_eq!(rally_march(&db, player).unwrap().state, March::RETURNING);
    }
    // Its members' cities have what it lends; one outside does not.
    let after: Vec<u64> = cities.iter().map(|city| rules::boost(&db, city.id, topic)).collect();
    let lent = topic.each() * levels as u64;
    assert_eq!(after, vec![before[0] + lent, before[1] + lent, before[2]]);
    assert_eq!(rules::hallowed(&db, cities[0].id, topic), levels);
    assert_eq!(db.call(|db| rules::call_rally(db, ada, Hex::unpacked(shrine.hex), &spears(10), 0)), Err(Refusal::OwnShrine));

    // A second of a kind lends no more; another kind lends its own.
    let mut others: Vec<Shrine> = Table::<Shrine>::all(&db).into_iter().filter(|other| other.id != shrine.id).collect();
    others.sort_by_key(|other| other.id);
    let mut twin = others.iter().find(|other| other.kind == shrine.kind).unwrap().clone();
    twin.holder = mere;
    db.update(twin);
    assert_eq!(rules::hallowed(&db, cities[0].id, topic), levels, "two of a kind lend as one");
    let mut heart = others.iter().find(|other| other.kind == Holy::Heartstone as u8).unwrap().clone();
    heart.holder = mere;
    db.update(heart.clone());
    for (lent, levels) in Holy::Heartstone.lends() {
        assert_eq!(rules::hallowed(&db, cities[0].id, *lent), *levels);
        assert_eq!(rules::hallowed(&db, cities[2].id, *lent), 0);
    }

    // Another alliance may not storm it within the day it was taken.
    let wardens = db.call(|db| rules::found_alliance(db, cole, "Wardens of the Shore", "WRD")).unwrap();
    let guarded = rules::shrine_guarded_until(&db, &taken);
    assert_eq!(guarded, taken.taken_at + catalog::DAY);
    assert_eq!(db.call(|db| rules::call_rally(db, cole, Hex::unpacked(shrine.hex), &spears(10), 0)), Err(Refusal::ShrineGuarded(guarded - db.clock)));
    assert_eq!(Refusal::ShrineGuarded(3_600).to_string(), "That holy site was taken lately. It may be stormed again in 1 hour.");
    // Nor at truce with its holder.
    until(&mut db, guarded);
    let envoy = db.call(|db| rules::send_envoy(db, cole, mere, realm::rows::Pact::TRUCE, 3)).unwrap();
    db.call(|db| rules::answer_envoy(db, ada, envoy.id, true)).unwrap();
    assert_eq!(db.call(|db| rules::call_rally(db, cole, Hex::unpacked(shrine.hex), &spears(10), 0)), Err(Refusal::AtTruce));
    let _ = wardens;
}

#[test]
fn a_holy_site_taken_from_an_alliance_is_lent_to_its_taker_and_its_members_are_told() {
    let (mut db, players, cities, mere) = allies(&["Ada", "Bryn", "Cole", "Dara"], &["Cole", "Dara"]);
    let (ada, bryn, cole, dara) = (players[0], players[1], players[2], players[3]);
    let wardens = db.call(|db| rules::found_alliance(db, cole, "Wardens of the Shore", "WRD")).unwrap();
    db.call(|db| rules::join_alliance(db, dara, wardens.id)).unwrap();
    let shrine = shrine_near(&db, &cities[2]);
    let kind = Holy::of(shrine.kind).unwrap();
    let (topic, levels) = kind.lends()[0];
    let opens = rules::shrines_open_at(&db);
    until(&mut db, opens);
    let mut held = Table::<Shrine>::get(&db, shrine.id).unwrap();
    (held.holder, held.holder_name, held.taken_at) = (mere, "[MERE] Keepers of the Mere".into(), db.clock - catalog::DAY);
    db.update(held);
    assert_eq!(rules::hallowed(&db, cities[0].id, topic), levels);

    let ended = rally_out(&mut db, cole, dara, Hex::unpacked(shrine.hex), enough(kind));
    let taken = Table::<Shrine>::get(&db, shrine.id).unwrap();
    assert_eq!((taken.holder, taken.taken_at), (wardens.id, ended));
    assert_eq!(rules::hallowed(&db, cities[0].id, topic), 0, "the Keepers have it no more");
    assert_eq!(rules::hallowed(&db, cities[2].id, topic), levels, "the Wardens have it");
    for player in [ada, bryn] {
        let told = reports(&db, player, Report::SHRINE);
        assert_eq!(told.len(), 1, "each Keeper is told");
        assert!(!told[0].won);
        assert_eq!(told[0].words, format!("[WRD] Wardens of the Shore took {} from your alliance. What it lent your cities is lent no more.", kind.name()));
    }
}

#[test]
fn a_rally_beaten_at_a_holy_site_leaves_it_kept_and_one_finding_it_taken_turns_home() {
    let (mut db, players, cities, mere) = allies(&["Ada", "Bryn"], &[]);
    let (ada, bryn) = (players[0], players[1]);
    let shrine = shrine_near(&db, &cities[0]);
    let kind = Holy::of(shrine.kind).unwrap();
    let opens = rules::shrines_open_at(&db);
    until(&mut db, opens);

    // Too few: beaten, each army told of its own losses, the site the Unquiet's still.
    rally_out(&mut db, ada, bryn, Hex::unpacked(shrine.hex), 400);
    assert_eq!(Table::<Shrine>::get(&db, shrine.id).map(|shrine| (shrine.holder, shrine.fighter)), Some((0, 0)));
    for player in [ada, bryn] {
        let told = reports(&db, player, Report::SHRINE);
        assert_eq!(told.len(), 1);
        assert!(!told[0].won);
        assert_eq!(told[0].fought, 400);
        let begins = format!("Your alliance's rally was beaten at {}: 2 armies, 800 soldiers in all. ", kind.name());
        assert!(told[0].words.starts_with(&begins), "{}", told[0].words);
    }

    // A rally whose site is its own alliance's by the time its last army is up turns for home.
    wait(&mut db, 100_000);
    let again = db.call(|db| rules::call_rally(db, ada, Hex::unpacked(shrine.hex), &spears(500), 0)).unwrap();
    db.call(|db| rules::join_rally(db, bryn, again.id, &spears(300), 0)).unwrap();
    until(&mut db, again.sets_out);
    let last = [ada, bryn].iter().map(|player| rally_march(&db, *player).unwrap().arrives).max().unwrap();
    let mut held = Table::<Shrine>::get(&db, shrine.id).unwrap();
    held.holder = mere;
    db.update(held);
    until(&mut db, last);
    assert!(Table::<Rally>::get(&db, again.id).is_none());
    for player in [ada, bryn] {
        assert_eq!(rally_march(&db, player).unwrap().state, March::RETURNING);
        let words = reports(&db, player, Report::SHRINE).last().unwrap().words.clone();
        assert!(words.starts_with(&format!("Your alliance's rally found {} held by your own alliance", kind.name())), "{words}");
    }
    assert_eq!(Table::<Shrine>::get(&db, shrine.id).unwrap().fighter, 0);

    // A rally no one joins stands down, its caller told.
    wait(&mut db, 100_000);
    let mut freed = Table::<Shrine>::get(&db, shrine.id).unwrap();
    freed.holder = 0;
    db.update(freed);
    let alone = db.call(|db| rules::call_rally(db, ada, Hex::unpacked(shrine.hex), &spears(500), 0)).unwrap();
    until(&mut db, alone.sets_out);
    assert!(Table::<Rally>::get(&db, alone.id).is_none());
    assert_eq!(reports(&db, ada, Report::SHRINE).last().unwrap().words, format!("No one joined your rally against {}. Your army has stood down.", kind.name()));
}

#[test]
fn the_seasons_turn_gives_the_holy_sites_back_to_the_unquiet_but_the_victors() {
    let (mut db, players, cities, mere) = allies(&["Ada", "Bryn", "Cole"], &["Cole"]);
    let cole = players[2];
    let wardens = db.call(|db| rules::found_alliance(db, cole, "Wardens of the Shore", "WRD")).unwrap();
    let mut shrines: Vec<Shrine> = Table::<Shrine>::all(&db);
    shrines.sort_by_key(|shrine| shrine.id);
    let holders = [mere, wardens.id, mere];
    for (shrine, holder) in shrines.iter_mut().zip(holders) {
        shrine.holder = holder;
        db.update(shrine.clone());
    }
    let wardens_lent = Holy::of(shrines[1].kind).unwrap().lends()[0];
    assert_eq!(rules::hallowed(&db, cities[2].id, wardens_lent.0), wardens_lent.1);
    let mut season = rules::season_now(&db);
    (season.victor, season.victor_name) = (mere, "Keepers of the Mere".into());
    db.update(season.clone());
    until(&mut db, season.ends);

    assert_eq!(rules::season_now(&db).number, 2);
    let mut after: Vec<Shrine> = Table::<Shrine>::all(&db);
    after.sort_by_key(|shrine| shrine.id);
    assert_eq!(after.iter().take(4).map(|shrine| shrine.holder).collect::<Vec<u64>>(), vec![mere, 0, mere, 0], "the victor keeps what it held; the rest go back");
    assert_eq!(rules::hallowed(&db, cities[2].id, wardens_lent.0), 0);
    assert_eq!(rules::shrines_open_at(&db), rules::season_now(&db).began + 3 * catalog::DAY, "shut again three days into the new season");

    // An alliance that ends gives back the sites it held.
    wait(&mut db, 10);
    db.call(|db| rules::leave_alliance(db, players[1])).unwrap();
    db.call(|db| rules::leave_alliance(db, players[0])).unwrap();
    assert!(Table::<Shrine>::all(&db).iter().all(|shrine| shrine.holder == 0));
}

#[test]
fn every_realm_has_all_thirteen_holy_sites_whatever_its_seed_and_size() {
    for seed in 0..300u64 {
        for radius in [24u32, 48, 128] {
            let spots = land::shrines(seed, radius);
            assert_eq!(spots.len(), 13, "seed {seed}, radius {radius}");
            for (hex, kind) in &spots {
                let inner = *kind == Holy::Heartstone;
                assert_eq!(land::lakeland(radius, *hex), inner, "seed {seed}, radius {radius}: {hex:?}");
                assert!(land::ground(seed, radius, *hex).is_open() && land::ground(seed, radius, *hex) != realm::land::Ground::Shallows);
            }
        }
    }
}
