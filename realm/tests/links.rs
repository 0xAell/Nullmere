//! A player's other devices over a store kept in memory: a code asked for
//! on one, in letters that can't be mistaken for one another, taken once
//! on another within ten minutes, and gone when its player is forgotten.

use realm::rows::Link;
use realm::rules::{self, Refusal};
use realm::store::{Mem, Seconds, Table};

const START: Seconds = 3_000_000;

fn realm_of(names: &[&str]) -> (Mem, Vec<u64>) {
    let mut db = Mem::new(START, 5);
    rules::open(&mut db, 7, 1, 48);
    let players = names.iter().map(|name| db.call(|db| rules::join(db, name)).unwrap().id).collect();
    (db, players)
}

fn later(db: &mut Mem, seconds: Seconds) {
    let to = db.clock + seconds;
    db.advance(to, |db, timer| rules::fire(db, timer));
}

#[test]
fn a_code_is_ten_letters_none_to_mistake_and_read_back_however_typed() {
    for code in [0u64, 1, 31, 32, 0xDEAD_BEEF, (1 << 50) - 1] {
        let letters = rules::link_letters(code);
        assert_eq!(letters.len(), rules::LINK_LETTERS);
        assert!(letters.chars().all(|letter| letter.is_ascii_uppercase() || letter.is_ascii_digit()));
        assert!(!letters.contains(['0', '1', 'I', 'O']), "{letters}");
        assert_eq!(rules::link_code(&letters), Some(code), "{letters}");
    }
    let letters = rules::link_letters(0x2_3456_789A_BCDE);
    let typed = format!("{} {}-{}", &letters[..3].to_lowercase(), &letters[3..6], &letters[6..].to_lowercase());
    assert_eq!(rules::link_code(&typed), Some(0x2_3456_789A_BCDE), "lower case, spaces and dashes let be");
    for wrong in ["", "ABCDEFGHJ", "ABCDEFGHJKL", "ABCDEFGHJ0", "ABCDEFGHJ!"] {
        assert_eq!(rules::link_code(wrong), None, "{wrong}");
    }
}

#[test]
fn a_code_brings_another_device_in_as_its_player_once_within_ten_minutes() {
    let (mut db, players) = realm_of(&["Ada", "Bryn"]);
    let (ada, bryn) = (players[0], players[1]);
    let first = db.call(|db| rules::offer_link(db, ada)).unwrap();
    assert_eq!((first.player, first.expires), (ada, START + rules::LINK_SECONDS));
    assert_eq!(first.letters, rules::link_letters(first.code));
    // One at a time: a new code takes the old one's place.
    later(&mut db, 5);
    let second = db.call(|db| rules::offer_link(db, ada)).unwrap();
    assert_ne!(second.code, first.code);
    assert_eq!(Table::<Link>::by(&db, 0, ada), vec![second.clone()]);
    assert_eq!(db.call(|db| rules::take_link(db, &first.letters)), Err(Refusal::NoSuchLink), "the old one is gone");
    // Bryn's own is his.
    let his = db.call(|db| rules::offer_link(db, bryn)).unwrap();
    assert_eq!(Table::<Link>::all(&db).len(), 2);

    // Taken: Ada's player, and only once.
    assert_eq!(db.call(|db| rules::take_link(db, &second.letters.to_lowercase())), Ok(ada));
    assert_eq!(db.call(|db| rules::take_link(db, &second.letters)), Err(Refusal::NoSuchLink));
    assert_eq!(Refusal::NoSuchLink.to_string(), "No code of yours reads so, or it has been used. Ask your other device for a new one.");
    assert_eq!(db.call(|db| rules::take_link(db, "not a code")), Err(Refusal::NoSuchLink));

    // Ten minutes on, too old.
    later(&mut db, rules::LINK_SECONDS + 1);
    assert_eq!(db.call(|db| rules::take_link(db, &his.letters)), Err(Refusal::LinkTooOld));
    assert_eq!(Refusal::LinkTooOld.to_string(), "That code is more than ten minutes old. Ask your other device for a new one.");
}

#[test]
fn a_forgotten_players_codes_go_with_them() {
    let (mut db, players) = realm_of(&["Ada"]);
    let code = db.call(|db| rules::offer_link(db, players[0])).unwrap();
    db.call(|db| rules::forget(db, players[0])).unwrap();
    assert!(Table::<Link>::all(&db).is_empty());
    assert_eq!(db.call(|db| rules::take_link(db, &code.letters)), Err(Refusal::NoSuchLink));
    assert_eq!(db.call(|db| rules::offer_link(db, 99)).map(|_| ()), Err(Refusal::NotAPlayer));
}
