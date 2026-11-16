//! The Forge: gear for commanders, made from what the barrows of the
//! Unquiet yield. Clearing a barrow yields materials, one for each of its
//! levels: iron, leather and bone, and from the tenth level silver too.
//! At the Forge they are worked, with goods, into gear: a weapon, a helm,
//! armour and boots, each in three grades, the better ones at a higher
//! Forge. A commander wears one piece in each place, and what they wear
//! adds to the army they lead, the city they keep, and the rally they
//! lead, as their way of war and their talents do.

use super::{asking, building_of, city_of, give, goods, held, set_goods, settle, take, Refusal};
use crate::catalog::{self, Building as Kind, Item, Leading, Piece};
use crate::rows::{Commander, Db, Gear, Pattern, Prisoner};
use crate::store::Table;

/// Writes what the Forge makes out as rows, for clients to show, as the
/// realm opens.
pub fn write_patterns(db: &mut impl Db) {
    for piece in Piece::ALL {
        let (materials, cost) = piece.cost();
        db.insert(Pattern {
            piece: piece as u64,
            name: piece.name().to_string(),
            slot: piece.slot() as u8,
            grade: piece.grade() as u8,
            words: piece.words(),
            iron: materials[0],
            leather: materials[1],
            bone: materials[2],
            silver: materials[3],
            grain: cost.grain,
            timber: cost.timber,
            stone: cost.stone,
            moonsalt: cost.moonsalt,
            forge_level: piece.forge_level(),
        });
    }
}

/// Things named in a list: "4 iron", "4 iron and 2 leather", "4 iron,
/// 2 leather and 1 bone".
fn listed(parts: &[String]) -> String {
    match parts {
        [] => String::new(),
        [one] => one.clone(),
        [rest @ .., last] => format!("{} and {last}", rest.join(", ")),
    }
}

/// So many of each material, in words: "3 iron and 1 bone".
pub fn materials_words(counts: [u64; 4]) -> String {
    let parts: Vec<String> = Item::MATERIALS.iter().zip(counts).filter(|(_, count)| *count > 0).map(|(item, count)| format!("{count} {}", item.name().to_lowercase())).collect();
    listed(&parts)
}

/// A barrow has been cleared: its materials go to the player who cleared
/// it. What it yields is fixed by the barrow itself, not drawn by chance.
/// The materials, as so many of each.
pub(super) fn yielded(db: &mut impl Db, player: u64, level: u32, barrow: u64) -> [u64; 4] {
    let mut seed = barrow.wrapping_mul(0x9E37_79B9_7F4A_7C15) | 1;
    let counts = catalog::spoils_of(level, || {
        seed = seed.wrapping_mul(6_364_136_223_846_793_005).wrapping_add(1_442_695_040_888_963_407);
        seed >> 33
    });
    for (item, count) in Item::MATERIALS.iter().zip(counts) {
        if count > 0 {
            give(db, player, *item, count);
        }
    }
    counts
}

/// A player has a piece made at their city's Forge: paid for in
/// materials and goods at once, theirs from that moment.
pub fn forge(db: &mut impl Db, player: u64, piece: u8) -> Result<Gear, Refusal> {
    asking(db, player)?;
    let city = city_of(db, player)?;
    let piece = Piece::of(piece).ok_or(Refusal::NoSuchPiece)?;
    let level = building_of(db, city.id, Kind::Forge).map(|forge| forge.level).unwrap_or(0);
    if level < piece.forge_level() {
        return Err(Refusal::NeedsOther(Kind::Forge, piece.forge_level()));
    }
    let (materials, cost) = piece.cost();
    let mut short = [0u64; 4];
    for (index, item) in Item::MATERIALS.iter().enumerate() {
        short[index] = materials[index].saturating_sub(held(db, player, *item));
    }
    if short.iter().any(|count| *count > 0) {
        return Err(Refusal::ShortOfMaterials(materials_words(short)));
    }
    let mut stock = settle(db, city.id)?;
    let have = goods(&stock);
    if !have.covers(cost) {
        return Err(Refusal::CannotAfford(have.short_of(cost)));
    }
    set_goods(&mut stock, have.minus(cost));
    db.update(stock);
    for (item, count) in Item::MATERIALS.iter().zip(materials) {
        if count > 0 {
            take(db, player, *item, count);
        }
    }
    Ok(db.insert(Gear { id: 0, owner: player, piece: piece as u8, commander: 0 }))
}

/// A player has one of their commanders wear a piece of their gear; what
/// the commander wore in that place comes off.
pub fn equip(db: &mut impl Db, player: u64, gear: u64, commander: u64) -> Result<Gear, Refusal> {
    asking(db, player)?;
    let mut row = Table::<Gear>::get(db, gear).filter(|row| row.owner == player).ok_or(Refusal::NoSuchGear)?;
    let wearer = Table::<Commander>::get(db, commander).filter(|row| row.owner == player).ok_or(Refusal::NoSuchCommander)?;
    if Table::<Prisoner>::get(db, commander).is_some() {
        return Err(Refusal::HeldPrisoner(wearer.name));
    }
    let piece = Piece::of(row.piece).ok_or(Refusal::NoSuchPiece)?;
    for mut other in Table::<Gear>::by(db, 1, commander) {
        if other.id != row.id && Piece::of(other.piece).map(|worn| worn.slot()) == Some(piece.slot()) {
            other.commander = 0;
            db.update(other);
        }
    }
    row.commander = commander;
    db.update(row.clone());
    Ok(row)
}

/// A player takes a piece of their gear off whoever wears it.
pub fn unequip(db: &mut impl Db, player: u64, gear: u64) -> Result<(), Refusal> {
    asking(db, player)?;
    let mut row = Table::<Gear>::get(db, gear).filter(|row| row.owner == player).ok_or(Refusal::NoSuchGear)?;
    row.commander = 0;
    db.update(row);
    Ok(())
}

/// What the gear a commander wears adds.
pub fn worn(db: &impl Db, commander: u64) -> Leading {
    Table::<Gear>::by(db, 1, commander).into_iter().filter_map(|gear| Piece::of(gear.piece)).fold(Leading::default(), |all, piece| all.plus(piece.leading()))
}
