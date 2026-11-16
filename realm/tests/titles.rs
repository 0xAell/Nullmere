//! The titles of the Mere over a store kept in memory: none to bestow
//! until a season is won; the winning alliance's leader the Lord of the
//! Mere, bestowing titles on whom they will and taking them back; each
//! lending what so many levels of a study would; and a new Lord's season
//! beginning with none held.

use realm::catalog::{self, Building as Kind, Goods, Title as Kind2, Topic, SPIRE_STAGES};
use realm::rows::{Building, City, Report, Stock, Title};
use realm::rules::{self, Refusal};
use realm::store::{Mem, Seconds, Table};

const START: Seconds = 3_000_000;

fn wait(db: &mut Mem, seconds: Seconds) {
    let to = db.clock + seconds;
    db.advance(to, rules::fire);
}

/// Ada leads the Keepers of the Mere with Bryn; Cole leads the Wardens of
/// the Shore; Edda is in no alliance. Each has an Embassy and goods enough
/// to raise a Moonspire whole.
fn realm() -> (Mem, [u64; 4], Vec<City>) {
    let mut db = Mem::new(START, 5);
    rules::open(&mut db, 7, 1, 48);
    let players: Vec<u64> = ["Ada", "Bryn", "Cole", "Edda"].iter().map(|name| db.call(|db| rules::join(db, name)).unwrap().id).collect();
    let mut cities = Vec::new();
    for player in &players {
        let city = rules::city_of(&db, *player).unwrap();
        db.insert(Building { id: 0, city: city.id, kind: Kind::Embassy as u8, level: 1 });
        let mut stock = rules::grown(&Table::<Stock>::get(&db, city.id).unwrap(), db.clock);
        (stock.grain, stock.timber, stock.stone, stock.moonsalt, stock.holds) = (90_000_000, 90_000_000, 90_000_000, 9_000_000, u64::MAX / 4);
        db.update(stock);
        cities.push(city);
    }
    let mere = db.call(|db| rules::found_alliance(db, players[0], "Keepers of the Mere", "MERE")).unwrap();
    db.call(|db| rules::join_alliance(db, players[1], mere.id)).unwrap();
    db.call(|db| rules::found_alliance(db, players[2], "Wardens of the Shore", "WRD")).unwrap();
    wait(&mut db, 30);
    (db, [players[0], players[1], players[2], players[3]], cities)
}

/// A player's alliance raises its Moonspire whole.
fn raise_whole(db: &mut Mem, player: u64) {
    let all: Goods = (1..=SPIRE_STAGES).map(catalog::spire_cost).fold(Goods::of(0, 0, 0, 0), |sum, cost| sum.plus(cost));
    db.call(|db| rules::give_to_spire(db, player, all)).unwrap();
    let whole: Seconds = (1..=SPIRE_STAGES).map(catalog::spire_seconds).sum();
    wait(db, whole + 3_600);
}

fn last_title_words(db: &Mem, player: u64) -> String {
    Table::<Report>::by(db, 0, player).into_iter().filter(|report| report.kind == Report::TITLE).max_by_key(|report| report.id).map(|report| report.words).unwrap_or_default()
}

