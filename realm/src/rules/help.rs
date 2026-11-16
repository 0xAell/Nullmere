//! Help: a player asks their alliance's help with a work under way in
//! their city, and each ally may help with it once. A help takes a
//! hundredth off what is left of the work, or a minute where that is
//! more; a higher Embassy lets more allies help with each work.

use super::{asking, building_of, city_of, member_of, realm, shown_name, Refusal, TIMER_JOB};
use crate::catalog::{self, Building as Kind};
use crate::rows::{Db, Helper, Job, Plea, Player};
use crate::store::Table;

/// A player asks their alliance's help with a work in their own city.
pub fn ask_help(db: &mut impl Db, player: u64, job: u64) -> Result<Plea, Refusal> {
    asking(db, player)?;
    let member = member_of(db, player).ok_or(Refusal::NotAllied)?;
    let city = city_of(db, player)?;
    let job = Table::<Job>::get(db, job)
        .filter(|row| row.city == city.id && matches!(row.kind, Job::RAISE | Job::STUDY | Job::TRAIN | Job::HEAL))
        .ok_or(Refusal::NoSuchJob)?;
    if Table::<Plea>::get(db, job.id).is_some() {
        return Err(Refusal::HelpAsked);
    }
    let embassy = building_of(db, city.id, Kind::Embassy).map(|building| building.level).unwrap_or(0);
    let name = Table::<Player>::get(db, player).map(|row| shown_name(db, &row)).unwrap_or_default();
    Ok(db.insert(Plea { job: job.id, alliance: member.alliance, asker: player, name, work: job.kind, helped: 0, most: catalog::helps(embassy) }))
}

/// Whether a player may help with a work: it is their alliance's, not
/// their own, they have not helped with it, and it may still be helped.
fn may_help(db: &impl Db, player: u64, plea: &Plea) -> Result<(), Refusal> {
    if plea.asker == player {
        return Err(Refusal::YourOwnWork);
    }
    if Table::<Helper>::get(db, Helper::key(plea.job, player)).is_some() {
        return Err(Refusal::AlreadyHelped);
    }
    if plea.helped >= plea.most {
        return Err(Refusal::HelpedEnough);
    }
    Ok(())
}

/// Takes a help's time off a work, and marks who gave it.
fn give(db: &mut impl Db, player: u64, mut plea: Plea) {
    let Some(mut job) = Table::<Job>::get(db, plea.job) else { return forget_plea(db, plea.job) };
    let now = db.now();
    let pace = realm(db).map(|realm| realm.pace).unwrap_or(1);
    let left = (job.ends - now).max(0);
    let off = (left / 100).max(catalog::paced(catalog::HELP_SECONDS, pace).max(1));
    db.cancel(job.timer);
    job.ends = (job.ends - off).max(now + 1).min(job.ends);
    job.timer = db.after(job.ends, TIMER_JOB, job.id);
    db.update(job);
    plea.helped += 1;
    db.insert(Helper { id: Helper::key(plea.job, player), job: plea.job, player });
    db.update(plea);
    super::honoured_for_help(db, player);
}

/// A player helps with an ally's work.
pub fn help(db: &mut impl Db, player: u64, job: u64) -> Result<u32, Refusal> {
    asking(db, player)?;
    let member = member_of(db, player).ok_or(Refusal::NotAllied)?;
    let plea = Table::<Plea>::get(db, job).filter(|plea| plea.alliance == member.alliance).ok_or(Refusal::NoSuchPlea)?;
    may_help(db, player, &plea)?;
    give(db, player, plea);
    Ok(1)
}

/// A player helps with every work of their alliance's that they may:
/// how many, which may be none.
pub fn help_all(db: &mut impl Db, player: u64) -> Result<u32, Refusal> {
    asking(db, player)?;
    let member = member_of(db, player).ok_or(Refusal::NotAllied)?;
    let mut helped = 0;
    for plea in Table::<Plea>::by(db, 0, member.alliance) {
        if may_help(db, player, &plea).is_ok() {
            give(db, player, plea);
            helped += 1;
        }
    }
    Ok(helped)
}

/// A work is done, or gone: so is the asking for help with it.
pub(super) fn forget_plea(db: &mut impl Db, job: u64) {
    if Table::<Plea>::get(db, job).is_none() {
        return;
    }
    for helper in Table::<Helper>::by(db, 0, job) {
        Table::<Helper>::delete(db, helper.id);
    }
    Table::<Plea>::delete(db, job);
}
