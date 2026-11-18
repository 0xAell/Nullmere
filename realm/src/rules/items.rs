//! What a player keeps in their satchel: hastes, each taking so much time
//! off a work under way in their city when it is used; peace, keeping
//! their city from attack for a while; and crates of goods, which no army
//! can carry off until they are opened into the city. The day's chests,
//! the contests' prizes and the alliance's stores hold them.

use super::{asking, city_of, did, goods, realm, set_goods, settle, Refusal, TIMER_JOB};
use crate::catalog::{self, Deed, Goods, Item};
use crate::rows::{City, Db, Draught, Job, March, Muster, Rally, Satchel, Ware};
use crate::store::Table;

/// Writes the items out as rows, for clients to show, as the realm opens.
pub fn write_wares(db: &mut impl Db) {
    for item in Item::ALL {
        let kind = if item.is_peace() {
            Ware::PEACE
        } else if item.is_material() {
            Ware::MATERIAL
        } else if item.is_tome() {
            Ware::TOME
        } else if item.is_summons() {
            Ware::SUMMONS
        } else if item.is_crate() {
            Ware::CRATE
        } else if item.is_draught() {
            Ware::DRAUGHT
        } else {
            Ware::HASTE
        };
        db.insert(Ware { item: item as u64, name: item.name().to_string(), words: item.words(), seconds: item.seconds(), kind });
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

/// So many of an item are taken from a player who has them.
pub(super) fn take(db: &mut impl Db, player: u64, item: Item, count: u64) {
    let have = held(db, player, item);
    keep(db, player, item, have.saturating_sub(count));
}

/// A player is given so many of an item.
pub fn give(db: &mut impl Db, player: u64, item: Item, count: u64) {
    let have = held(db, player, item);
    keep(db, player, item, have.saturating_add(count));
}

/// A player uses one of an item on a work under way in their own city:
/// it ends that much sooner, or at once if less than that was left.
pub fn use_item(db: &mut impl Db, player: u64, item: u8, job: u64) -> Result<Job, Refusal> {
    asking(db, player)?;
    let city = city_of(db, player)?;
    let item = Item::of(item).ok_or(Refusal::NoSuchItem)?;
    if item.is_peace() {
        return Err(Refusal::NotAHaste);
    }
    if item.is_material() {
        return Err(Refusal::AtTheForge);
    }
    if item.is_tome() {
        return Err(Refusal::ForACommander);
    }
    if item.is_summons() {
        return Err(Refusal::AtTheTavern);
    }
    if item.is_crate() {
        return Err(Refusal::ToBeOpened);
    }
    if item.is_draught() {
        return Err(Refusal::ToBeDrunk);
    }
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

/// The most crates opened at once.
pub const MOST_OPENED: u64 = 100;

/// A player opens so many of a crate they keep: what they hold goes into
/// their city's stock, though it overfill it, as a chest's does. What went
/// in.
pub fn open_crates(db: &mut impl Db, player: u64, item: u8, count: u64) -> Result<Goods, Refusal> {
    asking(db, player)?;
    let city = city_of(db, player)?;
    let item = Item::of(item).filter(|item| item.is_crate()).ok_or(Refusal::NotACrate)?;
    if count == 0 {
        return Err(Refusal::NothingAsked);
    }
    if count > MOST_OPENED {
        return Err(Refusal::TooMany(MOST_OPENED));
    }
    if held(db, player, item) < count {
        return Err(Refusal::NoneLeft);
    }
    let mut stock = settle(db, city.id)?;
    let opened = item.goods().times(count);
    let more = goods(&stock).plus(opened);
    set_goods(&mut stock, more);
    db.update(stock);
    take(db, player, item, count);
    Ok(opened)
}

/// Whether any of a player's armies is out against a city: sent to attack
/// one, or in a rally against one, and not yet on its way home.
fn against_a_city(db: &impl Db, player: u64) -> bool {
    Table::<March>::by(db, 0, player).into_iter().filter(|march| march.state != March::RETURNING).any(|march| match march.kind {
        March::ATTACK => true,
        March::RALLY => Table::<Muster>::get(db, march.id).and_then(|muster| Table::<Rally>::get(db, muster.rally)).is_some_and(|rally| rally.city != 0),
        _ => false,
    })
}

/// A player uses one of an item of peace on their city: no army may
/// attack it for so long from now, at the realm's pace. Not while any of
/// their armies is out against a city, and not where the city is already
/// at peace for longer.
pub fn keep_peace(db: &mut impl Db, player: u64, item: u8) -> Result<City, Refusal> {
    asking(db, player)?;
    let mut city = city_of(db, player)?;
    let item = Item::of(item).ok_or(Refusal::NoSuchItem)?;
    if item.is_material() {
        return Err(Refusal::AtTheForge);
    }
    if !item.is_peace() {
        return Err(Refusal::NotPeace);
    }
    let have = held(db, player, item);
    if have == 0 {
        return Err(Refusal::NoneLeft);
    }
    if against_a_city(db, player) {
        return Err(Refusal::AttacksUnderWay);
    }
    let now = db.now();
    let until = now + catalog::paced(item.seconds(), realm(db)?.pace).max(1);
    if city.shield >= until {
        return Err(Refusal::AtPeaceLonger(city.shield - now));
    }
    keep(db, player, item, have - 1);
    city.shield = until;
    db.update(city.clone());
    Ok(city)
}

/// The longest a draught's kind may last from now, drunk on and on: three
/// days, at the realm's pace.
pub const DRAUGHT_LONGEST: i64 = 3 * catalog::DAY;

/// A player drinks one of a draught they keep: what it lends their city
/// lasts so long from now, at the realm's pace, or so much longer than
/// one of its kind drunk before would, but never longer than three days
/// from now.
pub fn drink(db: &mut impl Db, player: u64, item: u8) -> Result<Draught, Refusal> {
    asking(db, player)?;
    city_of(db, player)?;
    let item = Item::of(item).ok_or(Refusal::NoSuchItem)?;
    if item.is_material() {
        return Err(Refusal::AtTheForge);
    }
    if !item.is_draught() {
        return Err(Refusal::NotADraught);
    }
    let have = held(db, player, item);
    if have == 0 {
        return Err(Refusal::NoneLeft);
    }
    let now = db.now();
    let pace = realm(db)?.pace;
    let key = Draught::key(player, item);
    let kept = Table::<Draught>::get(db, key);
    let from = kept.as_ref().map(|row| row.ends).unwrap_or(now).max(now);
    let ends = from + catalog::paced(item.seconds(), pace).max(1);
    let longest = catalog::paced(DRAUGHT_LONGEST, pace);
    if ends - now > longest {
        return Err(Refusal::DraughtLasting(from - now));
    }
    keep(db, player, item, have - 1);
    let row = Draught { key, player, item: item as u8, ends };
    if kept.is_some() {
        db.update(row.clone());
    } else {
        db.insert(row.clone());
    }
    Ok(row)
}

/// The levels of a study the draughts a city's owner has drunk lend it,
/// while they last.
pub fn drunk(db: &impl Db, city: u64, topic: catalog::Topic) -> u32 {
    let Some(owner) = Table::<City>::get(db, city).map(|city| city.owner) else { return 0 };
    let now = db.now();
    Table::<Draught>::by(db, 0, owner)
        .into_iter()
        .filter(|draught| draught.ends > now)
        .filter_map(|draught| Item::of(draught.item))
        .flat_map(|item| item.lends().iter())
        .filter(|(lent, _)| *lent == topic)
        .map(|(_, levels)| levels)
        .sum()
}
