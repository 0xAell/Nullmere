//! Letters over a store kept in memory: written to another player, read
//! and forgotten only by the one it is to, written by an officer to their
//! whole alliance, held to their length and pace, and a hundred kept.

use realm::catalog::{self, Building as Kind};
use realm::rows::{Building, Letter};
use realm::rules::{self, Refusal};
use realm::store::{Mem, Seconds, Table};

const START: Seconds = 3_000_000;

fn wait(db: &mut Mem, seconds: Seconds) {
    let to = db.clock + seconds;
    db.advance(to, rules::fire);
}

/// Ada leads the Keepers of the Mere with Bryn and Cole; Edda is in none.
fn realm() -> (Mem, [u64; 4]) {
    let mut db = Mem::new(START, 5);
    rules::open(&mut db, 7, 1, 48);
    let players: Vec<u64> = ["Ada", "Bryn", "Cole", "Edda"].iter().map(|name| db.call(|db| rules::join(db, name)).unwrap().id).collect();
    let city = rules::city_of(&db, players[0]).unwrap();
    db.insert(Building { id: 0, city: city.id, kind: Kind::Embassy as u8, level: 1 });
    let mere = db.call(|db| rules::found_alliance(db, players[0], "Keepers of the Mere", "MERE")).unwrap();
    for player in &players[1..3] {
        db.call(|db| rules::join_alliance(db, *player, mere.id)).unwrap();
    }
    wait(&mut db, 30);
    (db, [players[0], players[1], players[2], players[3]])
}

fn letters_to(db: &Mem, player: u64) -> Vec<Letter> {
    let mut all: Vec<Letter> = Table::<Letter>::by(db, 1, player);
    all.sort_by_key(|letter| letter.id);
    all
}

#[test]
fn a_letter_goes_to_another_player_and_is_read_and_forgotten_by_them_alone() {
    let (mut db, [ada, bryn, _, edda]) = realm();
    let letter = db.call(|db| rules::send_letter(db, edda, ada, "  The east road is clear.\nCome at dawn.  ")).unwrap();
    assert_eq!((letter.sender, letter.receiver, letter.name.as_str(), letter.words.as_str(), letter.read), (edda, ada, "Edda", "The east road is clear.\nCome at dawn.", false));
    wait(&mut db, 2);
    let back = db.call(|db| rules::send_letter(db, ada, edda, "We come.")).unwrap();
    assert_eq!(back.name, "[MERE] Ada", "a writer's name as others read it");

    // Only the one it is to marks it read, or forgets it.
    assert_eq!(db.call(|db| rules::read_letter(db, edda, letter.id)), Err(Refusal::NoSuchLetter));
    assert_eq!(db.call(|db| rules::forget_letter(db, bryn, letter.id)), Err(Refusal::NoSuchLetter));
    db.call(|db| rules::read_letter(db, ada, letter.id)).unwrap();
    assert!(Table::<Letter>::get(&db, letter.id).unwrap().read);
    db.call(|db| rules::forget_letter(db, ada, letter.id)).unwrap();
    assert!(Table::<Letter>::get(&db, letter.id).is_none());
    assert_eq!(Refusal::NoSuchLetter.to_string(), "There is no such letter of yours.");

    // Held to its words, its reader, and its pace.
    wait(&mut db, 2);
    assert_eq!(db.call(|db| rules::send_letter(db, ada, edda, "   ")), Err(Refusal::NothingSaid));
    assert_eq!(db.call(|db| rules::send_letter(db, ada, edda, &"a".repeat(1_001))), Err(Refusal::LetterTooLong(catalog::LETTER_LONGEST)));
    assert_eq!(db.call(|db| rules::send_letter(db, ada, edda, "a\u{7}bell")), Err(Refusal::LetterTooLong(1_000)));
    assert_eq!(Refusal::LetterTooLong(1_000).to_string(), "A letter holds 1,000 characters at most, and nothing unprintable.");
    assert_eq!(db.call(|db| rules::send_letter(db, ada, ada, "To myself.")), Err(Refusal::OwnLetter));
    assert_eq!(db.call(|db| rules::send_letter(db, ada, 999, "To no one.")), Err(Refusal::NoSuchPlayer));
    assert!(db.call(|db| rules::send_letter(db, ada, edda, &"a".repeat(1_000))).is_ok());
    assert_eq!(db.call(|db| rules::send_letter(db, ada, edda, "Again.")), Err(Refusal::SayingTooFast));
    // What is written is paced apart from what is said.
    assert!(db.call(|db| rules::say(db, ada, false, "Good morning, all.")).is_ok());
}

#[test]
fn an_officer_writes_to_the_whole_alliance_and_a_hundred_letters_are_kept() {
    let (mut db, [ada, bryn, cole, edda]) = realm();
    assert_eq!(db.call(|db| rules::send_alliance_letter(db, bryn, "To all.")), Err(Refusal::NotAnOfficer));
    assert_eq!(db.call(|db| rules::send_alliance_letter(db, edda, "To all.")), Err(Refusal::NotAllied));
    assert_eq!(db.call(|db| rules::send_alliance_letter(db, ada, "Muster at the ridge at dusk.")), Ok(2));
    for player in [bryn, cole] {
        assert_eq!(letters_to(&db, player).iter().map(|letter| letter.words.as_str()).collect::<Vec<_>>(), vec!["Muster at the ridge at dusk."]);
    }
    assert!(letters_to(&db, ada).is_empty(), "not to the writer");
    assert!(letters_to(&db, edda).is_empty(), "nor beyond the alliance");

    // A hundred kept: the oldest go as new ones come.
    for n in 0..(catalog::LETTERS_KEPT + 2) {
        wait(&mut db, 2);
        db.call(|db| rules::send_letter(db, edda, bryn, &format!("Letter {n}"))).unwrap();
    }
    let kept = letters_to(&db, bryn);
    assert_eq!(kept.len(), catalog::LETTERS_KEPT);
    assert_eq!(kept[0].words, "Letter 2", "of 103, the alliance's letter and Edda's first two are gone");
    assert_eq!(kept.last().unwrap().words, format!("Letter {}", catalog::LETTERS_KEPT + 1));
}
