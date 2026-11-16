//! A neighbourhood of the realm played into for the trailer: a dozen
//! players who arrived together, their cities raised as far as the trailer
//! shows them, written as a client reads the realm (its row, the land's
//! chunks about them, its players, cities, places, sites, barrows and
//! cairns) when NULLMERE_TRAILER_ROWS names a file to write.
//!
//!     NULLMERE_TRAILER_ROWS=../Sources/NullmereTrailer/TrailerRows.json cargo test --test trailer_rows

use realm::hex::Hex;
use realm::land::{self, chunk_of, Ground};
use realm::rows::{Barrow, Cairn, City, Land, Place, Player, Realm, Site};
use realm::rules;
use realm::store::{Mem, Seconds, Table};
use std::collections::BTreeSet;
use std::fmt::Write;

const START: Seconds = 3_000_000;
const SEED: u64 = 7;
const RADIUS: u32 = 48;
/// How far about the heart of the neighbourhood the land is written.
const REACH: u32 = 26;
const NAMES: [&str; 12] = ["Ilsen", "Corwen", "Maud", "Tamsin", "Bryn", "Edda", "Halen", "Osric", "Wenna", "Aldo", "Sefa", "Rook"];
/// Each city's Keep, as the trailer shows them: one raised whole at the
/// heart, a few grown great, the rest at the steps between.
const KEEPS: [u32; 12] = [25, 18, 16, 14, 12, 11, 10, 9, 8, 6, 5, 3];

fn neighbourhood() -> Mem {
    let mut db = Mem::new(START, 5);
    rules::open(&mut db, SEED, 1, RADIUS);
    for name in NAMES {
        db.call(|db| rules::join(db, name)).unwrap();
    }
    // Set about the lake country's shore, as the trailer's shots stand
    // about the lake: each city moved from where joining founded it.
    let shore = shore(&db, REACH - 6);
    assert!(shore.len() >= NAMES.len(), "room on the shore for a dozen: {}", shore.len());
    let mut cities = Table::<City>::all(&db);
    cities.sort_by_key(|city| city.id);
    for ((city, keep), hex) in cities.into_iter().zip(KEEPS).zip(shore) {
        Table::<Place>::delete(&mut db, city.hex);
        db.insert(Place { hex: hex.packed(), kind: Place::CITY, id: city.id });
        db.update(City { keep, hex: hex.packed(), ..city });
    }
    db
}

/// Hexes of the lake's shore within `within` of its middle, a city's room
/// apart and spread about it: buildable ground beside its water, with
/// nothing standing there.
fn shore(db: &Mem, within: u32) -> Vec<Hex> {
    let taken: BTreeSet<u64> = Table::<Place>::all(db).iter().map(|place| place.hex).collect();
    let mut found: Vec<Hex> = Hex::new(0, 0)
        .within(within)
        .into_iter()
        .filter(|hex| {
            land::ground(SEED, RADIUS, *hex).is_buildable()
                && hex.neighbours().iter().any(|next| matches!(land::ground(SEED, RADIUS, *next), Ground::Deep | Ground::Shallows))
                && !taken.contains(&hex.packed())
        })
        .collect();
    // Round the lake, by the angle each stands at from its middle.
    found.sort_by(|a, b| {
        let (ax, ay) = a.centre();
        let (bx, by) = b.centre();
        ay.atan2(ax).partial_cmp(&by.atan2(bx)).unwrap().then(a.q.cmp(&b.q)).then(a.r.cmp(&b.r))
    });
    // Every one a city's room from those before it, then a dozen of them
    // evenly round.
    let mut spaced: Vec<Hex> = Vec::new();
    for hex in found {
        if spaced.iter().all(|other| other.distance(hex) >= 5) {
            spaced.push(hex);
        }
    }
    let count = spaced.len();
    (0..NAMES.len().min(count)).map(|index| spaced[index * count / NAMES.len().min(count)]).collect()
}

fn hex_bytes(bytes: &[u8]) -> String {
    bytes.iter().fold(String::new(), |mut out, byte| {
        let _ = write!(out, "{byte:02x}");
        out
    })
}

fn quoted(words: &str) -> String {
    format!("\"{}\"", words.replace('\\', "\\\\").replace('"', "\\\""))
}

