//! The realm's tables, as the rules and the clients both read them.
//!
//! Each row is a plain struct and a SpacetimeDB table at once. A table
//! marked `public` is read by every client; the rest are read through
//! views that show each player their own rows.

use crate::row;
use crate::store::{Seconds, Table, World};

/// The realm itself: one row, keyed 0.
#[spacetimedb::table(accessor = realm, public)]
#[derive(Clone, Debug, PartialEq)]
pub struct Realm {
    #[primary_key]
    pub id: u64,
    /// What the world was grown from.
    pub seed: u64,
    /// The moment the realm opened.
    pub opened: Seconds,
    /// How many times faster than written every build, march and harvest
    /// runs: 1 for the realm proper, more for a trial realm.
    pub pace: u32,
    /// The minute in which players last joined, and how many did.
    pub joining_minute: Seconds,
    pub joined_in_minute: u32,
    /// How many hexes the world reaches from the lake's heart.
    pub radius: u32,
}
row!(Realm in realm, by id);

/// A chunk of the land, sixteen hexes by sixteen: a byte a hex, its ground
/// (`land::Ground`), row by row. Keyed by the chunk's own place.
#[spacetimedb::table(accessor = land, public)]
#[derive(Clone, Debug, PartialEq)]
pub struct Land {
    #[primary_key]
    pub chunk: u64,
    pub ground: Vec<u8>,
}
row!(Land in land, by chunk);

/// What stands on a hex: at most one thing. Keyed by the hex.
#[spacetimedb::table(accessor = place, public)]
#[derive(Clone, Debug, PartialEq)]
pub struct Place {
    #[primary_key]
    pub hex: u64,
    /// What kind of thing (`Place::CITY` and the rest), and its number
    /// among its kind.
    pub kind: u8,
    pub id: u64,
}
row!(Place in place, by hex);

impl Place {
    pub const CITY: u8 = 1;
    pub const SITE: u8 = 2;
    pub const BARROW: u8 = 3;
}

/// Somewhere on the land where goods lie to be gathered, until they run
/// out. Everyone sees it, and whose army is working it.
#[spacetimedb::table(accessor = site, public)]
#[derive(Clone, Debug, PartialEq)]
pub struct Site {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    pub hex: u64,
    /// Which good lies there (`Site::GRAIN` and the rest), how rich it was
    /// found, and how much is left.
    pub kind: u8,
    pub level: u32,
    pub left: u64,
    /// The march gathering there now; 0 for none.
    pub gatherer: u64,
}
row!(Site in site, auto, by id);

impl Site {
    pub const GRAIN: u8 = 1;
    pub const TIMBER: u8 = 2;
    pub const STONE: u8 = 3;
    pub const MOONSALT: u8 = 4;
}

/// An army out of its city: where it set out from, where it is bound, the
/// way it takes and when it gets there. Everyone sees it on the map; what
/// it is made of and what it carries are its owner's alone to read.
///
/// On the way out or home it moves along `route` from `departed` to
/// `arrives`, at an even pace. Working, it stands at `to` until `arrives`.
#[spacetimedb::table(accessor = march, public)]
#[derive(Clone, Debug, PartialEq)]
pub struct March {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    #[index(btree)]
    pub owner: u64,
    #[index(btree)]
    pub city: u64,
    /// What it set out to do (`March::GATHER`), and what it is doing now
    /// (`March::GOING`, `WORKING`, `RETURNING`).
    pub kind: u8,
    pub state: u8,
    pub from: u64,
    pub to: u64,
    /// What it set out for: a site's number, a barrow's, or a city's.
    pub target: u64,
    pub departed: Seconds,
    pub arrives: Seconds,
    /// How many soldiers march.
    pub soldiers: u64,
    /// The way it is on now, hex by hex (`hex::decode`).
    pub route: Vec<u8>,
    pub timer: u64,
    /// The commander who leads it; 0 for none.
    pub leader: u64,
}
row!(March in march, auto, by id, owner, city);

impl March {
    /// To gather at a site.
    pub const GATHER: u8 = 1;
    /// To clear a barrow of the Unquiet.
    pub const HUNT: u8 = 2;
    /// To take another player's city by storm and plunder it.
    pub const ATTACK: u8 = 3;
    /// To see what a city's garrison is, from its walls, without a fight.
    pub const SCOUT: u8 = 4;
    /// To join an ally's city as its garrison, and stay there.
    pub const REINFORCE: u8 = 5;
    /// To go against a barrow with allies' armies, as one (see `Rally`).
    pub const RALLY: u8 = 6;

