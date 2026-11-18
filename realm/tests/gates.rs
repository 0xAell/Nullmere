//! The gates of the ridge over a store kept in memory: held by the
//! Unquiet as the realm opens and barring every army, shut to rallies
//! until a week into the season, taken by a rally, passed and moved
//! within by the alliance that holds one, and given back at the season's
//! turn but by its victor.

use realm::catalog::{self, Building as Kind, Troops, Unit};
use realm::hex::Hex;
use realm::land;
use realm::rows::{Building, City, Gate, March, Place, Rally, Report, Season, Site, Stock, Troop};
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

/// The gate nearest a city that a way leads to, every gate barred but the
/// one gone to.
fn gate_near(city: &City) -> Hex {
    let from = Hex::unpacked(city.hex);
    let gates = land::gates(RADIUS);
    let mut near: Vec<Hex> = gates.to_vec();
    near.sort_by_key(|gate| (gate.distance(from), gate.packed()));
    near.into_iter().find(|gate| land::way_by(SEED, RADIUS, from, *gate, |hex| gates.contains(&hex)).is_some()).expect("a gate within reach")
}

/// A site of the lake country that a way leads to from a city through
/// one gate, the others barred.
fn site_within(db: &Mem, city: &City, gate: Hex) -> Site {
    let from = Hex::unpacked(city.hex);
    let gates = land::gates(RADIUS);
    let mut sites: Vec<Site> = Table::<Site>::all(db).into_iter().filter(|site| land::lakeland(RADIUS, Hex::unpacked(site.hex))).collect();
    sites.sort_by_key(|site| (Hex::unpacked(site.hex).distance(gate), site.id));
    sites
        .into_iter()
        .find(|site| land::way_by(SEED, RADIUS, from, Hex::unpacked(site.hex), |hex| hex != gate && gates.contains(&hex)).is_some())
        .expect("a site of the lake country through the gate")
}

fn reports(db: &Mem, player: u64, kind: u8) -> Vec<Report> {
    let mut all: Vec<Report> = Table::<Report>::by(db, 0, player).into_iter().filter(|report| report.kind == kind).collect();
    all.sort_by_key(|report| report.id);
    all
}

fn rally_march(db: &Mem, player: u64) -> Option<March> {
    Table::<March>::by(db, 0, player).into_iter().find(|march| march.kind == March::RALLY)
}

#[test]
fn the_gates_stand_in_the_passes_held_by_the_unquiet_and_bar_every_army() {
    let (mut db, players, cities, _) = allies(&["Ada", "Bryn"], &[]);
    let ada = players[0];
    let gates: Vec<Gate> = (1..=6).map(|id| Table::<Gate>::get(&db, id).unwrap()).collect();
    assert_eq!(gates.iter().map(|gate| gate.hex).collect::<Vec<u64>>(), land::gates(RADIUS).map(|hex| hex.packed()).to_vec());
    assert!(gates.iter().all(|gate| (gate.holder, gate.fighter) == (0, 0)), "the Unquiet hold every gate");
    for gate in &gates {
        assert_eq!(Table::<Place>::get(&db, gate.hex), Some(Place { hex: gate.hex, kind: Place::GATE, id: gate.id }));
        assert_eq!(rules::gate_at(&db, Hex::unpacked(gate.hex)).map(|found| found.id), Some(gate.id));
    }
    // Every city is settled in the outer land.
    assert!(Table::<City>::all(&db).iter().all(|city| Hex::unpacked(city.hex).length() >= land::outer_from(RADIUS)));

    // No army passes a gate its alliance does not hold: the lake country is shut.
    let gate = gate_near(&cities[0]);
    let site = site_within(&db, &cities[0], gate);
    assert_eq!(db.call(|db| rules::send(db, ada, Hex::unpacked(site.hex), March::GATHER, &spears(100))), Err(Refusal::NoWay));
    assert_eq!(rules::gates_barred_to(&db, ada).len(), 6);
    // Nor does a city move into it.
    let within = Hex::new(0, 0)
        .within(RADIUS)
        .into_iter()
        .filter(|hex| land::lakeland(RADIUS, *hex) && land::ground(SEED, RADIUS, *hex).is_buildable() && hex.within(2).iter().all(|near| Table::<Place>::get(&db, near.packed()).is_none()))
        .max_by_key(|hex| (hex.length(), hex.packed()))
        .unwrap();
    assert_eq!(db.call(|db| rules::relocate(db, ada, within)), Err(Refusal::LakelandShut));
    assert_eq!(Refusal::LakelandShut.to_string(), "Only an alliance that holds a gate of the ridge may move into the lake country.");

    // A rally against a gate waits a week into the season.
    let opens = rules::gates_open_at(&db);
    assert_eq!(opens, START + 7 * catalog::DAY);
    assert_eq!(db.call(|db| rules::call_rally(db, ada, gate, &spears(100), 0)), Err(Refusal::GatesShut(opens - db.clock)));
    assert_eq!(Refusal::GatesShut(3 * catalog::DAY).to_string(), "The gates of the ridge may be stormed in 3 days.");
    // And an army goes against one only in a rally.
    assert_eq!(db.call(|db| rules::send(db, ada, gate, March::ATTACK, &spears(100))), Err(Refusal::NoCityThere));
}

