//! The Lists: the realm's standing of bands. A player enters by setting a
//! band of soldiers standing ready in their city, as many as their Keep
//! allows, under one of their commanders or under none; it is a likeness
//! of them, kept as it was set, and the soldiers stay free for anything
//! else. They begin at the foot of the standing and challenge those up to
//! ten places above them, five times a day of the realm: the two bands
//! fight as armies do, none are lost, and a challenger who wins takes the
//! place of the one they beat, who goes down to theirs. Each day every
//! entrant claims a purse of goods and honour by their place.

use super::march::wanted;
use super::{asking, city_of, commanding, fight_learned, goods, honoured_for_lists, mastery, report, set_goods, settle, today, with_leading, Asked, Mastery, Refusal, HELD, MOST_ROUNDS};
use crate::catalog::{self, Goods, Troops, Unit};
use crate::rows::{Commander, Db, Entrant, Guard, Player, Purse, Report, Tilt};
use crate::store::Table;

/// Writes the purses out as rows, for clients to show, as the realm opens.
pub fn write_purses(db: &mut impl Db) {
    for (index, (first, last, goods, honour)) in catalog::lists_purses().into_iter().enumerate() {
        db.insert(Purse { id: index as u64 + 1, first, last, grain: goods.grain, timber: goods.timber, stone: goods.stone, honour });
    }
}

/// A player's band, its best soldiers first.
pub fn band_of(db: &impl Db, player: u64) -> Vec<Unit> {
    let mut band: Vec<Unit> = Table::<Guard>::by(db, 0, player)
        .into_iter()
        .filter_map(|guard| Troops::of(guard.kind).map(|kind| Unit { kind, tier: guard.tier, count: guard.count }))
        .collect();
    band.sort_by_key(|unit| (std::cmp::Reverse(unit.tier), unit.kind as u8));
    band
}

/// A player's day in the Lists, begun afresh on a new day.
pub fn tilt_of(db: &impl Db, player: u64) -> Tilt {
    let day = today(db);
    let mut tilt = Table::<Tilt>::get(db, player).unwrap_or(Tilt { player, day, tries: 0, claimed: 0, dawn_day: 0, dawn: 0 });
    if tilt.day != day {
        (tilt.day, tilt.tries) = (day, 0);
    }
    tilt
}

fn keep_tilt(db: &mut impl Db, tilt: Tilt) {
    if Table::<Tilt>::get(db, tilt.player).is_some() {
        db.update(tilt);
    } else {
        db.insert(tilt);
    }
}

/// The place a player held as the day's first challenge of theirs or
/// against them was fought: kept the first time in a day, so the day's
/// purse is paid by it, not by a place passed hand to hand that day.
fn keep_dawn(tilt: &mut Tilt, place: u64) {
    if tilt.dawn_day != tilt.day + 1 {
        (tilt.dawn_day, tilt.dawn) = (tilt.day + 1, place);
    }
}

/// What a band has beyond its numbers: what its city has learnt, and what
/// the commander it stands under adds, while they are still its owner's
/// and not held prisoner.
fn learnt(db: &impl Db, entrant: &Entrant) -> Mastery {
    let Ok(city) = city_of(db, entrant.player) else { return Mastery::default() };
    match Table::<Commander>::get(db, entrant.leader).filter(|commander| commander.owner == entrant.player && commander.march != HELD) {
        Some(commander) => with_leading(mastery(db, city.id), commanding(db, &commander)),
        None => mastery(db, city.id),
    }
}

/// A player sets their band, entering the Lists at its foot if they were
/// not in it.
pub fn enter_lists(db: &mut impl Db, player: u64, asked: &[Asked], leader: u64) -> Result<Entrant, Refusal> {
    asking(db, player)?;
    let city = city_of(db, player)?;
    let band = wanted(db, city.id, asked)?;
    let most = catalog::lists_most(city.keep);
    if band.iter().map(|ask| ask.count).sum::<u64>() > most {
        return Err(Refusal::BandTooBig(most));
    }
    if leader != 0 {
        let commander = Table::<Commander>::get(db, leader).filter(|commander| commander.owner == player).ok_or(Refusal::NoSuchCommander)?;
        if commander.march == HELD {
            return Err(Refusal::HeldPrisoner(commander.name));
        }
    }
    for guard in Table::<Guard>::by(db, 0, player) {
        Table::<Guard>::delete(db, guard.key);
    }
    for ask in &band {
        db.insert(Guard { key: Guard::key(player, ask.kind, ask.tier), player, kind: ask.kind, tier: ask.tier, count: ask.count });
    }
    let now = db.now();
    Ok(match Table::<Entrant>::get(db, player) {
        Some(mut entrant) => {
            (entrant.leader, entrant.set_at) = (leader, now);
            db.update(entrant.clone());
            entrant
        }
        None => {
            let place = Table::<Entrant>::all(db).len() as u64 + 1;
            db.insert(Entrant { player, place, leader, set_at: now })
        }
    })
}