    pub const GOING: u8 = 1;
    pub const WORKING: u8 = 2;
    pub const RETURNING: u8 = 3;
    /// Fighting where it stands, at `to`, until `arrives`.
    pub const FIGHTING: u8 = 4;
    /// In its city, gathered for a rally that sets out at `arrives`.
    pub const MUSTERING: u8 = 5;
    /// At the barrow, waiting for the rally's other armies to come up.
    pub const WAITING: u8 = 6;
}

/// The soldiers of one kind and tier in a march: its owner's alone to
/// read. Keyed by march, kind and tier.
#[spacetimedb::table(accessor = squad)]
#[derive(Clone, Debug, PartialEq)]
pub struct Squad {
    #[primary_key]
    pub id: u64,
    #[index(btree)]
    pub march: u64,
    pub kind: u8,
    pub tier: u32,
    /// How many march fit to fight, and how many it carries wounded.
    pub count: u64,
    pub wounded: u64,
}
row!(Squad in squad, by id, march);

impl Squad {
    pub fn key(march: u64, kind: u8, tier: u32) -> u64 {
        (march << 16) | ((kind as u64) << 8) | tier as u64
    }
}

/// What a march carries home: its owner's alone to read. Keyed by the
/// march.
#[spacetimedb::table(accessor = haul)]
#[derive(Clone, Debug, PartialEq)]
pub struct Haul {
    #[primary_key]
    pub march: u64,
    #[index(btree)]
    pub owner: u64,
    pub grain: u64,
    pub timber: u64,
    pub stone: u64,
    pub moonsalt: u64,
}
row!(Haul in haul, by march, owner);

/// What a building costs and gives at a level, as the catalogue has it:
/// the game's numbers, for clients to show. Keyed by kind and level.
#[spacetimedb::table(accessor = blueprint, public)]
#[derive(Clone, Debug, PartialEq)]
pub struct Blueprint {
    #[primary_key]
    pub id: u64,
    pub building: u8,
    pub level: u32,
    pub name: String,
    /// What raising it to this level costs, and how long it takes in this
    /// realm.
    pub grain: u64,
    pub timber: u64,
    pub stone: u64,
    pub moonsalt: u64,
    pub seconds: Seconds,
    /// What it gives each hour at this level in this realm.
    pub grain_hourly: u64,
    pub timber_hourly: u64,
    pub stone_hourly: u64,
    pub moonsalt_hourly: u64,
    /// The Keep level it opens at, and the other building and level that
    /// must stand first (0 for none).
    pub opens_at: u32,
    pub needs_building: u8,
    pub needs_level: u32,
    pub power: u64,
}
row!(Blueprint in blueprint, by id);

impl Blueprint {
    pub fn key(building: u8, level: u32) -> u64 {
        ((building as u64) << 32) | level as u64
    }
}

/// A player, as everyone may know them.
#[spacetimedb::table(accessor = player, public)]
#[derive(Clone, Debug, PartialEq)]
pub struct Player {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    /// The name folded to one case and hashed: no two players share a
    /// name, however it is capitalised.
    #[index(btree)]
    pub name_key: u64,
    pub name: String,
    pub joined: Seconds,
    /// Whether they are connected now, and when they were last seen.
    pub online: bool,
    pub seen: Seconds,
}
row!(Player in player, auto, by id, name_key);

/// How fast a player has been asking things of the realm: theirs alone,
/// keyed by their player number.
#[spacetimedb::table(accessor = pace)]
#[derive(Clone, Debug, PartialEq)]
pub struct Pace {
    #[primary_key]
    pub player: u64,
    /// The start of the ten seconds being counted, and the count.
    pub window: Seconds,
    pub asked: u32,
    /// When they last said something for others to read.
    pub said: Seconds,
}
row!(Pace in pace, by player);

/// A city: where it stands and whose it is, as everyone may know.
#[spacetimedb::table(accessor = city, public)]
#[derive(Clone, Debug, PartialEq)]
pub struct City {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    #[index(btree)]
    pub owner: u64,
    pub hex: u64,
    pub name: String,
    /// Its Keep's level, and the power of all that stands in it.
    pub keep: u32,
    pub power: u64,
    pub founded: Seconds,
    /// How many buildings it can raise at once.
    pub builders: u32,
    /// Until when it is at peace: no army may attack it before then.
    pub shield: Seconds,
}
row!(City in city, auto, by id, owner);

