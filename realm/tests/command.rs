//! Commanders over a store kept in memory: who a player has, taking on
//! more, an army led, and what its leader adds and learns.

use realm::catalog::{self, Building as Kind, Gift, Goods, Item, Leading, Renown, Troops, Way};
use realm::hex::Hex;
use realm::land;
use realm::rows::{Barrow, Building, City, Commander, Haul, March, Person, Report, Satchel, Site, Stock, Troop};
use realm::rules::{self, Asked, Refusal};
use realm::store::{Mem, Seconds, Table};

const START: Seconds = 3_000_000;
const SEED: u64 = 7;
const RADIUS: u32 = 48;

/// A realm with one player, their Keep high enough for three armies,
/// with spearmen ready, and their one commander.
fn led(spearmen: u64) -> (Mem, u64, City, Commander) {
    let mut db = Mem::new(START, 5);
    rules::open(&mut db, SEED, 1, RADIUS);
    let player = db.call(|db| rules::join(db, "Ada")).unwrap().id;
    let mut city = rules::city_of(&db, player).unwrap();
    city.keep = 12;
    db.update(city.clone());
    rules::keep_troop(&mut db, Troop { id: Troop::key(city.id, 1, 1), city: city.id, kind: 1, tier: 1, ready: spearmen, wounded: 0 });
    let commander = rules::commanders_of(&db, player).remove(0);
    (db, player, city, commander)
}

/// Gives a commander a way and a level.
fn make(db: &mut Mem, commander: &Commander, way: Way, level: u32) -> Commander {
    let mut row = Table::<Commander>::get(db, commander.id).unwrap();
    (row.way, row.level, row.seen, row.person, row.gift) = (way as u8, level, 0, 0, 0);
    db.update(row.clone());
    row
}

fn until(db: &mut Mem, moment: Seconds) {
    db.advance(moment, |db, timer| rules::fire(db, timer));
}

fn spears(count: u64) -> Vec<Asked> {
    vec![Asked { kind: Troops::Spearmen as u8, tier: 1, count }]
}

/// The nearest site or barrow of the first level that a way leads to.
fn nearest_site(db: &Mem, city: &City) -> Site {
    let from = Hex::unpacked(city.hex);
    let mut sites = Table::<Site>::all(db);
    sites.sort_by_key(|site| (Hex::unpacked(site.hex).distance(from), site.id));
    sites.into_iter().find(|site| land::way(SEED, RADIUS, from, Hex::unpacked(site.hex)).is_some()).unwrap()
}

fn nearest_barrow(db: &mut Mem, city: &City) -> Barrow {
    let from = Hex::unpacked(city.hex);
    let mut barrows = Table::<Barrow>::all(db);
    barrows.sort_by_key(|barrow| (Hex::unpacked(barrow.hex).distance(from), barrow.id));
    let mut barrow = barrows.into_iter().find(|barrow| land::way(SEED, RADIUS, from, Hex::unpacked(barrow.hex)).is_some()).unwrap();
    barrow.level = 1;
    db.update(barrow.clone());
    barrow
}

#[test]
fn each_way_of_war_adds_what_it_is_best_at() {
    assert_eq!(Way::ALL.len(), 6);
    for way in Way::ALL {
        assert_eq!(Way::of(way as u8), Some(way));
        assert!(!way.name().is_empty() && way.words().ends_with('.'));
        let (first, last) = (way.leading(1), way.leading(catalog::TOP_COMMAND));
        assert_ne!(first, Leading::default(), "{} adds something from the first", way.name());
        assert_ne!(first, last, "and more at the last");
        assert_eq!(way.leading(99), last);
        assert_eq!(way.leading(0), first);
    }
    assert_eq!(Way::of(0), None);
    assert_eq!(Way::of(7), None);
    assert_eq!(Way::Vanguard.leading(1), Leading { strikes: [6, 0, 0, 0], surge: 22, ..Leading::default() });
    assert_eq!(Way::Fletcher.leading(10).strikes, [0, 15, 0, 0]);
    assert_eq!(Way::Outrider.leading(10), Leading { strikes: [0, 0, 15, 0], haste: 8, surge: 40, ..Leading::default() });
    assert_eq!(Way::Wallbreaker.leading(30), Leading { strikes: [0, 0, 0, 35], breaches: 40, surge: 80, ..Leading::default() });
    assert_eq!((Way::Warden.leading(30).shields, Way::Warden.leading(30).stand, Way::Warden.leading(30).surge), (35, 80, 0), "a warden's skill is to stand");
    assert_eq!(Way::Gleaner.leading(5), Leading { gathers: 20, carries: 10, ..Leading::default() });
    assert_eq!([1, 2, 10].map(catalog::command_needs), [100, 400, 10_000]);
    assert_eq!([0, 1, 4, 5, 10, 19, 20, 25].map(catalog::commanders), [1, 2, 2, 3, 4, 5, 6, 6]);
    assert_eq!(catalog::hire_cost(1), Goods::of(2_000, 2_000, 1_000, 0));
    assert_eq!(catalog::hire_cost(3), Goods::of(18_000, 18_000, 9_000, 150));
}

