//! Commanders: the people who lead a player's armies. Each has a name, a
//! way of war, and a level that rises with what they have seen; an army
//! they lead is the better for it. Each level past the first brings a
//! point to spend on a talent. A second commander may go out beside the
//! one who leads, adding half of their own way; and one may keep the
//! city, adding what they bring to its defence.

use super::{asking, building_of, city_of, goods, held, set_goods, settle, take, Mastery, Refusal};
use crate::catalog::{self, Building as Kind, Item, Leading, Person, Renown, Talent, Way, PEOPLE, TOP_COMMAND, TALENT_MOST};
use crate::rows::{Bond, Commander, Db, Keeper, March, Prisoner, Skill};
use crate::store::Table;

const FIRST: [&str; 24] = [
    "Ael", "Bran", "Cor", "Dun", "Eir", "Fen", "Gar", "Hal", "Ior", "Kes", "Lun", "Mor", "Nev", "Orl", "Pen", "Ren", "Sel", "Tor", "Ul", "Ves", "Wyn", "Yor",
    "Isk", "Tam",
];
const LAST: [&str; 12] = ["a", "en", "ic", "is", "or", "wen", "eth", "ald", "ine", "ar", "us", "ry"];

/// Writes the realm's commanders out as rows for clients: who each is,
/// their way, renown and gift, and what it does at each level.
pub fn write_people(db: &mut impl Db) {
    for (at, person) in PEOPLE.iter().enumerate() {
        let gift_words = (1..=catalog::TOP_GIFT).map(|level| person.gift.words(level)).collect::<Vec<_>>().join("\n");
        db.insert(crate::rows::Person {
            number: at as u64 + 1,
            name: person.name.to_string(),
            way: person.way as u8,
            renown: person.renown as u8,
            gift: person.gift as u8,
            gift_name: person.gift.name().to_string(),
            gift_words,
        });
    }
}

/// A player's commanders, in the order they came.
pub fn commanders_of(db: &impl Db, player: u64) -> Vec<Commander> {
    let mut all = Table::<Commander>::by(db, 0, player);
    all.sort_by_key(|commander| commander.id);
    all
}

/// A new commander comes to a player: one of the realm's they have not
/// got, of a way none of theirs has yet where there is one, its renown
/// by the Tavern's odds (most steady, some famed, a few storied); or,
/// should they have every one, one of no renown under a name of its own.
pub fn enlist(db: &mut impl Db, player: u64) -> Commander {
    let have = commanders_of(db, player);
    let unmet: Vec<(u8, Person)> = (1..=PEOPLE.len() as u8)
        .filter_map(|number| catalog::person_of(number).map(|person| (number, person)))
        .filter(|(number, _)| !have.iter().any(|commander| commander.person == *number))
        .collect();
    let new_way: Vec<(u8, Person)> = unmet.iter().copied().filter(|(_, person)| !have.iter().any(|commander| commander.way == person.way as u8)).collect();
    let pool = if new_way.is_empty() { unmet } else { new_way };
    if !pool.is_empty() {
        let roll = db.chance() % 100;
        let mut renown = Renown::Steady;
        let mut upto = 0;
        for each in [Renown::Storied, Renown::Famed, Renown::Steady] {
            upto += each.odds();
            if roll < upto {
                renown = each;
                break;
            }
        }
        // Of the renown drawn where there is one such in the pool, and
        // of the next more common where not.
        let mut chosen: Vec<(u8, Person)> = Vec::new();
        for each in [renown, Renown::Famed, Renown::Steady, Renown::Storied] {
            chosen = pool.iter().copied().filter(|(_, person)| person.renown == each).collect();
            if !chosen.is_empty() {
                break;
            }
        }
        let (number, _) = chosen[(db.chance() % chosen.len() as u64) as usize];
        return welcome(db, player, number);
    }
    let free: Vec<Way> = Way::ALL.into_iter().filter(|way| !have.iter().any(|commander| commander.way == *way as u8)).collect();
    let ways = if free.is_empty() { Way::ALL.to_vec() } else { free };
    let way = ways[(db.chance() % ways.len() as u64) as usize];
    let mut name = String::new();
    for _ in 0..40 {
        let (a, b) = (db.chance(), db.chance());
        name = format!("{}{}", FIRST[(a % FIRST.len() as u64) as usize], LAST[(b % LAST.len() as u64) as usize]);
        if !have.iter().any(|commander| commander.name == name) {
            break;
        }
    }
    db.insert(Commander { id: 0, owner: player, name, way: way as u8, level: 1, seen: 0, march: 0, person: 0, gift: 0, sigils: 0 })
}

