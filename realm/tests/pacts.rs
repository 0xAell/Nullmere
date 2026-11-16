//! Envoys and pacts between alliances over a store kept in memory: an
//! envoy sent and answered, a truce holding attacks and rallies off and
//! turning back an army already on its way, a pact broken with a day's
//! notice, an envoy gone unanswered, passage through another's gates,
//! and an alliance's end taking its pacts with it.

use realm::catalog::{self, Building as Kind, Troops};
use realm::hex::Hex;
use realm::land;
use realm::rows::{Building, City, Envoy, Gate, March, Pact, Place, Report, Stock, Troop};
use realm::rules::{self, Asked, Refusal};
use realm::store::{Mem, Seconds, Table};

const START: Seconds = 3_000_000;
const SEED: u64 = 7;
const RADIUS: u32 = 48;

fn wait(db: &mut Mem, seconds: Seconds) {
    let to = db.clock + seconds;
    db.advance(to, rules::fire);
}

/// Two alliances: Ada leads the Keepers of the Mere with Bryn; Cole leads
/// the Wardens of the Shore with Dara. Each player has a Keep at its
/// eighth level, an Embassy, spearmen and goods, and a city open to attack.
fn two_alliances() -> (Mem, [u64; 4], Vec<City>, u64, u64) {
    let mut db = Mem::new(START, 5);
    rules::open(&mut db, SEED, 1, RADIUS);
    let names = ["Ada", "Bryn", "Cole", "Dara"];
    let players: Vec<u64> = names.iter().map(|name| db.call(|db| rules::join(db, name)).unwrap().id).collect();
    let mut cities = Vec::new();
    for player in &players {
        let mut city = rules::city_of(&db, *player).unwrap();
        city.keep = 8;
        city.shield = 0;
        db.update(city.clone());
        let mut keep = rules::building_of(&db, city.id, Kind::Keep).unwrap();
        keep.level = 8;
        db.update(keep);
        db.insert(Building { id: 0, city: city.id, kind: Kind::Embassy as u8, level: 1 });
        rules::keep_troop(&mut db, Troop { id: Troop::key(city.id, Troops::Spearmen as u8, 1), city: city.id, kind: Troops::Spearmen as u8, tier: 1, ready: 50_000, wounded: 0 });
        let mut stock = rules::grown(&Table::<Stock>::get(&db, city.id).unwrap(), db.clock);
        (stock.grain, stock.timber, stock.stone, stock.moonsalt) = (500_000, 500_000, 500_000, 0);
        db.update(stock);
        cities.push(city);
    }
    let mere = db.call(|db| rules::found_alliance(db, players[0], "Keepers of the Mere", "MERE")).unwrap().id;
    db.call(|db| rules::join_alliance(db, players[1], mere)).unwrap();
    let wardens = db.call(|db| rules::found_alliance(db, players[2], "Wardens of the Shore", "WRD")).unwrap().id;
    db.call(|db| rules::join_alliance(db, players[3], wardens)).unwrap();
    wait(&mut db, 30);
    (db, [players[0], players[1], players[2], players[3]], cities, mere, wardens)
}

fn spears(count: u64) -> Vec<Asked> {
    vec![Asked { kind: Troops::Spearmen as u8, tier: 1, count }]
}

fn pact_reports(db: &Mem, player: u64) -> Vec<String> {
    let mut all: Vec<Report> = Table::<Report>::by(db, 0, player).into_iter().filter(|report| report.kind == Report::PACT).collect();
    all.sort_by_key(|report| report.id);
    all.into_iter().map(|report| report.words).collect()
}

