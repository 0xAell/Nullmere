//! Keeping the peace over a store kept in memory: lines of chat reported
//! with what was said about them, taken away, players barred from
//! speaking, reports let go, and a player forgotten on asking.

use realm::catalog::Building as Kind;
use realm::rows::{AllianceChat, Building, City, Complaint, Letter, Player, RealmChat};
use realm::rules::{self, Refusal};
use realm::store::{Mem, Seconds, Table};

const START: Seconds = 3_000_000;

/// A realm with players of these names, each with a city.
fn realm_of(names: &[&str]) -> (Mem, Vec<u64>) {
    let mut db = Mem::new(START, 5);
    rules::open(&mut db, 7, 1, 48);
    let players = names.iter().map(|name| db.call(|db| rules::join(db, name)).unwrap().id).collect();
    (db, players)
}

/// Moves the clock on, so that saying is not too fast.
fn later(db: &mut Mem, seconds: Seconds) {
    let to = db.clock + seconds;
    db.advance(to, |db, timer| rules::fire(db, timer));
}

/// Someone says something to the realm, a moment after the last.
fn say(db: &mut Mem, player: u64, words: &str) -> u64 {
    later(db, 3);
    db.call(|db| rules::say(db, player, false, words)).unwrap();
    Table::<RealmChat>::all(db).into_iter().map(|said| said.id).max().unwrap()
}

#[test]
fn a_line_is_reported_with_what_was_said_about_it() {
    let (mut db, players) = realm_of(&["Ada", "Bryn", "Cato"]);
    let (ada, bryn, cato) = (players[0], players[1], players[2]);
    let lines: Vec<u64> = ["One", "Two", "Three", "Four"].iter().map(|words| say(&mut db, ada, words)).collect();
    let rude = say(&mut db, bryn, "Something rude");
    for words in ["Five", "Six", "Seven", "Eight"] {
        say(&mut db, ada, words);
    }

    let kept = db.call(|db| rules::report_line(db, cato, rude, false)).unwrap();
    assert_eq!((kept.reporter, kept.line, kept.alliance, kept.speaker, kept.words.as_str()), (cato, rude, 0, bryn, "Something rude"));
    assert_eq!(kept.reported, db.clock);
    assert_eq!(kept.around, "  Ada: Two\n  Ada: Three\n  Ada: Four\n> Bryn: Something rude\n  Ada: Five\n  Ada: Six\n  Ada: Seven");
    assert_eq!(Table::<Complaint>::all(&db).len(), 1);

    // Once each; never one's own words; never a line that isn't there.
    assert_eq!(db.call(|db| rules::report_line(db, cato, rude, false)), Err(Refusal::ReportedAlready));
    assert_eq!(db.call(|db| rules::report_line(db, bryn, rude, false)), Err(Refusal::OwnWords));
    assert_eq!(db.call(|db| rules::report_line(db, cato, 999, false)), Err(Refusal::NoSuchLine));
    assert_eq!(Refusal::NoSuchLine.to_string(), "There is no such line to report.");
    // Another may report it as well; and the first line, with nothing before it.
    db.call(|db| rules::report_line(db, ada, rude, false)).unwrap();
    let first = db.call(|db| rules::report_line(db, bryn, lines[0], false)).unwrap();
    assert_eq!(first.around, "> Ada: One\n  Ada: Two\n  Ada: Three\n  Ada: Four");

    // So many waiting at once, and no more.
    for _ in 0..rules::REPORTS_OPEN - 1 {
        let words = say(&mut db, bryn, "More");
        db.call(|db| rules::report_line(db, cato, words, false)).unwrap();
    }
    let one_more = say(&mut db, bryn, "One more");
    let refusal = db.call(|db| rules::report_line(db, cato, one_more, false)).unwrap_err();
    assert_eq!((refusal.clone(), refusal.to_string()), (Refusal::TooManyReports(20), "You have 20 reports waiting already. Wait for the realm's owner to read them.".to_string()));

    // The owner lets one go, and another may be made.
    assert_eq!(rules::dismiss(&mut db, kept.id), Ok(()));
    assert_eq!(rules::dismiss(&mut db, kept.id), Err(Refusal::NoSuchComplaint));
    assert!(db.call(|db| rules::report_line(db, cato, one_more, false)).is_ok());
}

