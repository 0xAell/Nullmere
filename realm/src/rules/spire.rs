//! The Moonspire: each alliance raises its own, a stage at a time, from
//! what its members give. Every stage that stands lifts what each
//! member's works bring in. The realm runs in seasons; the first alliance
//! to raise its Moonspire whole in a season is that season's victor, and
//! when the season turns every Moonspire falls, to be raised again.

use super::{asking, city_of, goods, member_of, realm, reckon, report, set_goods, settle, Refusal};
use crate::catalog::{self, Goods, SPIRE_STAGES};
use crate::rows::{Alliance, City, Db, Gift, Member, Report, Season, Spire};
use crate::store::{Seconds, Table};

/// A timer for a stage of a Moonspire that stands now: its subject is the alliance.
pub const TIMER_SPIRE: u8 = 3;
/// A timer for a season's end: its subject is the season's number.
pub const TIMER_SEASON: u8 = 4;

/// How long a season lasts at the realm's pace.
fn season_length(db: &impl Db) -> Seconds {
    let pace = realm(db).map(|realm| realm.pace).unwrap_or(1);
    catalog::paced(catalog::SEASON_DAYS * catalog::DAY, pace).max(1)
}

/// Writes a season's row as it begins, and sets the timer that ends it.
pub fn begin_season(db: &mut impl Db, number: u64, began: Seconds) {
    let ends = began + season_length(db);
    db.insert(Season { number, began, ends, victor: 0, victor_name: String::new(), won_at: 0 });
    db.after(ends, TIMER_SEASON, number);
}

/// The season it is: the last one begun.
pub fn season_now(db: &impl Db) -> Season {
    Table::<Season>::all(db).into_iter().max_by_key(|season| season.number).unwrap_or(Season { number: 1, began: 0, ends: Seconds::MAX, victor: 0, victor_name: String::new(), won_at: 0 })
}

/// An alliance's Moonspire this season: none raised yet if it has none,
/// or what it has is of a season gone.
pub fn spire_of(db: &impl Db, alliance: u64) -> Spire {
    let season = season_now(db).number;
    Table::<Spire>::get(db, alliance).filter(|spire| spire.season == season).unwrap_or_else(|| Spire {
        alliance,
        name: Table::<Alliance>::get(db, alliance).map(|row| row.name).unwrap_or_default(),
        season,
        stage: 0,
        rises_at: 0,
        timer: 0,
        grain: 0,
        timber: 0,
        stone: 0,
        moonsalt: 0,
    })
}

fn keep(db: &mut impl Db, spire: Spire) {
    if Table::<Spire>::get(db, spire.alliance).is_some() {
        db.update(spire);
    } else {
        db.insert(spire);
    }
}

/// By how many hundredths a player's alliance's Moonspire lifts what
/// their works bring in: nothing outside an alliance.
pub fn spire_boost(db: &impl Db, player: u64) -> u64 {
    member_of(db, player).map(|member| spire_of(db, member.alliance).stage as u64 * catalog::SPIRE_YIELD).unwrap_or(0)
}

/// Reckons a player's city afresh, if they have one: what it brings in may have changed.
pub(super) fn reckon_player(db: &mut impl Db, player: u64) {
    if let Some(city) = Table::<City>::by(db, 0, player).first() {
        reckon(db, city.id);
    }
}

fn reckon_members(db: &mut impl Db, alliance: u64) {
    for member in Table::<Member>::by(db, 0, alliance) {
        reckon_player(db, member.player);
    }
}

fn pooled(spire: &Spire) -> Goods {
    Goods::of(spire.grain, spire.timber, spire.stone, spire.moonsalt)
}

fn set_pool(spire: &mut Spire, goods: Goods) {
    (spire.grain, spire.timber, spire.stone, spire.moonsalt) = (goods.grain, goods.timber, goods.stone, goods.moonsalt);
}

/// Begins raising the next stage if it is not begun, not the last is
/// standing, and what has been given covers it.
fn raise_if_paid(db: &mut impl Db, spire: &mut Spire) {
    if spire.rises_at != 0 || spire.stage >= SPIRE_STAGES {
        return;
    }
    let cost = catalog::spire_cost(spire.stage + 1);
    if !pooled(spire).covers(cost) {
        return;
    }
    let left = pooled(spire).minus(cost);
    set_pool(spire, left);
    let pace = realm(db).map(|realm| realm.pace).unwrap_or(1);
    spire.rises_at = db.now() + catalog::paced(catalog::spire_seconds(spire.stage + 1), pace).max(1);
    spire.timer = db.after(spire.rises_at, TIMER_SPIRE, spire.alliance);
}