/// One of the realm's commanders comes to a player, at the first level,
/// their gift at its first.
pub(super) fn welcome(db: &mut impl Db, player: u64, number: u8) -> Commander {
    let (name, way) = catalog::person_of(number).map(|person| (person.name.to_string(), person.way as u8)).unwrap_or_default();
    db.insert(Commander { id: 0, owner: player, name, way, level: 1, seen: 0, march: 0, person: number, gift: 1, sigils: 0 })
}

/// A player takes on another commander: as many as their Tavern's level
/// allows, each dearer than the last.
pub fn hire(db: &mut impl Db, player: u64) -> Result<Commander, Refusal> {
    asking(db, player)?;
    let city = city_of(db, player)?;
    let have = commanders_of(db, player).len() as u32;
    let tavern = building_of(db, city.id, Kind::Tavern).map(|tavern| tavern.level).unwrap_or(0);
    if tavern == 0 {
        return Err(Refusal::NeedsOther(Kind::Tavern, 1));
    }
    if have >= catalog::commanders(tavern) {
        return Err(if have >= 6 { Refusal::NoMoreCommanders } else { Refusal::NeedsOther(Kind::Tavern, (have - 1) * 5) });
    }
    let mut stock = settle(db, city.id)?;
    let cost = catalog::hire_cost(have);
    let short = goods(&stock).short_of(cost);
    if !short.is_none() {
        return Err(Refusal::CannotAfford(short));
    }
    let left = goods(&stock).minus(cost);
    set_goods(&mut stock, left);
    db.update(stock);
    Ok(enlist(db, player))
}

/// The commander a player names to lead an army: theirs, and in the city.
pub(super) fn leader_for(db: &impl Db, player: u64, commander: u64) -> Result<Commander, Refusal> {
    let commander = Table::<Commander>::get(db, commander).filter(|commander| commander.owner == player).ok_or(Refusal::NoSuchCommander)?;
    if commander.march != 0 {
        return Err(Refusal::CommanderAway(commander.name));
    }
    Ok(commander)
}

/// What a commander's way of war adds at their level, as their renown
/// makes it.
pub fn way_of(commander: &Commander) -> Leading {
    let weight = catalog::person_of(commander.person).map(|person| person.renown.weight()).unwrap_or(100);
    Way::of(commander.way).map(|way| way.leading(commander.level).scaled(weight)).unwrap_or_default()
}

/// What a commander adds by their way of war and renown, their gift,
/// their talents and the gear they wear.
pub fn commanding(db: &impl Db, commander: &Commander) -> Leading {
    let mut leading = way_of(commander).plus(super::worn(db, commander.id));
    if let Some(person) = catalog::person_of(commander.person) {
        leading = leading.plus(person.gift.leading(commander.gift));
    }
    for skill in Table::<Skill>::by(db, 0, commander.id) {
        if let Some(talent) = Talent::of(skill.talent) {
            leading = leading.plus(talent.leading(skill.points));
        }
    }
    leading
}

/// The commander who goes out beside another, if one is bonded to them.
fn partner_of(db: &impl Db, commander: u64) -> Option<Commander> {
    Table::<Bond>::get(db, commander).and_then(|bond| Table::<Commander>::get(db, bond.partner))
}

/// The commander who went out beside the one leading a march. The bond
/// counts as the army sets out; who is out with it after that is who
/// went, whatever the player has bonded since.
fn beside(db: &impl Db, march: &March) -> Option<Commander> {
    if march.leader == 0 {
        return None;
    }
    Table::<Commander>::by(db, 0, march.owner).into_iter().find(|commander| commander.march == march.id && commander.id != march.leader)
}

/// What the commanders of a march add to it: the one who leads it, and
/// half the way of war of one who went out beside them; nothing where no
/// one leads it.
pub fn leading_of(db: &impl Db, march: &March) -> Leading {
    let Some(leader) = Table::<Commander>::get(db, march.leader) else { return Leading::default() };
    let mut leading = commanding(db, &leader);
    if let Some(partner) = beside(db, march) {
        leading = leading.plus(way_of(&partner).halved());
    }
    leading
}