/// A building in a city. Its owner's alone to read, but for the Keep's
/// level, which the city shows.
#[spacetimedb::table(accessor = building)]
#[derive(Clone, Debug, PartialEq)]
pub struct Building {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    #[index(btree)]
    pub city: u64,
    /// Which building (`catalog::Building`), and its level: 0 while it is
    /// first being raised.
    pub kind: u8,
    pub level: u32,
}
row!(Building in building, auto, by id, city);

/// Something a city has under way that ends at a moment: its owner's
/// alone to read.
#[spacetimedb::table(accessor = job)]
#[derive(Clone, Debug, PartialEq)]
pub struct Job {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    #[index(btree)]
    pub city: u64,
    /// What kind of work (`Job::RAISE` and the rest), on what, and to what:
    /// a building and its new level, or a training building, the tier it
    /// trains and how many.
    pub kind: u8,
    pub subject: u64,
    pub level: u32,
    pub amount: u64,
    pub started: Seconds,
    pub ends: Seconds,
    /// The timer that ends it.
    pub timer: u64,
}
row!(Job in job, auto, by id, city);

impl Job {
    /// A building being raised a level: its subject is the building.
    pub const RAISE: u8 = 1;
    /// Troops in training: its subject is the building that trains them.
    pub const TRAIN: u8 = 2;
    /// Wounded being healed: its subject is their troop row, its level
    /// their tier, its amount how many.
    pub const HEAL: u8 = 3;
    /// A topic being studied in the Academy: its subject is the topic,
    /// its level the one being learnt.
    pub const STUDY: u8 = 4;
}

/// A city's troops of one kind and tier: its owner's alone to read. Keyed
/// by city, kind and tier.
#[spacetimedb::table(accessor = troop)]
#[derive(Clone, Debug, PartialEq)]
pub struct Troop {
    #[primary_key]
    pub id: u64,
    #[index(btree)]
    pub city: u64,
    pub kind: u8,
    pub tier: u32,
    /// How many stand ready in the city, and how many lie wounded in its
    /// Hospital.
    pub ready: u64,
    pub wounded: u64,
}
row!(Troop in troop, by id, city);

impl Troop {
    pub fn key(city: u64, kind: u8, tier: u32) -> u64 {
        (city << 16) | ((kind as u64) << 8) | tier as u64
    }
}

/// What one soldier of a kind and tier is and costs in this realm, as the
/// catalogue has it, for clients to show. Keyed by kind and tier.
#[spacetimedb::table(accessor = soldier, public)]
#[derive(Clone, Debug, PartialEq)]
pub struct Soldier {
    #[primary_key]
    pub id: u64,
    pub kind: u8,
    pub tier: u32,
    pub name: String,
    pub attack: u64,
    pub defence: u64,
    pub health: u64,
    /// Tenths of a second to cross a hex, in this realm.
    pub pace: u64,
    pub load: u64,
    pub power: u64,
    pub grain: u64,
    pub timber: u64,
    pub stone: u64,
    pub moonsalt: u64,
    /// Thousandths of a second to train one, in this realm.
    pub millis: u64,
    /// The building that trains them, and the level it must have reached.
    pub building: u8,
    pub needs_level: u32,
}
row!(Soldier in soldier, by id);

impl Soldier {
    pub fn key(kind: u8, tier: u32) -> u64 {
        ((kind as u64) << 8) | tier as u64
    }
}

/// A city's goods: its owner's alone to read. Keyed by the city.
///
/// The amounts are as they stood at `as_of`. Since then each has grown by
/// its hourly rate, up to `holds`: the rules settle that whenever they
/// touch the row, and a client reckons it for itself between times.
#[spacetimedb::table(accessor = stock)]
#[derive(Clone, Debug, PartialEq)]
pub struct Stock {
    #[primary_key]
    pub city: u64,
    pub grain: u64,
    pub timber: u64,
    pub stone: u64,
    pub moonsalt: u64,
    pub as_of: Seconds,
    pub grain_hourly: u64,
    pub timber_hourly: u64,
    pub stone_hourly: u64,
    pub moonsalt_hourly: u64,
    /// What each good had earned toward its next whole unit at `as_of`, in
    /// 3,600ths.
    pub grain_part: u32,
    pub timber_part: u32,
    pub stone_part: u32,
    pub moonsalt_part: u32,
    /// The most of each good the city keeps: nothing more comes in past it.
    pub holds: u64,
}
row!(Stock in stock, by city);

