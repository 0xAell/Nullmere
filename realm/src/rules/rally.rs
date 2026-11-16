//! Rallies: allies' armies against a barrow too strong for one of them,
//! or against another player's city.
//!
//! A member of an alliance calls a rally against a barrow up to three
//! levels above what they may attack alone, or against a city they may
//! attack, and their army musters in their city. For as long as the
//! muster lasts allies join with armies of their own, each mustering in
//! its own city. When it ends they all set out, each from where it is;
//! those that reach the barrow or the walls first wait for the last; then
//! they fight as one, under the caller's commander. A rally no one joins
//! stands down. A rally against a barrow takes each army's energy, as a
//! hunt does; one against a city takes none, but every army in it gives
//! up its own city's peace, and the city's owner is warned as the rally
//! is called and again as it sets out.

use super::{
    allied, asking, barrow_at, city_at, dispatch, fought_together, gate_at, home, hunt_of, may_attack, may_raze, may_storm, member_of, realm, release, report,
    shown_name, spend_energy, squads, stormed_gate, stormed_together, stormed_ward, travel, turn_home, ward_at, warn, way_back, Asked, Refusal, TIMER_MARCH,
};
use crate::catalog;
use crate::hex::{self, Hex};
use crate::rows::{Barrow, City, Db, Gate, Haul, March, Muster, Player, Rally, Report, Ward};
use crate::store::Table;

/// What a rally goes against: a barrow, another player's city, a gate of
/// the ridge, or another alliance's wardstone (a rally's row names the
/// barrow or the city, and neither for a gate or a wardstone, which stands
/// at its hex).
pub(super) enum Aim {
    Barrow(Barrow),
    City(City),
    Gate(Gate),
    Ward(Ward),
}

/// The rally a player has an army in, if they have.
fn rally_with(db: &impl Db, player: u64) -> Option<Rally> {
    let march = Table::<March>::by(db, 0, player).into_iter().find(|march| march.kind == March::RALLY)?;
    Table::<Rally>::get(db, Table::<Muster>::get(db, march.id)?.rally)
}

/// A rally's armies, its caller's first.
fn armies(db: &impl Db, rally: &Rally) -> Vec<March> {
    let mut marches: Vec<March> = Table::<Muster>::by(db, 0, rally.id).into_iter().filter_map(|muster| Table::<March>::get(db, muster.march)).collect();
    marches.sort_by_key(|march| (march.owner != rally.caller, march.id));
    marches
}

/// Whether a player may send an army to a rally against what stands at a
/// hex: a barrow no one is fighting, with the energy for it; or a city
/// they may attack. (Whether there is a rally for it to go to is its
/// caller's business and its joiners': see `call_rally` and
/// `join_rally`.)
pub(super) fn may_go(db: &impl Db, player: u64, to: Hex) -> Result<Aim, Refusal> {
    if city_at(db, to).is_some() {
        return may_attack(db, player, to).map(Aim::City);
    }
    if let Some(gate) = gate_at(db, to) {
        may_storm(db, player, &gate)?;
        return Ok(Aim::Gate(gate));
    }
    if let Some(ward) = ward_at(db, to) {
        may_raze(db, player, &ward)?;
        return Ok(Aim::Ward(ward));
    }
    let barrow = barrow_at(db, to).ok_or(Refusal::NothingToFight)?;
    if barrow.fighter != 0 {
        return Err(Refusal::BarrowTaken);
    }
    let hunt = hunt_of(db, player);
    if hunt.energy < catalog::ENERGY_A_HUNT {
        return Err(Refusal::NoEnergy(hunt.energy));
    }
    Ok(Aim::Barrow(barrow))
}

/// A player's name as their reports give it.
fn named(db: &impl Db, player: u64) -> String {
    Table::<Player>::get(db, player).map(|row| row.name).unwrap_or_else(|| "Someone".into())
}

/// A report to one player about a rally, with nothing fought.
fn told(db: &mut impl Db, player: u64, kind: u8, rally: &Rally, foe: u64, words: String) {
    let at = db.now();
    report(
        db,
        Report {
            id: 0,
            player,
            at,
            kind,
            hex: rally.hex,
            won: false,
            foe,
            rounds: 0,
            fought: 0,
            wounded: 0,
            dead: 0,
            stood: 0,
            fell: 0,
            grain: 0,
            timber: 0,
            stone: 0,
            moonsalt: 0,
            words,
            read: false,
        },
    );
}

/// Holds an army just sent in its city until its rally sets out.
fn hold(db: &mut impl Db, mut march: March, rally: &Rally) {
    db.cancel(march.timer);
    march.state = March::MUSTERING;
    march.departed = db.now();
    march.arrives = rally.sets_out;
    march.timer = db.after(rally.sets_out, TIMER_MARCH, march.id);
    db.insert(Muster { march: march.id, rally: rally.id, player: march.owner, arrived: false });
    db.update(march);
}