/// A member gives goods from their city toward their alliance's
/// Moonspire. When what has been given covers the next stage, it begins
/// to be raised. What is given is given: it is not returned.
pub fn give_to_spire(db: &mut impl Db, player: u64, gift: Goods) -> Result<Spire, Refusal> {
    asking(db, player)?;
    let member = member_of(db, player).ok_or(Refusal::NotAllied)?;
    let city = city_of(db, player)?;
    if gift.is_none() {
        return Err(Refusal::NothingAsked);
    }
    let mut spire = spire_of(db, member.alliance);
    if spire.stage >= SPIRE_STAGES {
        return Err(Refusal::SpireComplete);
    }
    let mut stock = settle(db, city.id)?;
    let have = goods(&stock);
    if !have.covers(gift) {
        return Err(Refusal::CannotAfford(have.short_of(gift)));
    }
    set_goods(&mut stock, have.minus(gift));
    db.update(stock);
    let more = pooled(&spire).plus(gift);
    set_pool(&mut spire, more);
    raise_if_paid(db, &mut spire);
    keep(db, spire.clone());

    let season = spire.season;
    let mut record = Table::<Gift>::get(db, player).filter(|row| row.season == season).unwrap_or(Gift { player, season, given: 0 });
    record.given = record.given.saturating_add(gift.parts().iter().sum());
    if Table::<Gift>::get(db, player).is_some() {
        db.update(record);
    } else {
        db.insert(record);
    }
    Ok(spire)
}

/// Tells every member of an alliance the same thing.
fn tell_members(db: &mut impl Db, alliance: u64, words: &str) {
    let now = db.now();
    for member in Table::<Member>::by(db, 0, alliance) {
        report(
            db,
            Report {
                id: 0,
                player: member.player,
                at: now,
                kind: Report::SPIRE,
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
                words: words.to_string(),
                read: false,
            },
        );
    }
}

/// A stage of an alliance's Moonspire stands: every member's works bring
/// in more from now. The first to stand whole this season wins it. If
/// enough has been given already, the next stage is begun.
pub fn spire_risen(db: &mut impl Db, alliance: u64) {
    let Some(mut spire) = Table::<Spire>::get(db, alliance) else { return };
    let mut season = season_now(db);
    if spire.season != season.number || spire.rises_at == 0 || db.now() < spire.rises_at {
        return;
    }
    spire.stage += 1;
    spire.rises_at = 0;
    spire.timer = 0;
    let whole = spire.stage >= SPIRE_STAGES;
    if whole && season.victor == 0 {
        season.victor = alliance;
        season.victor_name = spire.name.clone();
        season.won_at = db.now();
        db.update(season.clone());
    }
    raise_if_paid(db, &mut spire);
    keep(db, spire.clone());
    reckon_members(db, alliance);
    let words = if whole && season.victor == alliance {
        format!("Your alliance's Moonspire stands whole, the first in the realm this season. Season {} is yours.", season.number)
    } else if whole {
        "Your alliance's Moonspire stands whole.".to_string()
    } else {
        format!("The {} stage of your alliance's Moonspire stands. Your works bring in {}% more.", catalog::ordinal(spire.stage), spire.stage as u64 * catalog::SPIRE_YIELD)
    };
    tell_members(db, alliance, &words);
}

/// A season is over: every Moonspire falls, and with it what it lifted;
/// what had been given toward a stage not yet begun is lost with it. The
/// next season begins.
pub fn turn_season(db: &mut impl Db, number: u64) {
    let season = season_now(db);
    if season.number != number || db.now() < season.ends {
        return;
    }
    let fallen: Vec<Spire> = Table::<Spire>::all(db);
    for spire in &fallen {
        if spire.timer != 0 {
            db.cancel(spire.timer);
        }
        Table::<Spire>::delete(db, spire.alliance);
    }
    begin_season(db, number + 1, season.ends);
    super::gates_turn(db, season.victor);
    for spire in fallen.iter().filter(|spire| spire.season == number && spire.stage > 0) {
        reckon_members(db, spire.alliance);
        let words = match season.victor {
            0 => format!("Season {number} is over, and no alliance raised its Moonspire whole. Every Moonspire has fallen; season {} begins.", number + 1),
            victor if victor == spire.alliance => format!("Season {number} is over, and it was your alliance's. Every Moonspire has fallen; season {} begins.", number + 1),
            _ => format!("Season {number} is over: {} raised its Moonspire first. Every Moonspire has fallen; season {} begins.", season.victor_name, number + 1),
        };
        tell_members(db, spire.alliance, &words);
    }
}
