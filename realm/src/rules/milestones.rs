//! The realm's milestones: what the whole realm does together.
//!
//! Each counts one feat of every player's from the realm's opening, cities
//! founded, barrows cleared, alliances founded or cairns found, and is
//! reached when the realm has done so many; then every player in it may
//! claim what it gives, once: goods into their city and an item into their
//! satchel. Every milestone is for all to read, how near it stands and
//! when it was reached.

use super::{asking, city_of, give, goods, set_goods, settle, Refusal};
use crate::catalog::{self, Feat, Goods, Item};
use crate::rows::{Claim, Db, Milestone};
use crate::store::Table;

/// Writes the milestones out as rows, none of them begun, as the realm opens.
pub fn write_milestones(db: &mut impl Db) {
    for (id, feat, goal, words, gives, item, items) in catalog::milestones() {
        db.insert(Milestone {
            id,
            feat: feat as u8,
            goal,
            done: 0,
            reached: 0,
            words: words.to_string(),
            grain: gives.grain,
            timber: gives.timber,
            stone: gives.stone,
            item: item as u8,
            items,
        });
    }
}

/// The realm has done a feat once more: each milestone not yet reached
/// that counts it is a step nearer, and reached at its goal.
pub fn feat_done(db: &mut impl Db, feat: Feat) {
    let now = db.now();
    for mut milestone in Table::<Milestone>::all(db).into_iter().filter(|milestone| milestone.feat == feat as u8 && milestone.reached == 0) {
        milestone.done += 1;
        if milestone.done >= milestone.goal {
            milestone.reached = now;
        }
        db.update(milestone);
    }
}

/// A player claims what a milestone the realm has reached gives. The goods.
pub fn claim_milestone(db: &mut impl Db, player: u64, milestone: u64) -> Result<Goods, Refusal> {
    asking(db, player)?;
    let city = city_of(db, player)?;
    let row = Table::<Milestone>::get(db, milestone).ok_or(Refusal::NoSuchMilestone)?;
    if row.reached == 0 {
        return Err(Refusal::MilestoneNotReached);
    }
    let key = Claim::key(player, milestone);
    if Table::<Claim>::get(db, key).is_some() {
        return Err(Refusal::MilestoneClaimed);
    }
    let gives = Goods::of(row.grain, row.timber, row.stone, 0);
    let mut stock = settle(db, city.id)?;
    let more = goods(&stock).plus(gives);
    set_goods(&mut stock, more);
    db.update(stock);
    if let Some(item) = Item::of(row.item) {
        give(db, player, item, row.items);
    }
    let at = db.now();
    db.insert(Claim { key, player, milestone, at });
    Ok(gives)
}