/// The rows a client would read, as the JSON the trailer keeps: each table
/// a list of rows, each row its columns in order.
fn rows(db: &Mem) -> String {
    let mut cities = Table::<City>::all(db);
    cities.sort_by_key(|city| city.id);
    let heart = Hex::new(0, 0);
    let near = |packed: u64| Hex::unpacked(packed).distance(heart) <= REACH;
    let reach = REACH as i32;
    let chunks: BTreeSet<u64> = (-reach..=reach)
        .flat_map(|dq| (-reach..=reach).map(move |dr| Hex::new(heart.q + dq, heart.r + dr)))
        .filter(|hex| hex.distance(heart) <= REACH)
        .map(|hex| chunk_of(hex).0)
        .collect();
    let mut tables: Vec<(&str, Vec<String>)> = Vec::new();
    tables.push(("realm", Table::<Realm>::all(db).iter().map(|realm| {
        format!("[{},{},{},{},{},{},{}]", realm.id, realm.seed, realm.opened, realm.pace, realm.joining_minute, realm.joined_in_minute, realm.radius)
    }).collect()));
    tables.push(("land", Table::<Land>::all(db).iter().filter(|land| chunks.contains(&land.chunk)).map(|land| {
        format!("[{},{}]", land.chunk, quoted(&hex_bytes(&land.ground)))
    }).collect()));
    tables.push(("player", Table::<Player>::all(db).iter().map(|player| {
        format!("[{},{},{},{},{},{}]", player.id, player.name_key, quoted(&player.name), player.joined, player.online, player.seen)
    }).collect()));
    tables.push(("city", cities.iter().map(|city| {
        format!("[{},{},{},{},{},{},{},{},{}]", city.id, city.owner, city.hex, quoted(&city.name), city.keep, city.power, city.founded, city.builders, city.shield)
    }).collect()));
    tables.push(("place", Table::<Place>::all(db).iter().filter(|place| near(place.hex)).map(|place| {
        format!("[{},{},{}]", place.hex, place.kind, place.id)
    }).collect()));
    tables.push(("site", Table::<Site>::all(db).iter().filter(|site| near(site.hex)).map(|site| {
        format!("[{},{},{},{},{},{}]", site.id, site.hex, site.kind, site.level, site.left, site.gatherer)
    }).collect()));
    tables.push(("barrow", Table::<Barrow>::all(db).iter().filter(|barrow| near(barrow.hex)).map(|barrow| {
        format!("[{},{},{},{}]", barrow.id, barrow.hex, barrow.level, barrow.fighter)
    }).collect()));
    tables.push(("cairn", Table::<Cairn>::all(db).iter().filter(|cairn| near(cairn.hex)).map(|cairn| {
        format!("[{},{},{}]", cairn.id, cairn.hex, cairn.level)
    }).collect()));
    let body: Vec<String> = tables.into_iter().map(|(name, rows)| format!("\"{name}\": [\n  {}\n]", rows.join(",\n  "))).collect();
    format!("{{\n{}\n}}\n", body.join(",\n"))
}

#[test]
fn a_neighbourhood_for_the_trailer() {
    let db = neighbourhood();
    let mut cities = Table::<City>::all(&db);
    cities.sort_by_key(|city| city.id);
    assert_eq!(cities.len(), NAMES.len());
    assert_eq!(cities.iter().map(|city| city.keep).collect::<Vec<_>>(), KEEPS.to_vec());
    // About the lake: every city within reach of its middle.
    let heart = Hex::new(0, 0);
    let far = cities.iter().map(|city| Hex::unpacked(city.hex).distance(heart)).max().unwrap();
    let near = cities.iter().map(|city| Hex::unpacked(city.hex).distance(heart)).min().unwrap();
    eprintln!("TRAILER the dozen lie from {near} to {far} of the lake's middle");
    // With room about each for its town, all within the land written.
    assert!(far + 6 <= REACH, "the dozen live close together: {far}");
    let written = rows(&db);
    assert!(written.contains("\"land\": [\n  ["), "the land about them is written");
    assert!(written.contains("\"Ilsen\""));
    if let Ok(path) = std::env::var("NULLMERE_TRAILER_ROWS") {
        std::fs::write(&path, written).unwrap();
    }
}
