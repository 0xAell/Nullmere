//! The Moonspire over a store kept in memory: given toward by members,
//! raised a stage at a time, lifting what members' works bring in, won by
//! the first alliance to raise it whole in a season, and fallen when the
//! season turns.

use realm::catalog::{self, Building as Kind, Goods, SPIRE_STAGES};
use realm::rows::{Building, City, Gift, Report, Season, Spire, Stock};
use realm::rules::{self, Refusal};
use realm::store::{Mem, Seconds, Table};

const START: Seconds = 3_000_000;

fn wait(db: &mut Mem, seconds: Seconds) {
    let to = db.clock + seconds;
    db.advance(to, |db, timer| rules::fire(db, timer));
}

/// A realm of players of these names, each with an Embassy and goods
/// enough; those not named in `apart` in one alliance founded by the
/// first, and those in `rivals` in another founded by the first of them.
fn realm_of(names: &[&str], apart: &[&str], rivals: &[&str]) -> (Mem, Vec<u64>, Vec<City>) {
    let mut db = Mem::new(START, 5);
    rules::open(&mut db, 7, 1, 48);
    let players: Vec<u64> = names.iter().map(|name| db.call(|db| rules::join(db, name)).unwrap().id).collect();
    let mut cities = Vec::new();
    for player in &players {
        let city = rules::city_of(&db, *player).unwrap();
        db.insert(Building { id: 0, city: city.id, kind: Kind::Embassy as u8, level: 1 });
        fill(&mut db, city.id);
        cities.push(city);
    }
    let ours = db.call(|db| rules::found_alliance(db, players[0], "Keepers of the Mere", "MERE")).unwrap();
    let mut theirs = None;
    for (name, player) in names.iter().zip(&players).skip(1) {
        if rivals.contains(name) {
            match theirs {
                None => theirs = Some(db.call(|db| rules::found_alliance(db, *player, "Wardens of the Shore", "WARD")).unwrap().id),
                Some(id) => {
                    db.call(|db| rules::join_alliance(db, *player, id)).unwrap();
                }
            }
        } else if !apart.contains(name) {
            db.call(|db| rules::join_alliance(db, *player, ours.id)).unwrap();
        }
    }
    wait(&mut db, 30);
    (db, players, cities)
}

fn fill(db: &mut Mem, city: u64) {
    let mut stock = rules::grown(&Table::<Stock>::get(db, city).unwrap(), db.clock);
    (stock.grain, stock.timber, stock.stone, stock.moonsalt) = (90_000_000, 90_000_000, 90_000_000, 9_000_000);
    stock.holds = u64::MAX / 4;
    db.update(stock);
}

fn hourly(db: &Mem, city: u64) -> u64 {
    Table::<Stock>::get(db, city).unwrap().grain_hourly
}

fn alliance_of(db: &Mem, player: u64) -> u64 {
    rules::member_of(db, player).unwrap().alliance
}

/// Gives a stage's whole cost from one player.
fn pay_stage(db: &mut Mem, player: u64, stage: u32) -> Spire {
    db.call(|db| rules::give_to_spire(db, player, catalog::spire_cost(stage))).unwrap()
}

fn last_words(db: &Mem, player: u64) -> String {
    Table::<Report>::by(db, 0, player).into_iter().max_by_key(|report| report.id).map(|report| report.words).unwrap_or_default()
}

#[test]
fn the_first_season_begins_as_the_realm_opens_and_its_end_is_set() {
    let db = { let mut db = Mem::new(START, 5); rules::open(&mut db, 7, 1, 48); db };
    let seasons = Table::<Season>::all(&db);
    assert_eq!(seasons.len(), 1);
    let first = &seasons[0];
    assert_eq!((first.number, first.began, first.ends, first.victor), (1, START, START + catalog::SEASON_DAYS * catalog::DAY, 0));
    assert_eq!(db.timers.values().filter(|timer| timer.kind == rules::TIMER_SEASON).count(), 1);
    assert_eq!(rules::season_now(&db).number, 1);
    // Each stage asks more than the last, and the last asks moonsalt as well.
    assert!((1..SPIRE_STAGES).all(|stage| catalog::spire_cost(stage + 1).grain > catalog::spire_cost(stage).grain));
    assert!(catalog::spire_cost(SPIRE_STAGES).moonsalt > 0 && catalog::spire_cost(1).moonsalt == 0);
}

