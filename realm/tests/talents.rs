//! Commanders' talents, pairs and keepers over a store kept in memory:
//! points from levels spent and forgotten, a second commander beside the
//! first, and one keeping the city in its defence.

use realm::catalog::{self, Talent, Troops, Way, TALENT_MOST};
use realm::hex::Hex;
use realm::land;
use realm::rows::{Bond, City, Commander, Keeper, March, Site, Skill, Stock, Troop};
use realm::rules::{self, Asked, Refusal};
use realm::store::{Mem, Seconds, Table};

const START: Seconds = 3_000_000;
const SEED: u64 = 7;
const RADIUS: u32 = 48;

/// A realm with players of these names, each with a Keep at its twelfth
/// level, spearmen ready, goods enough, and two commanders.
fn realm_of(names: &[&str]) -> (Mem, Vec<(u64, City, Commander, Commander)>) {
    let mut db = Mem::new(START, 5);
    rules::open(&mut db, SEED, 1, RADIUS);
    let mut all = Vec::new();
    for name in names {
        let player = db.call(|db| rules::join(db, name)).unwrap().id;
        let mut city = rules::city_of(&db, player).unwrap();
        city.keep = 12;
        db.update(city.clone());
        rules::keep_troop(&mut db, Troop { id: Troop::key(city.id, 1, 1), city: city.id, kind: 1, tier: 1, ready: 5_000, wounded: 0 });
        let mut stock = rules::grown(&Table::<Stock>::get(&db, city.id).unwrap(), db.clock);
        (stock.grain, stock.timber, stock.stone, stock.moonsalt) = (900_000, 900_000, 900_000, 90_000);
        db.update(stock);
        let first = rules::commanders_of(&db, player).remove(0);
        let second = rules::enlist(&mut db, player);
        all.push((player, city, first, second));
    }
    (db, all)
}

/// Gives a commander a way and a level.
fn make(db: &mut Mem, commander: &Commander, way: Way, level: u32) -> Commander {
    let mut row = Table::<Commander>::get(db, commander.id).unwrap();
    (row.way, row.level, row.seen) = (way as u8, level, 0);
    db.update(row.clone());
    row
}

fn wait(db: &mut Mem, seconds: Seconds) {
    let to = db.clock + seconds;
    db.advance(to, rules::fire);
}

fn spears(count: u64) -> Vec<Asked> {
    vec![Asked { kind: Troops::Spearmen as u8, tier: 1, count }]
}

fn nearest_site(db: &Mem, city: &City) -> Site {
    let from = Hex::unpacked(city.hex);
    let mut sites = Table::<Site>::all(db);
    sites.sort_by_key(|site| (Hex::unpacked(site.hex).distance(from), site.id));
    sites.into_iter().find(|site| land::way(SEED, RADIUS, from, Hex::unpacked(site.hex)).is_some()).unwrap()
}

#[test]
fn a_commander_has_a_point_for_each_level_past_the_first_and_spends_them_on_talents() {
    let (mut db, players) = realm_of(&["Ada", "Bryn"]);
    let (ada, _, first, _) = players[0].clone();
    let theirs = players[1].2.clone();
    assert_eq!((catalog::talent_points(1), catalog::talent_points(12), catalog::talent_points(99)), (0, 11, 29));

    // At the first level there is nothing to spend.
    assert_eq!(db.call(|db| rules::learn_talent(db, ada, first.id, Talent::Shields as u8)), Err(Refusal::NoTalentPoints(first.name.clone())));
    let first = make(&mut db, &first, Way::Vanguard, 13);
    assert_eq!(db.call(|db| rules::learn_talent(db, ada, first.id, 0)), Err(Refusal::NoSuchTalent));
    assert_eq!(db.call(|db| rules::learn_talent(db, ada, theirs.id, Talent::Shields as u8)), Err(Refusal::NoSuchCommander));

    // Ten points into shields and no more; two left go elsewhere; then none.
    for points in 1..=TALENT_MOST {
        assert_eq!(db.call(|db| rules::learn_talent(db, ada, first.id, Talent::Shields as u8)).unwrap().points, points);
        wait(&mut db, 1);
    }
    assert_eq!(db.call(|db| rules::learn_talent(db, ada, first.id, Talent::Shields as u8)), Err(Refusal::TalentFull(first.name.clone())));
    db.call(|db| rules::learn_talent(db, ada, first.id, Talent::Haste as u8)).unwrap();
    wait(&mut db, 1);
    db.call(|db| rules::learn_talent(db, ada, first.id, Talent::Haste as u8)).unwrap();
    wait(&mut db, 1);
    assert_eq!(db.call(|db| rules::learn_talent(db, ada, first.id, Talent::Gathering as u8)), Err(Refusal::NoTalentPoints(first.name.clone())));
    assert_eq!(Refusal::NoTalentPoints("Ael".into()).to_string(), "Ael has no points left to spend. They gain one with each level.");

    // What they add: their way, and their talents.
    let commanding = rules::commanding(&db, &Table::<Commander>::get(&db, first.id).unwrap());
    let way = Way::Vanguard.leading(13);
    assert_eq!(commanding.strikes, way.strikes);
    assert_eq!((commanding.shields, commanding.haste), (way.shields + TALENT_MOST as u64, way.haste + 4));
    assert_eq!(Talent::Haste.words(), "Their army marches 2% faster.");
}