#[test]
fn an_alliance_line_is_reported_by_its_members_alone() {
    let (mut db, players) = realm_of(&["Ada", "Bryn", "Cato"]);
    let (ada, bryn, cato) = (players[0], players[1], players[2]);
    let city = rules::city_of(&db, ada).unwrap();
    db.insert(Building { id: 0, city: city.id, kind: Kind::Embassy as u8, level: 1 });
    let mere = db.call(|db| rules::found_alliance(db, ada, "Keepers", "MERE")).unwrap().id;
    assert_eq!(db.call(|db| rules::join_alliance(db, bryn, mere)), Ok(true));
    later(&mut db, 3);
    db.call(|db| rules::say(db, bryn, true, "Within the walls")).unwrap();
    let line = Table::<AllianceChat>::by(&db, 0, mere)[0].id;

    // Cato is of no alliance; Ada of this one.
    assert_eq!(db.call(|db| rules::report_line(db, cato, line, true)), Err(Refusal::NotAllied));
    assert_eq!(db.call(|db| rules::report_line(db, ada, line, false)), Err(Refusal::NoSuchLine), "not a line of the realm's chat");
    let kept = db.call(|db| rules::report_line(db, ada, line, true)).unwrap();
    assert_eq!((kept.alliance, kept.speaker, kept.around.as_str()), (mere, bryn, "> Bryn: Within the walls"));

    // Taken away: its words gone, its reports let go, and none made of it again.
    assert_eq!(rules::take_away(&mut db, line, true), Ok(()));
    assert_eq!(Table::<AllianceChat>::get(&db, line).unwrap().words, "");
    assert!(Table::<Complaint>::all(&db).is_empty());
    assert_eq!(rules::take_away(&mut db, line, true), Err(Refusal::TakenAwayAlready));
    assert_eq!(db.call(|db| rules::report_line(db, ada, line, true)), Err(Refusal::TakenAwayAlready));
}

#[test]
fn a_line_taken_away_stands_where_it_was_without_its_words() {
    let (mut db, players) = realm_of(&["Ada", "Bryn", "Cato"]);
    let (ada, bryn, cato) = (players[0], players[1], players[2]);
    say(&mut db, ada, "Before");
    let rude = say(&mut db, bryn, "Something rude");
    say(&mut db, ada, "After");
    db.call(|db| rules::report_line(db, cato, rude, false)).unwrap();
    let other = say(&mut db, ada, "Fine words");
    db.call(|db| rules::report_line(db, cato, other, false)).unwrap();

    assert_eq!(rules::take_away(&mut db, rude, false), Ok(()));
    let said = Table::<RealmChat>::get(&db, rude).unwrap();
    assert_eq!((said.name.as_str(), said.words.as_str()), ("Bryn", ""));
    // Only its reports are let go, and a report about it says so.
    let waiting = Table::<Complaint>::all(&db);
    assert_eq!(waiting.iter().map(|complaint| complaint.line).collect::<Vec<_>>(), vec![other]);
    let near = say(&mut db, ada, "Near it");
    let about = db.call(|db| rules::report_line(db, bryn, near, false)).unwrap();
    assert!(about.around.contains("  Bryn: (taken away)"), "{}", about.around);
    assert_eq!(rules::take_away(&mut db, 999, false), Err(Refusal::NoSuchLine));
}