#[test]
fn an_envoy_brings_a_truce_that_holds_off_attacks_and_turns_back_an_army_on_its_way() {
    let (mut db, [ada, bryn, cole, dara], cities, mere, wardens) = two_alliances();
    let coles = Hex::unpacked(cities[2].hex);
    // An army already on its way to Cole's city before any truce.
    let attack = db.call(|db| rules::send(db, ada, coles, March::ATTACK, &spears(500))).unwrap();

    // Only an officer sends an envoy, to another alliance, with terms there are.
    assert_eq!(db.call(|db| rules::send_envoy(db, bryn, wardens, Pact::TRUCE, 3)), Err(Refusal::NotAnOfficer));
    assert_eq!(db.call(|db| rules::send_envoy(db, ada, mere, Pact::TRUCE, 3)), Err(Refusal::OwnAlliance));
    assert_eq!(db.call(|db| rules::send_envoy(db, ada, 999, Pact::TRUCE, 3)), Err(Refusal::NoSuchAlliance));
    assert_eq!(db.call(|db| rules::send_envoy(db, ada, wardens, 3, 3)), Err(Refusal::NoSuchTerms(catalog::PACT_MOST_DAYS)));
    assert_eq!(db.call(|db| rules::send_envoy(db, ada, wardens, Pact::TRUCE, 15)), Err(Refusal::NoSuchTerms(14)));
    assert_eq!(Refusal::NoSuchTerms(14).to_string(), "A pact is a truce or passage, for a day to 14 days.");
    let envoy = db.call(|db| rules::send_envoy(db, ada, wardens, Pact::TRUCE, 3)).unwrap();
    assert_eq!((envoy.sender, envoy.receiver, envoy.terms, envoy.days, envoy.name.as_str()), (mere, wardens, Pact::TRUCE, 3, "[MERE] Keepers of the Mere"));
    assert_eq!(db.call(|db| rules::send_envoy(db, ada, wardens, Pact::TRUCE, 3)), Err(Refusal::EnvoySent));
    for player in [cole, dara] {
        assert_eq!(
            pact_reports(&db, player),
            vec!["An envoy of [MERE] Keepers of the Mere has come offering a truce of 3 days. Your alliance's officers may accept it or turn it away within a day."]
        );
    }
    assert_eq!(pact_reports(&db, bryn), vec!["Your alliance's envoy has gone to [WRD] Wardens of the Shore offering a truce of 3 days."]);

    // Only an officer of the alliance it came to answers it.
    wait(&mut db, 10);
    assert_eq!(db.call(|db| rules::answer_envoy(db, dara, envoy.id, true)), Err(Refusal::NotAnOfficer));
    assert_eq!(db.call(|db| rules::answer_envoy(db, ada, envoy.id, true)), Err(Refusal::NoSuchEnvoy));
    let pact = db.call(|db| rules::answer_envoy(db, cole, envoy.id, true)).unwrap().unwrap();
    assert_eq!((pact.first, pact.second, pact.terms, pact.ends), (mere, wardens, Pact::TRUCE, db.clock + 3 * catalog::DAY));
    assert!(Table::<Envoy>::get(&db, envoy.id).is_none());
    assert!(rules::at_truce(&db, bryn, dara));
    assert_eq!(pact_reports(&db, bryn).last().unwrap(), "[WRD] Wardens of the Shore accepted your alliance's envoy: a truce of 3 days holds from now.");
    assert_eq!(db.call(|db| rules::send_envoy(db, cole, mere, Pact::TRUCE, 2)), Err(Refusal::PactHolds));

    // At truce: no attack, no rally against a city or a wardstone.
    wait(&mut db, 10);
    assert_eq!(db.call(|db| rules::send(db, bryn, coles, March::ATTACK, &spears(100))), Err(Refusal::AtTruce));
    assert_eq!(db.call(|db| rules::call_rally(db, bryn, coles, &spears(100), 0)), Err(Refusal::AtTruce));
    assert_eq!(Refusal::AtTruce.to_string(), "Your alliances are at truce.");
    let spot = Hex::unpacked(cities[2].hex)
        .ring(4)
        .into_iter()
        .find(|hex| land::ground(SEED, RADIUS, *hex).is_buildable() && Table::<Place>::get(&db, hex.packed()).is_none())
        .unwrap();
    db.call(|db| rules::raise_ward(db, cole, spot)).unwrap();
    assert_eq!(db.call(|db| rules::call_rally(db, bryn, spot, &spears(100), 0)), Err(Refusal::AtTruce));

    // The army on its way finds the truce at the walls, and turns home without a blow.
    let arrives = Table::<March>::get(&db, attack.id).unwrap().arrives;
    let to = arrives.max(db.clock);
    db.advance(to, rules::fire);
    assert_eq!(Table::<March>::get(&db, attack.id).unwrap().state, March::RETURNING);
    assert!(Table::<Report>::by(&db, 0, cole).iter().all(|report| report.kind != Report::DEFENCE), "no fight");

    // Broken by an officer of either: it holds a day more, then attacks may come again.
    assert_eq!(db.call(|db| rules::break_pact(db, dara, pact.id)), Err(Refusal::NotAnOfficer));
    let broken = db.call(|db| rules::break_pact(db, cole, pact.id)).unwrap();
    assert_eq!(broken.ends, db.clock + catalog::PACT_NOTICE);
    assert_eq!(pact_reports(&db, ada).last().unwrap(), "[WRD] Wardens of the Shore has broken its pact with your alliance. It holds until a day from now.");
    wait(&mut db, catalog::PACT_NOTICE - 60);
    assert_eq!(db.call(|db| rules::send(db, bryn, coles, March::ATTACK, &spears(100))), Err(Refusal::AtTruce));
    wait(&mut db, 120);
    assert!(!rules::at_truce(&db, bryn, dara));
    assert!(db.call(|db| rules::send(db, bryn, coles, March::ATTACK, &spears(100))).is_ok());
    assert_eq!(db.call(|db| rules::break_pact(db, cole, pact.id)), Err(Refusal::NoSuchPact), "an ended pact is not broken again");
}