/// A barrow of the Unquiet on the land, for players to clear. Everyone
/// sees it, and whether an army is fighting there.
#[spacetimedb::table(accessor = barrow, public)]
#[derive(Clone, Debug, PartialEq)]
pub struct Barrow {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    pub hex: u64,
    /// How strong it is, 1 to 25 (`catalog::barrow`).
    pub level: u32,
    /// The march fighting there now; 0 for none.
    pub fighter: u64,
}
row!(Barrow in barrow, auto, by id);

/// What a player has for hunting the Unquiet: theirs alone to read. Keyed
/// by their player number.
///
/// `energy` is as it stood at `as_of`. Since then it has grown by a point
/// every `point_millis`, up to `most`: the rules settle that whenever
/// they touch the row, and a client reckons it for itself between times.
#[spacetimedb::table(accessor = hunt)]
#[derive(Clone, Debug, PartialEq)]
pub struct Hunt {
    #[primary_key]
    pub player: u64,
    pub energy: u32,
    pub as_of: Seconds,
    pub most: u32,
    pub point_millis: u64,
    /// The strongest barrow they have cleared: they may attack one level
    /// above it.
    pub cleared: u32,
}
row!(Hunt in hunt, by player);

/// What happened to a player's army, told to them: theirs alone to read.
#[spacetimedb::table(accessor = report)]
#[derive(Clone, Debug, PartialEq)]
pub struct Report {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    #[index(btree)]
    pub player: u64,
    pub at: Seconds,
    /// What it tells of (`Report::HUNT`), where, and whether it went the
    /// player's way.
    pub kind: u8,
    pub hex: u64,
    pub won: bool,
    /// The other side: a barrow's level, or a player's number.
    pub foe: u64,
    pub rounds: u32,
    /// The player's soldiers: how many fought, and of them how many came
    /// away wounded and how many died.
    pub fought: u64,
    pub wounded: u64,
    pub dead: u64,
    /// The other side's: how many stood, and how many fell.
    pub stood: u64,
    pub fell: u64,
    /// What was won.
    pub grain: u64,
    pub timber: u64,
    pub stone: u64,
    pub moonsalt: u64,
    /// The whole of it in plain words.
    pub words: String,
    pub read: bool,
}
row!(Report in report, auto, by id, player);

impl Report {
    /// A fight at a barrow: `foe` is the barrow's level.
    pub const HUNT: u8 = 1;
    /// The player's army at another's city, and another's army at the
    /// player's own: `foe` is the other player's number.
    pub const ATTACK: u8 = 2;
    pub const DEFENCE: u8 = 3;
    /// Another's army is marching on the player's city: `foe` is that
    /// player's number, and the report says when it arrives.
    pub const WARNING: u8 = 4;
    /// What the player's scouts saw of another's city: `stood` is how many
    /// soldiers were ready in it, and `foe` its owner's number.
    pub const SCOUTED: u8 = 5;
    /// An ally's soldiers have joined the player's city as its garrison:
    /// `foe` is the ally's number, and `stood` how many came.
    pub const REINFORCED: u8 = 6;
    /// Of the player's alliance's Moonspire, and of the season's end.
    pub const SPIRE: u8 = 7;
}

/// An alliance of players. Everyone may read it.
#[spacetimedb::table(accessor = alliance, public)]
#[derive(Clone, Debug, PartialEq)]
pub struct Alliance {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    /// Its name and its tag, each folded to one case and hashed: no two
    /// alliances share either.
    #[index(btree)]
    pub name_key: u64,
    #[index(btree)]
    pub tag_key: u64,
    pub name: String,
    /// Its short name, three or four letters, shown before its members'.
    pub tag: String,
    pub leader: u64,
    pub founded: Seconds,
    pub members: u32,
    /// Whether anyone may join without being let in.
    pub open: bool,
    /// What it says of itself.
    pub words: String,
}
row!(Alliance in alliance, auto, by id, name_key, tag_key);

/// A player's place in an alliance. Everyone may read it. Keyed by the
/// player: no one is in two.
#[spacetimedb::table(accessor = member, public)]
#[derive(Clone, Debug, PartialEq)]
pub struct Member {
    #[primary_key]
    pub player: u64,
    #[index(btree)]
    pub alliance: u64,
    /// `Member::MEMBER`, `OFFICER` or `LEADER`.
    pub rank: u8,
    pub joined: Seconds,
}
row!(Member in member, by player, alliance);

impl Member {
    pub const MEMBER: u8 = 1;
    pub const OFFICER: u8 = 4;
    pub const LEADER: u8 = 5;
}

