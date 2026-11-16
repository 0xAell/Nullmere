//! Prisoners: the commander keeping a city, taken when it falls.
//!
//! When an army or a rally takes a city by storm, the commander keeping it
//! is taken prisoner by whoever led the storm, if they were in it. A
//! prisoner leads no army and keeps no city. Their owner may ransom them,
//! five thousand each of grain, timber and stone for each of their levels,
//! paid into their captor's city; their captor may let them go for
//! nothing; and after three days, at the realm's pace, they go free of
//! themselves. Both players are told at every step.

use super::{asking, city_of, goods, keeper_in, realm, report, set_goods, settle, Refusal};
use crate::catalog;
use crate::rows::{Commander, Db, Keeper, Player, Prisoner, Report};
use crate::store::Table;

pub const TIMER_PRISON: u8 = 6;

/// Where a prisoner is, as their commander's row has it: neither in the
/// city nor out with an army.
pub const HELD: u64 = u64::MAX;

fn name_of(db: &impl Db, player: u64) -> String {
    Table::<Player>::get(db, player).map(|row| row.name).unwrap_or_else(|| "Someone".into())
}

fn tell(db: &mut impl Db, player: u64, foe: u64, words: String) {
    let now = db.now();
    report(
        db,
        Report {
            id: 0,
            player,
            at: now,
            kind: Report::PRISONER,
            hex: 0,
            won: false,
            foe,
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
            words,
            read: false,
        },
    );
}

/// A city has been taken by storm: the commander keeping it, if they were
/// in it, is taken prisoner by whoever led the storm. Their name, if so.
pub(super) fn take_prisoner(db: &mut impl Db, owner: u64, captor: u64) -> Option<String> {
    let mut commander = keeper_in(db, owner)?;
    let pace = realm(db).map(|realm| realm.pace).unwrap_or(1);
    let ransom = catalog::ransom(commander.level);
    let freed_at = db.now() + catalog::paced(catalog::PRISON_DAYS * catalog::DAY, pace);
    commander.march = HELD;
    db.update(commander.clone());
    Table::<Keeper>::delete(db, owner);
    let timer = db.after(freed_at, TIMER_PRISON, commander.id);
    db.insert(Prisoner {
        commander: commander.id,
        owner,
        captor,
        name: commander.name.clone(),
        grain: ransom.grain,
        timber: ransom.timber,
        stone: ransom.stone,
        freed_at,
        timer,
    });
    let (theirs, holder) = (name_of(db, owner), name_of(db, captor));
    let name = commander.name.clone();
    tell(db, captor, owner, format!("Your army took {name}, who kept {theirs}'s city, prisoner. {theirs} may ransom them for {ransom}; in three days they go free."));
    tell(db, owner, captor, format!("{holder}'s army took {name} prisoner as your city fell. You may ransom them for {ransom}; in three days they go free."));
    Some(name)
}

/// A prisoner goes free: back in their own city, keeping nothing.
fn free(db: &mut impl Db, prisoner: &Prisoner) {
    db.cancel(prisoner.timer);
    Table::<Prisoner>::delete(db, prisoner.commander);
    if let Some(mut commander) = Table::<Commander>::get(db, prisoner.commander) {
        if commander.march == HELD {
            commander.march = 0;
            db.update(commander);
        }
    }
}

/// A player ransoms one of their commanders held prisoner: the ransom goes
/// from their city into their captor's, and the commander is free.
pub fn ransom(db: &mut impl Db, player: u64, commander: u64) -> Result<(), Refusal> {
    asking(db, player)?;
    let prisoner = Table::<Prisoner>::get(db, commander).filter(|prisoner| prisoner.owner == player).ok_or(Refusal::NoSuchPrisoner)?;
    let asked = catalog::Goods::of(prisoner.grain, prisoner.timber, prisoner.stone, 0);
    let city = city_of(db, player)?;
    let mut stock = settle(db, city.id)?;
    let have = goods(&stock);
    if !have.covers(asked) {
        return Err(Refusal::CannotAfford(have.short_of(asked)));
    }
    set_goods(&mut stock, have.minus(asked));
    db.update(stock);
    if let Ok(theirs) = city_of(db, prisoner.captor) {
        if let Ok(mut stock) = settle(db, theirs.id) {
            let more = goods(&stock).plus(asked);
            set_goods(&mut stock, more);
            db.update(stock);
        }
    }
    free(db, &prisoner);
    let (owner, name) = (name_of(db, player), prisoner.name.clone());
    tell(db, prisoner.captor, player, format!("{owner} ransomed {name} for {asked}, paid into your city."));
    tell(db, player, prisoner.captor, format!("You ransomed {name} for {asked}. They are home."));
    Ok(())
}

/// A captor lets a prisoner go, for nothing.
pub fn release_prisoner(db: &mut impl Db, player: u64, commander: u64) -> Result<(), Refusal> {
    asking(db, player)?;
    let prisoner = Table::<Prisoner>::get(db, commander).filter(|prisoner| prisoner.captor == player).ok_or(Refusal::NoSuchPrisoner)?;
    free(db, &prisoner);
    let (captor, name) = (name_of(db, player), prisoner.name.clone());
    tell(db, prisoner.owner, player, format!("{captor} let {name} go. They are home."));
    tell(db, player, prisoner.owner, format!("You let {name} go."));
    Ok(())
}

/// A prisoner's days are done: they go free of themselves.
pub fn prison_done(db: &mut impl Db, commander: u64) {
    let Some(prisoner) = Table::<Prisoner>::get(db, commander) else { return };
    if db.now() < prisoner.freed_at {
        return;
    }
    free(db, &prisoner);
    let name = prisoner.name.clone();
    tell(db, prisoner.owner, prisoner.captor, format!("{name} has gone free after three days held, and is home."));
    tell(db, prisoner.captor, prisoner.owner, format!("{name}, held by you three days, has gone free."));
}
