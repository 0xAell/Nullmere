//! Marks on the map over a store kept in memory: set by an alliance's
//! officers for its members, said anew where one stands, ten kept at most,
//! cleared by officers, and gone when the alliance ends.

use realm::catalog::Building as Kind;
use realm::hex::Hex;
use realm::rows::{Building, Mark, Member};
use realm::rules::{self, Refusal};
use realm::store::{Mem, Seconds, Table};

const START: Seconds = 3_000_000;

fn wait(db: &mut Mem, seconds: Seconds) {
    let to = db.clock + seconds;
    db.advance(to, rules::fire);
}

/// Ada leads the Keepers of the Mere with Bryn and Cole; Edda is in none.
fn realm() -> (Mem, [u64; 4], u64) {
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
    (db, [players[0], players[1], players[2], players[3]], mere.id)
}

fn marks(db: &Mem, alliance: u64) -> Vec<(Hex, String)> {
    let mut all = Table::<Mark>::by(db, 0, alliance);
    all.sort_by_key(|mark| mark.id);
    all.into_iter().map(|mark| (Hex::unpacked(mark.hex), mark.words)).collect()
}

#[test]
fn an_officer_marks_places_for_the_alliance_and_clears_them() {
    let (mut db, [ada, bryn, cole, edda], mere) = realm();
    let ford = Hex::new(3, -2);
    let mark = db.call(|db| rules::set_mark(db, ada, ford, "  Gather here at dusk ")).unwrap();
    assert_eq!((mark.alliance, Hex::unpacked(mark.hex), mark.words.as_str(), mark.setter, mark.at), (mere, ford, "Gather here at dusk", ada, db.clock));
    // Set again where it stands, it says the new words.
    let again = db.call(|db| rules::set_mark(db, ada, ford, "Gather here at dawn")).unwrap();
    assert_eq!(again.id, mark.id);
    assert_eq!(marks(&db, mere), vec![(ford, "Gather here at dawn".to_string())]);

    // Only an officer marks or clears; one in no alliance neither.
    assert_eq!(db.call(|db| rules::set_mark(db, bryn, ford, "Mine")), Err(Refusal::NotAnOfficer));
    assert_eq!(db.call(|db| rules::set_mark(db, edda, ford, "Mine")), Err(Refusal::NotAllied));
    assert_eq!(db.call(|db| rules::clear_mark(db, bryn, mark.id)), Err(Refusal::NotAnOfficer));
    db.call(|db| rules::set_rank(db, ada, cole, Member::OFFICER)).unwrap();
    db.call(|db| rules::set_mark(db, cole, Hex::new(-4, 1), "Barrow, take it")).unwrap();
    assert_eq!(marks(&db, mere).len(), 2);

    // Held to its words and the realm.
    assert_eq!(db.call(|db| rules::set_mark(db, ada, ford, "   ")), Err(Refusal::NothingSaid));
    assert_eq!(db.call(|db| rules::set_mark(db, ada, ford, &"a".repeat(41))), Err(Refusal::MarkTooLong(rules::MARK_LONGEST)));
    assert_eq!(db.call(|db| rules::set_mark(db, ada, ford, "a\u{7}bell")), Err(Refusal::MarkTooLong(40)));
    assert_eq!(db.call(|db| rules::set_mark(db, ada, Hex::new(49, 0), "Far")), Err(Refusal::BeyondTheRealm));
    assert_eq!(Refusal::MarkTooLong(40).to_string(), "A mark says 40 characters at most, and nothing unprintable.");
    assert_eq!(Refusal::BeyondTheRealm.to_string(), "That lies beyond the realm.");

    // Cleared by an officer, once.
    db.call(|db| rules::clear_mark(db, cole, mark.id)).unwrap();
    assert_eq!(marks(&db, mere), vec![(Hex::new(-4, 1), "Barrow, take it".to_string())]);
    assert_eq!(db.call(|db| rules::clear_mark(db, ada, mark.id)), Err(Refusal::NoSuchMark));
    assert_eq!(Refusal::NoSuchMark.to_string(), "Your alliance has no such mark.");
}

