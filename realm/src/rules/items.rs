//! What a player keeps in their satchel: hastes, each taking so much time
//! off a work under way in their city when it is used. The day's chests
//! hold them.

use super::{asking, city_of, did, realm, Refusal, TIMER_JOB};
use crate::catalog::{self, Deed, Item};
use crate::rows::{Db, Job, Satchel, Ware};
use crate::store::Table;

/// Writes the items out as rows, for clients to show, as the realm opens.
pub fn write_wares(db: &mut impl Db) {
    for item in Item::ALL {
        db.insert(Ware { item: item as u64, name: item.name().to_string(), words: item.words(), seconds: item.seconds() });
    }
}

/// How many of an item a player keeps.
pub fn held(db: &impl Db, player: u64, item: Item) -> u64 {
    Table::<Satchel>::get(db, Satchel::key(player, item as u8)).map(|row| row.count).unwrap_or(0)
}

/// Sets how many of an item a player keeps: no row for none.
fn keep(db: &mut impl Db, player: u64, item: Item, count: u64) {
    let id = Satchel::key(player, item as u8);
    let had = Table::<Satchel>::get(db, id).is_some();
    match (had, count) {
        (true, 0) => Table::<Satchel>::delete(db, id),
        (true, _) => db.update(Satchel { id, player, item: item as u8, count }),
        (false, 0) => {}
        (false, _) => {
            db.insert(Satchel { id, player, item: item as u8, count });
        }
    }
}

/// A player is given so many of an item.
pub(super) fn give(db: &mut impl Db, player: u64, item: Item, count: u64) {
    let have = held(db, player, item);
    keep(db, player, item, have.saturating_add(count));
}

/// A player uses one of an item on a work under way in their own city:
/// it ends that much sooner, or at once if less than that was left.
pub fn use_item(db: &mut impl Db, player: u64, item: u8, job: u64) -> Result<Job, Refusal> {
    asking(db, player)?;
    let city = city_of(db, player)?;
    let item = Item::of(item).ok_or(Refusal::NoSuchItem)?;
    let mut job = Table::<Job>::get(db, job)
        .filter(|row| row.city == city.id && matches!(row.kind, Job::RAISE | Job::STUDY | Job::TRAIN | Job::HEAL))
        .ok_or(Refusal::NoSuchJob)?;
    let now = db.now();
    if job.ends - now <= 1 {
        return Err(Refusal::NothingToSpeed);
    }
    let have = held(db, player, item);
    if have == 0 {
        return Err(Refusal::NoneLeft);
    }
    keep(db, player, item, have - 1);

    let off = catalog::paced(item.seconds(), realm(db)?.pace).max(1);
    db.cancel(job.timer);
    job.ends = (job.ends - off).max(now + 1);
    job.timer = db.after(job.ends, TIMER_JOB, job.id);
    db.update(job.clone());
    did(db, player, Deed::Hasten, 1);
    Ok(job)
}