#[test]
fn members_give_toward_their_alliances_moonspire_and_a_stage_paid_for_is_raised_on_a_timer() {
    let (mut db, players, cities) = realm_of(&["Ada", "Bryn", "Cole"], &["Cole"], &[]);
    let (ada, bryn, cole) = (players[0], players[1], players[2]);
    let alliance = alliance_of(&db, ada);
    assert_eq!(rules::spire_of(&db, alliance).stage, 0);

    // One in no alliance has no Moonspire to give toward; nothing is not a gift; one gives only what they have.
    assert_eq!(db.call(|db| rules::give_to_spire(db, cole, Goods::of(10, 10, 10, 0))), Err(Refusal::NotAllied));
    assert_eq!(db.call(|db| rules::give_to_spire(db, ada, Goods::of(0, 0, 0, 0))), Err(Refusal::NothingAsked));
    let mut poor = Table::<Stock>::get(&db, cities[1].id).unwrap();
    (poor.grain, poor.timber, poor.stone, poor.moonsalt) = (5, 5, 5, 0);
    db.update(poor);
    assert!(matches!(db.call(|db| rules::give_to_spire(db, bryn, Goods::of(100, 0, 0, 0))), Err(Refusal::CannotAfford(_))));
    fill(&mut db, cities[1].id);

    // Two members give half of the first stage each: the second half begins it.
    let half = Goods::from_parts(catalog::spire_cost(1).parts().map(|part| part / 2));
    let before = rules::goods(&rules::grown(&Table::<Stock>::get(&db, cities[0].id).unwrap(), db.clock));
    let first = db.call(|db| rules::give_to_spire(db, ada, half)).unwrap();
    assert_eq!((first.stage, first.rises_at, first.grain), (0, 0, half.grain), "half is not enough");
    let after = rules::goods(&rules::grown(&Table::<Stock>::get(&db, cities[0].id).unwrap(), db.clock));
    assert_eq!(after, before.minus(half), "what is given leaves the giver's stock");
    wait(&mut db, 3);
    let begun = db.call(|db| rules::give_to_spire(db, bryn, half)).unwrap();
    assert_eq!((begun.stage, begun.rises_at, begun.grain), (0, db.clock + catalog::spire_seconds(1), 0), "the second half begins it, and is spent on it");
    assert_eq!(Table::<Gift>::get(&db, bryn).unwrap().given, half.parts().iter().sum::<u64>());

    // It stands when its timer ends, and every member's works bring in more.
    let (ada_before, bryn_before, cole_before) = (hourly(&db, cities[0].id), hourly(&db, cities[1].id), hourly(&db, cities[2].id));
    wait(&mut db, catalog::spire_seconds(1) - 1);
    assert_eq!(rules::spire_of(&db, alliance).stage, 0);
    wait(&mut db, 1);
    let risen = rules::spire_of(&db, alliance);
    assert_eq!((risen.stage, risen.rises_at), (1, 0));
    assert_eq!(rules::spire_boost(&db, ada), catalog::SPIRE_YIELD);
    assert!(hourly(&db, cities[0].id) > ada_before && hourly(&db, cities[1].id) > bryn_before, "both members' works bring in more");
    assert_eq!(hourly(&db, cities[2].id), cole_before, "and one in no alliance's do not");
    assert!(last_words(&db, ada).starts_with("The first stage of your alliance's Moonspire stands."), "{}", last_words(&db, ada));
}

#[test]
fn what_is_given_beyond_a_stage_goes_toward_the_next_and_raises_it_in_turn() {
    let (mut db, players, _) = realm_of(&["Ada", "Bryn"], &[], &[]);
    let ada = players[0];
    let alliance = alliance_of(&db, ada);
    // The first two stages given at once: the first is raised, the second waits for it.
    let both = catalog::spire_cost(1).plus(catalog::spire_cost(2));
    let spire = db.call(|db| rules::give_to_spire(db, ada, both)).unwrap();
    assert_eq!((spire.stage, spire.grain), (0, catalog::spire_cost(2).grain));
    wait(&mut db, catalog::spire_seconds(1));
    let next = rules::spire_of(&db, alliance);
    assert_eq!((next.stage, next.grain, next.rises_at), (1, 0, db.clock + catalog::spire_seconds(2)), "the second begun as soon as the first stood");
    wait(&mut db, catalog::spire_seconds(2));
    assert_eq!(rules::spire_of(&db, alliance).stage, 2);
}

#[test]
fn joining_an_alliance_takes_up_what_its_moonspire_lifts_and_leaving_lays_it_down() {
    let (mut db, players, cities) = realm_of(&["Ada", "Bryn"], &["Bryn"], &[]);
    let (ada, bryn) = (players[0], players[1]);
    let alliance = alliance_of(&db, ada);
    pay_stage(&mut db, ada, 1);
    wait(&mut db, catalog::spire_seconds(1));
    let alone = hourly(&db, cities[1].id);
    db.call(|db| rules::join_alliance(db, bryn, alliance)).unwrap();
    assert_eq!(hourly(&db, cities[1].id), alone * (100 + catalog::SPIRE_YIELD) / 100);
    wait(&mut db, 3);
    db.call(|db| rules::leave_alliance(db, bryn)).unwrap();
    assert_eq!(hourly(&db, cities[1].id), alone);
}

