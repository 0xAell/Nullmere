//! A neighbourhood of the realm played into for the trailer: a dozen
//! players who arrived together, their cities raised as far as the trailer
//! shows them, written as a client reads the realm (its row, the land's
//! chunks about them, its players, cities, places, sites, barrows and
//! cairns) when NULLMERE_TRAILER_ROWS names a file to write.
//!
//!     NULLMERE_TRAILER_ROWS=../Sources/NullmereTrailer/TrailerRows.json cargo test --test trailer_rows

use realm::hex::Hex;
use realm::land::chunk_of;
use realm::rows::{Barrow, Cairn, City, Land, Place, Player, Realm, Site};
use realm::rules;
use realm::store::{Mem, Seconds, Table};
use std::collections::BTreeSet;
use std::fmt::Write;

const START: Seconds = 3_000_000;
/// How far about the heart of the neighbourhood the land is written.
const REACH: u32 = 26;
const NAMES: [&str; 12] = ["Ilsen", "Corwen", "Maud", "Tamsin", "Bryn", "Edda", "Halen", "Osric", "Wenna", "Aldo", "Sefa", "Rook"];
/// Each city's Keep, as the trailer shows them: one raised whole at the
/// heart, a few grown great, the rest at the steps between.
const KEEPS: [u32; 12] = [25, 18, 16, 14, 12, 11, 10, 9, 8, 6, 5, 3];

fn neighbourhood() -> Mem {
    let mut db = Mem::new(START, 5);
    rules::open(&mut db, 7, 1, 48);
    for name in NAMES {
        db.call(|db| rules::join(db, name)).unwrap();
    }
    let mut cities = Table::<City>::all(&db);
    cities.sort_by_key(|city| city.id);
    for (city, keep) in cities.into_iter().zip(KEEPS) {
        db.update(City { keep, ..city });
    }
    db
}

/// The city nearest the middle of them all, about which the land is written.
fn heart(cities: &[City]) -> Hex {
    let hexes: Vec<Hex> = cities.iter().map(|city| Hex::unpacked(city.hex)).collect();
    let n = hexes.len() as i32;
    let middle = Hex::new(hexes.iter().map(|hex| hex.q).sum::<i32>() / n, hexes.iter().map(|hex| hex.r).sum::<i32>() / n);
    *hexes.iter().min_by_key(|hex| (hex.distance(middle), hex.q, hex.r)).unwrap()
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
    let heart = heart(&cities);
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
    // Arrived together, so neighbours: every city within reach of the one in their midst.
    let heart = heart(&cities);
    let far = cities.iter().map(|city| Hex::unpacked(city.hex).distance(heart)).max().unwrap();
    eprintln!("TRAILER the dozen lie within {far} of the one in their midst");
    // With room about each for its town, all within the land written.
    assert!(far + 6 <= REACH, "the dozen live close together: {far}");
    let written = rows(&db);
    assert!(written.contains("\"land\": [\n  ["), "the land about them is written");
    assert!(written.contains("\"Ilsen\""));
    if let Ok(path) = std::env::var("NULLMERE_TRAILER_ROWS") {
        std::fs::write(&path, written).unwrap();
    }
}