#[test]
fn a_player_begins_with_one_commander_and_takes_on_more_from_a_tavern() {
    let (mut db, player, city, first) = led(0);
    assert_eq!(rules::commanders_of(&db, player), vec![first.clone()]);
    assert_eq!((first.owner, first.level, first.seen, first.march), (player, 1, 0, 0));
    assert!(Way::of(first.way).is_some());
    assert!(first.name.len() >= 3 && first.name.chars().next().unwrap().is_uppercase(), "{}", first.name);

    // No Tavern, no more.
    assert_eq!(db.call(|db| rules::hire(db, player)), Err(Refusal::NeedsOther(Kind::Tavern, 1)));
    let tavern = db.insert(Building { id: 0, city: city.id, kind: Kind::Tavern as u8, level: 1 });
    let before = rules::goods(&rules::grown(&Table::<Stock>::get(&db, city.id).unwrap(), db.clock));
    let second = db.call(|db| rules::hire(db, player)).unwrap();
    let after = rules::goods(&rules::grown(&Table::<Stock>::get(&db, city.id).unwrap(), db.clock));
    assert_eq!(before.minus(after), catalog::hire_cost(1));
    assert_ne!(second.way, first.way, "of a way she has not yet");
    assert_ne!(second.name, first.name);
    assert_eq!(rules::commanders_of(&db, player).len(), 2);
    // The third waits on the Tavern's fifth level.
    assert_eq!(db.call(|db| rules::hire(db, player)), Err(Refusal::NeedsOther(Kind::Tavern, 5)));

    // With a Tavern of the twentieth and goods enough, six in all: one of each way.
    let mut grown = tavern;
    grown.level = 20;
    db.update(grown);
    let mut rich = Table::<Stock>::get(&db, city.id).unwrap();
    (rich.grain, rich.timber, rich.stone, rich.moonsalt) = (9_000_000, 9_000_000, 9_000_000, 9_000);
    db.update(rich);
    for _ in 0..4 {
        db.call(|db| rules::hire(db, player)).unwrap();
    }
    let all = rules::commanders_of(&db, player);
    assert_eq!(all.len(), 6);
    let mut ways: Vec<u8> = all.iter().map(|commander| commander.way).collect();
    ways.sort();
    assert_eq!(ways, vec![1, 2, 3, 4, 5, 6]);
    let mut names: Vec<&str> = all.iter().map(|commander| commander.name.as_str()).collect();
    names.sort();
    names.dedup();
    assert_eq!(names.len(), 6, "no two of a name");
    assert_eq!(db.call(|db| rules::hire(db, player)), Err(Refusal::NoMoreCommanders));
    assert_eq!(Refusal::NoMoreCommanders.to_string(), "Your city keeps as many commanders as it can.");
    // Too dear is refused with what is missing.
    let (mut db, player, city, _) = led(0);
    db.insert(Building { id: 0, city: city.id, kind: Kind::Tavern as u8, level: 1 });
    let mut poor = Table::<Stock>::get(&db, city.id).unwrap();
    (poor.grain, poor.grain_hourly) = (500, 0);
    db.update(poor);
    assert_eq!(db.call(|db| rules::hire(db, player)), Err(Refusal::CannotAfford(Goods::of(1_500, 0, 0, 0))));
}

