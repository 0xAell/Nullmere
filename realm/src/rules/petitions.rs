//! Petitions: a member asks their alliance for goods, and allies send them.
//!
//! A member of an alliance petitions it for goods, half a million of each
//! at most, one petition at a time; it stands a day. Any other member may
//! answer it from their own city with what it still asks, or some of it;
//! a tenth of what is sent is taken by the road, and the rest comes into
//! the asker's city at once. Answered in full, the petition is done. The
//! asker is told of every answer. One whose day is done is answered no
//! more, and is replaced when its asker petitions anew.

use super::{asking, city_of, goods, member_of, realm, report, set_goods, settle, shown_name, Refusal};
use crate::catalog::{self, Goods};
use crate::rows::{Db, Petition, Player, Report};
use crate::store::Table;

fn asked(petition: &Petition) -> Goods {
    Goods::of(petition.grain, petition.timber, petition.stone, petition.moonsalt)
}

fn sent(petition: &Petition) -> Goods {
    Goods::of(petition.sent_grain, petition.sent_timber, petition.sent_stone, petition.sent_moonsalt)
}

/// What a petition still asks.
pub fn still_asked(petition: &Petition) -> Goods {
    let (asked, sent) = (asked(petition).parts(), sent(petition).parts());
    Goods::from_parts([0, 1, 2, 3].map(|part| asked[part].saturating_sub(sent[part])))
}

/// Whether a petition still stands.
fn stands(db: &impl Db, petition: &Petition) -> bool {
    let pace = realm(db).map(|realm| realm.pace).unwrap_or(1);
    db.now() < petition.made_at + catalog::paced(catalog::PETITION_STANDS, pace)
}

/// A member petitions their alliance for goods.
pub fn petition(db: &mut impl Db, player: u64, wanted: Goods) -> Result<Petition, Refusal> {
    asking(db, player)?;
    let member = member_of(db, player).ok_or(Refusal::NotAllied)?;
    if wanted.is_none() {
        return Err(Refusal::NothingAsked);
    }
    if wanted.parts().iter().any(|part| *part > catalog::PETITION_MOST) {
        return Err(Refusal::PetitionTooLarge(catalog::PETITION_MOST));
    }
    if let Some(open) = Table::<Petition>::get(db, player) {
        if stands(db, &open) && open.alliance == member.alliance {
            return Err(Refusal::PetitionStands);
        }
        Table::<Petition>::delete(db, player);
    }
    let name = Table::<Player>::get(db, player).map(|row| shown_name(db, &row)).unwrap_or_default();
    let row = Petition {
        asker: player,
        alliance: member.alliance,
        name,
        grain: wanted.grain,
        timber: wanted.timber,
        stone: wanted.stone,
        moonsalt: wanted.moonsalt,
        sent_grain: 0,
        sent_timber: 0,
        sent_stone: 0,
        sent_moonsalt: 0,
        made_at: db.now(),
    };
    db.insert(row.clone());
    Ok(row)
}

/// An ally answers a petition from their own city: as much of what is
/// sent as it still asks is taken, the road takes a tenth of that, and
/// the rest comes into the asker's city.
pub fn answer_petition(db: &mut impl Db, player: u64, asker: u64, sending: Goods) -> Result<Goods, Refusal> {
    asking(db, player)?;
    let member = member_of(db, player).ok_or(Refusal::NotAllied)?;
    let mut petition = Table::<Petition>::get(db, asker).filter(|petition| petition.alliance == member.alliance && petition.asker != player).ok_or(Refusal::NoSuchPetition)?;
    // One whose day is done, or whose asker has left the alliance, is answered no more; it is
    // replaced when its asker petitions anew.
    if !stands(db, &petition) || member_of(db, asker).is_none_or(|theirs| theirs.alliance != member.alliance) {
        return Err(Refusal::NoSuchPetition);
    }
    let still = still_asked(&petition).parts();
    let taken = Goods::from_parts([0, 1, 2, 3].map(|part| sending.parts()[part].min(still[part])));
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
    let arrives = Goods::from_parts(taken.parts().map(|part| part - part * catalog::PETITION_TOLL / 100));
    let theirs = city_of(db, asker)?;
    let mut stock = settle(db, theirs.id)?;
    let more = goods(&stock).plus(arrives);
    set_goods(&mut stock, more);
    db.update(stock);

    (petition.sent_grain, petition.sent_timber, petition.sent_stone, petition.sent_moonsalt) =
        (petition.sent_grain + taken.grain, petition.sent_timber + taken.timber, petition.sent_stone + taken.stone, petition.sent_moonsalt + taken.moonsalt);
    let done = still_asked(&petition).is_none();
    if done {
        Table::<Petition>::delete(db, asker);
    } else {
        db.update(petition);
    }
    let giver = Table::<Player>::get(db, player).map(|row| shown_name(db, &row)).unwrap_or_default();
    let mut words = format!("{giver} answered your petition: {arrives} came into your city, the road taking a tenth of what was sent.");
    if done {
        words += " Your petition is answered in full.";
    }
    let now = db.now();
    report(
        db,
        Report {
            id: 0,
            player: asker,
            at: now,
            kind: Report::PETITION,
            hex: 0,
            won: false,
            foe: player,
            rounds: 0,
            fought: 0,
            wounded: 0,
            dead: 0,
            stood: 0,
            fell: 0,
            grain: arrives.grain,
            timber: arrives.timber,
            stone: arrives.stone,
            moonsalt: arrives.moonsalt,
            words,
            read: false,
        },
    );
    Ok(arrives)
}

/// A member withdraws their petition.
pub fn withdraw_petition(db: &mut impl Db, player: u64) -> Result<(), Refusal> {
    asking(db, player)?;
    Table::<Petition>::get(db, player).ok_or(Refusal::NoSuchPetition)?;
    Table::<Petition>::delete(db, player);
    Ok(())
}
