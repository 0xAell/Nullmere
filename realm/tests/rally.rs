//! Rallies over a store kept in memory: called, joined, mustering,
//! setting out, waiting at the barrow, fighting as one, and what each
//! army brings home.

use realm::catalog::{self, Building as Kind, Contest, Troops, Unit};
use realm::hex::Hex;
use realm::land;
use realm::rows::{Barrow, Building, City, Haul, Hunt, March, Muster, Place, Rally, Report, Squad, Stock, Troop};
use realm::rules::{self, Asked, Refusal};
use realm::store::{Mem, Seconds, Table};

const START: Seconds = 3_000_000;
const SEED: u64 = 7;
const RADIUS: u32 = 48;

fn wait(db: &mut Mem, seconds: Seconds) {
    let to = db.clock + seconds;
    db.advance(to, |db, timer| rules::fire(db, timer));
}

/// Moves the clock on to a moment.
fn until(db: &mut Mem, moment: Seconds) {
    db.advance(moment, |db, timer| rules::fire(db, timer));
}

/// A realm of players of these names, each with a Keep at its eighth
/// level, an Embassy, and spearmen enough for anything here; all but
/// those named in `apart` in one alliance, founded by the first.
fn allies(names: &[&str], apart: &[&str]) -> (Mem, Vec<u64>, Vec<City>) {
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
        rules::keep_troop(&mut db, Troop { id: Troop::key(city.id, Troops::Spearmen as u8, 1), city: city.id, kind: Troops::Spearmen as u8, tier: 1, ready: 50_000, wounded: 0 });
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

fn spears(count: u64) -> Vec<Asked> {
    vec![Asked { kind: Troops::Spearmen as u8, tier: 1, count }]
}

/// The barrow nearest a city that a way leads to, set to a level.
fn barrow_near(db: &mut Mem, city: &City, level: u32) -> Barrow {
    let from = Hex::unpacked(city.hex);
    let mut barrows = Table::<Barrow>::all(db);
    barrows.sort_by_key(|barrow| (Hex::unpacked(barrow.hex).distance(from), barrow.id));
    let mut barrow = barrows.into_iter().find(|barrow| land::way(SEED, RADIUS, from, Hex::unpacked(barrow.hex)).is_some()).expect("a barrow within reach");
    barrow.level = level;
    db.update(barrow.clone());
    barrow
}

/// How many spearmen of the first tier one army needs to beat a barrow
/// when chance gives neither side anything.
fn enough_for(level: u32) -> u64 {
    let unquiet = catalog::barrow(level);
    (1..400).map(|hundreds| hundreds * 100).find(|count| rules::fight(&[Unit { kind: Troops::Spearmen, tier: 1, count: *count }], &unquiet, || 10).won).expect("some number is enough")
}

fn ready(db: &Mem, city: &City) -> u64 {
    rules::troop(db, city.id, Troops::Spearmen, 1).ready
}

fn energy(db: &Mem, player: u64) -> u32 {
    rules::hunt_of(db, player).energy
}

fn rally_march(db: &Mem, player: u64) -> Option<March> {
    Table::<March>::by(db, 0, player).into_iter().find(|march| march.kind == March::RALLY)
}

#[test]
fn a_member_calls_a_rally_against_a_barrow_beyond_their_own_reach() {
    let (mut db, players, cities) = allies(&["Ada", "Bryn", "Cole"], &["Cole"]);
    let (ada, cole) = (players[0], players[2]);
    let barrow = barrow_near(&mut db, &cities[0], 4);
    let to = Hex::unpacked(barrow.hex);

    // Alone, a barrow of the fourth level is three too strong for one who has cleared none.
    assert_eq!(db.call(|db| rules::send(db, ada, to, March::HUNT, &spears(100))), Err(Refusal::TooStrong(3)));
    // Only a member of an alliance calls a rally, and an army goes to one no other way.
    assert_eq!(db.call(|db| rules::call_rally(db, cole, to, &spears(100), 0)), Err(Refusal::NotAllied));
    assert_eq!(db.call(|db| rules::send(db, ada, to, March::RALLY, &spears(100))), Err(Refusal::NoSuchOrder));
    assert_eq!(db.call(|db| rules::call_rally(db, ada, Hex::unpacked(cities[0].hex), &spears(100), 0)), Err(Refusal::OwnCity));
    let empty = Hex::unpacked(cities[0].hex).within(3).into_iter().find(|hex| Table::<Place>::get(&db, hex.packed()).is_none()).unwrap();
    assert_eq!(db.call(|db| rules::call_rally(db, ada, empty, &spears(100), 0)), Err(Refusal::NothingToFight));

    let rally = db.call(|db| rules::call_rally(db, ada, to, &spears(1_000), 0)).unwrap();
    assert_eq!((rally.caller, rally.barrow, rally.level, rally.state, rally.armies, rally.soldiers), (ada, barrow.id, 4, Rally::MUSTERING, 1, 1_000));
    assert_eq!(rally.sets_out, db.clock + catalog::RALLY_MUSTER);
    assert!(rally.name.contains("Ada"));
    // Its army is out of the city, mustering there until the rally sets out; the attack's energy is spent.
    let march = rally_march(&db, ada).unwrap();
    assert_eq!((march.state, march.arrives, march.target, march.soldiers), (March::MUSTERING, rally.sets_out, barrow.id, 1_000));
    assert_eq!(ready(&db, &cities[0]), 49_000);
    assert_eq!(energy(&db, ada), 950);
    assert_eq!(Table::<Muster>::get(&db, march.id), Some(Muster { march: march.id, rally: rally.id, player: ada, arrived: false }));
    assert_eq!(Table::<Barrow>::get(&db, barrow.id).unwrap().fighter, 0, "the barrow is no one's until they are all there");

    // One rally at a time for a player, and no further than three levels past their own reach.
    wait(&mut db, 3);
    assert_eq!(db.call(|db| rules::call_rally(db, ada, to, &spears(100), 0)), Err(Refusal::AlreadyRallying));
    let mut stronger = barrow_near(&mut db, &cities[1], 1);
    if stronger.id == barrow.id {
        stronger = Table::<Barrow>::all(&db).into_iter().find(|other| other.id != barrow.id).unwrap();
    }
    stronger.level = 5;
    db.update(stronger.clone());
    assert_eq!(db.call(|db| rules::call_rally(db, players[1], Hex::unpacked(stronger.hex), &spears(100), 0)), Err(Refusal::RallyTooStrong(4)));
    assert_eq!(Refusal::RallyTooStrong(4).to_string(), "A rally of yours may go against a barrow of level 4 at most.");
}

#[test]
fn allies_join_a_rally_while_it_musters_and_no_one_else_does() {
    let (mut db, players, cities) = allies(&["Ada", "Bryn", "Cole", "Dara", "Edda", "Finn", "Gwen"], &["Cole"]);
    let (ada, bryn, cole) = (players[0], players[1], players[2]);
    let barrow = barrow_near(&mut db, &cities[0], 3);
    let to = Hex::unpacked(barrow.hex);
    let rally = db.call(|db| rules::call_rally(db, ada, to, &spears(500), 0)).unwrap();

    // An ally joins with an army of their own, which musters in their own city.
    let joined = db.call(|db| rules::join_rally(db, bryn, rally.id, &spears(700), 0)).unwrap();
    assert_eq!((joined.armies, joined.soldiers), (2, 1_200));
    let march = rally_march(&db, bryn).unwrap();
    assert_eq!((march.state, march.city, march.arrives, march.to), (March::MUSTERING, cities[1].id, rally.sets_out, barrow.hex));
    assert_eq!(energy(&db, bryn), 950);

    // Not twice; not one who is in no alliance, or in another; not a second rally against the same barrow.
    wait(&mut db, 3);
    assert_eq!(db.call(|db| rules::join_rally(db, bryn, rally.id, &spears(10), 0)), Err(Refusal::AlreadyRallying));
    assert_eq!(db.call(|db| rules::join_rally(db, cole, rally.id, &spears(10), 0)), Err(Refusal::NotAllied));
    db.call(|db| rules::found_alliance(db, cole, "Wardens", "WRD")).unwrap();
    wait(&mut db, 3);
    assert_eq!(db.call(|db| rules::join_rally(db, cole, rally.id, &spears(10), 0)), Err(Refusal::NoSuchRally));
    assert_eq!(db.call(|db| rules::join_rally(db, players[3], 999, &spears(10), 0)), Err(Refusal::NoSuchRally));
    assert_eq!(db.call(|db| rules::call_rally(db, players[3], to, &spears(10), 0)), Err(Refusal::RallyCalled));
    wait(&mut db, 3);
    // What is refused takes nothing: no soldiers, no energy.
    assert_eq!((ready(&db, &cities[3]), energy(&db, players[3])), (50_000, 1_000));

    // Five armies at most.
    for player in &players[3..6] {
        db.call(|db| rules::join_rally(db, *player, rally.id, &spears(100), 0)).unwrap();
    }
    assert_eq!(Table::<Rally>::get(&db, rally.id).unwrap().armies, 5);
    assert_eq!(db.call(|db| rules::join_rally(db, players[6], rally.id, &spears(100), 0)), Err(Refusal::RallyFull));

    // And not once it has set out.
    wait(&mut db, catalog::RALLY_MUSTER);
    assert_eq!(Table::<Rally>::get(&db, rally.id).map(|rally| rally.state), Some(Rally::MARCHING));
    assert_eq!(db.call(|db| rules::join_rally(db, players[6], rally.id, &spears(100), 0)), Err(Refusal::RallySetOut));
}

#[test]
fn a_rally_no_one_joins_stands_down_when_the_muster_ends() {
    let (mut db, players, cities) = allies(&["Ada", "Bryn"], &[]);
    let ada = players[0];
    let barrow = barrow_near(&mut db, &cities[0], 2);
    let rally = db.call(|db| rules::call_rally(db, ada, Hex::unpacked(barrow.hex), &spears(800), 0)).unwrap();
    wait(&mut db, catalog::RALLY_MUSTER - 1);
    assert!(rally_march(&db, ada).is_some(), "still mustering a second before");
    wait(&mut db, 1);
    assert!(rally_march(&db, ada).is_none());
    assert!(Table::<Rally>::get(&db, rally.id).is_none());
    assert!(Table::<Muster>::all(&db).is_empty());
    assert_eq!((ready(&db, &cities[0]), energy(&db, ada)), (50_000, 1_000), "the soldiers are ready again and the energy is back");
    let told = Table::<Report>::by(&db, 0, ada);
    assert_eq!(told.last().map(|report| report.words.as_str()), Some("No one joined your rally against the level 2 barrow. Your army has stood down."));
    assert_eq!(Table::<Barrow>::get(&db, barrow.id).unwrap().fighter, 0);
}

#[test]
fn the_armies_set_out_together_wait_for_the_last_and_clear_as_one_what_neither_could_alone() {
    let (mut db, players, cities) = allies(&["Ada", "Bryn"], &[]);
    let (ada, bryn) = (players[0], players[1]);
    let level = 4;
    let barrow = barrow_near(&mut db, &cities[0], level);
    let to = Hex::unpacked(barrow.hex);
    // Three quarters of what one army needs: too few alone whatever chance gives, enough together whatever it takes.
    let each = enough_for(level) * 3 / 4;
    let unquiet = catalog::barrow(level);
    assert!(!rules::fight(&[Unit { kind: Troops::Spearmen, tier: 1, count: each }], &unquiet, || 10).won);

    let rally = db.call(|db| rules::call_rally(db, ada, to, &spears(each), 0)).unwrap();
    db.call(|db| rules::join_rally(db, bryn, rally.id, &spears(each), 0)).unwrap();

    // The muster over, each sets out from its own city.
    wait(&mut db, catalog::RALLY_MUSTER);
    let (first, second) = (rally_march(&db, ada).unwrap(), rally_march(&db, bryn).unwrap());
    assert_eq!((first.state, second.state), (March::GOING, March::GOING));
    assert_eq!((first.from, second.from), (cities[0].hex, cities[1].hex));
    assert!(first.arrives > db.clock && second.arrives > db.clock);
    assert_eq!(db.call(|db| rules::recall(db, ada, first.id)), Err(Refusal::RallyUnderWay));

    // Whichever is there first waits for the other; the barrow is no one's meanwhile.
    let (sooner, later) = (first.arrives.min(second.arrives), first.arrives.max(second.arrives));
    if sooner < later {
        until(&mut db, sooner);
        let states: Vec<u8> = [ada, bryn].iter().map(|player| rally_march(&db, *player).unwrap().state).collect();
        assert!(states.contains(&March::WAITING) && states.contains(&March::GOING), "{states:?}");
        assert_eq!(Table::<Barrow>::get(&db, barrow.id).unwrap().fighter, 0);
        assert_eq!(Table::<Muster>::all(&db).iter().filter(|muster| muster.arrived).count(), 1);
    }

    // The last one up, the fight begins for both, and ends for both at one moment.
    until(&mut db, later);
    let (first, second) = (rally_march(&db, ada).unwrap(), rally_march(&db, bryn).unwrap());
    assert_eq!((first.state, second.state), (March::FIGHTING, March::FIGHTING));
    assert_eq!(first.arrives, second.arrives);
    assert_eq!(first.arrives, db.clock + catalog::FIGHT_SECONDS);
    assert_eq!(Table::<Rally>::get(&db, rally.id).unwrap().state, Rally::FIGHTING);
    assert_ne!(Table::<Barrow>::get(&db, barrow.id).unwrap().fighter, 0);
    assert_eq!(db.call(|db| rules::send(db, ada, to, March::GATHER, &spears(10))).is_err(), true);

    wait(&mut db, catalog::FIGHT_SECONDS);
    assert!(Table::<Barrow>::get(&db, barrow.id).is_none(), "together they cleared it");
    assert!(Table::<Place>::get(&db, barrow.hex).is_none());
    assert!(Table::<Rally>::get(&db, rally.id).is_none());
    assert!(Table::<Muster>::all(&db).is_empty());

    for (player, city) in [(ada, &cities[0]), (bryn, &cities[1])] {
        // Each army turns for home with what is left of it and its share of the spoils.
        let march = rally_march(&db, player).unwrap();
        assert_eq!(march.state, March::RETURNING);
        let squads: Vec<Squad> = Table::<Squad>::by(&db, 0, march.id);
        let (standing, wounded): (u64, u64) = (squads.iter().map(|squad| squad.count).sum(), squads.iter().map(|squad| squad.wounded).sum());
        assert_eq!(march.soldiers, standing);
        assert!(standing < each && standing > 0);
        assert!(wounded <= rules::room_for_wounded(&db, city.id) + wounded);
        let haul = Table::<Haul>::get(&db, march.id).expect("a share of the spoils");
        assert!(haul.grain + haul.timber + haul.stone + haul.moonsalt > 0);
        // Each is told, in their own numbers.
        let report = Table::<Report>::by(&db, 0, player).pop().unwrap();
        assert!(report.words.starts_with(&format!("Your alliance's rally cleared a level {level} barrow of the Unquiet: 2 armies, {} soldiers in all.", catalog::grouped(2 * each))), "{}", report.words);
        assert_eq!((report.won, report.fought, report.foe), (true, each, level as u64));
        assert_eq!(report.fought - report.wounded - report.dead, standing);
        // It counts for each as a barrow cleared today and in the hunt; what they may attack alone is as it was.
        assert_eq!(rules::daily_of(&db, player).cleared, 1);
        assert_eq!(rules::tally_of(&db, player, Contest::Hunt).points, 10 * level as u64);
        assert_eq!(Table::<Hunt>::get(&db, player).unwrap().cleared, 0);
    }
    // What the barrow yields for the Forge is the caller's, Ada's, and she is told of it.
    let held = |player: u64| realm::catalog::Item::MATERIALS.map(|item| rules::held(&db, player, item)).iter().sum::<u64>();
    assert_eq!((held(ada), held(bryn)), (level as u64, 0));
    assert!(Table::<Report>::by(&db, 0, ada).pop().unwrap().words.ends_with(" for the Forge."));
    // The spoils shared are no more than the barrow held.
    let shared: u64 = Table::<Haul>::all(&db).iter().map(|haul| haul.grain + haul.timber + haul.stone + haul.moonsalt).sum();
    assert!(shared <= catalog::spoils(level).parts().iter().sum::<u64>());

    // And home they come.
    wait(&mut db, 4 * 3_600);
    assert!(rally_march(&db, ada).is_none() && rally_march(&db, bryn).is_none());
    let home: u64 = ready(&db, &cities[0]) + rules::troop(&db, cities[0].id, Troops::Spearmen, 1).wounded;
    assert!(home <= 50_000 && home > 50_000 - each);
}

#[test]
fn a_rally_beaten_leaves_the_barrow_standing_and_each_army_its_own_losses() {
    let (mut db, players, cities) = allies(&["Ada", "Bryn"], &[]);
    let (ada, bryn) = (players[0], players[1]);
    let barrow = barrow_near(&mut db, &cities[0], 4);
    let rally = db.call(|db| rules::call_rally(db, ada, Hex::unpacked(barrow.hex), &spears(60), 0)).unwrap();
    db.call(|db| rules::join_rally(db, bryn, rally.id, &spears(20), 0)).unwrap();
    wait(&mut db, catalog::RALLY_MUSTER + 6 * 3_600);

    let standing = Table::<Barrow>::get(&db, barrow.id).expect("the barrow stands");
    assert_eq!(standing.fighter, 0, "and can be fought again");
    assert!(Table::<Rally>::all(&db).is_empty() && Table::<Muster>::all(&db).is_empty());
    for (player, brought) in [(ada, 60), (bryn, 20)] {
        let report = Table::<Report>::by(&db, 0, player).pop().unwrap();
        assert!(report.words.starts_with("Your alliance's rally was beaten at a level 4 barrow of the Unquiet: 2 armies, 80 soldiers in all."), "{}", report.words);
        assert_eq!((report.won, report.fought), (false, brought));
        assert_eq!(report.wounded + report.dead, brought, "everyone they brought fell");
        assert_eq!(rules::daily_of(&db, player).cleared, 0);
        assert!(rally_march(&db, player).is_none());
    }
}

#[test]
fn a_barrow_gone_before_they_are_all_there_turns_them_home_with_their_energy() {
    let (mut db, players, cities) = allies(&["Ada", "Bryn"], &[]);
    let (ada, bryn) = (players[0], players[1]);
    let barrow = barrow_near(&mut db, &cities[0], 3);
    let rally = db.call(|db| rules::call_rally(db, ada, Hex::unpacked(barrow.hex), &spears(900), 0)).unwrap();
    db.call(|db| rules::join_rally(db, bryn, rally.id, &spears(900), 0)).unwrap();
    wait(&mut db, catalog::RALLY_MUSTER);
    // Someone else clears it while they are on the road.
    Table::<Place>::delete(&mut db, barrow.hex);
    Table::<Barrow>::delete(&mut db, barrow.id);
    let last = rally_march(&db, ada).unwrap().arrives.max(rally_march(&db, bryn).unwrap().arrives);
    until(&mut db, last);
    for player in [ada, bryn] {
        let march = rally_march(&db, player).unwrap();
        assert_eq!(march.state, March::RETURNING);
        assert_eq!(march.soldiers, 900);
        assert_eq!(energy(&db, player), 1_000);
    }
    assert!(Table::<Rally>::all(&db).is_empty() && Table::<Muster>::all(&db).is_empty());
    wait(&mut db, 6 * 3_600);
    assert_eq!((ready(&db, &cities[0]), ready(&db, &cities[1])), (50_000, 50_000));
}

#[test]
fn an_army_stands_down_from_the_muster_and_the_callers_standing_down_ends_the_rally() {
    let (mut db, players, cities) = allies(&["Ada", "Bryn", "Cole"], &[]);
    let (ada, bryn, cole) = (players[0], players[1], players[2]);
    let barrow = barrow_near(&mut db, &cities[0], 2);
    let rally = db.call(|db| rules::call_rally(db, ada, Hex::unpacked(barrow.hex), &spears(400), 0)).unwrap();
    db.call(|db| rules::join_rally(db, bryn, rally.id, &spears(300), 0)).unwrap();
    db.call(|db| rules::join_rally(db, cole, rally.id, &spears(200), 0)).unwrap();
    wait(&mut db, 3);

    // A joiner calls their army home: it is out of the rally, the rest muster on.
    let march = rally_march(&db, cole).unwrap();
    db.call(|db| rules::recall(db, cole, march.id)).unwrap();
    assert!(rally_march(&db, cole).is_none());
    assert_eq!((ready(&db, &cities[2]), energy(&db, cole)), (50_000, 1_000));
    let left = Table::<Rally>::get(&db, rally.id).unwrap();
    assert_eq!((left.armies, left.soldiers), (2, 700));
    // And may join again.
    wait(&mut db, 3);
    db.call(|db| rules::join_rally(db, cole, rally.id, &spears(250), 0)).unwrap();

    // The caller calls theirs home: the rally is off for everyone.
    wait(&mut db, 3);
    let march = rally_march(&db, ada).unwrap();
    db.call(|db| rules::recall(db, ada, march.id)).unwrap();
    assert!(Table::<Rally>::all(&db).is_empty() && Table::<Muster>::all(&db).is_empty());
    for (player, city) in [(ada, &cities[0]), (bryn, &cities[1]), (cole, &cities[2])] {
        assert!(rally_march(&db, player).is_none());
        assert_eq!((ready(&db, city), energy(&db, player)), (50_000, 1_000));
    }
    // Nothing is left to fire when the muster would have ended.
    wait(&mut db, catalog::RALLY_MUSTER);
    assert!(Table::<March>::all(&db).is_empty());
    assert_eq!(Table::<Barrow>::get(&db, barrow.id).unwrap().fighter, 0);
}

/// Ends a city's peace, and leaves so many spearmen ready in it and so
/// much of each good in its store.
fn open_to_attack(db: &mut Mem, city: &City, spearmen: u64, each: u64) {
    let mut row = Table::<City>::get(db, city.id).unwrap();
    row.shield = 0;
    db.update(row);
    rules::keep_troop(db, Troop { id: Troop::key(city.id, Troops::Spearmen as u8, 1), city: city.id, kind: Troops::Spearmen as u8, tier: 1, ready: spearmen, wounded: 0 });
    let mut stock = rules::grown(&Table::<Stock>::get(db, city.id).unwrap(), db.clock);
    (stock.grain, stock.timber, stock.stone, stock.moonsalt) = (each, each, each, 0);
    db.update(stock);
}

fn reports(db: &Mem, player: u64, kind: u8) -> Vec<Report> {
    let mut all: Vec<Report> = Table::<Report>::by(db, 0, player).into_iter().filter(|report| report.kind == kind).collect();
    all.sort_by_key(|report| report.id);
    all
}

fn haul(db: &Mem, march: u64) -> u64 {
    Table::<Haul>::get(db, march).map(|haul| haul.grain + haul.timber + haul.stone + haul.moonsalt).unwrap_or(0)
}

fn stored(db: &Mem, city: &City) -> u64 {
    let stock = rules::grown(&Table::<Stock>::get(db, city.id).unwrap(), db.clock);
    stock.grain + stock.timber + stock.stone + stock.moonsalt
}

#[test]
fn a_rally_against_a_city_musters_marches_and_storms_it_together() {
    let (mut db, players, cities) = allies(&["Ada", "Bryn", "Cole"], &["Cole"]);
    let (ada, bryn, cole) = (players[0], players[1], players[2]);
    let walls = Hex::unpacked(cities[2].hex);

    // Not against one's own city, nor an ally's, nor one at peace.
    assert_eq!(db.call(|db| rules::call_rally(db, ada, Hex::unpacked(cities[1].hex), &spears(100), 0)), Err(Refusal::AllysCity));
    assert!(matches!(db.call(|db| rules::call_rally(db, ada, walls, &spears(100), 0)), Err(Refusal::AtPeace(_))));
    open_to_attack(&mut db, &cities[2], 500, 300_000);
    wait(&mut db, 10);

    let before = (energy(&db, ada), energy(&db, bryn));
    let rally = db.call(|db| rules::call_rally(db, ada, walls, &spears(3_000), 0)).unwrap();
    assert_eq!((rally.barrow, rally.city, rally.hex, rally.level, rally.state), (0, cities[2].id, cities[2].hex, cities[2].keep, Rally::MUSTERING));
    // A second rally against the same city is refused; joining it is how.
    assert_eq!(db.call(|db| rules::call_rally(db, bryn, walls, &spears(100), 0)), Err(Refusal::RallyCalled));
    db.call(|db| rules::join_rally(db, bryn, rally.id, &spears(2_000), 0)).unwrap();
    // No energy taken from either, as a hunt would; but each has given up their own city's peace.
    assert_eq!((energy(&db, ada), energy(&db, bryn)), before);
    for city in &cities[..2] {
        assert!(Table::<City>::get(&db, city.id).unwrap().shield <= db.clock, "a city in the rally is no longer at peace");
    }
    // The city's owner is warned as the rally is called.
    let warnings = reports(&db, cole, Report::WARNING);
    assert_eq!(warnings.len(), 1);
    assert!(warnings[0].words.starts_with("[MERE] Ada has called a rally against your city. Its armies set out in 5 minutes"), "{}", warnings[0].words);

    // The muster ends: both set out, and the owner is warned again, of when the last is at the walls.
    until(&mut db, rally.sets_out);
    let marches: Vec<March> = [ada, bryn].iter().map(|player| rally_march(&db, *player).unwrap()).collect();
    assert!(marches.iter().all(|march| march.state == March::GOING && march.target == cities[2].id));
    let last = marches.iter().map(|march| march.arrives).max().unwrap();
    let warnings = reports(&db, cole, Report::WARNING);
    assert_eq!(warnings.len(), 2);
    assert!(warnings[1].words.starts_with("[MERE] Ada's rally is marching on your city: 2 armies, 5,000 soldiers in all. The last of them is at your walls in "), "{}", warnings[1].words);

    // The last up, the assault begins, and lasts as long as one army's would.
    until(&mut db, last);
    let fighting: Vec<March> = [ada, bryn].iter().map(|player| rally_march(&db, *player).unwrap()).collect();
    assert!(fighting.iter().all(|march| march.state == March::FIGHTING && march.arrives == last + catalog::ASSAULT_SECONDS));
    assert_eq!(Table::<Rally>::get(&db, rally.id).unwrap().state, Rally::FIGHTING);
    let had = stored(&db, &cities[2]);
    until(&mut db, last + catalog::ASSAULT_SECONDS);

    // Taken by storm: the city at peace, the rally done, each army home-bound with its share.
    assert!(Table::<Rally>::get(&db, rally.id).is_none());
    assert_eq!(Table::<City>::get(&db, cities[2].id).unwrap().shield, db.clock + catalog::BEATEN_PEACE);
    let home: Vec<March> = [ada, bryn].iter().map(|player| rally_march(&db, *player).unwrap()).collect();
    assert!(home.iter().all(|march| march.state == March::RETURNING));
    assert!(Table::<Muster>::all(&db).is_empty());
    let (ada_took, bryn_took) = (haul(&db, home[0].id), haul(&db, home[1].id));
    assert!(ada_took > bryn_took && bryn_took > 0, "shared by what each can bear: {ada_took} and {bryn_took}");
    assert_eq!(had - stored(&db, &cities[2]), ada_took + bryn_took, "what left the city is what they carry");

    for (player, march) in [ada, bryn].iter().zip(&home) {
        let told = reports(&db, *player, Report::ATTACK);
        assert_eq!(told.len(), 1);
        assert!(told[0].won);
        assert!(told[0].words.starts_with("Your alliance's rally took Cole's city by storm: 2 armies, 5,000 soldiers in all. "), "{}", told[0].words);
        assert!(told[0].words.contains("Your army is bringing home"), "{}", told[0].words);
        assert_eq!(told[0].grain + told[0].timber + told[0].stone + told[0].moonsalt, haul(&db, march.id));
    }
    let defence = reports(&db, cole, Report::DEFENCE);
    assert_eq!(defence.len(), 1);
    assert!(!defence[0].won);
    assert_eq!((defence[0].foe, defence[0].stood), (ada, 5_000));
    assert!(defence[0].words.starts_with("Ada's rally of 2 armies took your city by storm and carried off "), "{}", defence[0].words);
    assert!(defence[0].words.ends_with(" Your city is at peace for 4 hours."), "{}", defence[0].words);
}

#[test]
fn a_rally_beaten_at_the_walls_leaves_each_army_its_own_losses() {
    let (mut db, players, cities) = allies(&["Ada", "Bryn", "Cole"], &["Cole"]);
    let (ada, bryn, cole) = (players[0], players[1], players[2]);
    open_to_attack(&mut db, &cities[2], 50_000, 300_000);
    wait(&mut db, 10);
    let rally = db.call(|db| rules::call_rally(db, ada, Hex::unpacked(cities[2].hex), &spears(1_000), 0)).unwrap();
    db.call(|db| rules::join_rally(db, bryn, rally.id, &spears(500), 0)).unwrap();
    until(&mut db, rally.sets_out);
    let last = [ada, bryn].iter().map(|player| rally_march(&db, *player).unwrap().arrives).max().unwrap();
    let had = stored(&db, &cities[2]);
    until(&mut db, last + catalog::ASSAULT_SECONDS);

    assert_eq!(stored(&db, &cities[2]), had, "nothing carried off");
    assert_eq!(Table::<City>::get(&db, cities[2].id).unwrap().shield, 0, "no peace for a city that held");
    let mut lost = 0;
    for (player, sent) in [(ada, 1_000), (bryn, 500)] {
        let told = reports(&db, player, Report::ATTACK);
        assert_eq!(told.len(), 1);
        assert!(!told[0].won);
        assert_eq!(told[0].fought, sent, "each is told of their own army");
        assert!(told[0].words.starts_with("Your alliance's rally was beaten at Cole's city: 2 armies, 1,500 soldiers in all. "), "{}", told[0].words);
        lost += told[0].wounded + told[0].dead;
    }
    let defence = reports(&db, cole, Report::DEFENCE);
    assert!(defence[0].won);
    assert!(defence[0].words.starts_with("Ada's rally of 2 armies attacked your city and was beaten. "), "{}", defence[0].words);
    assert_eq!(defence[0].fell, lost, "what the city's owner is told fell is what the armies lost");
}

#[test]
fn a_city_at_peace_when_the_last_army_comes_up_sends_the_rally_home_and_one_no_one_joins_stands_down() {
    let (mut db, players, cities) = allies(&["Ada", "Bryn", "Cole"], &["Cole"]);
    let (ada, bryn, cole) = (players[0], players[1], players[2]);
    open_to_attack(&mut db, &cities[2], 500, 300_000);
    wait(&mut db, 10);
    let rally = db.call(|db| rules::call_rally(db, ada, Hex::unpacked(cities[2].hex), &spears(1_000), 0)).unwrap();
    db.call(|db| rules::join_rally(db, bryn, rally.id, &spears(500), 0)).unwrap();
    until(&mut db, rally.sets_out);
    let last = [ada, bryn].iter().map(|player| rally_march(&db, *player).unwrap().arrives).max().unwrap();
    // The city comes under peace while they march.
    let mut city = Table::<City>::get(&db, cities[2].id).unwrap();
    city.shield = db.clock + 86_400;
    db.update(city);
    until(&mut db, last);
    assert!(Table::<Rally>::get(&db, rally.id).is_none());
    for player in [ada, bryn] {
        assert_eq!(rally_march(&db, player).unwrap().state, March::RETURNING);
        let told = reports(&db, player, Report::ATTACK);
        assert!(told[0].words.starts_with("Your alliance's rally found nothing to storm"), "{}", told[0].words);
    }
    assert!(reports(&db, cole, Report::DEFENCE).is_empty());

    // Home again, a rally no one joins stands down when its muster ends, its soldiers ready, no energy spent.
    wait(&mut db, 100_000);
    let mut row = Table::<City>::get(&db, cities[2].id).unwrap();
    row.shield = 0;
    db.update(row);
    let before = (ready(&db, &cities[0]), energy(&db, ada));
    let alone = db.call(|db| rules::call_rally(db, ada, Hex::unpacked(cities[2].hex), &spears(1_000), 0)).unwrap();
    until(&mut db, alone.sets_out);
    assert!(rally_march(&db, ada).is_none());
    assert_eq!((ready(&db, &cities[0]), energy(&db, ada)), before);
    let told = reports(&db, ada, Report::ATTACK);
    assert_eq!(told.last().unwrap().words, "No one joined your rally against Cole's city. Your army has stood down.");
}