#[test]
fn an_army_is_led_by_one_commander_who_comes_home_with_it() {
    let (mut db, player, city, commander) = led(100);
    let site = nearest_site(&db, &city);
    let to = Hex::unpacked(site.hex);

    // Someone else's, or no one's, leads nothing.
    let other = db.call(|db| rules::join(db, "Bryn")).unwrap().id;
    let theirs = rules::commanders_of(&db, other).remove(0);
    assert_eq!(db.call(|db| rules::send_led(db, player, to, March::GATHER, &spears(20), theirs.id)), Err(Refusal::NoSuchCommander));
    assert_eq!(db.call(|db| rules::send_led(db, player, to, March::GATHER, &spears(20), 999)), Err(Refusal::NoSuchCommander));
    assert_eq!(Refusal::NoSuchCommander.to_string(), "You have no such commander.");
    assert_eq!(rules::troop(&db, city.id, Troops::Spearmen, 1).ready, 100, "and no one has set out");

    // Led: the march names its leader, and the leader is out with it.
    let march = db.call(|db| rules::send_led(db, player, to, March::GATHER, &spears(20), commander.id)).unwrap();
    assert_eq!(march.leader, commander.id);
    assert_eq!(Table::<Commander>::get(&db, commander.id).unwrap().march, march.id);
    // They can't lead a second meanwhile; an army with no one to lead it still goes.
    let elsewhere = Table::<Site>::all(&db).into_iter().find(|other| other.id != site.id && land::way(SEED, RADIUS, Hex::unpacked(city.hex), Hex::unpacked(other.hex)).is_some()).unwrap();
    let again = db.call(|db| rules::send_led(db, player, Hex::unpacked(elsewhere.hex), March::GATHER, &spears(20), commander.id));
    assert_eq!(again, Err(Refusal::CommanderAway(commander.name.clone())));
    assert_eq!(Refusal::CommanderAway("Corwen".into()).to_string(), "Corwen is out with another army.");
    let unled = db.call(|db| rules::send(db, player, Hex::unpacked(elsewhere.hex), March::GATHER, &spears(20))).unwrap();
    assert_eq!(unled.leader, 0);
    assert_eq!(rules::leading_of(&db, &unled), Leading::default());

    // Home: the commander is in the city again, and has seen a little of the work.
    until(&mut db, START + 200_000);
    assert!(Table::<March>::get(&db, march.id).is_none());
    let back = Table::<Commander>::get(&db, commander.id).unwrap();
    assert_eq!(back.march, 0);
    assert!(back.seen > 0 || back.level > 1, "a load of 240 is twelve seen");
    assert!(db.call(|db| rules::send_led(db, player, to, March::GATHER, &spears(20), commander.id)).is_ok());
}

#[test]
fn what_a_commander_adds_tells_on_the_road_at_work_and_in_a_fight() {
    // The same road and the same work, led by no one, by an outrider and by a gleaner.
    let timed = |way: Option<(Way, u32)>| {
        let (mut db, player, city, commander) = led(100);
        let site = nearest_site(&db, &city);
        let leader = way.map(|(way, level)| make(&mut db, &commander, way, level).id).unwrap_or(0);
        let march = db.call(|db| rules::send_led(db, player, Hex::unpacked(site.hex), March::GATHER, &spears(50), leader)).unwrap();
        let road = march.arrives - march.departed;
        until(&mut db, march.arrives);
        let working = Table::<March>::get(&db, march.id).unwrap();
        let work = working.arrives - working.departed;
        until(&mut db, working.arrives);
        let haul = Table::<Haul>::get(&db, march.id).unwrap();
        (road, work, haul.grain + haul.timber + haul.stone + haul.moonsalt)
    };
    let (road, work, load) = timed(None);
    assert_eq!(load, 50 * 12);
    let (faster, _, same) = timed(Some((Way::Outrider, 30)));
    assert!(faster < road, "an outrider's army takes {faster} seconds of a road of {road}");
    assert_eq!(same, load);
    let (_, quicker, more) = timed(Some((Way::Gleaner, 30)));
    assert_eq!(more, load * 135 / 100, "a gleaner's army carries a third more");
    // A third more to gather at 1.7 times the speed: sooner all the same.
    assert!(quicker < work, "{quicker} seconds of work against {work}");

    // The same fight at a barrow, led by no one, by a vanguard and by a warden.
    let fallen = |way: Option<(Way, u32)>| {
        let (mut db, player, city, commander) = led(60);
        let barrow = nearest_barrow(&mut db, &city);
        let leader = way.map(|(way, level)| make(&mut db, &commander, way, level).id).unwrap_or(0);
        let march = db.call(|db| rules::send_led(db, player, Hex::unpacked(barrow.hex), March::HUNT, &spears(60), leader)).unwrap();
        until(&mut db, march.arrives + catalog::FIGHT_SECONDS);
        let report = Table::<Report>::by(&db, 0, player).pop().unwrap();
        assert!(report.won);
        let seen = Table::<Commander>::get(&db, commander.id).unwrap();
        (report.wounded + report.dead, seen.level, seen.seen)
    };
    let (unled, level, seen) = fallen(None);
    assert_eq!((level, seen), (1, 0), "a commander who stayed at home saw nothing");
    let (sharper, _, _) = fallen(Some((Way::Vanguard, 30)));
    let (guarded, _, _) = fallen(Some((Way::Warden, 30)));
    assert!(sharper < unled, "{sharper} fell under a vanguard, {unled} with no one");
    assert!(guarded < unled, "{guarded} fell under a warden, {unled} with no one");
    // A fletcher is nothing to spearmen; but whoever leads has seen twenty-five fall.
    let (plain, level, seen) = fallen(Some((Way::Fletcher, 1)));
    assert_eq!(plain, unled);
    assert_eq!((level, seen), (1, 25));
}