/// A member of an alliance calls a rally against the barrow or the city
/// at a hex, with an army of their own: it musters in their city until
/// the rally sets out.
pub fn call_rally(db: &mut impl Db, player: u64, to: Hex, asked: &[Asked], leader: u64) -> Result<Rally, Refusal> {
    asking(db, player)?;
    let member = member_of(db, player).ok_or(Refusal::NotAllied)?;
    let (barrow, city, level) = match (city_at(db, to), gate_at(db, to)) {
        (Some(_), _) => {
            let city = may_attack(db, player, to)?;
            (0, city.id, city.keep)
        }
        (None, Some(gate)) => {
            may_storm(db, player, &gate)?;
            (0, 0, 0)
        }
        (None, None) if ward_at(db, to).is_some() => {
            let ward = ward_at(db, to).ok_or(Refusal::NothingToFight)?;
            may_raze(db, player, &ward)?;
            (0, 0, 0)
        }
        (None, None) => {
            let barrow = barrow_at(db, to).ok_or(Refusal::NothingToFight)?;
            let reach = hunt_of(db, player).cleared + 1 + catalog::RALLY_REACH;
            if barrow.level > reach {
                return Err(Refusal::RallyTooStrong(reach));
            }
            (barrow.id, 0, barrow.level)
        }
    };
    if rally_with(db, player).is_some() {
        return Err(Refusal::AlreadyRallying);
    }
    if Table::<Rally>::by(db, 0, member.alliance).iter().any(|rally| (barrow != 0 && rally.barrow == barrow) || (city != 0 && rally.city == city) || rally.hex == to.packed()) {
        return Err(Refusal::RallyCalled);
    }
    let march = dispatch(db, player, to, March::RALLY, asked, leader)?;
    let pace = realm(db)?.pace;
    let name = Table::<Player>::get(db, player).map(|row| shown_name(db, &row)).unwrap_or_default();
    let rally = db.insert(Rally {
        id: 0,
        alliance: member.alliance,
        caller: player,
        name,
        barrow,
        city,
        hex: to.packed(),
        level,
        sets_out: db.now() + catalog::paced(catalog::RALLY_MUSTER, pace).max(1),
        state: Rally::MUSTERING,
        armies: 1,
        soldiers: march.soldiers,
    });
    let soldiers = march.soldiers;
    hold(db, march, &rally);
    if let Some(target) = Table::<City>::get(db, city) {
        let words = format!("{} has called a rally against your city. Its armies set out in {}.", rally.name, catalog::spoken(rally.sets_out - db.now()));
        warn(db, &target, player, soldiers, words);
    }
    Ok(rally)
}

/// A member joins a rally of their alliance that is still mustering,
/// with an army of their own, which musters in their city.
pub fn join_rally(db: &mut impl Db, player: u64, rally: u64, asked: &[Asked], leader: u64) -> Result<Rally, Refusal> {
    asking(db, player)?;
    let member = member_of(db, player).ok_or(Refusal::NotAllied)?;
    let mut rally = Table::<Rally>::get(db, rally).filter(|rally| rally.alliance == member.alliance).ok_or(Refusal::NoSuchRally)?;
    if rally.state != Rally::MUSTERING {
        return Err(Refusal::RallySetOut);
    }
    if rally_with(db, player).is_some() {
        return Err(Refusal::AlreadyRallying);
    }
    if rally.armies >= catalog::RALLY_ARMIES {
        return Err(Refusal::RallyFull);
    }
    let march = dispatch(db, player, Hex::unpacked(rally.hex), March::RALLY, asked, leader)?;
    rally.armies += 1;
    rally.soldiers += march.soldiers;
    db.update(rally.clone());
    hold(db, march, &rally);
    Ok(rally)
}

/// Whether an army of a rally took energy to send: one against a barrow
/// did, one against a city or a gate did not. Asked of the rally where
/// there is one, and of what stands where it was going where there is not.
fn took_energy(db: &impl Db, rally: Option<&Rally>, march: &March) -> bool {
    match rally {
        Some(rally) => rally.barrow != 0,
        None => city_at(db, Hex::unpacked(march.to)).is_none() && gate_at(db, Hex::unpacked(march.to)).is_none(),
    }
}

/// An army leaves its rally before anything has come of it: its soldiers
/// stand ready in their city again, and any energy it took comes back.
fn dismiss(db: &mut impl Db, march: &March, refund: bool) {
    db.cancel(march.timer);
    Table::<Muster>::delete(db, march.id);
    if refund {
        spend_energy(db, march.owner, true);
    }
    home(db, march);
}