#[test]
fn a_barred_player_says_nothing_until_the_bar_ends() {
    let (mut db, players) = realm_of(&["Ada", "Bryn"]);
    let (ada, bryn) = (players[0], players[1]);
    let until = rules::bar(&mut db, bryn, 2).unwrap();
    assert_eq!(until, db.clock + 7_200);
    assert_eq!(rules::barred_for(&db, bryn), Some(7_200));
    later(&mut db, 3);
    let refusal = db.call(|db| rules::say(db, bryn, false, "Hello?")).unwrap_err();
    assert_eq!((refusal.clone(), refusal.to_string()), (Refusal::Barred(7_197), "You may not speak for another 1 hour 59 minutes.".to_string()));
    assert_eq!(db.call(|db| rules::say(db, bryn, true, "Hello, allies?")), Err(Refusal::Barred(7_197)), "nor within an alliance");
    // Others speak as ever.
    assert_eq!(db.call(|db| rules::say(db, ada, false, "Hello")), Ok(()));

    // A bar ends in its time; another may be lifted.
    later(&mut db, 7_200);
    assert_eq!(rules::barred_for(&db, bryn), None);
    assert_eq!(db.call(|db| rules::say(db, bryn, false, "Back")), Ok(()));
    rules::bar(&mut db, bryn, 24).unwrap();
    assert!(rules::barred_for(&db, bryn).is_some());
    rules::bar(&mut db, bryn, 0).unwrap();
    assert_eq!(rules::barred_for(&db, bryn), None);
    later(&mut db, 3);
    assert_eq!(db.call(|db| rules::say(db, bryn, false, "Free")), Ok(()));

    assert_eq!(rules::bar(&mut db, 999, 2), Err(Refusal::NoSuchPlayer));
    let refusal = rules::bar(&mut db, bryn, rules::LONGEST_BAR_HOURS + 1).unwrap_err();
    assert_eq!(refusal.to_string(), "A player is barred for 8760 hours at most.");
}

#[test]
fn a_player_forgotten_leaves_their_name_behind() {
    let (mut db, players) = realm_of(&["Ada", "Bryn", "Cato"]);
    let (ada, bryn, cato) = (players[0], players[1], players[2]);
    let rude = say(&mut db, bryn, "Something rude");
    say(&mut db, ada, "Steady, Bryn");
    later(&mut db, 3);
    db.call(|db| rules::send_letter(db, bryn, ada, "A word, Ada")).unwrap();
    db.call(|db| rules::report_line(db, cato, rude, false)).unwrap();
    let theirs = say(&mut db, cato, "Mine");
    db.call(|db| rules::report_line(db, bryn, theirs, false)).unwrap();

    let name = rules::forget(&mut db, bryn).unwrap();
    assert_eq!(name, format!("Forgotten #{bryn}"));
    let row = Table::<Player>::get(&db, bryn).unwrap();
    assert_eq!((row.name.clone(), row.name_key, row.online), (name.clone(), rules::name_key(&name), false));
    assert!(rules::name_refusal(&name).is_some(), "no player joins under such a name");
    assert_eq!(Table::<City>::by(&db, 0, bryn)[0].name, name);
    assert_eq!(Table::<RealmChat>::get(&db, rude).unwrap().name, name);
    let letters = Table::<Letter>::by(&db, 0, bryn);
    assert!(!letters.is_empty() && letters.iter().all(|letter| letter.name == name));
    // Their reports go with them; a report of their words names them so,
    // though the words others wrote of them stay theirs.
    let waiting = Table::<Complaint>::all(&db);
    assert_eq!(waiting.len(), 1);
    assert_eq!(waiting[0].around, format!("> {name}: Something rude\n  Ada: Steady, Bryn"));
    // Their name is free for another to take.
    assert!(!rules::name_taken(&db, "Bryn"));
    assert!(db.call(|db| rules::join(db, "Bryn")).is_ok());

    assert_eq!(rules::forget(&mut db, bryn), Err(Refusal::ForgottenAlready));
    assert_eq!(rules::forget(&mut db, 999), Err(Refusal::NoSuchPlayer));
}

#[test]
fn a_report_names_a_forgotten_speaker_after_their_alliances_tag() {
    let (mut db, players) = realm_of(&["Ada", "Bryn"]);
    let (ada, bryn) = (players[0], players[1]);
    let city = rules::city_of(&db, ada).unwrap();
    db.insert(Building { id: 0, city: city.id, kind: Kind::Embassy as u8, level: 1 });
    db.call(|db| rules::found_alliance(db, ada, "Keepers", "MERE")).unwrap();
    let line = say(&mut db, ada, "Ada speaks of Ada");
    let kept = db.call(|db| rules::report_line(db, bryn, line, false)).unwrap();
    assert_eq!(kept.around, "> [MERE] Ada: Ada speaks of Ada");
    let name = rules::forget(&mut db, ada).unwrap();
    // The speaker renamed, after their tag; their words as they were.
    assert_eq!(Table::<Complaint>::get(&db, kept.id).unwrap().around, format!("> [MERE] {name}: Ada speaks of Ada"));
}
