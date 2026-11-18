//! The holy sites of the realm: three each of the Moonwell, the Still
//! Stone, the Salt Altar and the Broken Spire in the outer land, and the
//! Heartstone in the lake country (`land::shrines`, `catalog::Holy`).
//!
//! The Unquiet keep every one when the realm opens. Three days into each
//! season, at the realm's pace, they may be stormed, by a rally and no
//! other way; an alliance whose rally takes one holds it, and while it
//! does each of its members' cities has the levels of a study the site
//! lends, a kind's once however many of it are held. Another alliance may
//! take it from them as they took it, from the same garrison, once a day
//! has passed since it was taken. When the season turns every site goes
//! back to the Unquiet but those the season's victor holds; and when an
//! alliance ends, those it held.

use super::{fight_as_one, member_of, realm, reckon_player, report, season_now, Refusal};
use crate::catalog::{self, Holy, Topic};
use crate::hex::Hex;
use crate::land;
use crate::rows::{Alliance, City, Db, March, Member, Place, Rally, Report, Shrine};
use crate::store::{Seconds, Table};

/// Raises the holy sites as the realm opens, kept by the Unquiet.
pub(super) fn write_shrines(db: &mut impl Db, seed: u64, radius: u32) {
    for (index, (hex, kind)) in land::shrines(seed, radius).into_iter().enumerate() {
        let id = index as u64 + 1;
        if Table::<Shrine>::get(db, id).is_none() && Table::<Place>::get(db, hex.packed()).is_none() {
            db.insert(Shrine { id, hex: hex.packed(), kind: kind as u8, holder: 0, holder_name: String::new(), taken_at: 0, fighter: 0 });
            db.insert(Place { hex: hex.packed(), kind: Place::SHRINE, id });
        }
    }
}

/// The holy site at a hex, if one stands there.
pub fn shrine_at(db: &impl Db, hex: Hex) -> Option<Shrine> {
    match Table::<Place>::get(db, hex.packed()) {
        Some(place) if place.kind == Place::SHRINE => Table::<Shrine>::get(db, place.id),
        _ => None,
    }
}

/// When the holy sites may be stormed this season.
pub fn shrines_open_at(db: &impl Db) -> Seconds {
    let pace = realm(db).map(|realm| realm.pace).unwrap_or(1);
    season_now(db).began.saturating_add(catalog::paced(catalog::SHRINES_OPEN_DAYS * catalog::DAY, pace))
}

/// When a holy site may be stormed again, having been taken: a day after,
/// at the realm's pace. Before it ever is, at once.
pub fn shrine_guarded_until(db: &impl Db, shrine: &Shrine) -> Seconds {
    if shrine.holder == 0 {
        return 0;
    }
    let pace = realm(db).map(|realm| realm.pace).unwrap_or(1);
    shrine.taken_at.saturating_add(catalog::paced(catalog::SHRINE_GUARDED, pace))
}

/// Whether a player's alliance may send a rally against a holy site now:
/// the sites are open this season, it is not their alliance's own, no
/// other rally is at it, it was not taken within the day, and its holder
/// is not at truce with them.
pub(super) fn may_hallow(db: &impl Db, player: u64, shrine: &Shrine) -> Result<(), Refusal> {
    let member = member_of(db, player).ok_or(Refusal::NotAllied)?;
    let now = db.now();
    let left = shrines_open_at(db) - now;
    if left > 0 {
        return Err(Refusal::ShrinesShut(left));
    }
    if shrine.holder == member.alliance {
        return Err(Refusal::OwnShrine);
    }
    if shrine.fighter != 0 {
        return Err(Refusal::ShrineFought);
    }
    let guarded = shrine_guarded_until(db, shrine) - now;
    if guarded > 0 {
        return Err(Refusal::ShrineGuarded(guarded));
    }
    if super::pact_holds(db, member.alliance, shrine.holder, crate::rows::Pact::TRUCE) {
        return Err(Refusal::AtTruce);
    }
    Ok(())
}

/// Whether a rally's last army, come up to a holy site, finds it still
/// to be stormed: not its own alliance's, no other rally at it, and not
/// taken within the day.
pub(super) fn still_to_storm(db: &impl Db, shrine: &Shrine, alliance: u64) -> bool {
    shrine.fighter == 0 && shrine.holder != alliance && shrine_guarded_until(db, shrine) <= db.now()
}

/// The levels of a study the holy sites a city's owner's alliance holds
/// lend it: each kind's once.
pub fn hallowed(db: &impl Db, city: u64, topic: Topic) -> u32 {
    let Some(owner) = Table::<City>::get(db, city).map(|city| city.owner) else { return 0 };
    let Some(member) = member_of(db, owner) else { return 0 };
    let mut kinds: Vec<Holy> = Table::<Shrine>::all(db).into_iter().filter(|shrine| shrine.holder == member.alliance).filter_map(|shrine| Holy::of(shrine.kind)).collect();
    kinds.sort_by_key(|kind| *kind as u8);
    kinds.dedup();
    kinds.into_iter().flat_map(|kind| kind.lends().iter()).filter(|(lent, _)| *lent == topic).map(|(_, levels)| levels).sum()
}

/// Every member's city of an alliance reckoned afresh, for what its holy
/// sites lend.
fn reckon_members(db: &mut impl Db, alliance: u64) {
    if alliance == 0 {
        return;
    }
    for member in Table::<Member>::by(db, 0, alliance) {
        reckon_player(db, member.player);
    }
}

