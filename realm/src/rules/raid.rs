//! Armies against armies in the field: a player's army sent against
//! another player's army gathering at a site.
//!
//! Gatherers have no walls about them, and no peace keeps them: an army
//! may fall on any that are not its own, nor an ally's, nor of an alliance
//! at truce with its own; sending it gives up the sender's own city's
//! peace, as an attack on a city does. It fights as soon as it gets
//! there. Each side carries home as wounded as many of its fallen as its
//! own city has room to tend; the rest are dead. If the raiders win, the
//! gatherers are driven off for home, and the raiders carry off what
//! they had gathered, as much as those still standing can bear (the rest
//! the gatherers keep); if they lose, the gatherers work on, the fewer
//! for it. Each side is told, and each side's kills count to its fame.

use super::{allied, at_truce, fallen, fight_learned, gathered_so_far, led, load, off_site, report, room_for_wounded, seen_by_leader, squads, turn_home, way_back, Refusal, MOST_ROUNDS};
use crate::catalog::{self, Goods, Troops, Unit};
use crate::hex::Hex;
use crate::rows::{Db, Haul, March, Place, Player, Report, Site, Squad};
use crate::store::Table;

fn name_of(db: &impl Db, player: u64) -> String {
    Table::<Player>::get(db, player).map(|row| row.name).unwrap_or_else(|| "Someone".into())
}

/// The site at a hex and the army gathering there, if any is.
fn gathering_at(db: &impl Db, to: Hex) -> Option<(Site, March)> {
    let site = match Table::<Place>::get(db, to.packed()) {
        Some(place) if place.kind == Place::SITE => Table::<Site>::get(db, place.id)?,
        _ => return None,
    };
    let gatherers = Table::<March>::get(db, site.gatherer).filter(|march| march.state == March::WORKING)?;
    Some((site, gatherers))
}

/// Whether a player may send an army against the army gathering at a
/// hex: one gathers there, and it is not their own, nor an ally's, nor
/// of an alliance at truce with theirs. The site.
pub(super) fn may_raid(db: &impl Db, player: u64, to: Hex) -> Result<Site, Refusal> {
    let (site, gatherers) = gathering_at(db, to).ok_or(Refusal::NoOneGathering)?;
    if gatherers.owner == player {
        return Err(Refusal::OwnArmy);
    }
    if allied(db, player, gatherers.owner) {
        return Err(Refusal::AllysArmy);
    }
    if at_truce(db, player, gatherers.owner) {
        return Err(Refusal::AtTruce);
    }
    Ok(site)
}

/// One side of a fight in the field: its squads, the best first, as
/// units; who fell of each, carried home wounded while its city has room;
/// and what it came to.
struct Side {
    squads: Vec<Squad>,
    units: Vec<Unit>,
}

impl Side {
    fn of(db: &impl Db, march: &March) -> Side {
        let mut own: Vec<Squad> = squads(db, march.id).into_iter().filter(|squad| Troops::of(squad.kind).is_some() && squad.count > 0).collect();
        own.sort_by_key(|squad| (std::cmp::Reverse(squad.tier), squad.kind));
        let units = own.iter().filter_map(|squad| Troops::of(squad.kind).map(|kind| Unit { kind, tier: squad.tier, count: squad.count })).collect();
        Side { squads: own, units }
    }

    fn fought(&self) -> u64 {
        self.units.iter().map(|unit| unit.count).sum()
    }

    /// Its fallen: as many carried wounded as its city has room for, the
    /// best first; the rest dead. How many were wounded, and how many died.
    fn bear(&mut self, db: &mut impl Db, march: &mut March, lost: &[u64]) -> (u64, u64) {
        let mut room = room_for_wounded(db, march.city);
        let mercy = led(db, march).mercy;
        let (mut wounded, mut dead) = (0, 0);
        for (squad, lost) in self.squads.iter_mut().zip(lost) {
            let tended = (*lost).min(room);
            room -= tended;
            let saved = tended + super::spared(lost - tended, mercy);
            wounded += saved;
            dead += lost - saved;
            squad.count -= lost;
            squad.wounded += saved;
            if squad.count + squad.wounded == 0 {
                Table::<Squad>::delete(db, squad.id);
            } else {
                db.update(squad.clone());
            }
        }
        march.soldiers = march.soldiers.saturating_sub(wounded + dead);
        (wounded, dead)
    }
}