#[test]
fn an_envoy_turned_away_or_left_a_day_unanswered_brings_nothing() {
    let (mut db, [ada, bryn, cole, _], _, mere, wardens) = two_alliances();
    let envoy = db.call(|db| rules::send_envoy(db, ada, wardens, Pact::PASSAGE, 7)).unwrap();
    assert_eq!(db.call(|db| rules::answer_envoy(db, cole, envoy.id, false)), Ok(None));
    assert!(Table::<Pact>::all(&db).is_empty());
    assert_eq!(pact_reports(&db, bryn).last().unwrap(), "[WRD] Wardens of the Shore turned away your alliance's envoy and its offer of passage through one another's gates for 7 days.");

    let late = db.call(|db| rules::send_envoy(db, ada, wardens, Pact::PASSAGE, 7)).unwrap();
    wait(&mut db, catalog::ENVOY_WAITS + 1);
    assert_eq!(db.call(|db| rules::answer_envoy(db, cole, late.id, true)), Err(Refusal::NoSuchEnvoy));
    assert!(Table::<Pact>::all(&db).is_empty());
    assert!(!rules::pact_holds(&db, mere, wardens, Pact::PASSAGE));
}

#[test]
fn passage_opens_anothers_gates_and_a_truce_shuts_them_to_a_rally() {
    let (mut db, [ada, _, cole, dara], _, mere, wardens) = two_alliances();
    // The Keepers hold a gate.
    let mut gate = Table::<Gate>::get(&db, 1).unwrap();
    (gate.holder, gate.holder_name) = (mere, "[MERE] Keepers of the Mere".into());
    db.update(gate.clone());
    assert_eq!(rules::gates_barred_to(&db, cole).len(), 6);
    assert_eq!(rules::gates_barred_to(&db, ada).len(), 5);

    // With passage the Wardens pass it too; theirs, if they had one, the Keepers would.
    let envoy = db.call(|db| rules::send_envoy(db, cole, mere, Pact::PASSAGE, 2)).unwrap();
    db.call(|db| rules::answer_envoy(db, ada, envoy.id, true)).unwrap();
    assert_eq!(rules::passage_for(&db, wardens), vec![mere]);
    assert_eq!(rules::passage_for(&db, mere), vec![wardens]);
    assert_eq!(rules::gates_barred_to(&db, cole).len(), 5);
    assert_eq!(rules::gates_barred_to(&db, dara).len(), 5);
    // When it ends, they do not.
    wait(&mut db, 2 * catalog::DAY + 1);
    assert_eq!(rules::gates_barred_to(&db, cole).len(), 6);

    // At truce, the Wardens may not storm the Keepers' gate, open season or not.
    let opens = rules::gates_open_at(&db);
    let to = opens.max(db.clock);
    db.advance(to, rules::fire);
    let truce = db.call(|db| rules::send_envoy(db, ada, wardens, Pact::TRUCE, 5)).unwrap();
    db.call(|db| rules::answer_envoy(db, cole, truce.id, true)).unwrap();
    assert_eq!(db.call(|db| rules::call_rally(db, cole, Hex::unpacked(gate.hex), &spears(100), 0)), Err(Refusal::AtTruce));

    // An alliance that ends takes its pacts and its envoys with it.
    db.call(|db| rules::send_envoy(db, cole, mere, Pact::PASSAGE, 3)).unwrap();
    wait(&mut db, 10);
    db.call(|db| rules::leave_alliance(db, dara)).unwrap();
    db.call(|db| rules::leave_alliance(db, cole)).unwrap();
    assert!(Table::<Pact>::all(&db).is_empty());
    assert!(Table::<Envoy>::all(&db).is_empty());
}