#[test]
fn the_first_alliance_to_raise_its_moonspire_whole_wins_the_season() {
    let (mut db, players, _) = realm_of(&["Ada", "Bryn", "Cole", "Dara"], &[], &["Cole", "Dara"]);
    let (ada, cole) = (players[0], players[2]);
    let (ours, theirs) = (alliance_of(&db, ada), alliance_of(&db, cole));
    assert_ne!(ours, theirs);
    let all: Goods = (1..=SPIRE_STAGES).map(catalog::spire_cost).fold(Goods::of(0, 0, 0, 0), |sum, cost| sum.plus(cost));
    db.call(|db| rules::give_to_spire(db, ada, all)).unwrap();
    wait(&mut db, 3_600);
    db.call(|db| rules::give_to_spire(db, cole, all)).unwrap();
    let whole: Seconds = (1..=SPIRE_STAGES).map(catalog::spire_seconds).sum();
    wait(&mut db, whole + 3_600);

    assert_eq!(rules::spire_of(&db, ours).stage, SPIRE_STAGES);
    assert_eq!(rules::spire_of(&db, theirs).stage, SPIRE_STAGES);
    let season = rules::season_now(&db);
    assert_eq!((season.victor, season.victor_name.as_str()), (ours, "Keepers of the Mere"), "the first to stand whole, not the second");
    assert_eq!(season.won_at, START + 30 + whole);
    assert!(last_words(&db, ada).contains("the first in the realm this season"), "{}", last_words(&db, ada));
    assert_eq!(last_words(&db, cole), "Your alliance's Moonspire stands whole.");
    // Whole, it takes no more.
    assert_eq!(db.call(|db| rules::give_to_spire(db, ada, Goods::of(1, 0, 0, 0))), Err(Refusal::SpireComplete));
    assert_eq!(rules::spire_boost(&db, ada), SPIRE_STAGES as u64 * catalog::SPIRE_YIELD);
}

#[test]
fn when_the_season_turns_every_moonspire_falls_and_the_next_begins() {
    let (mut db, players, cities) = realm_of(&["Ada", "Bryn"], &[], &[]);
    let ada = players[0];
    let alliance = alliance_of(&db, ada);
    pay_stage(&mut db, ada, 1);
    wait(&mut db, catalog::spire_seconds(1));
    let lifted = hourly(&db, cities[0].id);
    // A second stage paid for but not yet standing when the season ends is lost with it.
    pay_stage(&mut db, ada, 2);
    let ends = rules::season_now(&db).ends;
    db.advance(ends - catalog::spire_seconds(2) / 2, |db, timer| rules::fire(db, timer));
    pay_stage(&mut db, ada, 2);
    db.advance(ends, |db, timer| rules::fire(db, timer));

    let seasons = Table::<Season>::all(&db);
    assert_eq!(seasons.len(), 2);
    let (first, second) = (seasons.iter().find(|season| season.number == 1).unwrap(), rules::season_now(&db));
    assert_eq!((first.victor, second.number, second.began, second.ends), (0, 2, ends, ends + catalog::SEASON_DAYS * catalog::DAY));
    assert!(Table::<Spire>::all(&db).is_empty(), "every Moonspire has fallen");
    assert_eq!(rules::spire_of(&db, alliance).stage, 0);
    assert!(hourly(&db, cities[0].id) < lifted, "and what it lifted with it");
    assert_eq!(rules::spire_boost(&db, ada), 0);
    assert!(last_words(&db, ada).starts_with("Season 1 is over, and no alliance raised its Moonspire whole."), "{}", last_words(&db, ada));
    // The stage that was rising when it fell does not stand later.
    wait(&mut db, catalog::spire_seconds(2));
    assert_eq!(rules::spire_of(&db, alliance).stage, 0);
    // What was given last season is last season's.
    assert_eq!(Table::<Gift>::get(&db, ada).map(|gift| gift.season), Some(1));
    // And the next season's end is set.
    assert_eq!(db.timers.values().filter(|timer| timer.kind == rules::TIMER_SEASON && timer.subject == 2).count(), 1);
}

#[test]
fn a_season_is_as_long_as_the_realms_pace_makes_it() {
    let mut db = Mem::new(START, 5);
    rules::open(&mut db, 7, 60, 48);
    assert_eq!(rules::season_now(&db).ends, START + catalog::SEASON_DAYS * catalog::DAY / 60);
}