#[test]
fn a_commander_rises_with_what_they_have_seen() {
    let (mut db, player, city, commander) = led(4_000);
    let mut row = Table::<Commander>::get(&db, commander.id).unwrap();
    row.seen = 90;
    db.update(row);
    let barrow = nearest_barrow(&mut db, &city);
    let march = db.call(|db| rules::send_led(db, player, Hex::unpacked(barrow.hex), March::HUNT, &spears(400), commander.id)).unwrap();
    until(&mut db, march.arrives + catalog::FIGHT_SECONDS);
    // Ninety and twenty-five more: past the hundred the second level asks.
    let risen = Table::<Commander>::get(&db, commander.id).unwrap();
    assert_eq!((risen.level, risen.seen), (2, 15));
    // What they lead with: their way at the second level as their renown
    // makes it, and their gift.
    let person = catalog::person_of(risen.person).unwrap();
    let expected = Way::of(risen.way).unwrap().leading(2).scaled(person.renown.weight()).plus(person.gift.leading(risen.gift));
    assert_eq!(rules::leading_of(&db, &Table::<March>::get(&db, march.id).unwrap()), expected);
    // Enough seen at once lifts them several levels, and never past the thirtieth.
    let mut much = risen.clone();
    (much.level, much.seen) = (29, 0);
    db.update(much);
    until(&mut db, START + 100_000);
    let barrow = nearest_barrow(&mut db, &city);
    let mut strong = barrow.clone();
    strong.level = 1;
    db.update(strong);
    let mut top = Table::<Commander>::get(&db, commander.id).unwrap();
    top.seen = catalog::command_needs(29) - 1;
    db.update(top);
    let march = db.call(|db| rules::send_led(db, player, Hex::unpacked(barrow.hex), March::HUNT, &spears(400), commander.id)).unwrap();
    until(&mut db, march.arrives + catalog::FIGHT_SECONDS);
    let last = Table::<Commander>::get(&db, commander.id).unwrap();
    assert_eq!(last.level, catalog::TOP_COMMAND);
    assert_eq!(last.seen, 24, "what is seen at the last level is only kept");
    // An army lost with no room for its wounded leaves no march, and its
    // commander, one of no renown and no gift, comes back to the city all
    // the same.
    let (mut db, player, city, commander) = led(10);
    let commander = make(&mut db, &commander, Way::Vanguard, 1);
    let mut full = rules::troop(&db, city.id, Troops::Archers, 1);
    full.wounded = 50;
    rules::keep_troop(&mut db, full);
    let barrow = nearest_barrow(&mut db, &city);
    let march = db.call(|db| rules::send_led(db, player, Hex::unpacked(barrow.hex), March::HUNT, &spears(10), commander.id)).unwrap();
    until(&mut db, march.arrives + catalog::FIGHT_SECONDS);
    assert!(Table::<March>::get(&db, march.id).is_none());
    assert_eq!(Table::<Commander>::get(&db, commander.id).unwrap().march, 0);
}

