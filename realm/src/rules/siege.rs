//! A city under attack: another player's army at its walls, the fight,
//! what is carried off, and the peace that follows.

use super::{allied, building_of, fallen, fight_learned, goods, leading_of, led, load, seen_by_leader, keep_troop, realm, reckon, report, room_for_wounded, set_goods, settle, squads, troop, Refusal, MOST_ROUNDS};
use crate::catalog::{self, Building as Kind, Goods, Troops, Unit};
use crate::hex::Hex;
use crate::rows::{City, Db, Haul, March, Place, Player, Report, Squad, Troop};
use crate::store::Table;

/// The city at a hex, if one stands there.
pub fn city_at(db: &impl Db, hex: Hex) -> Option<City> {
    match Table::<Place>::get(db, hex.packed()) {
        Some(place) if place.kind == Place::CITY => Table::<City>::get(db, place.id),
        _ => None,
    }
}

/// A player's name, for a report.
fn name_of(db: &impl Db, player: u64) -> String {
    Table::<Player>::get(db, player).map(|row| row.name).unwrap_or_else(|| "Someone".into())
}

/// Whether a player may send an army against the city at a hex: one
/// stands there, it is not their own nor an ally's, and it is not at
/// peace.
pub(super) fn may_attack(db: &impl Db, player: u64, to: Hex) -> Result<City, Refusal> {
    let city = city_at(db, to).ok_or(Refusal::NoCityThere)?;
    if city.owner == player {
        return Err(Refusal::OwnCity);
    }
    if allied(db, player, city.owner) {
        return Err(Refusal::AllysCity);
    }
    if super::at_truce(db, player, city.owner) {
        return Err(Refusal::AtTruce);
    }
    let left = city.shield - db.now();
    if left > 0 {
        return Err(Refusal::AtPeace(left));
    }
    Ok(city)
}

/// A player who sends an army against a city gives up their own city's
/// peace: it may be attacked from now on.
pub(super) fn break_peace(db: &mut impl Db, mut city: City) {
    let now = db.now();
    if city.shield > now {
        city.shield = now;
        db.update(city);
    }
}

/// Whether a player may send scouts against the city at a hex: one stands
/// there, not their own, and the player's own city has a Scout Camp.
pub(super) fn may_scout(db: &impl Db, player: u64, to: Hex, from: u64) -> Result<City, Refusal> {
    let city = city_at(db, to).ok_or(Refusal::NoCityThere)?;
    if city.owner == player {
        return Err(Refusal::OwnCity);
    }
    if building_of(db, from, Kind::ScoutCamp).is_none_or(|camp| camp.level < 1) {
        return Err(Refusal::NeedsOther(Kind::ScoutCamp, 1));
    }
    Ok(city)
}