/// A rally comes to nothing while it musters: every army stands down.
fn disband(db: &mut impl Db, rally: &Rally) {
    for march in armies(db, rally) {
        dismiss(db, &march, rally.barrow != 0);
    }
    Table::<Rally>::delete(db, rally.id);
}

/// A mustering army is called home by its owner. If it is the caller's,
/// the rally is off for everyone.
pub(super) fn stand_down(db: &mut impl Db, march: &March) {
    let rally = Table::<Muster>::get(db, march.id).and_then(|muster| Table::<Rally>::get(db, muster.rally));
    let refund = took_energy(db, rally.as_ref(), march);
    match rally {
        Some(rally) if rally.caller == march.owner => disband(db, &rally),
        Some(mut rally) => {
            rally.armies = rally.armies.saturating_sub(1);
            rally.soldiers = rally.soldiers.saturating_sub(march.soldiers);
            db.update(rally);
            dismiss(db, march, refund);
        }
        None => dismiss(db, march, refund),
    }
}

/// The muster is over (the timer of one of the rally's armies says so,
/// and the first to fire speaks for them all): with two armies or more
/// they set out, each from its own city; with the caller's alone the
/// rally stands down, and the caller is told.
pub(super) fn set_out(db: &mut impl Db, march: &March) {
    let rally = Table::<Muster>::get(db, march.id).and_then(|muster| Table::<Rally>::get(db, muster.rally));
    let Some(mut rally) = rally else {
        let refund = took_energy(db, None, march);
        return dismiss(db, march, refund);
    };
    if rally.state != Rally::MUSTERING {
        return;
    }
    let marches = armies(db, &rally);
    let target = Table::<City>::get(db, rally.city);
    if marches.len() < 2 {
        disband(db, &rally);
        match &target {
            Some(city) => {
                let words = format!("No one joined your rally against {}'s city. Your army has stood down.", named(db, city.owner));
                told(db, rally.caller, Report::ATTACK, &rally, city.owner, words);
            }
            None if rally.barrow == 0 && gate_at(db, Hex::unpacked(rally.hex)).is_some() => {
                let words = "No one joined your rally against a gate of the ridge. Your army has stood down.".to_string();
                told(db, rally.caller, Report::GATE, &rally, 0, words);
            }
            None if rally.barrow == 0 => {
                let words = "No one joined your rally against a wardstone. Your army has stood down.".to_string();
                told(db, rally.caller, Report::WARD, &rally, 0, words);
            }
            None => {
                let words = format!("No one joined your rally against the level {} barrow. Your army has stood down.", rally.level);
                told(db, rally.caller, Report::HUNT, &rally, rally.level as u64, words);
            }
        }
        return;
    }
    rally.state = Rally::MARCHING;
    db.update(rally.clone());
    let now = db.now();
    let mut last = now;
    for mut army in marches {
        db.cancel(army.timer);
        let steps = hex::decode(&army.route).len().saturating_sub(1);
        army.state = March::GOING;
        army.departed = now;
        army.arrives = now + travel(db, &army, &squads(db, army.id), steps);
        army.timer = db.after(army.arrives, TIMER_MARCH, army.id);
        last = last.max(army.arrives);
        db.update(army);
    }
    if let Some(city) = target {
        let words = format!(
            "{}'s rally is marching on your city: {} armies, {} soldiers in all. The last of them is at your walls in {}.",
            rally.name,
            rally.armies,
            catalog::grouped(rally.soldiers),
            catalog::spoken(last - now)
        );
        warn(db, &city, rally.caller, rally.soldiers, words);
    }
}

