//! A player's first tasks: a chain that leads a new city through its
//! first buildings, soldiers and fights, each giving goods when done, and
//! some hastes or tomes of war besides.

use super::{asking, building_of, city_of, give, goods, member_of, set_goods, settle, squads, Refusal};
use crate::catalog::{self, Goal, Goods, Item};
use crate::rows::{Db, Find, Hunt, March, Progress, Task, Troop};
use crate::store::Table;

/// Writes the tasks out as rows, for clients to show, as the realm opens.
pub fn write_tasks(db: &mut impl Db) {
    for (index, (goal, gives)) in catalog::tasks().into_iter().enumerate() {
        let (kind, amount, level) = goal.numbers();
        let step = index as u64 + 1;
        let items = catalog::task_items(step);
        let count = |item: Item| items.iter().filter(|(given, _)| *given == item).map(|(_, count)| count).sum();
        db.insert(Task {
            step,
            goal: kind,
            amount,
            level,
            words: goal.words(),
            grain: gives.grain,
            timber: gives.timber,
            stone: gives.stone,
            moonsalt: gives.moonsalt,
            brief_hastes: count(Item::Haste5),
            hour_hastes: count(Item::Haste60),
            long_hastes: count(Item::Haste480),
            tomes: count(Item::Tome),
        });
    }
}

/// The task a player is on: the first, until they have claimed one.
pub fn progress_of(db: &impl Db, player: u64) -> Progress {
    Table::<Progress>::get(db, player).unwrap_or(Progress { player, step: 1 })
}

/// Whether a player's city has done what a goal asks.
pub fn met(db: &impl Db, player: u64, goal: Goal) -> bool {
    let Ok(city) = city_of(db, player) else { return false };
    match goal {
        Goal::Keep(level) => city.keep >= level,
        Goal::Raised(building, level) => building_of(db, city.id, building).is_some_and(|raised| raised.level >= level),
        Goal::Soldiers(count) => {
            let home: u64 = Table::<Troop>::by(db, 0, city.id).iter().map(|row| row.ready + row.wounded).sum();
            let out: u64 = Table::<March>::by(db, 1, city.id).iter().flat_map(|march| squads(db, march.id)).map(|squad| squad.count + squad.wounded).sum();
            home + out >= count
        }
        Goal::Cleared(level) => Table::<Hunt>::get(db, player).is_some_and(|hunt| hunt.cleared >= level),
        Goal::Allied => member_of(db, player).is_some(),
        Goal::Power(power) => city.power >= power,
        Goal::Found(count) => Table::<Find>::by(db, 0, player).len() as u64 >= count,
    }
}

/// A player claims the task they are on: if their city has done what it
/// asks, the goods it gives go into their stock (though they overfill
/// it), its hastes and tomes into their satchel, and the next task is set.
pub fn claim_task(db: &mut impl Db, player: u64) -> Result<Goods, Refusal> {
    asking(db, player)?;
    let city = city_of(db, player)?;
    let mut progress = progress_of(db, player);
    let all = catalog::tasks();
    let Some((goal, gives)) = all.get(progress.step.saturating_sub(1) as usize).copied() else {
        return Err(Refusal::NoTasksLeft);
    };
    if !met(db, player, goal) {
        return Err(Refusal::TaskNotDone(goal.words()));
    }
    let mut stock = settle(db, city.id)?;
    let more = goods(&stock).plus(gives);
    set_goods(&mut stock, more);
    db.update(stock);
    for (item, count) in catalog::task_items(progress.step) {
        give(db, player, item, count);
    }
    progress.step += 1;
    if Table::<Progress>::get(db, player).is_some() {
        db.update(progress);
    } else {
        db.insert(progress);
    }
    Ok(gives)
}
