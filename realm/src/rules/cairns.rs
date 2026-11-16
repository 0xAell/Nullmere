//! Cairns the old folk left on the land, for scouts to find.
//!
//! They stand on open ground with nothing on it or beside it, one to
//! about every hundred and fifty hexes, each of a level from one to five,
//! the higher the nearer the lake. A player sends scouts to one from a
//! city with a Scout Camp. The first time their scouts come to a cairn
//! they find what was laid in it: grain, timber and stone by its level,
//! moonsalt too from the fourth, and a haste from the third, all of it
//! sent into their city at once and told in a report. Each player finds
//! each cairn once; it stays for everyone else to find after them.

use super::{city_of, give, goods, report, set_goods, settle, Refusal};
use crate::catalog::{Building as Kind, Goods, Item};
use crate::hex::Hex;
use crate::land::{self, Ground};
use crate::rows::{Cairn, Db, Find, March, Place, Report};
use crate::store::Table;

/// Hexes of the realm to each cairn on it.
pub const HEXES_A_CAIRN: u32 = 150;
pub const TOP_CAIRN: u32 = 5;

/// What a cairn of a level holds: a thousand of each of grain, timber
/// and stone times the level and the next, five hundred moonsalt a level
/// past the third, and a haste from the third level, an hour's at the top.
pub fn hoard_of(level: u32) -> (Goods, Option<Item>) {
    let each = 1_000 * level as u64 * (level as u64 + 1);
    let moonsalt = 500 * level.saturating_sub(3) as u64;
    let haste = match level {
        0..=2 => None,
        3 | 4 => Some(Item::Haste5),
        _ => Some(Item::Haste60),
    };
    (Goods::of(each, each, each, moonsalt), haste)
}

/// The cairn at a hex, if one stands there.
pub fn cairn_at(db: &impl Db, hex: Hex) -> Option<Cairn> {
    match Table::<Place>::get(db, hex.packed()) {
        Some(place) if place.kind == Place::CAIRN => Table::<Cairn>::get(db, place.id),
        _ => None,
    }
}

/// Whether a player's scouts have found what a cairn held.
pub fn has_found(db: &impl Db, player: u64, cairn: u64) -> bool {
    Table::<Find>::get(db, Find::key(player, cairn)).is_some()
}

/// A number drawn from the realm's seed for the nth of something: the
/// same for the same seed, so cairns stand where they stand without
/// drawing on the realm's chance.
fn drawn(seed: u64, n: u64) -> u64 {
    let mut z = (seed ^ 0xCA12_4E5D_0F01_DF0E).wrapping_add(n.wrapping_mul(0x9E37_79B9_7F4A_7C15));
    z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    z ^ (z >> 31)
}

/// Sets the nth cairn somewhere on the land, on open ground with nothing
/// on it or beside it; the nearer the lake, the higher its level. False
/// if no such hex was found for it.
fn place_cairn(db: &mut impl Db, nth: u64) -> bool {
    let Ok(realm) = super::realm(db) else { return false };
    let span = 2 * realm.radius as u64 + 1;
    for attempt in 0..60 {
        let draw = |part: u64| drawn(realm.seed, (nth * 60 + attempt) * 3 + part);
        let (a, b, c) = (draw(0), draw(1), draw(2));
        let hex = Hex::new((a % span) as i32 - realm.radius as i32, (b % span) as i32 - realm.radius as i32);
        if hex.length() > realm.radius || !matches!(land::ground(realm.seed, realm.radius, hex), Ground::Plain | Ground::Wood | Ground::Heath | Ground::Salt) {
            continue;
        }
        if hex.within(1).iter().any(|near| Table::<Place>::get(db, near.packed()).is_some()) {
            continue;
        }
        // One to three by how near the lake it stands, and by chance up
        // to two more.
        let nearer = 1 + (realm.radius - hex.length()) * 3 / realm.radius.max(1);
        let level = (nearer + (c % 3) as u32).clamp(1, TOP_CAIRN);
        let cairn = db.insert(Cairn { id: 0, hex: hex.packed(), level });
        db.insert(Place { hex: hex.packed(), kind: Place::CAIRN, id: cairn.id });
        return true;
    }
    false
}

/// Scatters the realm's cairns over its land as it opens.
pub fn scatter_cairns(db: &mut impl Db) {
    let Ok(realm) = super::realm(db) else { return };
    let hexes = 1 + 3 * realm.radius * (realm.radius + 1);
    for nth in 0..(hexes / HEXES_A_CAIRN) as u64 {
        place_cairn(db, nth);
    }
}

/// Whether a player may send scouts to the cairn at a hex: one stands
/// there, their scouts have not found it and are not on their way to it,
/// and their city has a Scout Camp.
pub(super) fn may_explore(db: &impl Db, player: u64, to: Hex, from: u64) -> Result<Cairn, Refusal> {
    let cairn = cairn_at(db, to).ok_or(Refusal::NoCairnThere)?;
    if has_found(db, player, cairn.id) {
        return Err(Refusal::FoundAlready);
    }
    let going = Table::<March>::by(db, 0, player).iter().any(|march| march.kind == March::EXPLORE && march.target == cairn.id && march.state == March::GOING);
    if going {
        return Err(Refusal::ScoutsOnTheWay);
    }
    if super::building_of(db, from, Kind::ScoutCamp).is_none_or(|camp| camp.level < 1) {
        return Err(Refusal::NeedsOther(Kind::ScoutCamp, 1));
    }
    Ok(cairn)
}

/// Scouts have come to a cairn: the first time their player's scouts
/// have, they find what it held, sent into the city at once and told.
pub(super) fn explored(db: &mut impl Db, march: &March) {
    let Some(cairn) = Table::<Cairn>::get(db, march.target) else { return };
    if has_found(db, march.owner, cairn.id) {
        return;
    }
    let now = db.now();
    db.insert(Find { id: Find::key(march.owner, cairn.id), player: march.owner, cairn: cairn.id, at: now });
    let (hoard, haste) = hoard_of(cairn.level);
    if let Ok(city) = city_of(db, march.owner) {
        if let Ok(mut stock) = settle(db, city.id) {
            let more = goods(&stock).plus(hoard);
            set_goods(&mut stock, more);
            db.update(stock);
        }
    }
    if let Some(item) = haste {
        give(db, march.owner, item, 1);
    }
    let mut words = format!("Your scouts found what the old folk laid in a cairn of level {}: {hoard}", cairn.level);
    match haste {
        Some(Item::Haste60) => words.push_str(", and an hour's haste"),
        Some(item) => words.push_str(&format!(", and a {}", item.name().to_lowercase())),
        None => {}
    }
    words.push_str(". It is in your city.");
    report(
        db,
        Report {
            id: 0,
            player: march.owner,
            at: now,
            kind: Report::CAIRN,
            hex: cairn.hex,
            won: true,
            foe: cairn.level as u64,
            rounds: 0,
            fought: march.soldiers,
            wounded: 0,
            dead: 0,
            stood: 0,
            fell: 0,
            grain: hoard.grain,
            timber: hoard.timber,
            stone: hoard.stone,
            moonsalt: hoard.moonsalt,
            words,
            read: false,
        },
    );
}
