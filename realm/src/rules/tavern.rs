//! The Tavern's summonses: once a day free, and with each summons a player
//! keeps, one of the realm's commanders is drawn by the Tavern's odds. One
//! the player lacks comes to them while the Tavern has room; one they have
//! already brings sigils, and with enough of them a commander's gift rises
//! a level, to the fifth.

use super::{asking, building_of, city_of, commanders_of, daily_of, held, take, welcome, Refusal};
use crate::catalog::{self, Building as Kind, Item, Renown, PEOPLE, SIGILS_A_DRAW, TOP_GIFT};
use crate::rows::{Commander, Daily, Db};
use crate::store::Table;

/// What a summons drew: the commander who came or was drawn again, and
/// whether they are new to the player.
#[derive(Clone, Debug, PartialEq)]
pub struct Drawn {
    pub commander: Commander,
    pub new: bool,
}

/// A player takes a summons to their Tavern: today's free one while it is
/// not taken, or else one they keep. A renown is drawn by the Tavern's
/// odds and one of the realm's commanders of it: one the player lacks
/// comes, while the Tavern has room for another; one they have brings
/// them sigils. With no room, the draw is among their own.
pub fn draw(db: &mut impl Db, player: u64) -> Result<Drawn, Refusal> {
    asking(db, player)?;
    let city = city_of(db, player)?;
    let tavern = building_of(db, city.id, Kind::Tavern).map(|tavern| tavern.level).unwrap_or(0);
    if tavern == 0 {
        return Err(Refusal::NeedsOther(Kind::Tavern, 1));
    }
    let mut today = daily_of(db, player);
    if today.drawn < catalog::FREE_DRAWS {
        today.drawn += 1;
        if Table::<Daily>::get(db, player).is_some() {
            db.update(today);
        } else {
            db.insert(today);
        }
    } else {
        if held(db, player, Item::Summons) == 0 {
            return Err(Refusal::NoSummons);
        }
        take(db, player, Item::Summons, 1);
    }

    let have = commanders_of(db, player);
    let room = (have.len() as u32) < catalog::commanders(tavern);
    let theirs = |number: u8| have.iter().find(|commander| commander.person == number).cloned();
    // Who may be drawn: every one of the realm's, or with no room, the
    // player's own of them.
    let pool: Vec<u8> = (1..=PEOPLE.len() as u8).filter(|number| room || theirs(*number).is_some()).collect();
    if pool.is_empty() {
        // No room, and none of theirs is one of the realm's: the summons
        // is kept for when there is.
        return Err(Refusal::NoMoreCommanders);
    }
    let roll = db.chance() % 100;
    let mut upto = 0;
    let mut renown = Renown::Steady;
    for each in [Renown::Storied, Renown::Famed, Renown::Steady] {
        upto += each.odds();
        if roll < upto {
            renown = each;
            break;
        }
    }
    let of = |renown: Renown| pool.iter().copied().filter(|number| catalog::person_of(*number).is_some_and(|person| person.renown == renown)).collect::<Vec<u8>>();
    let mut chosen = of(renown);
    for each in [Renown::Famed, Renown::Steady, Renown::Storied] {
        if !chosen.is_empty() {
            break;
        }
        chosen = of(each);
    }
    let number = chosen[(db.chance() % chosen.len() as u64) as usize];
    Ok(match theirs(number) {
        Some(mut commander) => {
            commander.sigils = commander.sigils.saturating_add(SIGILS_A_DRAW);
            db.update(commander.clone());
            Drawn { commander, new: false }
        }
        None => Drawn { commander: welcome(db, player, number), new: true },
    })
}

/// A player raises one of their commanders' gift a level with the sigils
/// they hold: as many as the level asks, to the fifth.
pub fn raise_gift(db: &mut impl Db, player: u64, commander: u64) -> Result<Commander, Refusal> {
    asking(db, player)?;
    let mut commander = Table::<Commander>::get(db, commander).filter(|commander| commander.owner == player).ok_or(Refusal::NoSuchCommander)?;
    if catalog::person_of(commander.person).is_none() {
        return Err(Refusal::NoGift);
    }
    if commander.gift >= TOP_GIFT {
        return Err(Refusal::GiftAtTop(commander.name));
    }
    let needs = catalog::gift_needs(commander.gift);
    if commander.sigils < needs {
        return Err(Refusal::TooFewSigils(commander.name.clone(), needs - commander.sigils));
    }
    commander.sigils -= needs;
    commander.gift += 1;
    db.update(commander.clone());
    Ok(commander)
}