#[test]
fn a_commander_reads_tomes_of_war_and_rises() {
    let (mut db, player, _city, commander) = led(10);
    let commander = make(&mut db, &commander, Way::Vanguard, 1);
    // None held: nothing to read; and what is no tome is never read.
    let refusal = db.call(|db| rules::read_tome(db, player, commander.id, Item::Tome as u8, 1)).unwrap_err();
    assert_eq!((refusal.clone(), refusal.to_string()), (Refusal::NoneLeft, Refusal::NoneLeft.to_string()));
    let refusal = db.call(|db| rules::read_tome(db, player, commander.id, Item::Haste5 as u8, 1)).unwrap_err();
    assert_eq!((refusal.clone(), refusal.to_string()), (Refusal::NotATome, "That is not a tome.".to_string()));
    assert_eq!(db.call(|db| rules::read_tome(db, player, 999, Item::Tome as u8, 1)), Err(Refusal::NoSuchCommander));

    // Two tomes, 1,000 seen: from the first level past the third (100 + 400 = 500 to the third, 900 more for the fourth).
    rules::give(&mut db, player, Item::Tome, 3);
    assert_eq!(db.call(|db| rules::read_tome(db, player, commander.id, Item::Tome as u8, 0)), Err(Refusal::NothingAsked));
    assert_eq!(db.call(|db| rules::read_tome(db, player, commander.id, Item::Tome as u8, 101)), Err(Refusal::TooMany(rules::MOST_READ)));
    let read = db.call(|db| rules::read_tome(db, player, commander.id, Item::Tome as u8, 2)).unwrap();
    assert_eq!((read.level, read.seen), (3, 500), "100 to the second, 400 to the third, 500 toward the fourth");
    assert_eq!(rules::held(&db, player, Item::Tome), 1);
    // A tome is never used on a work.
    let refusal = db.call(|db| rules::use_item(db, player, Item::Tome as u8, 1)).unwrap_err();
    assert_eq!((refusal.clone(), refusal.to_string()), (Refusal::ForACommander, "A tome is read by one of your commanders.".to_string()));

    // A great tome is ten of them; and one at the top has seen all there is.
    rules::give(&mut db, player, Item::GreatTome, 1);
    let read = db.call(|db| rules::read_tome(db, player, commander.id, Item::GreatTome as u8, 1)).unwrap();
    assert!(read.level > 3);
    let topped = make(&mut db, &commander, Way::Vanguard, catalog::TOP_COMMAND);
    let refusal = db.call(|db| rules::read_tome(db, player, topped.id, Item::Tome as u8, 1)).unwrap_err();
    assert_eq!(refusal.to_string(), format!("{} has seen all there is to see of war.", topped.name));
    assert_eq!(rules::held(&db, player, Item::Tome), 1, "nothing taken for it");
}

#[test]
fn the_realms_commanders_are_people_each_of_their_own() {
    // Twenty-four, four of each way: one storied, one famed, two steady;
    // every name their own.
    let mut names: Vec<&str> = catalog::PEOPLE.iter().map(|person| person.name).collect();
    names.sort();
    names.dedup();
    assert_eq!(names.len(), 24);
    for way in Way::ALL {
        let of: Vec<_> = catalog::PEOPLE.iter().filter(|person| person.way == way).collect();
        let count = |renown: Renown| of.iter().filter(|person| person.renown == renown).count();
        assert_eq!((of.len(), count(Renown::Storied), count(Renown::Famed), count(Renown::Steady)), (4, 1, 1, 2), "{}", way.name());
    }
    assert_eq!(catalog::person_of(0), None);
    assert_eq!(catalog::person_of(25), None);
    assert_eq!(catalog::person_of(1).map(|person| person.name), Some("Hallam Ironsworn"));
    // Each gift grows with its level, to the fifth.
    for gift in Gift::ALL {
        assert_ne!(gift.leading(1), gift.leading(5), "{}", gift.name());
        assert_eq!(gift.leading(5), gift.leading(9), "{} stops at the fifth", gift.name());
        assert!(gift.words(1).ends_with('.'));
    }
    assert_eq!(Gift::Mercy.words(1), "12 in a hundred of their army's dead are carried home wounded after all.");
    assert_eq!(Gift::Quick.leading(3).quick, 1);
    // The better known lead the better: a storied commander's way is a
    // quarter more than a steady one's.
    assert_eq!(Way::Vanguard.leading(10).scaled(Renown::Storied.weight()).strikes[0], (5 + 10) * 125 / 100);
}

