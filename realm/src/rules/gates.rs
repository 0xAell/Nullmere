//! The gates of the ridge: one in each of the six passes between the
//! lake country and the outer land.
//!
//! The Unquiet hold every gate when the realm opens, and an army passes
//! no gate that is not its own alliance's: the lake country is shut to
//! all. A week into each season, at the realm's pace, the gates may be
//! stormed, by a rally and no other way; an alliance whose rally takes one
//! holds it, and its members march through it, and may move their cities
//! into the lake country. Another alliance may take it from them as they
//! took it, from the same garrison. When the season turns every gate goes
//! back to the Unquiet but those the season's victor holds: what it won,
//! it keeps.

use super::{fight_as_one, member_of, realm, report, season_now, Refusal};
use crate::catalog;
use crate::hex::Hex;
use crate::land;
use crate::rows::{Alliance, Db, Gate, Member, Place, Rally, Report};
use crate::store::{Seconds, Table};

/// Raises the six gates as the realm opens, held by the Unquiet.
pub(super) fn write_gates(db: &mut impl Db, radius: u32) {
    for (index, hex) in land::gates(radius).into_iter().enumerate() {
        let id = index as u64 + 1;
        if Table::<Gate>::get(db, id).is_none() {
            db.insert(Gate { id, hex: hex.packed(), holder: 0, holder_name: String::new(), taken_at: 0, fighter: 0 });
            db.insert(Place { hex: hex.packed(), kind: Place::GATE, id });
        }
    }
}

/// The gate at a hex, if one stands there.
pub fn gate_at(db: &impl Db, hex: Hex) -> Option<Gate> {
    match Table::<Place>::get(db, hex.packed()) {
        Some(place) if place.kind == Place::GATE => Table::<Gate>::get(db, place.id),
        _ => None,
    }
}

/// The hexes of the gates a player's armies may not pass: every gate but
/// those their alliance holds.
pub fn gates_barred_to(db: &impl Db, player: u64) -> Vec<Hex> {
    let alliance = member_of(db, player).map(|member| member.alliance).unwrap_or(0);
    Table::<Gate>::all(db).into_iter().filter(|gate| gate.holder == 0 || gate.holder != alliance).map(|gate| Hex::unpacked(gate.hex)).collect()
}

/// Whether an alliance holds a gate of the ridge.
pub fn holds_gate(db: &impl Db, alliance: u64) -> bool {
    alliance != 0 && Table::<Gate>::all(db).iter().any(|gate| gate.holder == alliance)
}

/// When the gates may be stormed this season.
pub fn gates_open_at(db: &impl Db) -> Seconds {
    let pace = realm(db).map(|realm| realm.pace).unwrap_or(1);
    season_now(db).began.saturating_add(catalog::paced(catalog::GATES_OPEN_DAYS * catalog::DAY, pace))
}

/// Whether a player's alliance may send a rally against a gate now: the
/// gates are open this season, it is not their alliance's own, and no
/// other rally is at it.
pub(super) fn may_storm(db: &impl Db, player: u64, gate: &Gate) -> Result<(), Refusal> {
    let member = member_of(db, player).ok_or(Refusal::NotAllied)?;
    let left = gates_open_at(db) - db.now();
    if left > 0 {
        return Err(Refusal::GatesShut(left));
    }
    if gate.holder == member.alliance {
        return Err(Refusal::OwnGate);
    }
    if gate.fighter != 0 {
        return Err(Refusal::GateFought);
    }
    Ok(())
}

/// A rally's fight at a gate is over. Its armies fought as one against
/// the garrison behind the gate's walls, each losing what fell of its own
/// and carrying home as wounded what its own city has room for. If they
/// won, the gate is their alliance's. Every army's owner is told, and the
/// members of the alliance that held it, if one did.
pub(super) fn stormed_gate(db: &mut impl Db, marches: &mut [crate::rows::March], rally: &Rally) {
    let Some(mut gate) = gate_at(db, Hex::unpacked(rally.hex)) else { return };
    let garrison = catalog::gate_garrison();
    let together = fight_as_one(db, marches, &garrison, catalog::gate_shelter());
    let stood: u64 = garrison.iter().map(|unit| unit.count).sum();
    let fell: u64 = together.outcome.defenders_lost.iter().sum();
    let won = together.outcome.won;
    let before = gate.holder;
    let name = Table::<Alliance>::get(db, rally.alliance).map(|alliance| format!("[{}] {}", alliance.tag, alliance.name)).unwrap_or_default();
    gate.fighter = 0;
    if won {
        (gate.holder, gate.holder_name, gate.taken_at) = (rally.alliance, name.clone(), db.now());
    }
    db.update(gate.clone());

    let armies = marches.len();
    let all: u64 = together.fought.iter().sum();
    let now = db.now();
    for (index, march) in marches.iter().enumerate() {
        let mut words = if won {
            format!("Your alliance's rally took a gate of the ridge: {armies} armies, {} soldiers in all. Its members may pass it now.", catalog::grouped(all))
        } else {
            format!(
                "Your alliance's rally was beaten at a gate of the ridge: {armies} armies, {} soldiers in all. {} of its garrison still stood.",
                catalog::grouped(all),
                catalog::grouped(stood - fell)
            )
        };
        words += " ";
        words += &super::fallen(together.fought[index], together.wounded[index], together.dead[index], "soldier", "soldiers");
        let fight = Fight { rounds: together.outcome.rounds, mine: (together.fought[index], together.wounded[index], together.dead[index]), theirs: (stood, fell) };
        report(db, told(march.owner, now, &gate, won, fight, words));
    }
    if won && before != 0 && before != rally.alliance {
        let words = format!("{name} took one of your alliance's gates of the ridge. Your members may not pass it now.");
        for member in Table::<Member>::by(db, 0, before) {
            report(db, told(member.player, now, &gate, false, Fight { theirs: (all, 0), ..Fight::default() }, words.clone()));
        }
    }
}

/// What a report tells of a fight: its rounds, the reader's soldiers who
/// fought, were wounded and died, and the other side's who stood and fell.
#[derive(Default)]
struct Fight {
    rounds: u32,
    mine: (u64, u64, u64),
    theirs: (u64, u64),
}

fn told(player: u64, at: Seconds, gate: &Gate, won: bool, fight: Fight, words: String) -> Report {
    let Fight { rounds, mine, theirs } = fight;
    Report {
        id: 0,
        player,
        at,
        kind: Report::GATE,
        hex: gate.hex,
        won,
        foe: gate.id,
        rounds,
        fought: mine.0,
        wounded: mine.1,
        dead: mine.2,
        stood: theirs.0,
        fell: theirs.1,
        grain: 0,
        timber: 0,
        stone: 0,
        moonsalt: 0,
        words,
        read: false,
    }
}

/// The season has turned: every gate goes back to the Unquiet but those
/// the season's victor holds.
pub(super) fn gates_turn(db: &mut impl Db, victor: u64) {
    for mut gate in Table::<Gate>::all(db) {
        if gate.holder != 0 && gate.holder != victor {
            (gate.holder, gate.holder_name, gate.taken_at) = (0, String::new(), 0);
            db.update(gate);
        }
    }
}

/// An alliance has ended: the gates it held go back to the Unquiet.
pub(super) fn gates_fall(db: &mut impl Db, alliance: u64) {
    for mut gate in Table::<Gate>::all(db) {
        if gate.holder == alliance {
            (gate.holder, gate.holder_name, gate.taken_at) = (0, String::new(), 0);
            db.update(gate);
        }
    }
}