/// A player asking to be let into an alliance that is not open: for the
/// player and that alliance's officers to read. Keyed by the player: one
/// asking at a time.
#[spacetimedb::table(accessor = applicant)]
#[derive(Clone, Debug, PartialEq)]
pub struct Applicant {
    #[primary_key]
    pub player: u64,
    #[index(btree)]
    pub alliance: u64,
    pub name: String,
    pub at: Seconds,
}
row!(Applicant in applicant, by player, alliance);

/// Something said in the realm, for everyone to read.
#[spacetimedb::table(accessor = realm_chat, public)]
#[derive(Clone, Debug, PartialEq)]
pub struct RealmChat {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    pub player: u64,
    /// Their name as it was, with their alliance's tag if they had one.
    pub name: String,
    pub at: Seconds,
    pub words: String,
}
row!(RealmChat in realm_chat, auto, by id);

/// Something said within an alliance, for its members alone to read.
#[spacetimedb::table(accessor = alliance_chat)]
#[derive(Clone, Debug, PartialEq)]
pub struct AllianceChat {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    #[index(btree)]
    pub alliance: u64,
    pub player: u64,
    pub name: String,
    pub at: Seconds,
    pub words: String,
}
row!(AllianceChat in alliance_chat, auto, by id, alliance);

/// One of a player's first tasks, as the catalogue has it, for clients to
/// show: what it asks, in words and in numbers a client can check
/// against its own rows (`catalog::Goal::numbers`), and what it gives.
/// Keyed by its place in the order, from 1.
#[spacetimedb::table(accessor = task, public)]
#[derive(Clone, Debug, PartialEq)]
pub struct Task {
    #[primary_key]
    pub step: u64,
    pub goal: u8,
    pub amount: u64,
    pub level: u64,
    pub words: String,
    pub grain: u64,
    pub timber: u64,
    pub stone: u64,
    pub moonsalt: u64,
}
row!(Task in task, by step);

/// How far through their tasks a player is: theirs alone to read. Keyed
/// by their player number. `step` is the task they are on; one past the
/// last when they have done them all.
#[spacetimedb::table(accessor = progress)]
#[derive(Clone, Debug, PartialEq)]
pub struct Progress {
    #[primary_key]
    pub player: u64,
    pub step: u64,
}
row!(Progress in progress, by player);

/// A deed of the day's work, for clients to show: what it asks and the
/// marks it earns. Keyed by deed.
#[spacetimedb::table(accessor = duty, public)]
#[derive(Clone, Debug, PartialEq)]
pub struct Duty {
    #[primary_key]
    pub deed: u64,
    pub asks: u64,
    pub marks: u32,
    pub words: String,
}
row!(Duty in duty, by deed);

/// One of the day's chests, for clients to show: the marks it asks and
/// what it holds. Keyed by its place among them, from 1.
#[spacetimedb::table(accessor = chest, public)]
#[derive(Clone, Debug, PartialEq)]
pub struct Chest {
    #[primary_key]
    pub id: u64,
    pub marks: u32,
    pub grain: u64,
    pub timber: u64,
    pub stone: u64,
    pub moonsalt: u64,
    /// How many of each haste it holds: five minutes', an hour's, eight hours'.
    pub brief_hastes: u64,
    pub hour_hastes: u64,
    pub long_hastes: u64,
}
row!(Chest in chest, by id);

/// The points a commander has put into a talent: their owner's alone to
/// read. Keyed by commander and talent.
#[spacetimedb::table(accessor = skill)]
#[derive(Clone, Debug, PartialEq)]
pub struct Skill {
    #[primary_key]
    pub id: u64,
    #[index(btree)]
    pub commander: u64,
    #[index(btree)]
    pub owner: u64,
    pub talent: u8,
    pub points: u32,
}
row!(Skill in skill, by id, commander, owner);

impl Skill {
    pub fn key(commander: u64, talent: u8) -> u64 {
        (commander << 8) | talent as u64
    }
}

/// A commander who goes out beside another, adding half of their own way
/// of war: their owner's alone to read. Keyed by the commander who leads.
#[spacetimedb::table(accessor = bond)]
#[derive(Clone, Debug, PartialEq)]
pub struct Bond {
    #[primary_key]
    pub commander: u64,
    #[index(btree)]
    pub owner: u64,
    pub partner: u64,
}
row!(Bond in bond, by commander, owner);

/// The commander a player has keep their city, who adds what they bring
/// to its defence while they are in it: theirs alone to read. Keyed by
/// player.
#[spacetimedb::table(accessor = keeper)]
#[derive(Clone, Debug, PartialEq)]
pub struct Keeper {
    #[primary_key]
    pub player: u64,
    pub commander: u64,
}
row!(Keeper in keeper, by player);