#[test]
fn the_tavern_brings_the_realms_own_commanders_by_their_renown() {
    // Each player's first commander is one of the realm's; over many
    // players most are steady, some famed, a few storied.
    let mut db = Mem::new(START, 5);
    rules::open(&mut db, SEED, 1, 128);
    let mut renown = [0usize; 4];
    for index in 0..300 {
        // No more than the realm lets join in a minute.
        if index % 100 == 99 {
            let later = db.clock + 61;
            until(&mut db, later);
        }
        let player = db.call(|db| rules::join(db, &format!("Player {index}"))).unwrap().id;
        let first = rules::commanders_of(&db, player).remove(0);
        let person = catalog::person_of(first.person).expect("one of the realm's");
        assert_eq!((first.name.as_str(), first.way, first.gift, first.sigils), (person.name, person.way as u8, 1, 0));
        renown[person.renown as usize] += 1;
    }
    let (steady, famed, storied) = (renown[1], renown[2], renown[3]);
    assert!((170..=250).contains(&steady) && (45..=110).contains(&famed) && (3..=30).contains(&storied), "{steady} steady, {famed} famed, {storied} storied");

    // A player's commanders from the Tavern: none twice, of new ways
    // while there are any.
    let (mut db, player, city, _) = led(10);
    let mut tavern = rules::building_of(&db, city.id, Kind::Tavern).unwrap_or(Building { id: 0, city: city.id, kind: Kind::Tavern as u8, level: 0 });
    tavern.level = 25;
    if tavern.id == 0 { db.insert(tavern); } else { db.update(tavern); }
    let mut stock = Table::<Stock>::get(&db, city.id).unwrap();
    (stock.grain, stock.timber, stock.stone, stock.moonsalt, stock.holds) = (10_000_000, 10_000_000, 10_000_000, 10_000_000, 50_000_000);
    db.update(stock);
    while db.call(|db| rules::hire(db, player)).is_ok() {}
    let all = rules::commanders_of(&db, player);
    assert_eq!(all.len(), 6);
    let mut people: Vec<u8> = all.iter().map(|commander| commander.person).collect();
    people.sort();
    people.dedup();
    assert_eq!(people.len(), 6, "none twice");
    let mut ways: Vec<u8> = all.iter().map(|commander| commander.way).collect();
    ways.sort();
    ways.dedup();
    assert_eq!(ways.len(), 6, "a commander of every way");
}

#[test]
fn the_realms_commanders_are_written_out_for_clients() {
    let mut db = Mem::new(START, 5);
    rules::open(&mut db, SEED, 1, RADIUS);
    let mut people = Table::<Person>::all(&db);
    people.sort_by_key(|person| person.number);
    assert_eq!(people.len(), 24);
    let first = &people[0];
    assert_eq!((first.number, first.name.as_str(), first.way, first.renown, first.gift, first.gift_name.as_str()), (1, "Hallam Ironsworn", Way::Vanguard as u8, Renown::Storied as u8, Gift::Quick as u8, "Quick"));
    let lines: Vec<&str> = people[2].gift_words.lines().collect();
    assert_eq!(lines.len(), 5, "a line for each of the gift's levels");
    assert_eq!(lines[0], "12 in a hundred of their army's dead are carried home wounded after all.");
    assert_eq!(lines[4], "28 in a hundred of their army's dead are carried home wounded after all.");
}

/// A player with a Tavern of a level, and nothing else changed.
fn with_tavern(level: u32) -> (Mem, u64, City) {
    let (mut db, player, city, _) = led(10);
    db.insert(Building { id: 0, city: city.id, kind: Kind::Tavern as u8, level });
    (db, player, city)
}

/// Gives a player so many summonses.
fn summonses(db: &mut Mem, player: u64, count: u64) {
    db.insert(Satchel { id: Satchel::key(player, Item::Summons as u8), player, item: Item::Summons as u8, count });
}

