//! Carts of goods over a store kept in memory: sent to an ally's city,
//! the carters' tenth, what is refused, and what comes back when the city
//! is no ally's by the time they come to it.

use realm::catalog::{Building as Kind, Goods, Troops};
use realm::hex::Hex;
use realm::rows::{Building, City, Haul, March, Report, Stock, Troop};
use realm::rules::{self, Asked, Refusal};
use realm::store::{Mem, Seconds, Table};

const START: Seconds = 3_000_000;

fn wait(db: &mut Mem, seconds: Seconds) {
    let to = db.clock + seconds;
    db.advance(to, |db, timer| rules::fire(db, timer));
}

/// A realm of players of these names, each with a Keep at its fifteenth
/// level, a Storehouse at its fourth, an Embassy and goods enough; all
/// but those named in `apart` in one alliance, founded by the first.
fn allies(names: &[&str], apart: &[&str]) -> (Mem, Vec<u64>, Vec<City>) {
    let mut db = Mem::new(START, 5);
    rules::open(&mut db, 7, 1, 48);
    let players: Vec<u64> = names.iter().map(|name| db.call(|db| rules::join(db, name)).unwrap().id).collect();
    let mut cities = Vec::new();
    for player in &players {
        let mut city = rules::city_of(&db, *player).unwrap();
        city.keep = 15;
        db.update(city.clone());
        let mut keep = rules::building_of(&db, city.id, Kind::Keep).unwrap();
        keep.level = 15;
        db.update(keep);
        db.insert(Building { id: 0, city: city.id, kind: Kind::Embassy as u8, level: 1 });
        match rules::building_of(&db, city.id, Kind::Storehouse) {
            Some(mut storehouse) => {
                storehouse.level = 4;
                db.update(storehouse);
            }
            None => {
                db.insert(Building { id: 0, city: city.id, kind: Kind::Storehouse as u8, level: 4 });
            }
        }
        let mut stock = rules::grown(&Table::<Stock>::get(&db, city.id).unwrap(), db.clock);
        (stock.grain, stock.timber, stock.stone, stock.moonsalt) = (500_000, 500_000, 500_000, 50_000);
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
    (db, players, cities)
}

fn stock(db: &Mem, city: u64) -> Goods {
    rules::goods(&rules::grown(&Table::<Stock>::get(db, city).unwrap(), db.clock))
}

/// What a city's stock has gained beyond what it would have grown to by
/// now from a row kept earlier.
fn added(db: &Mem, city: u64, earlier: &Stock) -> Goods {
    stock(db, city).minus(rules::goods(&rules::grown(earlier, db.clock)))
}

fn last_report(db: &Mem, player: u64) -> Report {
    Table::<Report>::by(db, 0, player).into_iter().max_by_key(|report| report.id).unwrap()
}

#[test]
fn carts_carry_goods_to_an_ally_and_the_carters_keep_a_tenth() {
    let (mut db, players, cities) = allies(&["Ada", "Bryn"], &[]);
    let (ada, bryn) = (players[0], players[1]);
    // Bryn's grain as much as the city holds: the carts fill it over.
    let mut row = rules::grown(&Table::<Stock>::get(&db, cities[1].id).unwrap(), db.clock);
    row.grain = row.holds;
    let holds = row.holds;
    db.update(row);
    let before = stock(&db, cities[0].id);

    let load = Goods::of(50_000, 30_000, 10_000, 1_000);
    let carts = db.call(|db| rules::send_goods(db, ada, Hex::unpacked(cities[1].hex), load)).unwrap();
    assert_eq!((carts.kind, carts.state, carts.soldiers, carts.target), (March::CARTS, March::GOING, 0, cities[1].id));
    assert!(carts.arrives > db.clock);
    // Taken from Ada's city at once; the carts carry nine tenths.
    let after = stock(&db, cities[0].id);
    assert_eq!(before.minus(after), load);
    let haul = Table::<Haul>::get(&db, carts.id).unwrap();
    assert_eq!(Goods::of(haul.grain, haul.timber, haul.stone, haul.moonsalt), Goods::of(45_000, 27_000, 9_000, 900));
    assert_eq!(rules::carters_due(load), (Goods::of(5_000, 3_000, 1_000, 100), Goods::of(45_000, 27_000, 9_000, 900)));

    // Carts keep no army from marching: Ada still sends her three.
    let city = cities[0].id;
    rules::keep_troop(&mut db, Troop { id: Troop::key(city, Troops::Spearmen as u8, 1), city, kind: Troops::Spearmen as u8, tier: 1, ready: 300, wounded: 0 });
    let spears = vec![Asked { kind: Troops::Spearmen as u8, tier: 1, count: 100 }];
    assert_eq!(rules::armies_out(&db, city).len(), 0);
    let bryns = Hex::unpacked(cities[1].hex);
    for _ in 0..3 {
        db.call(|db| rules::send(db, ada, bryns, March::REINFORCE, &spears)).unwrap();
    }
    assert_eq!(rules::armies_out(&db, city).len(), 3);
    assert_eq!(rules::carts_out(&db, city).len(), 1);

    // Come to Bryn's city, they are unloaded into it, over what it holds, and both are told.
    let unloaded = Goods::of(45_000, 27_000, 9_000, 900);
    let bryn_before = Table::<Stock>::get(&db, cities[1].id).unwrap();
    let ahead = carts.arrives - db.clock;
    wait(&mut db, ahead);
    assert!(Table::<March>::get(&db, carts.id).is_none(), "the carts are done");
    assert!(Table::<Haul>::get(&db, carts.id).is_none());
    assert_eq!(added(&db, cities[1].id, &bryn_before), unloaded);
    assert_eq!(stock(&db, cities[1].id).grain, holds + 45_000, "the stock is filled over what it holds");
    let told = last_report(&db, bryn);
    assert_eq!((told.kind, told.foe, Goods::of(told.grain, told.timber, told.stone, told.moonsalt)), (Report::CARTS, ada, unloaded));
    assert_eq!(told.words, "Carts from Ada's city were unloaded into yours: 45,000 grain, 27,000 timber, 9,000 stone and 900 moonsalt.");
    let back = last_report(&db, ada);
    assert_eq!((back.kind, back.foe), (Report::CARTS, bryn));
    assert_eq!(back.words, "Your carts unloaded 45,000 grain, 27,000 timber, 9,000 stone and 900 moonsalt into Bryn's city.");
}

#[test]
fn carts_are_refused_what_they_cannot_do_and_are_not_called_back() {
    let (mut db, players, cities) = allies(&["Ada", "Bryn", "Cole"], &["Cole"]);
    let (ada, bryn) = (players[0], players[1]);
    let to = |index: usize| Hex::unpacked(cities[index].hex);
    let refused = |db: &mut Mem, player: u64, at: Hex, load: Goods| {
        let refusal = db.call(|db| rules::send_goods(db, player, at, load)).unwrap_err();
        (refusal.clone(), refusal.to_string())
    };
    let some = Goods::of(1_000, 0, 0, 0);
    assert_eq!(refused(&mut db, ada, to(0), some), (Refusal::OwnCity, Refusal::OwnCity.to_string()));
    assert_eq!(refused(&mut db, ada, to(2), some), (Refusal::CartsToAlliesOnly, "Carts go only to an ally's city.".to_string()), "Cole is in no alliance of Ada's");
    assert_eq!(refused(&mut db, players[2], to(0), some).0, Refusal::CartsToAlliesOnly);
    assert_eq!(refused(&mut db, ada, to(1), Goods::NONE).0, Refusal::NothingAsked);
    let empty = Hex::new(to(1).q + 40, to(1).r);
    assert_eq!(refused(&mut db, ada, empty, some), (Refusal::NoCityForCarts, "There is no city there to send carts to.".to_string()));
    // A Storehouse at its fourth level loads 100,000 in all.
    assert_eq!((rules::cartload(0), rules::cartload(4), rules::cartload(99)), (20_000, 100_000, 520_000));
    assert_eq!(
        refused(&mut db, ada, to(1), Goods::of(50_000, 50_000, 0, 1)),
        (Refusal::TooMuchForCarts(100_000), "A load of carts takes at most 100,000 goods; raise your Storehouse for more.".to_string())
    );
    // More than the city has.
    let mut row = rules::grown(&Table::<Stock>::get(&db, cities[0].id).unwrap(), db.clock);
    row.stone = 10;
    db.update(row);
    assert!(matches!(refused(&mut db, ada, to(1), Goods::of(0, 0, 5_000, 0)).0, Refusal::CannotAfford(_)));
    let left = stock(&db, cities[0].id);

    // Three loads on the road, as many as a fifteenth-level Keep sends armies; a fourth is refused.
    let mut sent = Vec::new();
    for _ in 0..3 {
        sent.push(db.call(|db| rules::send_goods(db, ada, to(1), some)).unwrap());
    }
    assert_eq!(
        refused(&mut db, ada, to(1), some),
        (Refusal::CartsOnTheRoad(3), "You have 3 loads of carts on the road already, as many as your Keep allows.".to_string())
    );
    assert_eq!(left.grain - stock(&db, cities[0].id).grain, 3_000, "nothing refused was taken");
    assert_eq!(Refusal::CartsOnTheRoad(1).to_string(), "You have a load of carts on the road already, as many as your Keep allows.");
    // Carts are not called back, by their owner or anyone.
    let refusal = db.call(|db| rules::recall(db, ada, sent[0].id)).unwrap_err();
    assert_eq!((refusal.clone(), refusal.to_string()), (Refusal::CartsGoOn, "Carts go on to the city they were sent to; they are not called back.".to_string()));
    assert_eq!(db.call(|db| rules::recall(db, bryn, sent[0].id)).unwrap_err(), Refusal::NotYours);
    // Ada may still move her city: carts are no army.
    assert!(rules::armies_out(&db, cities[0].id).is_empty());
    assert!(!matches!(db.call(|db| rules::relocate(db, ada, empty)), Err(Refusal::ArmyOut)));
}

#[test]
fn carts_come_to_a_city_no_longer_an_ally_s_and_bring_back_what_they_carry() {
    let (mut db, players, cities) = allies(&["Ada", "Bryn"], &[]);
    let (ada, bryn) = (players[0], players[1]);
    let carts = db.call(|db| rules::send_goods(db, ada, Hex::unpacked(cities[1].hex), Goods::of(20_000, 0, 0, 0))).unwrap();
    db.call(|db| rules::leave_alliance(db, bryn)).unwrap();
    let (ada_before, bryn_before) = (Table::<Stock>::get(&db, cities[0].id).unwrap(), Table::<Stock>::get(&db, cities[1].id).unwrap());
    let ahead = carts.arrives - db.clock;
    wait(&mut db, ahead);
    assert!(Table::<March>::get(&db, carts.id).is_none());
    // Nothing for Bryn; Ada's grain back, less the carters' due.
    assert_eq!(added(&db, cities[1].id, &bryn_before), Goods::NONE);
    assert_eq!(added(&db, cities[0].id, &ada_before), Goods::of(18_000, 0, 0, 0));
    let told = last_report(&db, ada);
    assert_eq!(told.kind, Report::CARTS);
    assert_eq!(told.words, "The city your carts were sent to is no ally's now. What they carried is back in your city: 18,000 grain.");
}