/// One of a rally's armies has come up to the barrow or the walls: it
/// waits there for the others, and when the last is up the fight begins.
/// If the barrow is gone by then, or another army is at it, they all turn
/// for home and their energy comes back; so too, with no energy to give
/// back, if the city has moved, is at peace, or is an ally's now.
pub(super) fn reached(db: &mut impl Db, mut march: March) {
    let Some(mut muster) = Table::<Muster>::get(db, march.id) else {
        let way = way_back(&march);
        return turn_home(db, march, way);
    };
    let now = db.now();
    march.state = March::WAITING;
    march.departed = now;
    march.arrives = now;
    march.timer = 0;
    db.update(march);
    muster.arrived = true;
    db.update(muster.clone());
    if Table::<Muster>::by(db, 0, muster.rally).iter().any(|other| !other.arrived) {
        return;
    }
    let Some(mut rally) = Table::<Rally>::get(db, muster.rally) else { return };
    let marches = armies(db, &rally);
    let Some(first) = marches.first() else { return };
    let lasts = if rally.city != 0 {
        let stands = Table::<City>::get(db, rally.city)
            .is_some_and(|city| city.hex == rally.hex && city.shield <= now && !allied(db, rally.caller, city.owner) && !super::at_truce(db, rally.caller, city.owner));
        if !stands {
            let words = "Your alliance's rally found nothing to storm when its last army came up: the city had moved, was at peace, or was an ally's. Your army is turning for home.";
            for army in marches {
                Table::<Muster>::delete(db, army.id);
                told(db, army.owner, Report::ATTACK, &rally, 0, words.to_string());
                let way = way_back(&army);
                turn_home(db, army, way);
            }
            Table::<Rally>::delete(db, rally.id);
            return;
        }
        catalog::ASSAULT_SECONDS
    } else if rally.barrow == 0 && gate_at(db, Hex::unpacked(rally.hex)).is_some() {
        let Some(mut gate) = gate_at(db, Hex::unpacked(rally.hex)).filter(|gate| gate.fighter == 0 && gate.holder != rally.alliance) else {
            let words = "Your alliance's rally found its gate held by your own alliance, or stormed by another, when its last army came up. Your army is turning for home.";
            return turn_back(db, marches, &rally, Report::GATE, words);
        };
        gate.fighter = first.id;
        db.update(gate);
        catalog::ASSAULT_SECONDS
    } else if rally.barrow == 0 {
        if ward_at(db, Hex::unpacked(rally.hex)).is_none_or(|ward| ward.alliance == rally.alliance) {
            let words = "Your alliance's rally found its wardstone gone, or your own alliance's, when its last army came up. Your army is turning for home.";
            return turn_back(db, marches, &rally, Report::WARD, words);
        }
        catalog::ASSAULT_SECONDS
    } else {
        let Some(mut barrow) = Table::<Barrow>::get(db, rally.barrow).filter(|barrow| barrow.fighter == 0) else {
            for army in marches {
                Table::<Muster>::delete(db, army.id);
                spend_energy(db, army.owner, true);
                let way = way_back(&army);
                turn_home(db, army, way);
            }
            Table::<Rally>::delete(db, rally.id);
            return;
        };
        barrow.fighter = first.id;
        db.update(barrow);
        catalog::FIGHT_SECONDS
    };
    rally.state = Rally::FIGHTING;
    db.update(rally);
    let pace = realm(db).map(|realm| realm.pace).unwrap_or(1);
    let ends = now + catalog::paced(lasts, pace).max(1);
    for (index, mut army) in marches.into_iter().enumerate() {
        army.state = March::FIGHTING;
        army.departed = now;
        army.arrives = ends;
        // One timer ends the fight for them all: the caller's army's.
        army.timer = if index == 0 { db.after(ends, TIMER_MARCH, army.id) } else { 0 };
        db.update(army);
    }
}

/// The rally's fight is over: each army turns for home with what is left
/// of it and what it won, and the rally is done.
pub(super) fn ended(db: &mut impl Db, march: &March) {
    let rally = Table::<Muster>::get(db, march.id).and_then(|muster| Table::<Rally>::get(db, muster.rally));
    let Some(rally) = rally else { return };
    let mut marches = armies(db, &rally);
    if rally.city != 0 {
        stormed_together(db, &mut marches);
    } else if rally.barrow == 0 && gate_at(db, Hex::unpacked(rally.hex)).is_some() {
        stormed_gate(db, &mut marches, &rally);
    } else if rally.barrow == 0 {
        stormed_ward(db, &mut marches, &rally);
    } else {
        fought_together(db, &mut marches);
    }
    for army in marches {
        Table::<Muster>::delete(db, army.id);
        if squads(db, army.id).is_empty() {
            // No one is left to come home, but the one who led them.
            release(db, &army);
            Table::<Haul>::delete(db, army.id);
            Table::<March>::delete(db, army.id);
        } else {
            let way = way_back(&army);
            turn_home(db, army, way);
        }
    }
    Table::<Rally>::delete(db, rally.id);
}

/// A rally that found nothing to fight when its last army came up: every
/// army turns for home, each owner told why.
fn turn_back(db: &mut impl Db, marches: Vec<March>, rally: &Rally, kind: u8, words: &str) {
    for army in marches {
        Table::<Muster>::delete(db, army.id);
        told(db, army.owner, kind, rally, 0, words.to_string());
        if squads(db, army.id).is_empty() {
            release(db, &army);
            Table::<Haul>::delete(db, army.id);
            Table::<March>::delete(db, army.id);
        } else {
            let way = way_back(&army);
            turn_home(db, army, way);
        }
    }
    Table::<Rally>::delete(db, rally.id);
}