#[test]
fn a_rally_takes_a_gate_and_its_alliance_passes_it_and_moves_within() {
    let (mut db, players, cities, mere) = allies(&["Ada", "Bryn", "Cole"], &["Cole"]);
    let (ada, bryn, cole) = (players[0], players[1], players[2]);
    let gate = gate_near(&cities[0]);
    let id = rules::gate_at(&db, gate).unwrap().id;
    // Enough to take it when chance gives neither side anything, and as much again.
    let garrison = catalog::gate_garrison();
    let enough = (1..200)
        .map(|thousands| thousands * 1_000)
        .find(|count| rules::fight_sheltered(&[Unit { kind: Troops::Spearmen, tier: 5, count: *count }], &garrison, catalog::gate_shelter(), || 10).won)
        .expect("some number is enough");
    assert!(enough <= 50_000, "a rally can take a gate: {enough}");

    let opens = rules::gates_open_at(&db);
    until(&mut db, opens);
    let energy = rules::hunt_of(&db, ada).energy;
    let shield = Table::<City>::get(&db, cities[0].id).unwrap().shield;
    let rally = db.call(|db| rules::call_rally(db, ada, gate, &spears(enough), 0)).unwrap();
    assert_eq!((rally.barrow, rally.city, rally.hex), (0, 0, gate.packed()), "a gate's rally names neither barrow nor city");
    db.call(|db| rules::join_rally(db, bryn, rally.id, &spears(enough), 0)).unwrap();
    assert_eq!(rules::hunt_of(&db, ada).energy, energy, "no energy taken");
    assert_eq!(Table::<City>::get(&db, cities[0].id).unwrap().shield, shield, "nor the caller's peace");
    assert_eq!(db.call(|db| rules::call_rally(db, bryn, gate, &spears(10), 0)), Err(Refusal::AlreadyRallying));

    until(&mut db, rally.sets_out);
    let last = [ada, bryn].iter().map(|player| rally_march(&db, *player).unwrap().arrives).max().unwrap();
    until(&mut db, last);
    assert_eq!(rules::gate_at(&db, gate).unwrap().fighter, rally_march(&db, ada).unwrap().id, "the rally is at the gate");
    until(&mut db, last + catalog::ASSAULT_SECONDS);

    // Taken: the gate is the alliance's, the rally done, its armies home-bound.
    let taken = Table::<Gate>::get(&db, id).unwrap();
    assert_eq!((taken.holder, taken.holder_name.as_str(), taken.taken_at, taken.fighter), (mere, "[MERE] Keepers of the Mere", last + catalog::ASSAULT_SECONDS, 0));
    assert!(Table::<Rally>::get(&db, rally.id).is_none());
    for player in [ada, bryn] {
        let told = reports(&db, player, Report::GATE);
        assert_eq!(told.len(), 1);
        assert!(told[0].won);
        assert!(told[0].words.starts_with("Your alliance's rally took a gate of the ridge: 2 armies, "), "{}", told[0].words);
        assert_eq!(rally_march(&db, player).unwrap().state, March::RETURNING);
    }
    assert!(rules::holds_gate(&db, mere));
    assert_eq!(db.call(|db| rules::call_rally(db, ada, gate, &spears(10), 0)), Err(Refusal::OwnGate));
    wait(&mut db, 20_000);

    // Its members pass it; one outside does not.
    let site = site_within(&db, &cities[0], gate);
    assert_eq!(rules::gates_barred_to(&db, ada).len(), 5);
    db.call(|db| rules::send(db, ada, Hex::unpacked(site.hex), March::GATHER, &spears(100))).unwrap();
    assert_eq!(db.call(|db| rules::send(db, cole, Hex::unpacked(site.hex), March::GATHER, &spears(100))), Err(Refusal::NoWay));
    // And may move into the lake country, once no army of theirs is out.
    wait(&mut db, 100_000);
    let within = Hex::new(0, 0)
        .within(RADIUS)
        .into_iter()
        .filter(|hex| land::lakeland(RADIUS, *hex) && land::ground(SEED, RADIUS, *hex).is_buildable() && hex.within(2).iter().all(|near| Table::<Place>::get(&db, near.packed()).is_none()))
        .max_by_key(|hex| (hex.length(), hex.packed()))
        .unwrap();
    assert_eq!(db.call(|db| rules::relocate(db, cole, within)), Err(Refusal::LakelandShut));
    let moved = db.call(|db| rules::relocate(db, bryn, within)).unwrap();
    assert_eq!(moved.hex, within.packed());
}

