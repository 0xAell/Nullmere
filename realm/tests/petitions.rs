//! Petitions over a store kept in memory: a member asks their alliance
//! for goods, allies answer with what is still asked, a tenth lost on the
//! road, until it is answered in full; one at a time, standing a day,
//! withdrawn at will.

use realm::catalog::{self, Building as Kind, Goods};
use realm::rows::{Building, City, Petition, Report, Stock};
use realm::rules::{self, Refusal};
use realm::store::{Mem, Seconds, Table};

const START: Seconds = 3_000_000;

fn wait(db: &mut Mem, seconds: Seconds) {
    let to = db.clock + seconds;
    db.advance(to, rules::fire);
}

/// Ada and Bryn of one alliance, Cole of none, each with goods.
fn realm() -> (Mem, [u64; 3], Vec<City>) {
    let mut db = Mem::new(START, 5);
    rules::open(&mut db, 7, 1, 48);
    let players: Vec<u64> = ["Ada", "Bryn", "Cole"].iter().map(|name| db.call(|db| rules::join(db, name)).unwrap().id).collect();
    let mut cities = Vec::new();
    for player in &players {
        let city = rules::city_of(&db, *player).unwrap();
        db.insert(Building { id: 0, city: city.id, kind: Kind::Embassy as u8, level: 1 });
        let mut stock = rules::grown(&Table::<Stock>::get(&db, city.id).unwrap(), db.clock);
        (stock.grain, stock.timber, stock.stone, stock.moonsalt, stock.holds) = (200_000, 200_000, 200_000, 0, 10_000_000);
        db.update(stock);
        cities.push(city);
    }
    let alliance = db.call(|db| rules::found_alliance(db, players[0], "Keepers of the Mere", "MERE")).unwrap();
    db.call(|db| rules::join_alliance(db, players[1], alliance.id)).unwrap();
    wait(&mut db, 30);
    (db, [players[0], players[1], players[2]], cities)
}

fn goods_of(db: &Mem, city: &City) -> Goods {
    rules::goods(&rules::grown(&Table::<Stock>::get(db, city.id).unwrap(), db.clock))
}

#[test]
fn allies_answer_a_petition_with_what_it_still_asks_less_the_roads_tenth() {
    let (mut db, [ada, bryn, cole], cities) = realm();
    assert_eq!(db.call(|db| rules::petition(db, cole, Goods::of(10, 0, 0, 0))), Err(Refusal::NotAllied));
    assert_eq!(db.call(|db| rules::petition(db, ada, Goods::NONE)), Err(Refusal::NothingAsked));
    assert_eq!(db.call(|db| rules::petition(db, ada, Goods::of(500_001, 0, 0, 0))), Err(Refusal::PetitionTooLarge(catalog::PETITION_MOST)));
    assert_eq!(Refusal::PetitionTooLarge(500_000).to_string(), "A petition asks 500,000 of each good at most.");
    let asked = db.call(|db| rules::petition(db, ada, Goods::of(100_000, 50_000, 0, 0))).unwrap();
    assert_eq!((asked.alliance, asked.name.as_str(), asked.grain, asked.timber), (asked.alliance, "[MERE] Ada", 100_000, 50_000));
    assert_eq!(db.call(|db| rules::petition(db, ada, Goods::of(10, 0, 0, 0))), Err(Refusal::PetitionStands));

    // Not answered by its asker, nor by one outside the alliance.
    assert_eq!(db.call(|db| rules::answer_petition(db, ada, ada, Goods::of(10, 0, 0, 0))), Err(Refusal::NoSuchPetition));
    assert_eq!(db.call(|db| rules::answer_petition(db, cole, ada, Goods::of(10, 0, 0, 0))), Err(Refusal::NotAllied));

    // Bryn sends some grain: a tenth is lost on the road.
    let (hers, his) = (goods_of(&db, &cities[0]), goods_of(&db, &cities[1]));
    let came = db.call(|db| rules::answer_petition(db, bryn, ada, Goods::of(60_000, 0, 0, 0))).unwrap();
    assert_eq!(came, Goods::of(54_000, 0, 0, 0));
    assert_eq!(goods_of(&db, &cities[1]), his.minus(Goods::of(60_000, 0, 0, 0)));
    assert_eq!(goods_of(&db, &cities[0]), hers.plus(came));
    assert_eq!(rules::still_asked(&Table::<Petition>::get(&db, ada).unwrap()), Goods::of(40_000, 50_000, 0, 0));
    assert_eq!(db.call(|db| rules::answer_petition(db, bryn, ada, Goods::of(0, 0, 900, 0))), Err(Refusal::NothingNeeded), "stone was not asked for");

    // More than is still asked: only what is asked is taken, and the petition is done.
    let his = goods_of(&db, &cities[1]);
    let came = db.call(|db| rules::answer_petition(db, bryn, ada, Goods::of(100_000, 100_000, 0, 0))).unwrap();
    assert_eq!(came, Goods::of(36_000, 45_000, 0, 0));
    assert_eq!(goods_of(&db, &cities[1]), his.minus(Goods::of(40_000, 50_000, 0, 0)));
    assert!(Table::<Petition>::get(&db, ada).is_none());
    let told: Vec<String> = Table::<Report>::by(&db, 0, ada).into_iter().filter(|report| report.kind == Report::PETITION).map(|report| report.words).collect();
    assert_eq!(told.len(), 2);
    assert!(told.iter().any(|words| words == "[MERE] Bryn answered your petition: 36,000 grain and 45,000 timber came into your city, the road taking a tenth of what was sent. Your petition is answered in full."), "{told:?}");
}

