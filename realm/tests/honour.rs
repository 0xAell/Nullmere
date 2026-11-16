//! Honour over a store kept in memory: earned by helping allies and by
//! giving toward what the alliance learns, and spent in its stores.

use realm::catalog::{Building as Kind, Goods, Item};
use realm::rows::{Building, Honour, Job, Price, Satchel, Stock};
use realm::rules::{self, Refusal};
use realm::store::{Mem, Seconds, Table};

const START: Seconds = 3_000_000;

fn wait(db: &mut Mem, seconds: Seconds) {
    let to = db.clock + seconds;
    db.advance(to, rules::fire);
}

/// Ada and Bryn in one alliance founded by Ada; Cole in none.
fn alliance() -> (Mem, [u64; 3]) {
    let mut db = Mem::new(START, 5);
    rules::open(&mut db, 7, 1, 48);
    let players = ["Ada", "Bryn", "Cole"].map(|name| db.call(|db| rules::join(db, name)).unwrap().id);
    let city = rules::city_of(&db, players[0]).unwrap();
    db.insert(Building { id: 0, city: city.id, kind: Kind::Embassy as u8, level: 10 });
    let founded = db.call(|db| rules::found_alliance(db, players[0], "Keepers of the Mere", "MERE")).unwrap();
    db.call(|db| rules::join_alliance(db, players[1], founded.id)).unwrap();
    wait(&mut db, 30);
    (db, players)
}

fn honour(db: &Mem, player: u64) -> u64 {
    rules::honour_of(db, player).honour
}

fn held(db: &Mem, player: u64, item: Item) -> u64 {
    Table::<Satchel>::by(db, 0, player).iter().filter(|row| row.item == item as u8).map(|row| row.count).sum()
}

/// A work under way in a player's city, a long one, asked help with.
fn plea(db: &mut Mem, player: u64) -> u64 {
    let city = rules::city_of(db, player).unwrap();
    let now = db.clock;
    let job = db.insert(Job { id: 0, city: city.id, kind: Job::RAISE, subject: 0, level: 2, amount: 0, started: now, ends: now + 86_400, timer: 0 });
    db.call(|db| rules::ask_help(db, player, job.id)).unwrap();
    job.id
}

#[test]
fn honour_is_earned_helping_allies_up_to_a_day_s_worth() {
    let (mut db, [ada, bryn, cole]) = alliance();
    assert_eq!(honour(&db, bryn), 0);
    assert!(Table::<Honour>::all(&db).is_empty(), "no row for none");

    // Each help Bryn gives Ada is twenty honour.
    let first = plea(&mut db, ada);
    db.call(|db| rules::help(db, bryn, first)).unwrap();
    assert_eq!(honour(&db, bryn), rules::HONOUR_A_HELP);
    assert_eq!(honour(&db, ada), 0, "nothing for the one helped");
    assert_eq!(honour(&db, cole), 0);

    // Up to a thousand of it from helping in a day: fifty helps.
    for _ in 0..60 {
        plea(&mut db, ada);
        wait(&mut db, 3);
        db.call(|db| rules::help_all(db, bryn)).unwrap();
        wait(&mut db, 3);
    }
    assert_eq!(honour(&db, bryn), rules::HONOUR_FROM_HELP_A_DAY);
    assert_eq!(rules::honour_of(&db, bryn).from_help, rules::HONOUR_FROM_HELP_A_DAY);
    // A new day, more may be earned.
    wait(&mut db, 86_400);
    assert_eq!(rules::honour_of(&db, bryn).from_help, 0, "a new day's helping");
    let job = plea(&mut db, ada);
    wait(&mut db, 3);
    db.call(|db| rules::help(db, bryn, job)).unwrap();
    assert_eq!(honour(&db, bryn), rules::HONOUR_FROM_HELP_A_DAY + rules::HONOUR_A_HELP);
}

#[test]
fn honour_is_earned_giving_toward_the_alliance_s_learning_and_spent_in_its_stores() {
    let (mut db, [ada, bryn, cole]) = alliance();
    // The stores' prices, written out for clients.
    let prices: Vec<(u64, u64)> = { let mut all: Vec<_> = Table::<Price>::all(&db).iter().map(|row| (row.item, row.honour)).collect(); all.sort(); all };
    assert_eq!(prices, vec![(1, 100), (2, 1_000), (3, 6_000), (4, 5_000), (9, 250), (10, 2_000)]);
    assert_eq!(rules::price_of(Item::Iron), None, "materials are not sold");

    // Ada gives 30,000 goods toward the alliance's first topic: thirty honour.
    let city = rules::city_of(&db, ada).unwrap();
    let mut stock = Table::<Stock>::get(&db, city.id).unwrap();
    (stock.grain, stock.timber, stock.stone) = (500_000, 500_000, 500_000);
    db.update(stock);
    db.call(|db| rules::give_to_learning(db, ada, 1, Goods::of(10_000, 10_000, 10_000, 0))).unwrap();
    assert_eq!(honour(&db, ada), 30, "one for every thousand taken");

    // Too little to buy an hour's haste; enough for a five minutes'.
    let refusal = db.call(|db| rules::buy(db, ada, Item::Haste60 as u8, 1)).unwrap_err();
    assert_eq!((refusal.clone(), refusal.to_string()), (Refusal::NotEnoughHonour(30), "You have only 30 honour.".to_string()));
    // The rest of the level's 300,000 taken: 270 more.
    wait(&mut db, 3);
    db.call(|db| rules::give_to_learning(db, ada, 1, Goods::of(100_000, 100_000, 100_000, 0))).unwrap();
    assert_eq!(honour(&db, ada), 300);
    wait(&mut db, 3);
    let left = db.call(|db| rules::buy(db, ada, Item::Haste5 as u8, 3)).unwrap();
    assert_eq!(left, 0);
    assert_eq!(honour(&db, ada), 0);
    assert_eq!(held(&db, ada, Item::Haste5), 3, "into her satchel");

    // What the stores don't sell, none at all, too many at once, and one in no alliance.
    wait(&mut db, 3);
    let refusal = db.call(|db| rules::buy(db, ada, Item::Iron as u8, 1)).unwrap_err();
    assert_eq!((refusal.clone(), refusal.to_string()), (Refusal::NoSuchWare, "The alliance's stores sell no such thing.".to_string()));
    wait(&mut db, 3);
    assert_eq!(db.call(|db| rules::buy(db, ada, Item::Haste5 as u8, 0)), Err(Refusal::NothingAsked));
    wait(&mut db, 3);
    assert_eq!(db.call(|db| rules::buy(db, ada, Item::Haste5 as u8, 101)), Err(Refusal::TooMany(rules::MOST_BOUGHT)));
    assert_eq!(db.call(|db| rules::buy(db, cole, Item::Haste5 as u8, 1)), Err(Refusal::NotAllied));
    // Honour stays with its owner: Bryn, who earned none, buys nothing.
    assert_eq!(db.call(|db| rules::buy(db, bryn, Item::Haste5 as u8, 1)), Err(Refusal::NotEnoughHonour(0)));
}