/// An alliance's Moonspire this season: the stage it stands at, whether
/// the next is being raised and till when, and the goods given toward the
/// next. For everyone to read: the realm's seasons are a race to raise
/// one. Keyed by alliance.
#[spacetimedb::table(accessor = spire, public)]
#[derive(Clone, Debug, PartialEq)]
pub struct Spire {
    #[primary_key]
    pub alliance: u64,
    /// The alliance's name as it was when it began this one.
    pub name: String,
    pub season: u64,
    pub stage: u32,
    /// When the stage being raised stands; 0 when none is.
    pub rises_at: Seconds,
    pub timer: u64,
    pub grain: u64,
    pub timber: u64,
    pub stone: u64,
    pub moonsalt: u64,
}
row!(Spire in spire, by alliance);

/// A season of the realm: when it began and ends, and the alliance that
/// first raised its Moonspire whole in it, if one has. For everyone to
/// read. Keyed by its number, from 1.
#[spacetimedb::table(accessor = season, public)]
#[derive(Clone, Debug, PartialEq)]
pub struct Season {
    #[primary_key]
    pub number: u64,
    pub began: Seconds,
    pub ends: Seconds,
    /// The first alliance to raise its Moonspire whole, and its name then; 0 and empty for none yet.
    pub victor: u64,
    pub victor_name: String,
    pub won_at: Seconds,
}
row!(Season in season, by number);

/// What a player has given toward their alliance's Moonspire this season:
/// theirs alone to read. Keyed by player.
#[spacetimedb::table(accessor = gift)]
#[derive(Clone, Debug, PartialEq)]
pub struct Gift {
    #[primary_key]
    pub player: u64,
    pub season: u64,
    /// Goods given, all four counted together.
    pub given: u64,
}
row!(Gift in gift, by player);

/// A work its owner has asked their alliance's help with: the alliance's
/// alone to read. Keyed by the work's job. It lasts as long as the work.
#[spacetimedb::table(accessor = plea)]
#[derive(Clone, Debug, PartialEq)]
pub struct Plea {
    #[primary_key]
    pub job: u64,
    #[index(btree)]
    pub alliance: u64,
    /// Who asked, and their name as it was then.
    pub asker: u64,
    pub name: String,
    /// What kind of work it is (`Job::RAISE` and the rest).
    pub work: u8,
    /// How many have helped, and how many may.
    pub helped: u32,
    pub most: u32,
}
row!(Plea in plea, by job, alliance);

/// That a player has helped with a work: they may once. Keyed by the
/// work's job and the player.
#[spacetimedb::table(accessor = helper)]
#[derive(Clone, Debug, PartialEq)]
pub struct Helper {
    #[primary_key]
    pub id: u64,
    #[index(btree)]
    pub job: u64,
    #[index(btree)]
    pub player: u64,
}
row!(Helper in helper, by id, job, player);

impl Helper {
    pub fn key(job: u64, player: u64) -> u64 {
        (job << 24) | (player & 0xFF_FFFF)
    }
}

/// A rally: allies' armies against a barrow too strong for one of them.
/// Each musters in its own city until the rally sets out, marches from
/// there, waits at the barrow for the last, and they fight as one. Its
/// alliance's alone to read.
#[spacetimedb::table(accessor = rally)]
#[derive(Clone, Debug, PartialEq)]
pub struct Rally {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    #[index(btree)]
    pub alliance: u64,
    /// Who called it, and their name as it was then.
    pub caller: u64,
    pub name: String,
    pub barrow: u64,
    pub hex: u64,
    pub level: u32,
    /// When the muster ends and the armies set out.
    pub sets_out: Seconds,
    /// `Rally::MUSTERING`, `MARCHING` or `FIGHTING`.
    pub state: u8,
    pub armies: u32,
    pub soldiers: u64,
}
row!(Rally in rally, auto, by id, alliance);

impl Rally {
    pub const MUSTERING: u8 = 1;
    pub const MARCHING: u8 = 2;
    pub const FIGHTING: u8 = 3;
}

/// An army's place in a rally: its alliance's alone to read. Keyed by
/// the army's march.
#[spacetimedb::table(accessor = muster)]
#[derive(Clone, Debug, PartialEq)]
pub struct Muster {
    #[primary_key]
    pub march: u64,
    #[index(btree)]
    pub rally: u64,
    pub player: u64,
    /// Whether it has come up to the barrow.
    pub arrived: bool,
}
row!(Muster in muster, by march, rally);