#[test]
fn the_lord_of_the_mere_bestows_titles_that_lend_what_studies_would() {
    let (mut db, [ada, bryn, cole, edda], cities) = realm();
    // No season won yet: there is no Lord.
    assert_eq!(rules::lord(&db), None);
    assert_eq!(db.call(|db| rules::bestow_title(db, ada, Kind2::Forager as u8, edda)), Err(Refusal::NotTheLord));
    assert_eq!(
        Refusal::NotTheLord.to_string(),
        "Only the Lord of the Mere bestows its titles: the leader of the alliance that won the last season won."
    );

    // The Keepers raise their Moonspire whole and win the season: Ada is the Lord.
    raise_whole(&mut db, ada);
    assert_eq!(rules::lord(&db), Some(ada));
    assert_eq!(db.call(|db| rules::bestow_title(db, bryn, Kind2::Forager as u8, edda)), Err(Refusal::NotTheLord));
    assert_eq!(db.call(|db| rules::bestow_title(db, ada, 9, edda)), Err(Refusal::NoSuchTitle));
    assert_eq!(db.call(|db| rules::bestow_title(db, ada, Kind2::Forager as u8, 999)), Err(Refusal::NoSuchPlayer));

    // A title on anyone in the realm, ally or not: Edda, in no alliance, is made Forager.
    let before = rules::boost(&db, cities[3].id, Topic::Gathering);
    let made = db.call(|db| rules::bestow_title(db, ada, Kind2::Forager as u8, edda)).unwrap();
    assert_eq!((made.title, made.holder, made.name.as_str()), (Kind2::Forager as u64, edda, "Edda"));
    assert_eq!(rules::boost(&db, cities[3].id, Topic::Gathering), before + 2 * Topic::Gathering.each(), "as two levels of Gathering");
    assert_eq!(last_title_words(&db, edda), "The Lord of the Mere has made you Forager of the Mere.");
    assert_eq!(db.call(|db| rules::bestow_title(db, ada, Kind2::Forager as u8, edda)), Err(Refusal::TitleHeld));

    // Bestowed on another, it is taken from the one who held it.
    wait(&mut db, 10);
    db.call(|db| rules::bestow_title(db, ada, Kind2::Forager as u8, cole)).unwrap();
    assert_eq!(rules::boost(&db, cities[3].id, Topic::Gathering), before);
    assert_eq!(rules::boost(&db, cities[2].id, Topic::Gathering), 2 * Topic::Gathering.each());
    assert_eq!(last_title_words(&db, edda), "The Lord of the Mere has taken the title of Forager of the Mere from you.");

    // Each title lends its own study; one player may hold more than one.
    db.call(|db| rules::bestow_title(db, ada, Kind2::Mason as u8, bryn)).unwrap();
    db.call(|db| rules::bestow_title(db, ada, Kind2::Warden as u8, bryn)).unwrap();
    assert_eq!(rules::boost(&db, cities[1].id, Topic::Building), 4 * Topic::Building.each());
    assert_eq!(rules::boost(&db, cities[1].id, Topic::Shields), 3 * Topic::Shields.each());
    assert_eq!(Table::<Title>::all(&db).len(), 3);

    // Taken back by the Lord.
    db.call(|db| rules::take_title(db, ada, Kind2::Mason as u8)).unwrap();
    assert_eq!(rules::boost(&db, cities[1].id, Topic::Building), 0);
    assert_eq!(db.call(|db| rules::take_title(db, ada, Kind2::Mason as u8)), Err(Refusal::NoSuchTitle));
    assert_eq!(db.call(|db| rules::take_title(db, bryn, Kind2::Warden as u8)), Err(Refusal::NotTheLord));
}

#[test]
fn a_new_lords_season_begins_with_no_title_held() {
    let (mut db, [ada, _, cole, edda], cities) = realm();
    raise_whole(&mut db, ada);
    db.call(|db| rules::bestow_title(db, ada, Kind2::Herald as u8, edda)).unwrap();
    assert_eq!(rules::boost(&db, cities[3].id, Topic::Marching), 3 * Topic::Marching.each());

    // The season turns; the next is the Wardens': Cole is the Lord, and what Ada bestowed lapses.
    let ends = rules::season_now(&db).ends;
    let to = ends + 10;
    db.advance(to, rules::fire);
    assert_eq!(rules::season_now(&db).number, 2);
    assert_eq!(rules::lord(&db), Some(ada), "until another season is won");
    assert_eq!(Table::<Title>::all(&db).len(), 1, "a season's turn takes no title");
    raise_whole(&mut db, cole);
    assert_eq!(rules::lord(&db), Some(cole));
    assert!(Table::<Title>::all(&db).is_empty());
    assert_eq!(rules::boost(&db, cities[3].id, Topic::Marching), 0);
    assert_eq!(db.call(|db| rules::bestow_title(db, ada, Kind2::Herald as u8, edda)), Err(Refusal::NotTheLord));
    assert!(db.call(|db| rules::bestow_title(db, cole, Kind2::Herald as u8, edda)).is_ok());
}