/// A rally's fight at a holy site is over. Its armies fought as one
/// against the Unquiet keeping it, each losing what fell of its own and
/// carrying home as wounded what its own city has room for. If they won,
/// the site is their alliance's. Every army's owner is told, and the
/// members of the alliance that held it, if one did.
pub(super) fn stormed_shrine(db: &mut impl Db, marches: &mut [March], rally: &Rally) {
    let Some(mut shrine) = shrine_at(db, Hex::unpacked(rally.hex)) else { return };
    let Some(kind) = Holy::of(shrine.kind) else { return };
    let garrison = kind.garrison();
    let together = fight_as_one(db, marches, &garrison, catalog::shrine_shelter(), true);
    let stood: u64 = garrison.iter().map(|unit| unit.count).sum();
    let fell: u64 = together.outcome.defenders_lost.iter().sum();
    let won = together.outcome.won;
    let before = shrine.holder;
    let name = Table::<Alliance>::get(db, rally.alliance).map(|alliance| format!("[{}] {}", alliance.tag, alliance.name)).unwrap_or_default();
    shrine.fighter = 0;
    if won {
        (shrine.holder, shrine.holder_name, shrine.taken_at) = (rally.alliance, name.clone(), db.now());
    }
    db.update(shrine.clone());
    if won {
        reckon_members(db, rally.alliance);
        if before != rally.alliance {
            reckon_members(db, before);
        }
    }

    let armies = marches.len();
    let all: u64 = together.fought.iter().sum();
    let now = db.now();
    for (index, march) in marches.iter().enumerate() {
        let mut words = if won {
            format!("Your alliance's rally took {}: {armies} armies, {} soldiers in all. {}", kind.name(), catalog::grouped(all), kind.words())
        } else {
            format!(
                "Your alliance's rally was beaten at {}: {armies} armies, {} soldiers in all. {} of the Unquiet keeping it still stood.",
                kind.name(),
                catalog::grouped(all),
                catalog::grouped(stood - fell)
            )
        };
        words += " ";
        words += &super::fallen(together.fought[index], together.wounded[index], together.dead[index], "soldier", "soldiers");
        let fight = Fight { rounds: together.outcome.rounds, mine: (together.fought[index], together.wounded[index], together.dead[index]), theirs: (stood, fell) };
        report(db, told(march.owner, now, &shrine, won, fight, words));
    }
    if won && before != 0 && before != rally.alliance {
        let words = format!("{name} took {} from your alliance. What it lent your cities is lent no more.", kind.name());
        for member in Table::<Member>::by(db, 0, before) {
            report(db, told(member.player, now, &shrine, false, Fight { theirs: (all, 0), ..Fight::default() }, words.clone()));
        }
    }
}

/// What a report tells of a fight: its rounds, the reader's soldiers who
/// fought, were wounded and died, and the other side's who stood and fell.
#[derive(Default)]
struct Fight {
    rounds: u32,
    mine: (u64, u64, u64),
    theirs: (u64, u64),
}

fn told(player: u64, at: Seconds, shrine: &Shrine, won: bool, fight: Fight, words: String) -> Report {
    let Fight { rounds, mine, theirs } = fight;
    Report {
        id: 0,
        player,
        at,
        kind: Report::SHRINE,
        hex: shrine.hex,
        won,
        foe: shrine.id,
        rounds,
        fought: mine.0,
        wounded: mine.1,
        dead: mine.2,
        stood: theirs.0,
        fell: theirs.1,
        grain: 0,
        timber: 0,
        stone: 0,
        moonsalt: 0,
        words,
        read: false,
    }
}

/// What a rally against a holy site that no one joined tells its caller.
pub(super) fn unjoined(shrine: &Shrine) -> String {
    format!("No one joined your rally against {}. Your army has stood down.", Holy::of(shrine.kind).map(Holy::name).unwrap_or("the holy site"))
}

/// What a rally that found its holy site not to be stormed, when its last
/// army came up, tells each army's owner.
pub(super) fn found_held(shrine: &Shrine) -> String {
    format!(
        "Your alliance's rally found {} held by your own alliance, stormed by another, or taken within the day, when its last army came up. Your army is turning for home.",
        Holy::of(shrine.kind).map(Holy::name).unwrap_or("the holy site")
    )
}

/// The season has turned: every holy site goes back to the Unquiet but
/// those the season's victor holds.
pub(super) fn shrines_turn(db: &mut impl Db, victor: u64) {
    let mut lost = Vec::new();
    for mut shrine in Table::<Shrine>::all(db) {
        if shrine.holder != 0 && shrine.holder != victor {
            lost.push(shrine.holder);
            (shrine.holder, shrine.holder_name, shrine.taken_at) = (0, String::new(), 0);
            db.update(shrine);
        }
    }
    lost.sort_unstable();
    lost.dedup();
    for alliance in lost {
        reckon_members(db, alliance);
    }
}

/// An alliance has ended: the holy sites it held go back to the Unquiet.
pub(super) fn shrines_fall(db: &mut impl Db, alliance: u64) {
    for mut shrine in Table::<Shrine>::all(db) {
        if shrine.holder == alliance {
            (shrine.holder, shrine.holder_name, shrine.taken_at) = (0, String::new(), 0);
            db.update(shrine);
        }
    }
}