/// A commander has seen something of war or of work: so much is added to
/// what they have seen, and they rise a level for each measure of it, to
/// the thirtieth.
fn seen_by(db: &mut impl Db, commander: u64, amount: u64) {
    let Some(mut commander) = Table::<Commander>::get(db, commander) else { return };
    commander.seen += amount;
    while commander.level < TOP_COMMAND && commander.seen >= catalog::command_needs(commander.level) {
        commander.seen -= catalog::command_needs(commander.level);
        commander.level += 1;
    }
    db.update(commander);
}

/// The most tomes read at once.
pub const MOST_READ: u64 = 100;

/// A player has one of their commanders read so many tomes of war: what
/// each tells is added to what the commander has seen, and they rise as
/// it carries them. Not a commander held prisoner, nor one who has seen
/// all there is. What the commander is now.
pub fn read_tome(db: &mut impl Db, player: u64, commander: u64, item: u8, count: u64) -> Result<Commander, Refusal> {
    asking(db, player)?;
    let reader = Table::<Commander>::get(db, commander).filter(|row| row.owner == player).ok_or(Refusal::NoSuchCommander)?;
    let tome = Item::of(item).filter(|item| item.is_tome()).ok_or(Refusal::NotATome)?;
    if count == 0 {
        return Err(Refusal::NothingAsked);
    }
    if count > MOST_READ {
        return Err(Refusal::TooMany(MOST_READ));
    }
    if Table::<Prisoner>::get(db, commander).is_some() {
        return Err(Refusal::HeldPrisoner(reader.name));
    }
    if reader.level >= TOP_COMMAND {
        return Err(Refusal::SeenAll(reader.name));
    }
    if held(db, player, tome) < count {
        return Err(Refusal::NoneLeft);
    }
    take(db, player, tome, count);
    seen_by(db, commander, tome.seen() * count);
    Table::<Commander>::get(db, commander).ok_or(Refusal::NoSuchCommander)
}

/// A march's commanders have seen something of war or of work: the one
/// who leads it all of it, one beside them half.
pub(super) fn seen_by_leader(db: &mut impl Db, march: &March, amount: u64) {
    if let Some(partner) = beside(db, march) {
        seen_by(db, partner.id, amount / 2);
    }
    seen_by(db, march.leader, amount);
}

/// An army sets out under a commander: one bonded to go out beside them
/// goes too, if they are in the city.
pub(super) fn set_out_with(db: &mut impl Db, march: &March) {
    if let Some(mut partner) = partner_of(db, march.leader).filter(|partner| partner.march == 0) {
        partner.march = march.id;
        db.update(partner);
    }
}

/// A march is over: its commanders are back in the city.
pub(super) fn release(db: &mut impl Db, march: &March) {
    if let Some(mut commander) = Table::<Commander>::get(db, march.leader) {
        commander.march = 0;
        db.update(commander);
    }
    if let Some(mut partner) = beside(db, march) {
        partner.march = 0;
        db.update(partner);
    }
}

/// One of a player's commanders, by number.
fn own_commander(db: &impl Db, player: u64, commander: u64) -> Result<Commander, Refusal> {
    Table::<Commander>::get(db, commander).filter(|commander| commander.owner == player).ok_or(Refusal::NoSuchCommander)
}

/// A player puts one of a commander's points into a talent.
pub fn learn_talent(db: &mut impl Db, player: u64, commander: u64, talent: u8) -> Result<Skill, Refusal> {
    asking(db, player)?;
    let commander = own_commander(db, player, commander)?;
    let talent = Talent::of(talent).ok_or(Refusal::NoSuchTalent)?;
    let skills = Table::<Skill>::by(db, 0, commander.id);
    let spent: u32 = skills.iter().map(|skill| skill.points).sum();
    if spent >= catalog::talent_points(commander.level) {
        return Err(Refusal::NoTalentPoints(commander.name));
    }
    let id = Skill::key(commander.id, talent as u8);
    let mut skill = Table::<Skill>::get(db, id).unwrap_or(Skill { id, commander: commander.id, owner: player, talent: talent as u8, points: 0 });
    if skill.points >= TALENT_MOST {
        return Err(Refusal::TalentFull(commander.name));
    }
    skill.points += 1;
    if skill.points == 1 {
        db.insert(skill.clone());
    } else {
        db.update(skill.clone());
    }
    Ok(skill)
}

