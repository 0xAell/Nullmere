//! Merits: what a player has done over all their days. Every deed the
//! day's work counts (soldiers trained, goods gathered, barrows cleared,
//! works begun and hastened) is kept on the player's record as well, and
//! each deed has four tiers of merit, each reached by doing so much more
//! of it; a tier reached is claimed once, for goods and, from the second,
//! an item.

use super::{asking, city_of, give, goods, set_goods, settle, Refusal};
use crate::catalog::{self, Deed, Goods};
use crate::rows::{Db, Merit, Record};
use crate::store::Table;

/// Writes the tiers of merit out as rows, for clients to show, as the
/// realm opens.
pub fn write_merits(db: &mut impl Db) {
    for deed in Deed::ALL {
        for tier in 1..=catalog::MERIT_TIERS {
            let (goal, gives, item) = catalog::merit(deed, tier);
            let (item, items) = item.map(|(item, count)| (item as u8, count)).unwrap_or((0, 0));
            db.insert(Merit {
                id: Merit::key(deed as u8, tier),
                deed: deed as u8,
                tier,
                name: deed.merit_name().to_string(),
                words: deed.merit_words().to_string(),
                goal,
                grain: gives.grain,
                timber: gives.timber,
                stone: gives.stone,
                item,
                items,
            });
        }
    }
}

/// A player's record of a deed.
pub fn record_of(db: &impl Db, player: u64, deed: Deed) -> Record {
    Table::<Record>::get(db, Record::key(player, deed as u8)).unwrap_or(Record { key: Record::key(player, deed as u8), player, deed: deed as u8, done: 0, claimed: 0 })
}

fn keep(db: &mut impl Db, record: Record) {
    if Table::<Record>::get(db, record.key).is_some() {
        db.update(record);
    } else {
        db.insert(record);
    }
}

/// So much more of a deed done, kept on the player's record.
pub(super) fn recorded(db: &mut impl Db, player: u64, deed: Deed, amount: u64) {
    if amount == 0 {
        return;
    }
    let mut record = record_of(db, player, deed);
    record.done = record.done.saturating_add(amount);
    keep(db, record);
}

/// A player claims the next tier of merit of a deed, once they have done
/// enough of it: its goods into their city, its item into their satchel.
/// The tier claimed, and what it gave.
pub fn claim_merit(db: &mut impl Db, player: u64, deed: u8) -> Result<(u32, Goods), Refusal> {
    asking(db, player)?;
    let city = city_of(db, player)?;
    let deed = Deed::of(deed).ok_or(Refusal::NoSuchMerit)?;
    let mut record = record_of(db, player, deed);
    let tier = record.claimed + 1;
    if tier > catalog::MERIT_TIERS {
        return Err(Refusal::MeritsClaimed);
    }
    let (goal, gives, item) = catalog::merit(deed, tier);
    if record.done < goal {
        return Err(Refusal::MeritNotReached(record.done, goal));
    }
    let mut stock = settle(db, city.id)?;
    let more = goods(&stock).plus(gives);
    set_goods(&mut stock, more);
    db.update(stock);
    if let Some((item, count)) = item {
        give(db, player, item, count);
    }
    record.claimed = tier;
    keep(db, record);
    Ok((tier, gives))
}
