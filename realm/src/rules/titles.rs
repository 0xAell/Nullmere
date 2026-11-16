//! The titles of the Mere, bestowed by its Lord.
//!
//! The leader of the alliance that won the last season won is the Lord of
//! the Mere, until another season is won. The Lord bestows the realm's
//! five titles on whom they will, anyone in the realm, one holder to a
//! title; bestowing a title on another takes it from whoever held it, and
//! the Lord may take one back. Each lends its holder what so many levels
//! of a study would: their armies gather or march faster, their soldiers
//! are trained or their buildings raised sooner, everyone they send or
//! keep harder to bring down. A new Lord's season begins with no title
//! held.

use super::{asking, reckon_player, report, Refusal};
use crate::catalog::{Title as Kind, Topic};
use crate::rows::{Alliance, City, Db, Player, Report, Season, Title};
use crate::store::Table;

/// The Lord of the Mere: the leader of the alliance that won the latest
/// season won, if it stands.
pub fn lord(db: &impl Db) -> Option<u64> {
    let won = Table::<Season>::all(db).into_iter().filter(|season| season.victor != 0).max_by_key(|season| season.number)?;
    Table::<Alliance>::get(db, won.victor).map(|alliance| alliance.leader)
}

/// The levels of a study a city's owner holds by a title.
pub fn titled(db: &impl Db, city: u64, topic: Topic) -> u32 {
    let Some(owner) = Table::<City>::get(db, city).map(|city| city.owner) else { return 0 };
    Table::<Title>::all(db)
        .into_iter()
        .filter(|title| title.holder == owner)
        .filter_map(|title| Kind::of(title.title as u8))
        .filter(|kind| kind.lends().0 == topic)
        .map(|kind| kind.lends().1)
        .sum()
}

fn tell(db: &mut impl Db, player: u64, title: Kind, words: String) {
    let now = db.now();
    report(
        db,
        Report {
            id: 0,
            player,
            at: now,
            kind: Report::TITLE,
            hex: 0,
            won: false,
            foe: title as u64,
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

/// The Lord bestows a title on a player, taking it from whoever held it.
pub fn bestow_title(db: &mut impl Db, player: u64, title: u8, on: u64) -> Result<Title, Refusal> {
    asking(db, player)?;
    if lord(db) != Some(player) {
        return Err(Refusal::NotTheLord);
    }
    let kind = Kind::of(title).ok_or(Refusal::NoSuchTitle)?;
    let name = Table::<Player>::get(db, on).map(|row| row.name).ok_or(Refusal::NoSuchPlayer)?;
    let before = Table::<Title>::get(db, kind as u64);
    if let Some(held) = &before {
        if held.holder == on {
            return Err(Refusal::TitleHeld);
        }
    }
    let row = Title { title: kind as u64, holder: on, name, since: db.now() };
    if before.is_some() {
        db.update(row.clone());
    } else {
        db.insert(row.clone());
    }
    if let Some(held) = before {
        reckon_player(db, held.holder);
        tell(db, held.holder, kind, format!("The Lord of the Mere has taken the title of {} from you.", kind.name()));
    }
    reckon_player(db, on);
    tell(db, on, kind, format!("The Lord of the Mere has made you {}.", kind.name()));
    Ok(row)
}

/// The Lord takes a title back from whoever holds it.
pub fn take_title(db: &mut impl Db, player: u64, title: u8) -> Result<(), Refusal> {
    asking(db, player)?;
    if lord(db) != Some(player) {
        return Err(Refusal::NotTheLord);
    }
    let kind = Kind::of(title).ok_or(Refusal::NoSuchTitle)?;
    let held = Table::<Title>::get(db, kind as u64).ok_or(Refusal::NoSuchTitle)?;
    Table::<Title>::delete(db, kind as u64);
    reckon_player(db, held.holder);
    tell(db, held.holder, kind, format!("The Lord of the Mere has taken the title of {} from you.", kind.name()));
    Ok(())
}

/// A season has been won: its Lord begins with no title held.
pub(super) fn titles_lapse(db: &mut impl Db) {
    for title in Table::<Title>::all(db) {
        Table::<Title>::delete(db, title.title);
        reckon_player(db, title.holder);
    }
}