/// A raiding army has reached its site. If an army not its own nor an
/// ally's still gathers there, they fight; otherwise it finds no one and
/// turns home. Either way the raiders are left to be sent home by the
/// caller; the gatherers, if beaten, are sent home here.
pub(super) fn raided(db: &mut impl Db, raiders: &mut March) {
    let now = db.now();
    let Some(site) = Table::<Site>::get(db, raiders.target) else { return };
    let Some(mut gatherers) = Table::<March>::get(db, site.gatherer)
        .filter(|march| march.state == March::WORKING && march.owner != raiders.owner && !allied(db, raiders.owner, march.owner))
    else {
        return;
    };
    let (raider, gatherer) = (name_of(db, raiders.owner), name_of(db, gatherers.owner));
    let good = match site.kind {
        Site::GRAIN => "grain",
        Site::TIMBER => "timber",
        Site::STONE => "stone",
        _ => "moonsalt",
    };
    // What the gatherers had gathered by the time the raiders fell on them.
    let gathered = gathered_so_far(db, &gatherers);

    let mut attacking = Side::of(db, raiders);
    let mut defending = Side::of(db, &gatherers);
    let mut rolls: Vec<u64> = (0..2 * MOST_ROUNDS).map(|_| db.chance()).collect();
    let outcome = fight_learned(&attacking.units, &defending.units, [led(db, raiders), led(db, &gatherers)], 0, || rolls.pop().unwrap_or(0));
    let (fought, stood) = (attacking.fought(), defending.fought());
    let (wounded, dead) = attacking.bear(db, raiders, &outcome.attackers_lost);
    let (hurt, slain) = defending.bear(db, &mut gatherers, &outcome.defenders_lost);
    let fell: u64 = outcome.defenders_lost.iter().sum();
    let lost: u64 = outcome.attackers_lost.iter().sum();

    // Fame: each side's kill points for what it struck down.
    let struck = super::kill_points(defending.units.iter().zip(&outcome.defenders_lost).map(|(unit, lost)| (unit.tier, *lost)));
    let suffered = super::kill_points(attacking.units.iter().zip(&outcome.attackers_lost).map(|(unit, lost)| (unit.tier, *lost)));
    super::add_fame(db, raiders.owner, struck, fell, dead);
    super::add_fame(db, gatherers.owner, suffered, lost, slain);
    seen_by_leader(db, raiders, 2 * fell);
    seen_by_leader(db, &gatherers, 2 * lost);

    // Beaten, the gatherers are driven off with what they had gathered,
    // and the raiders carry off as much of it as they can bear.
    let mut carried = Goods::NONE;
    if outcome.won {
        db.cancel(gatherers.timer);
        let taken = off_site(db, &gatherers, gathered);
        let all: u64 = taken.parts().iter().sum();
        let bearable = load(db, raiders);
        carried = Goods::from_parts(taken.parts().map(|part| if all > bearable { (part as u128 * bearable as u128 / all as u128) as u64 } else { part }));
        let kept = taken.minus(carried);
        if !carried.is_none() {
            db.insert(Haul { march: raiders.id, owner: raiders.owner, grain: carried.grain, timber: carried.timber, stone: carried.stone, moonsalt: carried.moonsalt });
        }
        if !kept.is_none() {
            db.insert(Haul { march: gatherers.id, owner: gatherers.owner, grain: kept.grain, timber: kept.timber, stone: kept.stone, moonsalt: kept.moonsalt });
        }
        if squads(db, gatherers.id).is_empty() {
            super::release(db, &gatherers);
            Table::<Haul>::delete(db, gatherers.id);
            Table::<March>::delete(db, gatherers.id);
        } else {
            let way = way_back(&gatherers);
            turn_home(db, gatherers.clone(), way);
        }
    } else {
        db.update(gatherers.clone());
    }

    // Each side is told, in its own words.
    let report_of = |player: u64, kind: u8, won: bool, foe: u64, mine: (u64, u64, u64), theirs: (u64, u64), goods: Goods, words: String| Report {
        id: 0,
        player,
        at: now,
        kind,
        hex: site.hex,
        won,
        foe,
        rounds: outcome.rounds,
        fought: mine.0,
        wounded: mine.1,
        dead: mine.2,
        stood: theirs.0,
        fell: theirs.1,
        grain: goods.grain,
        timber: goods.timber,
        stone: goods.stone,
        moonsalt: goods.moonsalt,
        words,
        read: false,
    };
    let mut to_raiders = if outcome.won {
        format!("Your army fell on {gatherer}'s army gathering {good} and drove it off.")
    } else {
        format!("Your army fell on {gatherer}'s army gathering {good} and was beaten. {} of them still stood.", catalog::grouped(stood - fell))
    };
    to_raiders += " ";
    to_raiders += &fallen(fought, wounded, dead, "soldier", "soldiers");
    if outcome.won {
        to_raiders += &if carried.is_none() { " They had gathered nothing yet.".to_string() } else { format!(" It is bringing home {carried}.") };
    }
    report(db, report_of(raiders.owner, Report::FIELD, outcome.won, gatherers.owner, (fought, wounded, dead), (stood, fell), carried, to_raiders));
    let mut to_gatherers = if outcome.won {
        if carried.is_none() {
            format!("{raider}'s army fell on your army gathering {good} and drove it off.")
        } else {
            format!("{raider}'s army fell on your army gathering {good}, drove it off and carried off {carried}.")
        }
    } else {
        format!("{raider}'s army fell on your army gathering {good} and was beaten. Your army gathers on.")
    };
    to_gatherers += " ";
    to_gatherers += &fallen(stood, hurt, slain, "soldier", "soldiers");
    report(db, report_of(gatherers.owner, Report::FIELD_DEFENCE, !outcome.won, raiders.owner, (stood, hurt, slain), (fought, lost), carried, to_gatherers));
}