/// A contest of the realm, for clients to show: how it is scored, every
/// how many days it comes round and for how many of them it runs. Keyed
/// by contest.
#[spacetimedb::table(accessor = trial, public)]
#[derive(Clone, Debug, PartialEq)]
pub struct Trial {
    #[primary_key]
    pub id: u64,
    pub name: String,
    pub words: String,
    pub every: u64,
    pub lasts: u64,
}
row!(Trial in trial, by id);

/// A prize of a contest, for clients to show: the points it asks and what
/// it gives. Keyed by contest and its place among that contest's prizes,
/// from 1.
#[spacetimedb::table(accessor = prize, public)]
#[derive(Clone, Debug, PartialEq)]
pub struct Prize {
    #[primary_key]
    pub id: u64,
    pub trial: u8,
    pub place: u8,
    pub points: u64,
    pub grain: u64,
    pub timber: u64,
    pub stone: u64,
    pub moonsalt: u64,
    pub brief_hastes: u64,
    pub hour_hastes: u64,
    pub long_hastes: u64,
}
row!(Prize in prize, by id);

impl Prize {
    pub fn key(trial: u8, place: u8) -> u64 {
        ((trial as u64) << 8) | place as u64
    }
}

/// What a player has scored in a contest's round: theirs alone to read.
/// Keyed by player and contest. It holds for the round it names, and is
/// begun afresh when they score in a later one.
#[spacetimedb::table(accessor = tally)]
#[derive(Clone, Debug, PartialEq)]
pub struct Tally {
    #[primary_key]
    pub id: u64,
    #[index(btree)]
    pub player: u64,
    pub trial: u8,
    /// Which coming-round of the contest these were scored in, from 0.
    pub round: u64,
    pub points: u64,
    /// Which prizes have been claimed: a bit for each, the first the lowest.
    pub claimed: u8,
}
row!(Tally in tally, by id, player);

impl Tally {
    pub fn key(player: u64, trial: u8) -> u64 {
        (player << 8) | trial as u64
    }
}

/// An item, for clients to show: its name, what it does, and the time it
/// takes off a work as written (in a realm that runs faster, as much less
/// as everything there takes less). Keyed by item.
#[spacetimedb::table(accessor = ware, public)]
#[derive(Clone, Debug, PartialEq)]
pub struct Ware {
    #[primary_key]
    pub item: u64,
    pub name: String,
    pub words: String,
    pub seconds: Seconds,
}
row!(Ware in ware, by item);

/// How many of an item a player keeps: theirs alone to read. Keyed by
/// player and item.
#[spacetimedb::table(accessor = satchel)]
#[derive(Clone, Debug, PartialEq)]
pub struct Satchel {
    #[primary_key]
    pub id: u64,
    #[index(btree)]
    pub player: u64,
    pub item: u8,
    pub count: u64,
}
row!(Satchel in satchel, by id, player);

impl Satchel {
    pub fn key(player: u64, item: u8) -> u64 {
        (player << 8) | item as u64
    }
}

/// What a player has done of the day's work: theirs alone to read. Keyed
/// by player. It holds for the day it names, and is begun afresh the
/// first time they do something on a later one.
#[spacetimedb::table(accessor = daily)]
#[derive(Clone, Debug, PartialEq)]
pub struct Daily {
    #[primary_key]
    pub player: u64,
    /// The day of the realm these were done on, counted from its opening.
    pub day: u64,
    pub trained: u64,
    pub gathered: u64,
    pub cleared: u64,
    pub begun: u64,
    pub hastened: u64,
    /// Which chests have been opened: a bit for each, the first the lowest.
    pub opened: u8,
}
row!(Daily in daily, by player);

/// A level of favour, for clients to show: the favour it asks, and by
/// how many hundredths it hastens every work. Keyed by level, from 0.
#[spacetimedb::table(accessor = grace, public)]
#[derive(Clone, Debug, PartialEq)]
pub struct Grace {
    #[primary_key]
    pub level: u64,
    pub points: u64,
    pub sooner: u32,
}
row!(Grace in grace, by level);

/// The favour a player has earned, and the level it stands at: theirs
/// alone to read. Keyed by player; there is no row until they earn some.
#[spacetimedb::table(accessor = favour)]
#[derive(Clone, Debug, PartialEq)]
pub struct Favour {
    #[primary_key]
    pub player: u64,
    pub points: u64,
    pub level: u32,
}
row!(Favour in favour, by player);