/// A player challenges another above them in the Lists. Whether they won.
pub fn challenge(db: &mut impl Db, player: u64, opponent: u64) -> Result<bool, Refusal> {
    asking(db, player)?;
    city_of(db, player)?;
    let mut mine = Table::<Entrant>::get(db, player).ok_or(Refusal::NotInTheLists)?;
    let mut theirs = Table::<Entrant>::get(db, opponent).ok_or(Refusal::NoSuchEntrant)?;
    if theirs.place >= mine.place {
        return Err(Refusal::NotAbove);
    }
    if mine.place - theirs.place > catalog::LISTS_REACH {
        return Err(Refusal::TooFarAbove(catalog::LISTS_REACH));
    }
    let mut tilt = tilt_of(db, player);
    if tilt.tries >= catalog::LISTS_TRIES {
        return Err(Refusal::NoChallengesLeft(catalog::LISTS_TRIES));
    }
    // The places both held as the day's first challenge of each is fought.
    let mut met = tilt_of(db, opponent);
    keep_dawn(&mut tilt, mine.place);
    keep_dawn(&mut met, theirs.place);
    keep_tilt(db, met);
    let (ours, foes) = (band_of(db, player), band_of(db, opponent));
    let learnt = [learnt(db, &mine), learnt(db, &theirs)];
    let mut rolls: Vec<u64> = (0..2 * MOST_ROUNDS).map(|_| db.chance()).collect();
    let outcome = fight_learned(&ours, &foes, learnt, 0, || rolls.pop().unwrap_or(0));
    tilt.tries += 1;
    keep_tilt(db, tilt);
    if outcome.won {
        (mine.place, theirs.place) = (theirs.place, mine.place);
        db.update(mine.clone());
        db.update(theirs.clone());
    }

    let (challenger, challenged) = (name_of(db, player), name_of(db, opponent));
    let fought: u64 = ours.iter().map(|unit| unit.count).sum();
    let stood: u64 = foes.iter().map(|unit| unit.count).sum();
    let (lost, fell): (u64, u64) = (outcome.attackers_lost.iter().sum(), outcome.defenders_lost.iter().sum());
    let how = format!(
        "of your {} soldiers {} fell, of their {} {}",
        catalog::grouped(fought),
        catalog::grouped(lost),
        catalog::grouped(stood),
        catalog::grouped(fell)
    );
    let (to_challenger, to_challenged) = if outcome.won {
        (
            format!("You challenged {challenged} in the Lists and won: {how}. You take their place, the {}.", placed(mine.place)),
            format!("{challenger} challenged you in the Lists and won. You go down to the {} place. None of yours were lost.", placed(theirs.place)),
        )
    } else {
        (
            format!("You challenged {challenged} in the Lists and were beaten: {how}. You keep your place, the {}.", placed(mine.place)),
            format!("{challenger} challenged you in the Lists, and your band held. You keep your place, the {}.", placed(theirs.place)),
        )
    };
    let now = db.now();
    for (to, foe, won, words, fought, stood, fell) in [
        (player, opponent, outcome.won, to_challenger, fought, stood, fell),
        (opponent, player, !outcome.won, to_challenged, stood, fought, lost),
    ] {
        let hex = city_of(db, to).map(|city| city.hex).unwrap_or(0);
        report(
            db,
            Report {
                id: 0,
                player: to,
                at: now,
                kind: Report::LISTS,
                hex,
                won,
                foe,
                rounds: outcome.rounds,
                fought,
                wounded: 0,
                dead: 0,
                stood,
                fell,
                grain: 0,
                timber: 0,
                stone: 0,
                moonsalt: 0,
                words,
                read: false,
            },
        );
    }
    Ok(outcome.won)
}

fn name_of(db: &impl Db, player: u64) -> String {
    Table::<Player>::get(db, player).map(|row| row.name).unwrap_or_default()
}

/// A player forgotten leaves the Lists: their band goes, and everyone below
/// them comes up a place, so the standing has no gap.
pub(super) fn leave_lists(db: &mut impl Db, player: u64) {
    let Some(gone) = Table::<Entrant>::get(db, player) else { return };
    for guard in Table::<Guard>::by(db, 0, player) {
        Table::<Guard>::delete(db, guard.key);
    }
    Table::<Entrant>::delete(db, player);
    for mut below in Table::<Entrant>::all(db).into_iter().filter(|entrant| entrant.place > gone.place) {
        below.place -= 1;
        db.update(below);
    }
}

/// A place in the standing in words: "1st", "12th", "23rd".
fn placed(place: u64) -> String {
    let suffix = match (place % 10, place % 100) {
        (_, 11..=13) => "th",
        (1, _) => "st",
        (2, _) => "nd",
        (3, _) => "rd",
        _ => "th",
    };
    format!("{place}{suffix}")
}

/// A player in the Lists claims the purse of their place, once a day of
/// the realm: goods into their city and honour.
pub fn claim_purse(db: &mut impl Db, player: u64) -> Result<(Goods, u64), Refusal> {
    asking(db, player)?;
    let city = city_of(db, player)?;
    let entrant = Table::<Entrant>::get(db, player).ok_or(Refusal::NotInTheLists)?;
    let mut tilt = tilt_of(db, player);
    if tilt.claimed == tilt.day + 1 {
        return Err(Refusal::PurseClaimed);
    }
    // By the place held as the day's first challenge was fought, where one
    // has been: a place won today pays tomorrow, so no place's purse is
    // paid twice in a day by passing it from hand to hand.
    let place = if tilt.dawn_day == tilt.day + 1 { tilt.dawn } else { entrant.place };
    let (gives, honour) = catalog::lists_purse(place);
    let mut stock = settle(db, city.id)?;
    let more = goods(&stock).plus(gives);
    set_goods(&mut stock, more);
    db.update(stock);
    honoured_for_lists(db, player, honour);
    tilt.claimed = tilt.day + 1;
    keep_tilt(db, tilt);
    Ok((gives, honour))
}