#[test]
fn the_seasons_turn_gives_the_gates_back_to_the_unquiet_but_the_victors() {
    let (mut db, players, _, mere) = allies(&["Ada", "Bryn", "Cole"], &["Cole"]);
    let cole = players[2];
    let wardens = db.call(|db| rules::found_alliance(db, cole, "Wardens of the Shore", "WRD")).unwrap();
    let mut gates: Vec<Gate> = (1..=3).map(|id| Table::<Gate>::get(&db, id).unwrap()).collect();
    (gates[0].holder, gates[1].holder, gates[2].holder) = (mere, wardens.id, mere);
    for gate in &gates {
        db.update(gate.clone());
    }
    let mut season = rules::season_now(&db);
    (season.victor, season.victor_name) = (mere, "Keepers of the Mere".into());
    db.update(season.clone());
    until(&mut db, season.ends);

    assert_eq!(rules::season_now(&db).number, 2);
    let holders: Vec<u64> = (1..=6).map(|id| Table::<Gate>::get(&db, id).unwrap().holder).collect();
    assert_eq!(holders, vec![mere, 0, mere, 0, 0, 0], "the victor keeps what it held; the rest go back to the Unquiet");
    assert!(Table::<Season>::get(&db, 2).is_some());

    // An alliance that ends gives back the gates it held.
    wait(&mut db, 10);
    db.call(|db| rules::leave_alliance(db, players[1])).unwrap();
    db.call(|db| rules::leave_alliance(db, players[0])).unwrap();
    assert!((1..=6).all(|id| Table::<Gate>::get(&db, id).unwrap().holder == 0));
}