/// What a city has learnt of a topic: its owner's alone to read. Keyed
/// by city and topic.
#[spacetimedb::table(accessor = lore)]
#[derive(Clone, Debug, PartialEq)]
pub struct Lore {
    #[primary_key]
    pub id: u64,
    #[index(btree)]
    pub city: u64,
    pub topic: u8,
    pub level: u32,
}
row!(Lore in lore, by id, city);

impl Lore {
    pub fn key(city: u64, topic: u8) -> u64 {
        (city << 8) | topic as u64
    }
}

/// What learning a level of a topic costs and gives in this realm, as
/// the catalogue has it, for clients to show. Keyed by topic and level.
#[spacetimedb::table(accessor = study, public)]
#[derive(Clone, Debug, PartialEq)]
pub struct Study {
    #[primary_key]
    pub id: u64,
    pub topic: u8,
    pub level: u32,
    pub name: String,
    /// What the topic does, in a player's words, and how many hundredths
    /// each level adds.
    pub words: String,
    pub each: u64,
    pub grain: u64,
    pub timber: u64,
    pub stone: u64,
    pub moonsalt: u64,
    pub seconds: Seconds,
    /// The level the Academy must have reached.
    pub needs_level: u32,
}
row!(Study in study, by id);

impl Study {
    pub fn key(topic: u8, level: u32) -> u64 {
        ((topic as u64) << 32) | level as u64
    }
}

/// Someone who leads a player's armies: their owner's alone to read.
#[spacetimedb::table(accessor = commander)]
#[derive(Clone, Debug, PartialEq)]
pub struct Commander {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    #[index(btree)]
    pub owner: u64,
    pub name: String,
    /// Their way of war (`catalog::Way`), their level, and what they have
    /// seen toward the next.
    pub way: u8,
    pub level: u32,
    pub seen: u64,
    /// The march they lead now; 0 while they are in the city.
    pub march: u64,
}
row!(Commander in commander, auto, by id, owner);

/// Everything the rules keep: every table, the clock, chance and timers.
pub trait Db:
    World
    + Table<Realm>
    + Table<Player>
    + Table<Pace>
    + Table<Land>
    + Table<Place>
    + Table<Blueprint>
    + Table<City>
    + Table<Building>
    + Table<Job>
    + Table<Stock>
    + Table<Troop>
    + Table<Soldier>
    + Table<Site>
    + Table<March>
    + Table<Squad>
    + Table<Haul>
    + Table<Barrow>
    + Table<Hunt>
    + Table<Report>
    + Table<Alliance>
    + Table<Member>
    + Table<Applicant>
    + Table<RealmChat>
    + Table<AllianceChat>
    + Table<Task>
    + Table<Progress>
    + Table<Duty>
    + Table<Chest>
    + Table<Daily>
    + Table<Grace>
    + Table<Favour>
    + Table<Ware>
    + Table<Satchel>
    + Table<Trial>
    + Table<Prize>
    + Table<Tally>
    + Table<Rally>
    + Table<Muster>
    + Table<Plea>
    + Table<Helper>
    + Table<Spire>
    + Table<Season>
    + Table<Gift>
    + Table<Skill>
    + Table<Bond>
    + Table<Keeper>
    + Table<Lore>
    + Table<Study>
    + Table<Commander>
{
}

impl<
        T: World
            + Table<Realm>
            + Table<Player>
            + Table<Pace>
            + Table<Land>
            + Table<Place>
            + Table<Blueprint>
            + Table<City>
            + Table<Building>
            + Table<Job>
            + Table<Stock>
            + Table<Troop>
            + Table<Soldier>
            + Table<Site>
            + Table<March>
            + Table<Squad>
            + Table<Haul>
            + Table<Barrow>
            + Table<Hunt>
            + Table<Report>
            + Table<Alliance>
            + Table<Member>
            + Table<Applicant>
            + Table<RealmChat>
            + Table<AllianceChat>
            + Table<Task>
            + Table<Progress>
            + Table<Duty>
            + Table<Chest>
            + Table<Daily>
            + Table<Grace>
            + Table<Favour>
            + Table<Ware>
            + Table<Satchel>
            + Table<Trial>
            + Table<Prize>
            + Table<Tally>
            + Table<Rally>
            + Table<Muster>
            + Table<Plea>
            + Table<Helper>
            + Table<Spire>
            + Table<Season>
            + Table<Gift>
            + Table<Skill>
            + Table<Bond>
            + Table<Keeper>
            + Table<Lore>
            + Table<Study>
            + Table<Commander>,
    > Db for T
{
}