#[test]
fn the_tavern_summons_once_a_day_free_and_then_with_summonses() {
    let (mut db, player, _) = with_tavern(5);
    let before = rules::commanders_of(&db, player).len();
    let drawn = db.call(|db| rules::draw(db, player)).unwrap();
    // A first commander of the realm's own came with the player, and
    // three may be had at a Tavern of the fifth level: one new comes, or
    // one they have is drawn again.
    let after = rules::commanders_of(&db, player);
    assert!(catalog::person_of(drawn.commander.person).is_some(), "one of the realm's");
    assert_eq!(after.len(), before + drawn.new as usize);
    // The free summons is taken for today; with none kept, refused.
    assert_eq!(db.call(|db| rules::draw(db, player)), Err(Refusal::NoSummons));
    assert_eq!(Refusal::NoSummons.to_string(), "The Tavern's free summons is taken for today, and you have no summons to bring it.");
    summonses(&mut db, player, 2);
    db.call(|db| rules::draw(db, player)).unwrap();
    assert_eq!(rules::held(&db, player, Item::Summons), 1, "one taken");
    // A summons is not used on a work, and a new day brings a free one.
    assert_eq!(db.call(|db| rules::use_item(db, player, Item::Summons as u8, 1)), Err(Refusal::AtTheTavern));
    until(&mut db, START + 86_400 + 60);
    db.call(|db| rules::draw(db, player)).unwrap();
    assert_eq!(rules::held(&db, player, Item::Summons), 1, "the day's free one, the kept one kept");
    // The day's last chest holds one.
    assert!(catalog::chest_items(3).contains(&(Item::Summons, 1)));
    // No Tavern, no summons.
    let (mut none, player, _, _) = led(10);
    assert_eq!(none.call(|db| rules::draw(db, player)), Err(Refusal::NeedsOther(Kind::Tavern, 1)));
}

#[test]
fn one_drawn_again_brings_sigils_and_sigils_raise_a_gift() {
    // A Tavern with room for no one more: every draw is among the player's
    // own, and brings sigils.
    let (mut db, player, _) = with_tavern(1);
    let first = rules::commanders_of(&db, player)[0].clone();
    let other = if first.person == 1 { 2 } else { 1 };
    let name = catalog::person_of(other).unwrap().name.to_string();
    db.insert(Commander { id: 0, owner: player, name, way: catalog::person_of(other).unwrap().way as u8, level: 1, seen: 0, march: 0, person: other, gift: 1, sigils: 0 });
    let theirs = rules::commanders_of(&db, player);
    assert_eq!(theirs.len() as u32, catalog::commanders(1));
    summonses(&mut db, player, 30);
    for _ in 0..30 {
        let drawn = db.call(|db| rules::draw(db, player)).unwrap();
        assert!(!drawn.new);
    }
    let first = Table::<Commander>::get(&db, theirs[0].id).unwrap();
    let total: u32 = rules::commanders_of(&db, player).iter().map(|commander| commander.sigils).sum();
    assert_eq!(total, 30 * catalog::SIGILS_A_DRAW, "the day's free summons and twenty-nine kept, ten sigils each");
    assert_eq!(rules::held(&db, player, Item::Summons), 1);
    // Ten, twenty, forty, eighty: a hundred and fifty raise a gift to the fifth.
    assert_eq!((1..5).map(catalog::gift_needs).collect::<Vec<_>>(), vec![10, 20, 40, 80]);
    let mut row = first.clone();
    row.sigils = 145;
    db.update(row);
    for level in 2..=4 {
        assert_eq!(db.call(|db| rules::raise_gift(db, player, first.id)).unwrap().gift, level);
    }
    let short = db.call(|db| rules::raise_gift(db, player, first.id));
    assert_eq!(short, Err(Refusal::TooFewSigils(first.name.clone(), 5)));
    assert_eq!(short.unwrap_err().to_string(), format!("{} needs 5 more sigils to raise their gift.", first.name));
    let mut row = Table::<Commander>::get(&db, first.id).unwrap();
    row.sigils += 5;
    db.update(row);
    assert_eq!(db.call(|db| rules::raise_gift(db, player, first.id)).unwrap().gift, 5);
    assert_eq!(db.call(|db| rules::raise_gift(db, player, first.id)), Err(Refusal::GiftAtTop(first.name.clone())));
    // Its gift at the fifth level, in what they lead with.
    let raised = Table::<Commander>::get(&db, first.id).unwrap();
    let person = catalog::person_of(raised.person).unwrap();
    assert_eq!(rules::commanding(&db, &raised), rules::way_of(&raised).plus(person.gift.leading(5)));
    // One of no renown has no gift, and another's commander is not theirs.
    let plain = make(&mut db, &raised, Way::Vanguard, 1);
    assert_eq!(db.call(|db| rules::raise_gift(db, player, plain.id)), Err(Refusal::NoGift));
    let bryn = db.call(|db| rules::join(db, "Bryn")).unwrap().id;
    assert_eq!(db.call(|db| rules::raise_gift(db, bryn, raised.id)).map(|_| ()).unwrap_err(), Refusal::NoSuchCommander);
}
