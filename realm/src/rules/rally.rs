//! Rallies: allies' armies against a barrow too strong for one of them.
//!
//! A member of an alliance calls a rally against a barrow up to three
//! levels above what they may attack alone, and their army musters in
//! their city. For as long as the muster lasts allies join with armies
//! of their own, each mustering in its own city. When it ends they all
//! set out, each from where it is; those that reach the barrow first wait
//! for the last; then they fight as one, under the caller's commander. A
//! rally no one joins stands down.

use super::{
    asking, barrow_at, dispatch, fought_together, home, hunt_of, member_of, realm, release, report, shown_name, spend_energy, squads, travel, turn_home, way_back, Asked,
    Refusal, TIMER_MARCH,
};
use crate::catalog;
use crate::hex::{self, Hex};
use crate::rows::{Barrow, Db, Haul, March, Muster, Player, Rally, Report};
use crate::store::Table;

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

/// Whether a player may send an army to a rally against the barrow at a
/// hex: one stands there, no one is fighting it, and they have the
/// energy. (Whether there is a rally for it to go to is its caller's
/// business and its joiners': see `call_rally` and `join_rally`.)
pub(super) fn may_go(db: &impl Db, player: u64, to: Hex) -> Result<Barrow, Refusal> {
    let barrow = barrow_at(db, to).ok_or(Refusal::NothingToFight)?;
    if barrow.fighter != 0 {
        return Err(Refusal::BarrowTaken);
    }
    let hunt = hunt_of(db, player);
    if hunt.energy < catalog::ENERGY_A_HUNT {
        return Err(Refusal::NoEnergy(hunt.energy));
    }
    Ok(barrow)
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

/// A member of an alliance calls a rally against the barrow at a hex,
/// with an army of their own: it musters in their city until the rally
/// sets out.
pub fn call_rally(db: &mut impl Db, player: u64, to: Hex, asked: &[Asked], leader: u64) -> Result<Rally, Refusal> {
    asking(db, player)?;
    let member = member_of(db, player).ok_or(Refusal::NotAllied)?;
    let barrow = barrow_at(db, to).ok_or(Refusal::NothingToFight)?;
    let reach = hunt_of(db, player).cleared + 1 + catalog::RALLY_REACH;
    if barrow.level > reach {
        return Err(Refusal::RallyTooStrong(reach));
    }
    if rally_with(db, player).is_some() {
        return Err(Refusal::AlreadyRallying);
    }
    if Table::<Rally>::by(db, 0, member.alliance).iter().any(|rally| rally.barrow == barrow.id) {
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
        barrow: barrow.id,
        hex: barrow.hex,
        level: barrow.level,
        sets_out: db.now() + catalog::paced(catalog::RALLY_MUSTER, pace).max(1),
        state: Rally::MUSTERING,
        armies: 1,
        soldiers: march.soldiers,
    });
    hold(db, march, &rally);
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

/// An army leaves its rally before anything has come of it: its soldiers
/// stand ready in their city again, and the energy it took comes back.
fn dismiss(db: &mut impl Db, march: &March) {
    db.cancel(march.timer);
    Table::<Muster>::delete(db, march.id);
    spend_energy(db, march.owner, true);
    home(db, march);
}

/// A rally comes to nothing while it musters: every army stands down.
fn disband(db: &mut impl Db, rally: &Rally) {
    for march in armies(db, rally) {
        dismiss(db, &march);
    }
    Table::<Rally>::delete(db, rally.id);
}

/// A mustering army is called home by its owner. If it is the caller's,
/// the rally is off for everyone.
pub(super) fn stand_down(db: &mut impl Db, march: &March) {
    let rally = Table::<Muster>::get(db, march.id).and_then(|muster| Table::<Rally>::get(db, muster.rally));
    match rally {
        Some(rally) if rally.caller == march.owner => disband(db, &rally),
        Some(mut rally) => {
            rally.armies = rally.armies.saturating_sub(1);
            rally.soldiers = rally.soldiers.saturating_sub(march.soldiers);
            db.update(rally);
            dismiss(db, march);
        }
        None => dismiss(db, march),
    }
}

/// The muster is over (the timer of one of the rally's armies says so,
/// and the first to fire speaks for them all): with two armies or more
/// they set out, each from its own city; with the caller's alone the
/// rally stands down, and the caller is told.
pub(super) fn set_out(db: &mut impl Db, march: &March) {
    let rally = Table::<Muster>::get(db, march.id).and_then(|muster| Table::<Rally>::get(db, muster.rally));
    let Some(mut rally) = rally else { return dismiss(db, march) };
    if rally.state != Rally::MUSTERING {
        return;
    }
    let marches = armies(db, &rally);
    if marches.len() < 2 {
        disband(db, &rally);
        let words = format!("No one joined your rally against the level {} barrow. Your army has stood down.", rally.level);
        report(
            db,
            Report {
                id: 0,
                player: rally.caller,
                at: db.now(),
                kind: Report::HUNT,
                hex: rally.hex,
                won: false,
                foe: rally.level as u64,
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
        return;
    }
    rally.state = Rally::MARCHING;
    db.update(rally);
    let now = db.now();
    for mut army in marches {
        db.cancel(army.timer);
        let steps = hex::decode(&army.route).len().saturating_sub(1);
        army.state = March::GOING;
        army.departed = now;
        army.arrives = now + travel(db, &army, &squads(db, army.id), steps);
        army.timer = db.after(army.arrives, TIMER_MARCH, army.id);
        db.update(army);
    }
}

/// One of a rally's armies has come up to the barrow: it waits there for
/// the others, and when the last is up the fight begins. If the barrow
/// is gone by then, or another army is at it, they all turn for home and
/// their energy comes back.
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
    let Some(first) = marches.first() else { return };
    barrow.fighter = first.id;
    db.update(barrow);
    rally.state = Rally::FIGHTING;
    db.update(rally);
    let pace = realm(db).map(|realm| realm.pace).unwrap_or(1);
    let ends = now + catalog::paced(catalog::FIGHT_SECONDS, pace).max(1);
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
    fought_together(db, &mut marches);
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