#[test]
fn a_rally_beaten_at_a_gate_leaves_it_held_and_one_finding_it_their_own_turns_home() {
    let (mut db, players, cities, mere) = allies(&["Ada", "Bryn"], &[]);
    let (ada, bryn) = (players[0], players[1]);
    let gate = gate_near(&cities[0]);
    let id = rules::gate_at(&db, gate).unwrap().id;
    let opens = rules::gates_open_at(&db);
    until(&mut db, opens);

    // Too few: beaten, each army told of its own losses, the gate the Unquiet's still.
    let rally = db.call(|db| rules::call_rally(db, ada, gate, &spears(500), 0)).unwrap();
    db.call(|db| rules::join_rally(db, bryn, rally.id, &spears(300), 0)).unwrap();
    until(&mut db, rally.sets_out);
    let last = [ada, bryn].iter().map(|player| rally_march(&db, *player).unwrap().arrives).max().unwrap();
    until(&mut db, last + catalog::ASSAULT_SECONDS);
    assert_eq!(Table::<Gate>::get(&db, id).map(|gate| (gate.holder, gate.fighter)), Some((0, 0)));
    for (player, sent) in [(ada, 500), (bryn, 300)] {
        let told = reports(&db, player, Report::GATE);
        assert_eq!(told.len(), 1);
        assert!(!told[0].won);
        assert_eq!(told[0].fought, sent);
        assert!(told[0].words.starts_with("Your alliance's rally was beaten at a gate of the ridge: 2 armies, 800 soldiers in all. "), "{}", told[0].words);
    }

    // A rally whose gate is its own alliance's by the time its last army is up turns for home.
    wait(&mut db, 100_000);
    let again = db.call(|db| rules::call_rally(db, ada, gate, &spears(500), 0)).unwrap();
    db.call(|db| rules::join_rally(db, bryn, again.id, &spears(300), 0)).unwrap();
    until(&mut db, again.sets_out);
    let last = [ada, bryn].iter().map(|player| rally_march(&db, *player).unwrap().arrives).max().unwrap();
    let mut held = Table::<Gate>::get(&db, id).unwrap();
    held.holder = mere;
    db.update(held);
    until(&mut db, last);
    assert!(Table::<Rally>::get(&db, again.id).is_none());
    for player in [ada, bryn] {
        assert_eq!(rally_march(&db, player).unwrap().state, March::RETURNING);
        assert!(reports(&db, player, Report::GATE).last().unwrap().words.starts_with("Your alliance's rally found its gate held by your own alliance"));
    }
    assert_eq!(Table::<Gate>::get(&db, id).unwrap().fighter, 0);
}

#[test]
fn with_every_gate_barred_no_way_crosses_the_ridge_and_none_is_looked_for() {
    // Searched in full, no way leads from the outer land into the lake
    // country, nor out of it, through the ridge with all six gates barred:
    // which is why the rules refuse such a way without searching.
    let gates = land::gates(RADIUS);
    let open = |hex: &Hex| land::ground(SEED, RADIUS, *hex).is_open();
    let all = Hex::new(0, 0).within(RADIUS);
    let inner: Vec<Hex> = all.iter().copied().filter(|hex| land::lakeland(RADIUS, *hex) && open(hex)).step_by(97).take(3).collect();
    let outer: Vec<Hex> = all.iter().copied().filter(|hex| hex.length() >= land::outer_from(RADIUS) && open(hex)).step_by(211).take(3).collect();
    assert_eq!((inner.len(), outer.len()), (3, 3));
    for from in &outer {
        for to in &inner {
            assert!(land::way_by(SEED, RADIUS, *from, *to, |hex| gates.contains(&hex)).is_none(), "{from:?} to {to:?}");
            assert!(land::way_by(SEED, RADIUS, *to, *from, |hex| gates.contains(&hex)).is_none(), "{to:?} to {from:?}");
        }
    }

    // And the rules refuse at once an army or carts sent across it.
    let (mut db, players, cities, _) = allies(&["Ada", "Bryn"], &[]);
    let site = Table::<Site>::all(&db).into_iter().find(|site| land::lakeland(RADIUS, Hex::unpacked(site.hex))).unwrap();
    assert_eq!(db.call(|db| rules::send(db, players[0], Hex::unpacked(site.hex), March::GATHER, &spears(100))), Err(Refusal::NoWay));
    // With one gate held, the same army goes.
    let mut gate = Table::<Gate>::get(&db, 1).unwrap();
    gate.holder = realm::rules::member_of(&db, players[0]).unwrap().alliance;
    db.update(gate);
    let through = gate_near(&cities[0]);
    let mut held = rules::gate_at(&db, through).unwrap();
    held.holder = realm::rules::member_of(&db, players[0]).unwrap().alliance;
    db.update(held);
    let site = site_within(&db, &cities[0], through);
    assert!(db.call(|db| rules::send(db, players[0], Hex::unpacked(site.hex), March::GATHER, &spears(100))).is_ok());
    let _ = players[1];
}