#[test]
fn talents_tell_on_the_road_and_are_forgotten_for_goods() {
    let (mut db, players) = realm_of(&["Ada"]);
    let (ada, city, first, _) = players[0].clone();
    let first = make(&mut db, &first, Way::Gleaner, 11);
    let site = nearest_site(&db, &city);
    let plain = db.call(|db| rules::send_led(db, ada, Hex::unpacked(site.hex), March::GATHER, &spears(100), first.id)).unwrap();
    let road = plain.arrives - plain.departed;
    db.call(|db| rules::recall(db, ada, plain.id)).unwrap();
    wait(&mut db, 3_600);
    for _ in 0..TALENT_MOST {
        db.call(|db| rules::learn_talent(db, ada, first.id, Talent::Haste as u8)).unwrap();
        wait(&mut db, 1);
    }
    let quick = db.call(|db| rules::send_led(db, ada, Hex::unpacked(site.hex), March::GATHER, &spears(100), first.id)).unwrap();
    assert!(quick.arrives - quick.departed < road, "twenty hundredths faster: {} against {road}", quick.arrives - quick.departed);
    db.call(|db| rules::recall(db, ada, quick.id)).unwrap();
    wait(&mut db, 3_600);

    // Forgotten, for goods: the points are free again.
    let before = rules::goods(&rules::grown(&Table::<Stock>::get(&db, city.id).unwrap(), db.clock));
    db.call(|db| rules::forget_talents(db, ada, first.id)).unwrap();
    assert!(Table::<Skill>::by(&db, 0, first.id).is_empty());
    let after = rules::goods(&rules::grown(&Table::<Stock>::get(&db, city.id).unwrap(), db.clock));
    assert_eq!(after, before.minus(catalog::FORGET_COST));
    wait(&mut db, 1);
    assert_eq!(db.call(|db| rules::forget_talents(db, ada, first.id)), Err(Refusal::NothingToForget));
    db.call(|db| rules::learn_talent(db, ada, first.id, Talent::Carrying as u8)).unwrap();
}

#[test]
fn a_second_commander_goes_out_beside_the_first_adding_half_their_way() {
    let (mut db, players) = realm_of(&["Ada", "Bryn"]);
    let (ada, city, first, second) = players[0].clone();
    let theirs = players[1].2.clone();
    let first = make(&mut db, &first, Way::Vanguard, 10);
    let second = make(&mut db, &second, Way::Warden, 20);

    assert_eq!(db.call(|db| rules::pair(db, ada, first.id, first.id)), Err(Refusal::SameCommander));
    assert_eq!(db.call(|db| rules::pair(db, ada, first.id, theirs.id)), Err(Refusal::NoSuchCommander));
    db.call(|db| rules::pair(db, ada, first.id, second.id)).unwrap();
    assert_eq!(Table::<Bond>::get(&db, first.id), Some(Bond { commander: first.id, owner: ada, partner: second.id }));
    wait(&mut db, 1);
    // One bond for each: the second leads no one else, and no one else goes beside them.
    assert_eq!(db.call(|db| rules::pair(db, ada, second.id, first.id)), Err(Refusal::AlreadyPaired(first.name.clone())));
    assert_eq!(Refusal::AlreadyPaired("Ael".into()).to_string(), "Ael already goes out with another commander.");

    // The army sets out with both; what it has is the first's way and half the second's.
    let site = nearest_site(&db, &city);
    let march = db.call(|db| rules::send_led(db, ada, Hex::unpacked(site.hex), March::GATHER, &spears(100), first.id)).unwrap();
    assert_eq!(Table::<Commander>::get(&db, second.id).unwrap().march, march.id, "the second went too");
    let leading = rules::leading_of(&db, &march);
    assert_eq!(leading, Way::Vanguard.leading(10).plus(Way::Warden.leading(20).halved()));
    assert_eq!(leading.shields, Way::Warden.leading(20).shields / 2);
    // Neither can lead another army meanwhile.
    assert!(db.call(|db| rules::send_led(db, ada, Hex::unpacked(site.hex), March::GATHER, &spears(10), second.id)).is_err());

    // Unpaired while they are out, the second is still with the army, and comes home with it.
    wait(&mut db, 10);
    db.call(|db| rules::pair(db, ada, first.id, 0)).unwrap();
    assert_eq!(rules::leading_of(&db, &march), leading, "who went out is who is with it");

    // Home, both are back.
    db.call(|db| rules::recall(db, ada, march.id)).unwrap();
    wait(&mut db, 3_600);
    assert_eq!((Table::<Commander>::get(&db, first.id).unwrap().march, Table::<Commander>::get(&db, second.id).unwrap().march), (0, 0));
    db.call(|db| rules::pair(db, ada, first.id, second.id)).unwrap();

    // A second away does not hold the first back: the army goes without them.
    let alone = db.call(|db| rules::send_led(db, ada, Hex::unpacked(site.hex), March::GATHER, &spears(100), second.id));
    assert!(alone.is_ok(), "the second may lead an army of their own");
    let other = Table::<Site>::all(&db).into_iter().filter(|other| other.id != site.id && land::way(SEED, RADIUS, Hex::unpacked(city.hex), Hex::unpacked(other.hex)).is_some()).min_by_key(|other| Hex::unpacked(other.hex).distance(Hex::unpacked(city.hex))).unwrap();
    let without = db.call(|db| rules::send_led(db, ada, Hex::unpacked(other.hex), March::GATHER, &spears(100), first.id)).unwrap();
    assert_eq!(rules::leading_of(&db, &without), Way::Vanguard.leading(10));

    // Unpaired with 0.
    wait(&mut db, 1);
    db.call(|db| rules::pair(db, ada, first.id, 0)).unwrap();
    assert!(Table::<Bond>::get(&db, first.id).is_none());
}

