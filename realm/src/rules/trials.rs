//! The realm's contests: each comes round every so many days and runs
//! for the first few of them. While one runs, what it is for scores
//! points; a player who has scored enough claims its prizes, once each a
//! round, until it comes round again.

use super::{asking, city_of, give, goods, set_goods, settle, today, Refusal};
use crate::catalog::{Contest, Goods, Item};
use crate::rows::{Db, Laurel, Prize, Standing, Tally, Trial};
use crate::store::Table;

/// How many of a round's first places are given laurels.
pub const PLACES: usize = 3;

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
                peaces: count(Item::Peace8),
            });
        }
        for (index, (gives, items)) in contest.laurels().into_iter().enumerate() {
            let count = |item: Item| items.iter().filter(|(held, _)| *held == item).map(|(_, count)| count).sum();
            let place = index as u8 + 1;
            db.insert(Laurel {
                id: Prize::key(contest as u8, place),
                trial: contest as u8,
                place,
                grain: gives.grain,
                timber: gives.timber,
                stone: gives.stone,
                moonsalt: gives.moonsalt,
                brief_hastes: count(Item::Haste5),
                hour_hastes: count(Item::Haste60),
                long_hastes: count(Item::Haste480),
                peaces: count(Item::Peace8),
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
    let (round, total) = (row.round, row.points);
    keep(db, row);
    // And where they stand, for all to read.
    let id = Standing::key(player, contest as u8, round);
    let now = db.now();
    match Table::<Standing>::get(db, id) {
        Some(mut standing) => {
            standing.points = total;
            standing.at = now;
            db.update(standing);
        }
        None => {
            db.insert(Standing { id, contest_round: Standing::of_round(contest as u8, round), player, trial: contest as u8, round, points: total, at: now, claimed: false });
            // What they stood at two rounds ago is past claiming.
            if round >= 2 {
                Table::<Standing>::delete(db, Standing::key(player, contest as u8, round - 2));
            }
        }
    }
}

/// The standings of a contest's round, the first first: the most points,
/// and among equal points who reached them first.
pub fn standings(db: &impl Db, contest: Contest, round: u64) -> Vec<Standing> {
    let mut all = Table::<Standing>::by(db, 0, Standing::of_round(contest as u8, round));
    all.sort_by_key(|standing| (std::cmp::Reverse(standing.points), standing.at, standing.player));
    all
}

/// The last round of a contest that is over: none before the first ends.
pub fn last_round_over(db: &impl Db, contest: Contest) -> Option<u64> {
    let (every, lasts, opens) = contest.round();
    let day = today(db);
    let round = day / every;
    if day % every >= opens + lasts {
        Some(round)
    } else {
        round.checked_sub(1)
    }
}

/// A player claims what their place among the first three of a
/// contest's last round over gives: its goods into their stock, though it
/// overfill it, and its hastes into their satchel; once, until another
/// round is over.
pub fn claim_place(db: &mut impl Db, player: u64, contest: u8) -> Result<Goods, Refusal> {
    asking(db, player)?;
    let city = city_of(db, player)?;
    let contest = Contest::of(contest).ok_or(Refusal::NoSuchPrize)?;
    let round = last_round_over(db, contest).ok_or(Refusal::NoRoundOver)?;
    let first = standings(db, contest, round);
    let place = first.iter().take(PLACES).position(|standing| standing.player == player).ok_or(Refusal::NotPlaced)?;
    let mut standing = first[place].clone();
    if standing.claimed {
        return Err(Refusal::PlaceClaimed);
    }
    let (gives, items) = contest.laurels()[place].clone();
    let mut stock = settle(db, city.id)?;
    let more = goods(&stock).plus(gives);
    set_goods(&mut stock, more);
    db.update(stock);
    for (item, count) in items {
        give(db, player, item, count);
    }
    standing.claimed = true;
    db.update(standing);
    Ok(gives)
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