/// Scouts have reached a city: they see how many soldiers stand ready in
/// it, and report it to their player. Nothing is fought.
pub(super) fn scouted(db: &mut impl Db, march: &March) {
    let Some(city) = Table::<City>::get(db, march.target) else { return };
    let now = db.now();
    let stood: u64 = Table::<Troop>::by(db, 0, city.id).iter().map(|row| row.ready).sum();
    let words = format!("Your scouts saw {} soldiers ready in {}'s city.", catalog::grouped(stood), name_of(db, city.owner));
    report(
        db,
        Report {
            id: 0,
            player: march.owner,
            at: now,
            kind: Report::SCOUTED,
            hex: city.hex,
            won: true,
            foe: city.owner,
            rounds: 0,
            fought: march.soldiers,
            wounded: 0,
            dead: 0,
            stood,
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

/// Whether a player may send soldiers to reinforce the city at a hex: one
/// stands there, it is an ally's, and it is not the player's own.
pub(super) fn may_reinforce(db: &impl Db, player: u64, to: Hex) -> Result<City, Refusal> {
    let city = city_at(db, to).ok_or(Refusal::NoCityThere)?;
    if city.owner == player {
        return Err(Refusal::OwnCity);
    }
    if !allied(db, player, city.owner) {
        return Err(Refusal::NotAnAlly);
    }
    Ok(city)
}

/// Soldiers who reached an ally's city join its garrison, ready, and stay
/// there. False if the city is gone, or no longer an ally's: then they
/// march home instead.
pub(super) fn reinforced(db: &mut impl Db, march: &March) -> bool {
    let Some(city) = Table::<City>::get(db, march.target) else { return false };
    if !allied(db, march.owner, city.owner) {
        return false;
    }
    let mut came = 0;
    for squad in squads(db, march.id) {
        if let Some(kind) = Troops::of(squad.kind) {
            let mut row = troop(db, city.id, kind, squad.tier);
            row.ready += squad.count;
            keep_troop(db, row);
            came += squad.count;
        }
        Table::<Squad>::delete(db, squad.id);
    }
    let now = db.now();
    let words = format!("{}'s army joined your city's garrison with {} soldiers.", name_of(db, march.owner), catalog::grouped(came));
    report(
        db,
        Report {
            id: 0,
            player: city.owner,
            at: now,
            kind: Report::REINFORCED,
            hex: city.hex,
            won: true,
            foe: march.owner,
            rounds: 0,
            fought: 0,
            wounded: 0,
            dead: 0,
            stood: came,
            fell: 0,
            grain: 0,
            timber: 0,
            stone: 0,
            moonsalt: 0,
            words,
            read: false,
        },
    );
    true
}

/// The owner of a city is warned when an army sets out against it: whose
/// it is, and when it arrives. Nothing is done about it; the realm only
/// tells.
pub(super) fn warn_of_attack(db: &mut impl Db, march: &March) {
    let Some(city) = Table::<City>::get(db, march.target) else { return };
    let now = db.now();
    let attacker = name_of(db, march.owner);
    let words = format!("{attacker}'s army is marching on your city, and arrives in {}.", catalog::spoken((march.arrives - now).max(0)));
    warn(db, &city, march.owner, march.soldiers, words);
}

/// A warning to a city's owner of what is coming against it, from whom,
/// and how many.
pub(super) fn warn(db: &mut impl Db, city: &City, foe: u64, soldiers: u64, words: String) {
    let now = db.now();
    report(
        db,
        Report {
            id: 0,
            player: city.owner,
            at: now,
            kind: Report::WARNING,
            hex: city.hex,
            won: false,
            foe,
            rounds: 0,
            fought: soldiers,
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

/// An army has reached the city it set out against: if it still stands
/// there and is not at peace, the assault begins, and lasts a while.
/// False if there is nothing to attack.
pub(super) fn besiege(db: &mut impl Db, march: &mut March) -> bool {
    let now = db.now();
    // Gone, at peace, or its owner's alliance at truce with the attacker's since the army set out: nothing to attack.
    let stands = Table::<City>::get(db, march.target).is_some_and(|city| city.hex == march.to && city.shield <= now && !super::at_truce(db, march.owner, city.owner));
    if !stands {
        return false;
    }
    let pace = realm(db).map(|realm| realm.pace).unwrap_or(1);
    march.state = March::FIGHTING;
    march.departed = now;
    march.arrives = now + catalog::paced(catalog::ASSAULT_SECONDS, pace).max(1);
    true
}

/// An army's assault on a city is over.
///
/// Everyone standing ready in the city defends it, each harder to bring
/// down for every level of its Wall. Of the army's fallen, half are
/// carried home wounded while its own city has room to tend them, and
/// the rest die. The city's fallen lie wounded within it while it has
/// room, and the rest die. If the army holds the field it carries off as
/// much of the city's goods as those still standing can bear, less what
/// the Storehouse keeps safe, and the city is at peace for a while. Both
/// players are told.
pub(super) fn stormed(db: &mut impl Db, march: &mut March) {
    storm(db, std::slice::from_mut(march));
}

/// A rally's assault on a city is over: its armies fought as one, under
/// the caller's commander, whose army is first. Each loses what fell of
/// its own and carries home wounded what its own city has room for; what
/// is carried off is shared by what each can bear. Every army's owner is
/// told, and the city's.
pub(super) fn stormed_together(db: &mut impl Db, marches: &mut [March]) {
    storm(db, marches);
}

fn storm(db: &mut impl Db, marches: &mut [March]) {
    let Some(first) = marches.first() else { return };
    let Some(mut city) = Table::<City>::get(db, first.target) else { return };
    let (leader, attacker, defender) = (first.owner, name_of(db, first.owner), name_of(db, city.owner));
    let armies = marches.len();
    let rally = armies > 1;

    // Every squad of every army, the best first, each remembering whose it is.
    let mut own: Vec<(usize, Squad)> = Vec::new();
    for (index, march) in marches.iter().enumerate() {
        own.extend(squads(db, march.id).into_iter().map(|squad| (index, squad)));
    }
    own.sort_by_key(|(index, squad)| (std::cmp::Reverse(squad.tier), squad.kind, *index));
    own.retain(|(_, squad)| Troops::of(squad.kind).is_some());
    let army: Vec<Unit> = own.iter().filter_map(|(_, squad)| Troops::of(squad.kind).map(|kind| Unit { kind, tier: squad.tier, count: squad.count })).collect();
    let mut garrison: Vec<Troop> = Table::<Troop>::by(db, 0, city.id).into_iter().filter(|row| row.ready > 0 && Troops::of(row.kind).is_some()).collect();
    garrison.sort_by_key(|row| (std::cmp::Reverse(row.tier), row.kind));
    let defenders: Vec<Unit> = garrison.iter().filter_map(|row| Troops::of(row.kind).map(|kind| Unit { kind, tier: row.tier, count: row.ready })).collect();
    let wall = building_of(db, city.id, Kind::Wall).map(|building| building.level).unwrap_or(0);
    let mut rolls: Vec<u64> = (0..2 * MOST_ROUNDS).map(|_| db.chance()).collect();
    // A Wall shelters its city less from an army a wallbreaker leads.
    let shelter = catalog::shelter(wall) * (100 - leading_of(db, &marches[0]).breaches.min(100)) / 100;
    let outcome = fight_learned(&army, &defenders, [led(db, &marches[0]), super::defence_of(db, city.id, city.owner)], shelter, || rolls.pop().unwrap_or(0));

    // Each army's fallen: half carried home wounded, while its own city has room.
    let mut room: Vec<u64> = marches.iter().map(|march| room_for_wounded(db, march.city)).collect();
    let (mut fought, mut wounded, mut dead) = (vec![0u64; armies], vec![0u64; armies], vec![0u64; armies]);
    for ((index, squad), lost) in own.iter_mut().zip(&outcome.attackers_lost) {
        let saved = (lost / 2).min(room[*index]);
        room[*index] -= saved;
        fought[*index] += squad.count;
        wounded[*index] += saved;
        dead[*index] += lost - saved;
        squad.count -= lost;
        squad.wounded += saved;
        if squad.count + squad.wounded == 0 {
            Table::<Squad>::delete(db, squad.id);
        } else {
            db.update(squad.clone());
        }
    }
    for (index, march) in marches.iter_mut().enumerate() {
        march.soldiers = fought[index] - wounded[index] - dead[index];
    }
    let together: u64 = fought.iter().sum();
    let standing: u64 = marches.iter().map(|march| march.soldiers).sum();

    // The city's fallen: wounded within it, while there is room.
    let mut room = room_for_wounded(db, city.id);
    let (mut hurt, mut slain) = (0, 0);
    for (row, lost) in garrison.iter_mut().zip(&outcome.defenders_lost) {
        let saved = (*lost).min(room);
        room -= saved;
        hurt += saved;
        slain += lost - saved;
        row.ready -= lost;
        row.wounded += saved;
        keep_troop(db, row.clone());
    }
    let stood: u64 = defenders.iter().map(|unit| unit.count).sum();
    let fell: u64 = outcome.defenders_lost.iter().sum();
    seen_by_leader(db, &marches[0], 2 * fell + together / 10);
    // Whoever kept the city has seen as much of its attackers fall.
    super::seen_by_keeper(db, city.owner, 2 * (together - standing));

    // What is carried off: as much as all of them can bear, each army's
    // share as much as it can bear of it.
    let mut won = vec![Goods::NONE; armies];
    let now = db.now();
    let pace = realm(db).map(|realm| realm.pace).unwrap_or(1);
    if outcome.won {
        if let Ok(mut stock) = settle(db, city.id) {
            let storehouse = building_of(db, city.id, Kind::Storehouse).map(|building| building.level).unwrap_or(0);
            let safe = catalog::kept_safe(storehouse);
            let open = goods(&stock).parts().map(|part| part.saturating_sub(safe));
            let all: u64 = open.iter().sum();
            let loads: Vec<u64> = marches.iter().map(|march| load(db, march)).collect();
            let bearable: u64 = loads.iter().sum();
            let taken = Goods::from_parts(open.map(|part| if all > bearable { (part as u128 * bearable as u128 / all as u128) as u64 } else { part }));
            for (index, share) in won.iter_mut().enumerate() {
                *share = if armies == 1 {
                    taken
                } else {
                    Goods::from_parts(taken.parts().map(|part| (part as u128 * loads[index] as u128 / bearable.max(1) as u128) as u64))
                };
            }
            let carried = won.iter().fold(Goods::NONE, |sum, share| sum.plus(*share));
            let left = goods(&stock).minus(carried);
            set_goods(&mut stock, left);
            db.update(stock);
        }
        for (index, march) in marches.iter().enumerate() {
            let share = won[index];
            if !share.is_none() {
                db.insert(Haul { march: march.id, owner: march.owner, grain: share.grain, timber: share.timber, stone: share.stone, moonsalt: share.moonsalt });
            }
        }
        city.shield = now + catalog::paced(catalog::BEATEN_PEACE, pace);
        db.update(city.clone());
    }
    let taken = won.iter().fold(Goods::NONE, |sum, share| sum.plus(*share));

    // Each side is told, in its own words.
    let report_of = |player: u64, kind: u8, won: bool, foe: u64, mine: (u64, u64, u64), theirs: (u64, u64), goods: Goods, words: String| Report {
        id: 0,
        player,
        at: now,
        kind,
        hex: city.hex,
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
    for (index, march) in marches.iter().enumerate() {
        let mut words = match (rally, outcome.won) {
            (false, true) => format!("Your army took {defender}'s city by storm."),
            (false, false) => format!("Your army was beaten at {defender}'s city. {} of its defenders still stood.", catalog::grouped(stood - fell)),
            (true, true) => format!("Your alliance's rally took {defender}'s city by storm: {armies} armies, {} soldiers in all.", catalog::grouped(together)),
            (true, false) => format!(
                "Your alliance's rally was beaten at {defender}'s city: {armies} armies, {} soldiers in all. {} of its defenders still stood.",
                catalog::grouped(together),
                catalog::grouped(stood - fell)
            ),
        };
        words += " ";
        words += &fallen(fought[index], wounded[index], dead[index], "soldier", "soldiers");
        if outcome.won {
            words += &match (won[index].is_none(), rally) {
                (true, _) => " There was nothing to carry off.".to_string(),
                (false, false) => format!(" It is bringing home {}.", won[index]),
                (false, true) => format!(" Your army is bringing home {}.", won[index]),
            };
        }
        report(db, report_of(march.owner, Report::ATTACK, outcome.won, city.owner, (fought[index], wounded[index], dead[index]), (stood, fell), won[index], words));
    }
    let by = if rally { format!("{attacker}'s rally of {armies} armies") } else { format!("{attacker}'s army") };
    let mut to_defender = if outcome.won {
        if taken.is_none() {
            format!("{by} took your city by storm, and found nothing to carry off.")
        } else {
            format!("{by} took your city by storm and carried off {taken}.")
        }
    } else {
        format!("{by} attacked your city and was beaten. {} of its {} fell.", catalog::grouped(together - standing), catalog::grouped(together))
    };
    to_defender += " ";
    to_defender += &if stood == 0 { "Your city had no defenders.".to_string() } else { fallen(stood, hurt, slain, "defender", "defenders") };
    if outcome.won {
        to_defender += &format!(" Your city is at peace for {}.", catalog::spoken(catalog::paced(catalog::BEATEN_PEACE, pace)));
    }
    report(db, report_of(city.owner, Report::DEFENCE, !outcome.won, leader, (stood, hurt, slain), (together, together - standing), taken, to_defender));
    reckon(db, city.id);
}
