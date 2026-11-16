//! What an alliance learns together.
//!
//! Its members give grain, timber and stone toward the next level of any
//! of the topics a city studies at its Academy. When what they have given
//! pays for that level, the alliance studies it for a while, and then
//! every member has it as if they had learnt one more level of the topic
//! in their own city: their works bring in more, their soldiers fight
//! harder, they build and train and march sooner, as the topic says.
//! Five levels at most of each. A member who leaves has none of it.

use super::{asking, city_of, goods, member_of, realm, reckon_player, report, set_goods, settle, Refusal};
use crate::catalog::{self, Goods, Topic, TOP_ALLIANCE_STUDY};
use crate::rows::{City, Db, Learning, Member, Report};
use crate::store::Table;

pub const TIMER_LEARNING: u8 = 5;

/// What an alliance has learnt of a topic, or a fresh page of it.
pub fn learning_of(db: &impl Db, alliance: u64, topic: Topic) -> Learning {
    let id = Learning::key(alliance, topic as u8);
    Table::<Learning>::get(db, id).unwrap_or(Learning { id, alliance, topic: topic as u8, level: 0, rises_at: 0, timer: 0, grain: 0, timber: 0, stone: 0 })
}

/// The levels of a topic a city has from its owner's alliance.
pub fn learnt_together(db: &impl Db, city: u64, topic: Topic) -> u32 {
    let Some(owner) = Table::<City>::get(db, city).map(|city| city.owner) else { return 0 };
    let Some(member) = member_of(db, owner) else { return 0 };
    Table::<Learning>::get(db, Learning::key(member.alliance, topic as u8)).map(|learning| learning.level).unwrap_or(0)
}

fn given(learning: &Learning) -> Goods {
    Goods::of(learning.grain, learning.timber, learning.stone, 0)
}

fn keep(db: &mut impl Db, learning: Learning) {
    if Table::<Learning>::get(db, learning.id).is_some() {
        db.update(learning);
    } else {
        db.insert(learning);
    }
}

/// A member gives goods from their city toward the next level of a topic
/// their alliance learns. Only what that level still needs is taken; if
/// it is paid for, the alliance begins to study it.
pub fn give_to_learning(db: &mut impl Db, player: u64, topic: u8, gift: Goods) -> Result<Learning, Refusal> {
    asking(db, player)?;
    let member = member_of(db, player).ok_or(Refusal::NotAllied)?;
    let topic = Topic::of(topic).ok_or(Refusal::NoSuchTopic)?;
    let gift = Goods::of(gift.grain, gift.timber, gift.stone, 0);
    if gift.is_none() {
        return Err(Refusal::NothingAsked);
    }
    let mut learning = learning_of(db, member.alliance, topic);
    if learning.level >= TOP_ALLIANCE_STUDY {
        return Err(Refusal::LearntTogether);
    }
    if learning.rises_at != 0 {
        return Err(Refusal::StudiedTogether);
    }
    let cost = catalog::alliance_study_cost(learning.level + 1);
    let still = Goods::from_parts([0, 1, 2, 3].map(|part| cost.parts()[part].saturating_sub(given(&learning).parts()[part])));
    let taken = Goods::from_parts([0, 1, 2, 3].map(|part| gift.parts()[part].min(still.parts()[part])));
    if taken.is_none() {
        return Err(Refusal::NothingNeeded);
    }
    let city = city_of(db, player)?;
    let mut stock = settle(db, city.id)?;
    let have = goods(&stock);
    if !have.covers(taken) {
        return Err(Refusal::CannotAfford(have.short_of(taken)));
    }
    set_goods(&mut stock, have.minus(taken));
    db.update(stock);
    super::honoured_for_giving(db, player, taken.grain + taken.timber + taken.stone);
    (learning.grain, learning.timber, learning.stone) = (learning.grain + taken.grain, learning.timber + taken.timber, learning.stone + taken.stone);
    if given(&learning).covers(cost) {
        let pace = realm(db)?.pace;
        learning.rises_at = db.now() + catalog::paced(catalog::alliance_study_seconds(learning.level + 1), pace).max(1);
        learning.timer = db.after(learning.rises_at, TIMER_LEARNING, learning.id);
        (learning.grain, learning.timber, learning.stone) = (0, 0, 0);
    }
    keep(db, learning.clone());
    Ok(learning)
}

/// An alliance has learnt a topic to its next level: every member has it
/// from now, and is told.
pub fn learnt_together_now(db: &mut impl Db, id: u64) {
    let Some(mut learning) = Table::<Learning>::get(db, id) else { return };
    if learning.rises_at == 0 || db.now() < learning.rises_at {
        return;
    }
    learning.level += 1;
    (learning.rises_at, learning.timer) = (0, 0);
    db.update(learning.clone());
    let name = Topic::of(learning.topic).map(|topic| topic.name()).unwrap_or("a study");
    let words = format!("Your alliance has learnt {name} to level {}. Every member has it as their own.", learning.level);
    let now = db.now();
    for member in Table::<Member>::by(db, 0, learning.alliance) {
        reckon_player(db, member.player);
        report(
            db,
            Report {
                id: 0,
                player: member.player,
                at: now,
                kind: Report::LEARNING,
                hex: 0,
                won: false,
                foe: 0,
                rounds: 0,
                fought: 0,
                wounded: 0,
                dead: 0,
                stood: 0,
                fell: 0,
                grain: 0,
                timber: 0,
                stone: 0,
                moonsalt: 0,
                words: words.clone(),
                read: false,
            },
        );
    }
}

/// An alliance has ended: what it learnt is gone with it.
pub(super) fn forget_together(db: &mut impl Db, alliance: u64) {
    for learning in Table::<Learning>::by(db, 0, alliance) {
        db.cancel(learning.timer);
        Table::<Learning>::delete(db, learning.id);
    }
}