#[test]
fn an_alliance_keeps_ten_marks_and_none_once_it_ends() {
    let (mut db, [ada, bryn, cole, _], mere) = realm();
    for at in 0..rules::MOST_MARKS as i32 {
        db.call(|db| rules::set_mark(db, ada, Hex::new(at, 0), &format!("Mark {at}"))).unwrap();
        wait(&mut db, 1);
    }
    assert_eq!(db.call(|db| rules::set_mark(db, ada, Hex::new(0, 5), "One more")), Err(Refusal::MarksAll(10)));
    assert_eq!(Refusal::MarksAll(10).to_string(), "Your alliance has all the marks it may: 10. Clear one first.");
    // Where one stands, it may still be said anew.
    assert!(db.call(|db| rules::set_mark(db, ada, Hex::new(0, 0), "Mark zero, again")).is_ok());

    // The alliance ends: its marks are gone.
    for player in [bryn, cole] {
        db.call(|db| rules::leave_alliance(db, player)).unwrap();
    }
    wait(&mut db, 10);
    db.call(|db| rules::leave_alliance(db, ada)).unwrap();
    assert!(Table::<Mark>::get(&db, 1).is_none());
    assert!(marks(&db, mere).is_empty());
}

#[test]
fn no_mark_is_set_far_beyond_the_realm_nor_in_unseen_letters() {
    let (mut db, [ada, ..], _) = realm();
    // So far out that the reckoning of distance once wrapped round to near.
    assert_eq!(db.call(|db| rules::set_mark(db, ada, Hex::new(1_073_741_824, 1_073_741_825), "Here")), Err(Refusal::BeyondTheRealm));
    // Writing turned about, a space of no width, and a letter heaped with marks.
    for words in ["\u{202E}ereh rehtaG", "Gather\u{200B}here", "Gathe\u{0301}\u{0302}\u{0303}r"] {
        assert_eq!(db.call(|db| rules::set_mark(db, ada, Hex::new(2, -1), words)), Err(Refusal::MarkTooLong(rules::MARK_LONGEST)), "{words:?}");
    }
    // An accent or two on a letter is writing.
    assert!(db.call(|db| rules::set_mark(db, ada, Hex::new(2, -1), "Café of the shore")).is_ok());
}

#[test]
fn a_leader_forgotten_hands_the_alliance_on_and_a_member_forgotten_leaves_it() {
    let (mut db, [ada, bryn, cole, edda], mere) = realm();
    db.call(|db| rules::set_rank(db, ada, cole, realm::rows::Member::OFFICER)).unwrap();
    wait(&mut db, 1);
    // Edda asks to join, then Ada, the leader, is forgotten: the officer leads now.
    let mut alliance = Table::<realm::rows::Alliance>::get(&db, mere).unwrap();
    alliance.open = false;
    db.update(alliance);
    db.call(|db| rules::join_alliance(db, edda, mere)).unwrap();
    db.call(|db| rules::forget(db, ada)).unwrap();
    assert!(Table::<Member>::get(&db, ada).is_none(), "out of it");
    assert_eq!(Table::<Member>::get(&db, cole).unwrap().rank, Member::LEADER);
    assert_eq!(Table::<realm::rows::Alliance>::get(&db, mere).unwrap().leader, cole);
    assert_eq!(Table::<realm::rows::Alliance>::get(&db, mere).unwrap().members, 2);
    // Edda, forgotten while asking to join, is asking no more.
    db.call(|db| rules::forget(db, edda)).unwrap();
    assert!(Table::<realm::rows::Applicant>::get(&db, edda).is_none());
    // Bryn, a member, forgotten, leaves it; Cole alone, forgotten, ends it.
    db.call(|db| rules::forget(db, bryn)).unwrap();
    db.call(|db| rules::forget(db, cole)).unwrap();
    assert!(Table::<realm::rows::Alliance>::get(&db, mere).is_none(), "an alliance of no one is no more");
}
