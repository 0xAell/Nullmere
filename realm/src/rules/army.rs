//! Troops: counted by kind and tier, trained in batches on a timer.

use super::{asking, did, favoured, goods, realm, set_goods, settle, sooner, Refusal, TIMER_JOB};
use crate::catalog::{self, Building as Kind, Deed, Topic, Troops, TOP_TIER};
use crate::rows::{Building, City, Db, Job, Troop};
use crate::store::Table;

/// A city's troops of a kind and tier; none of them if it has none.
pub fn troop(db: &impl Db, city: u64, kind: Troops, tier: u32) -> Troop {
    let id = Troop::key(city, kind as u8, tier);
    Table::<Troop>::get(db, id).unwrap_or(Troop { id, city, kind: kind as u8, tier, ready: 0, wounded: 0 })
}

/// Keeps a city's troops of a kind and tier as they now stand; where none
/// are left, ready or wounded, no row is kept.
pub fn keep_troop(db: &mut impl Db, row: Troop) {
    let kept = Table::<Troop>::get(db, row.id).is_some();
    match (kept, row.ready + row.wounded > 0) {
        (true, true) => db.update(row),
        (true, false) => Table::<Troop>::delete(db, row.id),
        (false, true) => {
            db.insert(row);
        }
        (false, false) => {}
    }
}

/// The power of all a city's troops, ready or wounded.
pub fn troop_power(db: &impl Db, city: u64) -> u64 {
    Table::<Troop>::by(db, 0, city)
        .iter()
        .map(|row| Troops::of(row.kind).map(|kind| kind.soldier(row.tier).power).unwrap_or(0) * (row.ready + row.wounded))
        .sum()
}

/// A player trains a batch of troops of a tier in one of their training
/// buildings: paid for at once, ready when the timer ends.
pub fn train(db: &mut impl Db, player: u64, building: u64, tier: u32, count: u64) -> Result<Job, Refusal> {
    asking(db, player)?;
    let building = Table::<Building>::get(db, building).ok_or(Refusal::NoSuchBuilding)?;
    let city = Table::<City>::get(db, building.city).ok_or(Refusal::NoSuchBuilding)?;
    if city.owner != player {
        return Err(Refusal::NotYours);
    }
    let kind = Kind::of(building.kind).ok_or(Refusal::NoSuchBuilding)?;
    let troops = Troops::trained_by(kind).ok_or(Refusal::TrainsNothing(kind))?;
    if !(1..=TOP_TIER).contains(&tier) {
        return Err(Refusal::NoSuchTroops);
    }
    let jobs = Table::<Job>::by(db, 0, city.id);
    if building.level == 0 || jobs.iter().any(|job| job.kind == Job::RAISE && job.subject == building.id) {
        return Err(Refusal::AlreadyRising(kind));
    }
    if jobs.iter().any(|job| job.kind == Job::TRAIN && job.subject == building.id) {
        return Err(Refusal::AlreadyTraining(kind));
    }
    let soldier = troops.soldier(tier);
    if building.level < soldier.needs_level {
        return Err(Refusal::NeedsOther(kind, soldier.needs_level));
    }
    if count == 0 {
        return Err(Refusal::NothingAsked);
    }
    let most = catalog::batch(building.level);
    if count > most {
        return Err(Refusal::TooMany(most));
    }
    let mut stock = settle(db, city.id)?;
    let cost = soldier.cost.times(count);
    let short = goods(&stock).short_of(cost);
    if !short.is_none() {
        return Err(Refusal::CannotAfford(short));
    }
    let left = goods(&stock).minus(cost);
    set_goods(&mut stock, left);
    db.update(stock);
    let now = db.now();
    let ends = now + favoured(db, player, sooner(db, city.id, Topic::Drill, catalog::paced(soldier.seconds * count as i64, realm(db)?.pace)));
    let mut job = db.insert(Job { id: 0, city: city.id, kind: Job::TRAIN, subject: building.id, level: tier, amount: count, started: now, ends, timer: 0 });
    job.timer = db.after(ends, TIMER_JOB, job.id);
    db.update(job.clone());
    did(db, player, Deed::Train, count);
    super::scored(db, player, crate::catalog::Contest::Arms, count * tier as u64);
    Ok(job)
}

