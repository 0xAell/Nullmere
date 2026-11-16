//! Gifts within an alliance: as a member clears a barrow or wins a rally
//! against one, every other member is given goods, to claim within a day.

use super::{asking, goods, set_goods, settle, Refusal};
use crate::catalog::Goods;
use crate::rows::{Boon, Db, Member};
use crate::store::{Seconds, Table};

pub const TIMER_BOON: u8 = 7;
/// How long a gift waits to be claimed, in seconds of the realm's clock.
pub const BOON_LASTS: Seconds = 86_400;
/// The most gifts kept waiting on one member: the oldest go first.
pub const BOONS_KEPT: usize = 50;

/// What a gift from a barrow of a level holds: two hundred of each of
/// grain, timber and stone a level.
pub fn boon_of(level: u32) -> Goods {
    let each = 200 * level as u64;
    Goods::of(each, each, each, 0)
}

/// A member cleared a barrow of a level: every other member of their
/// alliance is given a gift of it. Nothing for one in no alliance.
pub fn give_boons(db: &mut impl Db, giver: u64, level: u32) {
    let Some(alliance) = super::member_of(db, giver).map(|member| member.alliance) else { return };
    let gift = boon_of(level);
    let now = db.now();
    for member in Table::<Member>::by(db, 0, alliance) {
        if member.player == giver {
            continue;
        }
        let mut waiting = Table::<Boon>::by(db, 0, member.player);
        if waiting.len() >= BOONS_KEPT {
            waiting.sort_by_key(|boon| boon.id);
            for oldest in &waiting[..=waiting.len() - BOONS_KEPT] {
                Table::<Boon>::delete(db, oldest.id);
            }
        }
        let mut boon = db.insert(Boon {
            id: 0,
            player: member.player,
            giver,
            level,
            grain: gift.grain,
            timber: gift.timber,
            stone: gift.stone,
            expires: now + BOON_LASTS,
            timer: 0,
        });
        boon.timer = db.after(boon.expires, TIMER_BOON, boon.id);
        db.update(boon);
    }
}

/// A player claims every gift waiting on them: their goods come into
/// their city, as much as it holds. What they came to, together.
pub fn claim_boons(db: &mut impl Db, player: u64) -> Result<Goods, Refusal> {
    asking(db, player)?;
    let waiting = Table::<Boon>::by(db, 0, player);
    if waiting.is_empty() {
        return Err(Refusal::NoBoons);
    }
    let city = super::city_of(db, player)?;
    let all = waiting.iter().fold(Goods::NONE, |sum, boon| sum.plus(Goods::of(boon.grain, boon.timber, boon.stone, 0)));
    let mut stock = settle(db, city.id)?;
    let more = goods(&stock).plus(all);
    set_goods(&mut stock, more);
    db.update(stock);
    for boon in waiting {
        db.cancel(boon.timer);
        Table::<Boon>::delete(db, boon.id);
    }
    Ok(all)
}

/// A gift's day is over: it is gone, unclaimed.
pub(super) fn boon_gone(db: &mut impl Db, boon: u64) {
    Table::<Boon>::delete(db, boon);
}