#[test]
fn a_petition_stands_a_day_and_may_be_withdrawn() {
    let (mut db, [ada, bryn, _], _) = realm();
    db.call(|db| rules::petition(db, ada, Goods::of(1_000, 0, 0, 0))).unwrap();
    wait(&mut db, catalog::PETITION_STANDS + 1);
    assert_eq!(db.call(|db| rules::answer_petition(db, bryn, ada, Goods::of(1_000, 0, 0, 0))), Err(Refusal::NoSuchPetition), "its day is done");
    // A petition whose day is done does not stand in the way of a new one.
    let anew = db.call(|db| rules::petition(db, ada, Goods::of(3_000, 0, 0, 0))).unwrap();
    assert_eq!((anew.grain, anew.made_at), (3_000, db.clock));
    db.call(|db| rules::withdraw_petition(db, ada)).unwrap();
    assert!(Table::<Petition>::get(&db, ada).is_none());
    assert_eq!(db.call(|db| rules::withdraw_petition(db, ada)), Err(Refusal::NoSuchPetition));
    // Withdrawn, another may be made.
    assert!(db.call(|db| rules::petition(db, ada, Goods::of(2_000, 0, 0, 0))).is_ok());
}

#[test]
fn a_market_takes_the_roads_toll_down() {
    assert_eq!([0, 1, 3, 4, 6, 7, 24, 25].map(catalog::petition_toll), [10, 9, 9, 8, 8, 7, 2, 2]);
    let (mut db, [ada, bryn, _], cities) = realm();
    db.insert(Building { id: 0, city: cities[1].id, kind: Kind::Market as u8, level: 4 });
    db.call(|db| rules::petition(db, ada, Goods::of(100_000, 0, 0, 0))).unwrap();
    let came = db.call(|db| rules::answer_petition(db, bryn, ada, Goods::of(50_000, 0, 0, 0))).unwrap();
    assert_eq!(came, Goods::of(46_000, 0, 0, 0), "eight hundredths taken, from a Market of the fourth level");
    let told: Vec<String> = Table::<Report>::by(&db, 0, ada).into_iter().filter(|report| report.kind == Report::PETITION).map(|report| report.words).collect();
    assert!(told.iter().any(|words| words.contains("came into your city, the road taking 8 hundredths of what was sent.")), "{told:?}");
}
