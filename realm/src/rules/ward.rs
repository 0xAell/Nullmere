//! An alliance's land: wardstones raised by its officers, each claiming
//! the ground about it once it stands.
//!
//! The first may stand on any clear ground; every one after it on land
//! the alliance holds already, so that its land grows outward as one.
//! Land another alliance holds is theirs: no wardstone of anyone else's
//! may stand on it, and where two claims meet the older keeps the
//! ground. An alliance may have one wardstone, and one more for every
//! five members, to twenty. Its members gather faster on its land. When
//! the alliance ends its wardstones fall.

use super::{asking, goods, member_of, officer, realm, set_goods, settle, Refusal};
use crate::catalog::{self, WARD_REACH};
use crate::hex::Hex;
use crate::land;
use crate::rows::{Alliance, Db, Place, Ward};
use crate::store::Table;

/// The alliance whose land a hex is, if any's: the one whose standing
/// wardstone within reach of it was raised first.
pub fn land_of(db: &impl Db, hex: Hex) -> Option<u64> {
    let now = db.now();
    Table::<Ward>::all(db).into_iter().filter(|ward| ward.stands_at <= now && Hex::unpacked(ward.hex).distance(hex) <= WARD_REACH).min_by_key(|ward| ward.id).map(|ward| ward.alliance)
}

/// Hundredths faster a player gathers at a hex: more on their alliance's
/// own land, nothing anywhere else.
pub fn gathering_on(db: &impl Db, player: u64, hex: Hex) -> u64 {
    match member_of(db, player) {
        Some(member) if land_of(db, hex) == Some(member.alliance) => catalog::WARD_GATHERING,
        _ => 0,
    }
}

/// An officer of an alliance raises a wardstone at a hex, paid for out
/// of their own city. It stands, and claims its land, after a while.
pub fn raise_ward(db: &mut impl Db, player: u64, to: Hex) -> Result<Ward, Refusal> {
    asking(db, player)?;
    let member = officer(db, player)?;
    let alliance = Table::<Alliance>::get(db, member.alliance).ok_or(Refusal::NotAllied)?;
    let realm = realm(db)?;
    let ours = Table::<Ward>::by(db, 0, alliance.id);
    let most = catalog::wards_for(alliance.members);
    if ours.len() as u32 >= most {
        return Err(Refusal::WardsAll(most));
    }
    let clear = to.length() <= realm.radius && land::ground(realm.seed, realm.radius, to).is_buildable() && Table::<Place>::get(db, to.packed()).is_none();
    if !clear {
        return Err(Refusal::NoWardThere);
    }
    match land_of(db, to) {
        Some(other) if other != alliance.id => {
            let theirs = Table::<Alliance>::get(db, other).map(|other| format!("[{}] {}", other.tag, other.name)).unwrap_or_default();
            return Err(Refusal::OthersLand(theirs));
        }
        None if !ours.is_empty() => return Err(Refusal::OffOwnLand),
        _ => {}
    }
    let city = super::city_of(db, player)?;
    let mut stock = settle(db, city.id)?;
    let have = goods(&stock);
    if !have.covers(catalog::WARD_COST) {
        return Err(Refusal::CannotAfford(have.short_of(catalog::WARD_COST)));
    }
    set_goods(&mut stock, have.minus(catalog::WARD_COST));
    db.update(stock);
    let stands_at = db.now() + catalog::paced(catalog::WARD_SECONDS, realm.pace).max(1);
    let ward = db.insert(Ward { id: 0, alliance: alliance.id, hex: to.packed(), raised_by: player, stands_at });
    db.insert(Place { hex: ward.hex, kind: Place::WARD, id: ward.id });
    Ok(ward)
}

/// An officer takes down one of their alliance's wardstones, and the land
/// it claimed is no longer the alliance's for it. Nothing is given back.
pub fn raze_ward(db: &mut impl Db, player: u64, ward: u64) -> Result<(), Refusal> {
    asking(db, player)?;
    let member = officer(db, player)?;
    let ward = Table::<Ward>::get(db, ward).filter(|ward| ward.alliance == member.alliance).ok_or(Refusal::NoSuchWard)?;
    fell(db, &ward);
    Ok(())
}

fn fell(db: &mut impl Db, ward: &Ward) {
    if Table::<Place>::get(db, ward.hex).is_some_and(|place| place.kind == Place::WARD && place.id == ward.id) {
        Table::<Place>::delete(db, ward.hex);
    }
    Table::<Ward>::delete(db, ward.id);
}

/// An alliance has ended: its wardstones fall with it.
pub(super) fn fell_wards(db: &mut impl Db, alliance: u64) {
    for ward in Table::<Ward>::by(db, 0, alliance) {
        fell(db, &ward);
    }
}
