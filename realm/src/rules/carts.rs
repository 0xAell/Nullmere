//! Carts of goods sent to an ally's city.
//!
//! A player loads carts at their Storehouse with goods for an ally: so
//! much in all as the Storehouse's level allows a load, taken from their
//! city at once. The carters keep a tenth of it for their trouble; the
//! rest is unloaded into the ally's city when the carts come to it, though
//! it overfill it, and both are told. No army goes with carts and none is
//! kept from marching by them: a city may have as many loads on the road
//! at once as it may send armies, and they go on whatever is asked of
//! them. If the city they were sent to is gone when they come to it, or is
//! no longer an ally's, what they carry comes back to whoever sent it.

use super::{allied, asking, building_of, city_at, city_of, gates_barred_to, goods, realm, report, set_goods, settle, Refusal, TIMER_MARCH};
use crate::catalog::{self, Building as Kind, Goods};
use crate::hex::{self, Hex};
use crate::land;
use crate::rows::{City, Db, Haul, March, Player, Report};
use crate::store::{Seconds, Table};

/// The hundredths of a load the carters keep.
pub const CARTERS_DUE: u64 = 10;
/// Seconds a load of carts takes over each hex of its way, at the written
/// pace: as slow as the slowest soldiers.
pub const CART_PACE: Seconds = 60;

/// The most goods, all four together, one load of carts takes, by the
/// Storehouse's level: 20,000 with none built, 20,000 more a level.
pub fn cartload(storehouse: u32) -> u64 {
    20_000 + 20_000 * storehouse.min(catalog::TOP_LEVEL) as u64
}

/// What the carters keep of a load, and what is unloaded at its end.
pub fn carters_due(load: Goods) -> (Goods, Goods) {
    let due = Goods::from_parts(load.parts().map(|part| part * CARTERS_DUE / 100));
    (due, load.minus(due))
}

fn name_of(db: &impl Db, player: u64) -> String {
    Table::<Player>::get(db, player).map(|row| row.name).unwrap_or_else(|| "Someone".into())
}

/// A city's loads of carts on the road.
pub fn carts_out(db: &impl Db, city: u64) -> Vec<March> {
    Table::<March>::by(db, 1, city).into_iter().filter(|march| march.kind == March::CARTS).collect()
}

/// A player sends a load of goods to the city of an ally at a hex. The
/// carts as they set out.
pub fn send_goods(db: &mut impl Db, player: u64, to: Hex, load: Goods) -> Result<March, Refusal> {
    asking(db, player)?;
    let city = city_of(db, player)?;
    let ally = city_at(db, to).ok_or(Refusal::NoCityForCarts)?;
    if ally.owner == player {
        return Err(Refusal::OwnCity);
    }
    if !allied(db, player, ally.owner) {
        return Err(Refusal::CartsToAlliesOnly);
    }
    let all: u64 = load.parts().iter().sum();
    if all == 0 {
        return Err(Refusal::NothingAsked);
    }
    let storehouse = building_of(db, city.id, Kind::Storehouse).map(|building| building.level).unwrap_or(0);
    let most = cartload(storehouse);
    if all > most {
        return Err(Refusal::TooMuchForCarts(most));
    }
    let roads = catalog::marches(city.keep);
    if carts_out(db, city.id).len() as u32 >= roads {
        return Err(Refusal::CartsOnTheRoad(roads));
    }
    let realm = realm(db)?;
    let barred = gates_barred_to(db, player);
    let way = land::way_by(realm.seed, realm.radius, Hex::unpacked(city.hex), to, |hex| barred.contains(&hex)).ok_or(Refusal::NoWay)?;
    let mut stock = settle(db, city.id)?;
    let have = goods(&stock);
    if !have.covers(load) {
        return Err(Refusal::CannotAfford(have.short_of(load)));
    }
    set_goods(&mut stock, have.minus(load));
    db.update(stock);

    let now = db.now();
    let arrives = now + catalog::paced(CART_PACE * (way.len() as Seconds - 1).max(1), realm.pace).max(1);
    let mut carts = db.insert(March {
        id: 0,
        owner: player,
        city: city.id,
        kind: March::CARTS,
        state: March::GOING,
        from: city.hex,
        to: to.packed(),
        target: ally.id,
        departed: now,
        arrives,
        soldiers: 0,
        route: hex::encode(&way),
        timer: 0,
        leader: 0,
    });
    carts.timer = db.after(arrives, TIMER_MARCH, carts.id);
    db.update(carts.clone());
    let (_, unloaded) = carters_due(load);
    db.insert(Haul { march: carts.id, owner: player, grain: unloaded.grain, timber: unloaded.timber, stone: unloaded.stone, moonsalt: unloaded.moonsalt });
    Ok(carts)
}

/// A load of carts has come to the city it was sent to: unloaded there
/// if it is still an ally's, else what it carries goes back to whoever
/// sent it. Either way the carts are done, and both are told.
pub(super) fn unloaded(db: &mut impl Db, carts: &March) {
    let carried = Table::<Haul>::get(db, carts.id).map(|haul| Goods::of(haul.grain, haul.timber, haul.stone, haul.moonsalt)).unwrap_or(Goods::NONE);
    Table::<Haul>::delete(db, carts.id);
    Table::<March>::delete(db, carts.id);
    let sender = name_of(db, carts.owner);
    let ally = Table::<City>::get(db, carts.target).filter(|city| allied(db, carts.owner, city.owner));
    let (into, words) = match &ally {
        Some(city) => (city.id, format!("Carts from {sender}'s city were unloaded into yours: {carried}.")),
        None => (carts.city, format!("The city your carts were sent to is no ally's now. What they carried is back in your city: {carried}.")),
    };
    if let Ok(mut stock) = settle(db, into) {
        let more = goods(&stock).plus(carried);
        set_goods(&mut stock, more);
        db.update(stock);
    }
    let now = db.now();
    let tell = |player: u64, hex: u64, words: String| Report {
        id: 0,
        player,
        at: now,
        kind: Report::CARTS,
        hex,
        won: true,
        foe: 0,
        rounds: 0,
        fought: 0,
        wounded: 0,
        dead: 0,
        stood: 0,
        fell: 0,
        grain: carried.grain,
        timber: carried.timber,
        stone: carried.stone,
        moonsalt: carried.moonsalt,
        words,
        read: false,
    };
    match ally {
        Some(city) => {
            let mut told = tell(city.owner, city.hex, words);
            told.foe = carts.owner;
            report(db, told);
            let mut back = tell(carts.owner, city.hex, format!("Your carts unloaded {carried} into {}'s city.", name_of(db, city.owner)));
            back.foe = city.owner;
            report(db, back);
        }
        None => {
            report(db, tell(carts.owner, carts.to, words));
        }
    }
}
