//! The realm's contests: each comes round every so many days and runs
//! for the first few of them. While one runs, what it is for scores
//! points; a player who has scored enough claims its prizes, once each a
//! round, until it comes round again.

use super::{asking, city_of, give, goods, set_goods, settle, today, Refusal};
use crate::catalog::{Contest, Goods, Item};
use crate::rows::{Db, Prize, Tally, Trial};
use crate::store::Table;

/// Writes the contests and their prizes out as rows, for clients to show,
/// as the realm opens.
pub fn write_trials(db: &mut impl Db) {
    for contest in Contest::ALL {
        let (every, lasts, opens) = contest.round();
        db.insert(Trial { id: contest as u64, name: contest.name().to_string(), words: contest.words().to_string(), every, lasts, opens });
        for (index, (points, gives, items)) in contest.prizes().into_iter().enumerate() {
            let count = |item: Item| items.iter().filter(|(held, _)| *held == item).map(|(_, count)| count).sum();
            let place = index as u8 + 1;
            db.insert(Prize {
                id: Prize::key(contest as u8, place),
                trial: contest as u8,
                place,
                points,
                grain: gives.grain,
                timber: gives.timber,
                stone: gives.stone,
                moonsalt: gives.moonsalt,
                brief_hastes: count(Item::Haste5),
                hour_hastes: count(Item::Haste60),
                long_hastes: count(Item::Haste480),
            });
        }
    }
}

/// Which coming-round of a contest today falls in, and whether the
/// contest is running today.
pub fn round_of(db: &impl Db, contest: Contest) -> (u64, bool) {
    let (every, lasts, opens) = contest.round();
    let day = today(db);
    let into = day % every;
    (day / every, into >= opens && into < opens + lasts)
}

/// What a player has scored in a contest this round: nothing, if what is
/// kept is of an earlier one.
pub fn tally_of(db: &impl Db, player: u64, contest: Contest) -> Tally {
    let (round, _) = round_of(db, contest);
    let id = Tally::key(player, contest as u8);
    Table::<Tally>::get(db, id).filter(|row| row.round == round).unwrap_or(Tally { id, player, trial: contest as u8, round, points: 0, claimed: 0 })
}

fn keep(db: &mut impl Db, row: Tally) {
    if Table::<Tally>::get(db, row.id).is_some() {
        db.update(row);
    } else {
        db.insert(row);
    }
}

/// A player has done what a contest is for: it scores, if the contest is
/// running.
pub(super) fn scored(db: &mut impl Db, player: u64, contest: Contest, points: u64) {
    if !round_of(db, contest).1 || points == 0 {
        return;
    }
    let mut row = tally_of(db, player, contest);
    row.points = row.points.saturating_add(points);
    keep(db, row);
}

/// A player claims a prize of a contest: if they have scored the points
/// it asks this round and have not claimed it, its goods go into their
/// stock, though it overfill it, and its hastes into their satchel.
pub fn claim_prize(db: &mut impl Db, player: u64, contest: u8, place: u8) -> Result<Goods, Refusal> {
    asking(db, player)?;
    let city = city_of(db, player)?;
    let contest = Contest::of(contest).ok_or(Refusal::NoSuchPrize)?;
    let prizes = contest.prizes();
    if place > 8 {
        return Err(Refusal::NoSuchPrize);
    }
    let (asks, gives, items) = prizes.get((place as usize).wrapping_sub(1)).cloned().ok_or(Refusal::NoSuchPrize)?;
    let mut row = tally_of(db, player, contest);
    let bit = 1u8 << (place - 1);
    if row.claimed & bit != 0 {
        return Err(Refusal::PrizeClaimed);
    }
    if row.points < asks {
        return Err(Refusal::PrizeNotEarned(asks));
    }
    let mut stock = settle(db, city.id)?;
    let more = goods(&stock).plus(gives);
    set_goods(&mut stock, more);
    db.update(stock);
    for (item, count) in items {
        give(db, player, item, count);
    }
    row.claimed |= bit;
    keep(db, row);
    Ok(gives)
}