/// A player raises troops of a kind standing ready in their city to a
/// higher tier, in the building that trains them: they pay what the higher
/// tier costs beyond the lower and wait what it takes beyond, the troops
/// out of the ranks until the timer ends, when they stand ready at the
/// higher tier. It counts as training them, for the day's work and the
/// Call to Arms, by the tiers they rise.
pub fn promote(db: &mut impl Db, player: u64, building: u64, from: u32, to: u32, count: u64) -> Result<Job, Refusal> {
    asking(db, player)?;
    let building = Table::<Building>::get(db, building).ok_or(Refusal::NoSuchBuilding)?;
    let city = Table::<City>::get(db, building.city).ok_or(Refusal::NoSuchBuilding)?;
    if city.owner != player {
        return Err(Refusal::NotYours);
    }
    let kind = Kind::of(building.kind).ok_or(Refusal::NoSuchBuilding)?;
    let troops = Troops::trained_by(kind).ok_or(Refusal::TrainsNothing(kind))?;
    if !(1..=TOP_TIER).contains(&from) || !(1..=TOP_TIER).contains(&to) {
        return Err(Refusal::NoSuchTroops);
    }
    if to <= from {
        return Err(Refusal::OnlyHigher);
    }
    let jobs = Table::<Job>::by(db, 0, city.id);
    if building.level == 0 || jobs.iter().any(|job| job.kind == Job::RAISE && job.subject == building.id) {
        return Err(Refusal::AlreadyRising(kind));
    }
    if jobs.iter().any(|job| job.kind == Job::TRAIN && job.subject == building.id) {
        return Err(Refusal::AlreadyTraining(kind));
    }
    let (lower, higher) = (troops.soldier(from), troops.soldier(to));
    if building.level < higher.needs_level {
        return Err(Refusal::NeedsOther(kind, higher.needs_level));
    }
    if count == 0 {
        return Err(Refusal::NothingAsked);
    }
    let most = catalog::batch(building.level);
    if count > most {
        return Err(Refusal::TooMany(most));
    }
    let mut ranks = troop(db, city.id, troops, from);
    if ranks.ready < count {
        return Err(Refusal::NotEnoughTroops(troops, from, ranks.ready));
    }
    let mut stock = settle(db, city.id)?;
    let cost = higher.cost.minus(lower.cost).times(count);
    let short = goods(&stock).short_of(cost);
    if !short.is_none() {
        return Err(Refusal::CannotAfford(short));
    }
    let left = goods(&stock).minus(cost);
    set_goods(&mut stock, left);
    db.update(stock);
    ranks.ready -= count;
    keep_troop(db, ranks);
    // Out of the ranks until they are raised, they count for nothing.
    super::reckon(db, city.id);
    let now = db.now();
    let seconds = (higher.seconds - lower.seconds) * count as i64;
    let ends = now + favoured(db, player, sooner(db, city.id, Topic::Drill, catalog::paced(seconds, realm(db)?.pace)));
    let mut job = db.insert(Job { id: 0, city: city.id, kind: Job::TRAIN, subject: building.id, level: to, amount: count, started: now, ends, timer: 0 });
    job.timer = db.after(ends, TIMER_JOB, job.id);
    db.update(job.clone());
    did(db, player, Deed::Train, count);
    super::scored(db, player, crate::catalog::Contest::Arms, count * (to - from) as u64);
    Ok(job)
}

/// A batch's training is done: the troops stand ready in their city.
pub(super) fn trained(db: &mut impl Db, job: &Job) {
    let Some(building) = Table::<Building>::get(db, job.subject) else { return };
    let Some(kind) = Kind::of(building.kind).and_then(Troops::trained_by) else { return };
    let mut row = troop(db, job.city, kind, job.level);
    row.ready += job.amount;
    keep_troop(db, row);
}
