//! An alliance's land over a store kept in memory: wardstones raised by
//! officers, the land each claims once it stands, the land growing as one
//! and never onto another alliance's, faster gathering on it, and
//! wardstones falling when razed or when their alliance ends.

use realm::catalog::{self, Building as Kind, Troops, WARD_REACH};
use realm::hex::Hex;
use realm::land;
use realm::rows::{Building, City, March, Member, Place, Site, Stock, Troop, Ward};
use realm::rules::{self, Asked, Refusal};
use realm::store::{Mem, Seconds, Table};

const START: Seconds = 3_000_000;
const SEED: u64 = 7;
const RADIUS: u32 = 48;

fn wait(db: &mut Mem, seconds: Seconds) {
    let to = db.clock + seconds;
    db.advance(to, rules::fire);
}

/// A realm of players of these names, each with a Keep at its eighth
/// level, an Embassy, spearmen, and goods enough; all but those named in
/// `apart` in one alliance, founded by the first.
fn allies(names: &[&str], apart: &[&str]) -> (Mem, Vec<u64>, Vec<City>, u64) {
    let mut db = Mem::new(START, 5);
    rules::open(&mut db, SEED, 1, RADIUS);
    let players: Vec<u64> = names.iter().map(|name| db.call(|db| rules::join(db, name)).unwrap().id).collect();
    let mut cities = Vec::new();
    for player in &players {
        let mut city = rules::city_of(&db, *player).unwrap();
        city.keep = 8;
        db.update(city.clone());
        db.insert(Building { id: 0, city: city.id, kind: Kind::Embassy as u8, level: 1 });
        rules::keep_troop(&mut db, Troop { id: Troop::key(city.id, Troops::Spearmen as u8, 1), city: city.id, kind: Troops::Spearmen as u8, tier: 1, ready: 50_000, wounded: 0 });
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

/// Clear ground a wardstone may stand on, so many steps from a hex.
fn clear_at(db: &Mem, around: Hex, steps: u32) -> Hex {
    around
        .ring(steps)
        .into_iter()
        .find(|hex| hex.length() <= RADIUS && land::ground(SEED, RADIUS, *hex).is_buildable() && Table::<Place>::get(db, hex.packed()).is_none())
        .expect("clear ground there")
}

fn goods_of(db: &Mem, city: &City) -> catalog::Goods {
    rules::goods(&rules::grown(&Table::<Stock>::get(db, city.id).unwrap(), db.clock))
}

#[test]
fn an_officer_raises_a_wardstone_and_it_claims_the_land_about_it_once_it_stands() {
    let (mut db, players, cities, mere) = allies(&["Ada", "Bryn", "Cole"], &["Cole"]);
    let (ada, bryn, cole) = (players[0], players[1], players[2]);
    let home = Hex::unpacked(cities[0].hex);
    let spot = clear_at(&db, home, 5);

    // Raised by an officer of an alliance, on clear ground.
    assert_eq!(db.call(|db| rules::raise_ward(db, cole, spot)), Err(Refusal::NotAllied));
    assert_eq!(db.call(|db| rules::raise_ward(db, bryn, spot)), Err(Refusal::NotAnOfficer));
    assert_eq!(db.call(|db| rules::raise_ward(db, ada, home)), Err(Refusal::NoWardThere));
    assert_eq!(Refusal::NoWardThere.to_string(), "No wardstone can stand there: it needs clear ground.");

    let before = goods_of(&db, &cities[0]);
    let ward = db.call(|db| rules::raise_ward(db, ada, spot)).unwrap();
    assert_eq!((ward.alliance, ward.hex, ward.raised_by, ward.stands_at), (mere, spot.packed(), ada, db.clock + catalog::WARD_SECONDS));
    assert_eq!(goods_of(&db, &cities[0]), before.minus(catalog::WARD_COST), "paid for out of the raiser's city");
    assert_eq!(Table::<Place>::get(&db, spot.packed()), Some(Place { hex: spot.packed(), kind: Place::WARD, id: ward.id }));

    // It claims nothing until it stands; then everything within reach of it, and nothing beyond.
    assert_eq!(rules::land_of(&db, spot), None);
    wait(&mut db, catalog::WARD_SECONDS);
    assert_eq!(rules::land_of(&db, spot), Some(mere));
    assert!(spot.ring(WARD_REACH).iter().all(|hex| rules::land_of(&db, *hex) == Some(mere)));
    assert!(spot.ring(WARD_REACH + 1).iter().all(|hex| rules::land_of(&db, *hex).is_none()));

    // One wardstone for an alliance of two; one more for every five members.
    let next = clear_at(&db, spot, 2);
    assert_eq!(db.call(|db| rules::raise_ward(db, ada, next)), Err(Refusal::WardsAll(1)));
    assert_eq!(Refusal::WardsAll(1).to_string(), "Your alliance has all the wardstones it may: 1. It may raise one more for every five members, twenty at most.");
    assert_eq!((catalog::wards_for(4), catalog::wards_for(5), catalog::wards_for(500)), (1, 2, 20));
}

#[test]
fn later_wardstones_stand_on_the_alliances_own_land_and_none_on_anothers() {
    let (mut db, players, cities, mere) = allies(&["Ada", "Bryn", "Cole", "Dara", "Eben", "Fen"], &["Fen"]);
    let (ada, fen) = (players[0], players[5]);
    let first = clear_at(&db, Hex::unpacked(cities[0].hex), 6);
    db.call(|db| rules::raise_ward(db, ada, first)).unwrap();

    // Before the first stands the alliance has no land for a second to stand on.
    let near = clear_at(&db, first, 3);
    assert_eq!(db.call(|db| rules::raise_ward(db, ada, near)), Err(Refusal::OffOwnLand));
    wait(&mut db, catalog::WARD_SECONDS);
    let far = clear_at(&db, first, 8);
    assert_eq!(db.call(|db| rules::raise_ward(db, ada, far)), Err(Refusal::OffOwnLand));
    let second = db.call(|db| rules::raise_ward(db, ada, near)).unwrap();
    wait(&mut db, catalog::WARD_SECONDS);
    assert!(Hex::unpacked(second.hex).ring(WARD_REACH).iter().all(|hex| rules::land_of(&db, *hex) == Some(mere)), "the land grows by the second");

    // Another alliance raises none on that land, but may beside it; where the two claims meet the older keeps the ground.
    let wardens = db.call(|db| rules::found_alliance(db, fen, "Wardens of the Shore", "WRD")).unwrap();
    wait(&mut db, 10);
    assert_eq!(db.call(|db| rules::raise_ward(db, fen, first.ring(2)[0])), Err(Refusal::OthersLand("[MERE] Keepers of the Mere".into())));
    let theirs = (5..12)
        .flat_map(|steps| first.ring(steps))
        .find(|hex| {
            hex.length() <= RADIUS
                && land::ground(SEED, RADIUS, *hex).is_buildable()
                && Table::<Place>::get(&db, hex.packed()).is_none()
                && rules::land_of(&db, *hex).is_none()
                && hex.within(WARD_REACH).iter().any(|near| rules::land_of(&db, *near) == Some(mere))
        })
        .expect("ground beside the Keepers' land");
    let ward = db.call(|db| rules::raise_ward(db, fen, theirs)).unwrap();
    wait(&mut db, catalog::WARD_SECONDS);
    let claimed: Vec<Hex> = theirs.within(WARD_REACH);
    assert!(claimed.iter().any(|hex| rules::land_of(&db, *hex) == Some(wardens.id)));
    assert!(claimed.iter().any(|hex| rules::land_of(&db, *hex) == Some(mere)), "the Keepers keep the ground they held first");
    assert_eq!(rules::land_of(&db, theirs), Some(wardens.id));
    assert_eq!(ward.alliance, wardens.id);
}

#[test]
fn members_gather_faster_on_their_alliances_land() {
    let (mut db, players, cities, mere) = allies(&["Ada", "Bryn"], &[]);
    let ada = players[0];
    let from = Hex::unpacked(cities[0].hex);
    let mut sites = Table::<Site>::all(&db);
    sites.sort_by_key(|site| (Hex::unpacked(site.hex).distance(from), site.id));
    let site = sites.into_iter().find(|site| land::way(SEED, RADIUS, from, Hex::unpacked(site.hex)).is_some()).unwrap();
    let spears = vec![Asked { kind: Troops::Spearmen as u8, tier: 1, count: 1_000 }];

    // How long a thousand take at work there: off any alliance's land, and on their own.
    let at_work = |db: &mut Mem| {
        let mut row = Table::<Site>::get(db, site.id).unwrap();
        row.left = 10_000_000;
        db.update(row);
        let march = db.call(|db| rules::send(db, ada, Hex::unpacked(site.hex), March::GATHER, &spears)).unwrap();
        wait(db, march.arrives - db.clock);
        let working = Table::<March>::get(db, march.id).unwrap();
        assert_eq!(working.state, March::WORKING);
        db.call(|db| rules::recall(db, ada, march.id)).unwrap();
        wait(db, 20_000);
        working.arrives - working.departed
    };
    let off = at_work(&mut db);
    let spot = clear_at(&db, Hex::unpacked(site.hex), 2);
    db.call(|db| rules::raise_ward(db, ada, spot)).unwrap();
    wait(&mut db, catalog::WARD_SECONDS);
    assert_eq!(rules::land_of(&db, Hex::unpacked(site.hex)), Some(mere));
    let on = at_work(&mut db);
    assert!(on < off, "on their own land, {on} seconds; off it, {off}");
    assert!((on as u64 * (100 + catalog::WARD_GATHERING)).abs_diff(off as u64 * 100) <= 200, "a quarter faster: {on} against {off}");
}

#[test]
fn a_wardstone_razed_or_its_alliance_ended_falls_with_its_land() {
    let (mut db, players, cities, mere) = allies(&["Ada", "Bryn", "Cole"], &["Cole"]);
    let (ada, bryn, cole) = (players[0], players[1], players[2]);
    let spot = clear_at(&db, Hex::unpacked(cities[0].hex), 5);
    let ward = db.call(|db| rules::raise_ward(db, ada, spot)).unwrap();
    wait(&mut db, catalog::WARD_SECONDS);

    // Only an officer of its own alliance takes it down.
    assert_eq!(db.call(|db| rules::raze_ward(db, bryn, ward.id)), Err(Refusal::NotAnOfficer));
    assert_eq!(db.call(|db| rules::raze_ward(db, cole, ward.id)), Err(Refusal::NotAllied));
    assert_eq!(db.call(|db| rules::raze_ward(db, ada, ward.id + 99)), Err(Refusal::NoSuchWard));
    db.call(|db| rules::set_rank(db, ada, bryn, Member::OFFICER)).unwrap();
    wait(&mut db, 10);
    db.call(|db| rules::raze_ward(db, bryn, ward.id)).unwrap();
    assert!(Table::<Ward>::get(&db, ward.id).is_none());
    assert!(Table::<Place>::get(&db, spot.packed()).is_none());
    assert_eq!(rules::land_of(&db, spot), None);

    // Raised again, it falls when the alliance ends: its last member gone.
    let again = db.call(|db| rules::raise_ward(db, ada, spot)).unwrap();
    wait(&mut db, catalog::WARD_SECONDS);
    assert_eq!(rules::land_of(&db, spot), Some(mere));
    db.call(|db| rules::leave_alliance(db, bryn)).unwrap();
    assert!(Table::<Ward>::get(&db, again.id).is_some(), "not while anyone is left");
    db.call(|db| rules::leave_alliance(db, ada)).unwrap();
    assert!(Table::<Ward>::all(&db).is_empty());
    assert!(Table::<Place>::get(&db, spot.packed()).is_none());
    assert_eq!(rules::land_of(&db, spot), None);
}