/// A player has a commander forget every talent, for goods: their points
/// are theirs to spend again.
pub fn forget_talents(db: &mut impl Db, player: u64, commander: u64) -> Result<(), Refusal> {
    asking(db, player)?;
    let commander = own_commander(db, player, commander)?;
    let skills = Table::<Skill>::by(db, 0, commander.id);
    if skills.is_empty() {
        return Err(Refusal::NothingToForget);
    }
    let city = city_of(db, player)?;
    let mut stock = settle(db, city.id)?;
    let have = goods(&stock);
    if !have.covers(catalog::FORGET_COST) {
        return Err(Refusal::CannotAfford(have.short_of(catalog::FORGET_COST)));
    }
    set_goods(&mut stock, have.minus(catalog::FORGET_COST));
    db.update(stock);
    for skill in skills {
        Table::<Skill>::delete(db, skill.id);
    }
    Ok(())
}

/// Whether a commander is in a bond already, leading or beside: the bond.
fn bond_with(db: &impl Db, player: u64, commander: u64) -> Option<Bond> {
    Table::<Bond>::by(db, 0, player).into_iter().find(|bond| bond.commander == commander || bond.partner == commander)
}

/// A player has one commander go out beside another whenever the other
/// leads an army; with 0 for the partner, no one goes beside them.
pub fn pair(db: &mut impl Db, player: u64, commander: u64, partner: u64) -> Result<(), Refusal> {
    asking(db, player)?;
    let leader = own_commander(db, player, commander)?;
    if partner == 0 {
        Table::<Bond>::delete(db, leader.id);
        return Ok(());
    }
    let partner = own_commander(db, player, partner)?;
    if partner.id == leader.id {
        return Err(Refusal::SameCommander);
    }
    // Each commander in one bond at most: the leader's own may be replaced.
    if let Some(bond) = bond_with(db, player, partner.id) {
        if bond.commander != leader.id {
            return Err(Refusal::AlreadyPaired(partner.name));
        }
    }
    if bond_with(db, player, leader.id).is_some_and(|bond| bond.commander != leader.id) {
        return Err(Refusal::AlreadyPaired(leader.name));
    }
    let bond = Bond { commander: leader.id, owner: player, partner: partner.id };
    if Table::<Bond>::get(db, leader.id).is_some() {
        db.update(bond);
    } else {
        db.insert(bond);
    }
    Ok(())
}

/// A player has one of their commanders keep their city; with 0, none.
pub fn keep_city(db: &mut impl Db, player: u64, commander: u64) -> Result<(), Refusal> {
    asking(db, player)?;
    if commander == 0 {
        Table::<Keeper>::delete(db, player);
        return Ok(());
    }
    let commander = own_commander(db, player, commander)?;
    let keeper = Keeper { player, commander: commander.id };
    if Table::<Keeper>::get(db, player).is_some() {
        db.update(keeper);
    } else {
        db.insert(keeper);
    }
    Ok(())
}

/// The commander keeping a player's city who is in it now.
pub(super) fn keeper_in(db: &impl Db, player: u64) -> Option<Commander> {
    Table::<Keeper>::get(db, player).and_then(|keeper| Table::<Commander>::get(db, keeper.commander)).filter(|commander| commander.march == 0)
}

/// What a city's defenders have beyond their numbers: what it has
/// learnt, what its Watchtower adds, and what the commander keeping it
/// brings to a fight.
pub fn defence_of(db: &impl Db, city: u64, owner: u64) -> Mastery {
    let mut all = super::mastery(db, city);
    // The Watchtower's watchers loose with every defender.
    let watch = catalog::watch(building_of(db, city, Kind::Watchtower).map(|tower| tower.level).unwrap_or(0));
    for strike in all.strikes.iter_mut() {
        *strike += watch;
    }
    if let Some(keeper) = keeper_in(db, owner) {
        let leading = commanding(db, &keeper);
        for kind in 0..4 {
            all.strikes[kind] += leading.strikes[kind];
        }
        all.shields += leading.shields;
        all.surge += leading.surge;
        all.stand += leading.stand;
        all.quick += leading.quick;
        all.mercy += leading.mercy;
    }
    all
}

/// The commander keeping a city has seen it defended: so much is added to what they have seen.
pub(super) fn seen_by_keeper(db: &mut impl Db, player: u64, amount: u64) {
    if let Some(keeper) = keeper_in(db, player) {
        seen_by(db, keeper.id, amount);
    }
}