#[test]
fn a_commander_keeping_the_city_adds_to_its_defence_while_they_are_in_it() {
    let (mut db, players) = realm_of(&["Ada", "Bryn"]);
    let (bryn, his, keeper, _) = players[1].clone();
    let keeper = make(&mut db, &keeper, Way::Warden, 25);
    let bare = rules::defence_of(&db, his.id, bryn);
    db.call(|db| rules::keep_city(db, bryn, keeper.id)).unwrap();
    assert_eq!(Table::<Keeper>::get(&db, bryn), Some(Keeper { player: bryn, commander: keeper.id }));
    let kept = rules::defence_of(&db, his.id, bryn);
    assert_eq!(kept.shields, bare.shields + Way::Warden.leading(25).shields);
    assert_eq!(db.call(|db| rules::keep_city(db, bryn, players[0].2.id)), Err(Refusal::NoSuchCommander));

    // Out with an army, they keep nothing.
    let site = nearest_site(&db, &his);
    db.call(|db| rules::send_led(db, bryn, Hex::unpacked(site.hex), March::GATHER, &spears(100), keeper.id)).unwrap();
    assert_eq!(rules::defence_of(&db, his.id, bryn), bare);
    wait(&mut db, 1);
    db.call(|db| rules::keep_city(db, bryn, 0)).unwrap();
    assert!(Table::<Keeper>::get(&db, bryn).is_none());
}

#[test]
fn a_city_kept_by_a_warden_loses_fewer_of_its_defenders_and_the_warden_learns_from_it() {
    // The same assault on the same city, with chance the same, kept and not kept.
    let lost = |kept: bool| {
        let (mut db, players) = realm_of(&["Ada", "Bryn"]);
        let (ada, _, _, _) = players[0].clone();
        let (bryn, his, keeper, _) = players[1].clone();
        let keeper = make(&mut db, &keeper, Way::Warden, 5);
        if kept {
            db.call(|db| rules::keep_city(db, bryn, keeper.id)).unwrap();
        }
        let mut row = Table::<City>::get(&db, his.id).unwrap();
        row.shield = db.clock;
        db.update(row);
        let march = db.call(|db| rules::send(db, ada, Hex::unpacked(his.hex), March::ATTACK, &spears(4_000))).unwrap();
        db.advance(march.arrives + 3_600, rules::fire);
        let defenders = rules::troop(&db, his.id, Troops::Spearmen, 1);
        (5_000 - defenders.ready, Table::<Commander>::get(&db, keeper.id).unwrap().level)
    };
    let (without, level_without) = lost(false);
    let (with, level_with) = lost(true);
    assert!(with < without, "kept by a warden, {with} fell; not kept, {without}");
    assert_eq!(level_without, 5, "one not keeping the city sees nothing of its defence");
    assert!(level_with > 5, "the warden who kept it rose from what fell before it: level {level_with}");
}
