//! The realm as a SpacetimeDB module.
//!
//! Nothing of the game is decided here. Each reducer finds who is asking,
//! hands the request to the rules over the database (`Stdb`), and gives the
//! player the rules' refusal, in its own words, if there is one. The one
//! timer table schedules whatever the rules ask to happen later.

use spacetimedb::{reducer, table, view, Identity, ReducerContext, ScheduleAt, SpacetimeType, Table as _, Timestamp, ViewContext};

use crate::hex::Hex;
use crate::rows::{
    alliance as _, alliance_chat as _, alliance_chat__view as _, applicant as _, applicant__view as _, barrow as _, blueprint as _, building as _,
    chest as _, daily as _, daily__view as _, duty as _, fame as _, boon as _, boon__view as _, cairn as _, find as _, find__view as _, honour as _, honour__view as _, price as _, favour as _, favour__view as _, grace as _, satchel as _, satchel__view as _, ware as _, prize as _, tally as _, tally__view as _, standing as _, laurel as _, link as _, link__view as _, trial as _, muster as _, muster__view as _, rally as _, rally__view as _, helper as _, helper__view as _, plea as _, plea__view as _, gift as _, gift__view as _, season as _, spire as _, bond as _, bond__view as _, keeper as _, keeper__view as _, skill as _, skill__view as _, ward as _, learning as _, gate as _, envoy as _, envoy__view as _, pact as _, prisoner as _, prisoner__view as _, petition as _, petition__view as _, title as _, letter as _, letter__view as _, shun as _, shun__view as _, mark as _, mark__view as _, milestone as _, claim as _, claim__view as _, welcome as _, welcome__view as _, stage as _, road as _, road__view as _, gear as _, gear__view as _, pattern as _,
    building__view as _, city as _, city__view as _, commander as _, commander__view as _, haul as _, haul__view as _, hunt as _, hunt__view as _, job as _, job__view as _, land as _, lore as _, lore__view as _,
    march as _, march__view as _, member as _, member__view as _, pace as _, place as _, player as _, player__view as _, progress as _, progress__view as _, realm as _,
    realm_chat as _, complaint as _, bar as _, report as _, report__view as _, site as _, soldier as _, squad as _, squad__view as _, stock as _, stock__view as _, study as _, task as _,
    person as _, troop as _, troop__view as _, Alliance, AllianceChat, Applicant, Barrow, Blueprint, Bond, Building, Chest, City, Commander, Daily, Duty, Fame, Boon, Cairn, Find, Honour, Price, Favour, Gift, Grace, Haul, Helper, Hunt, Job, Keeper, Land, Lore, March, Member, Muster, Rally,
    Pace, Place, Player, Plea, Prize, Progress, Realm, RealmChat, Complaint, Bar, Report, Satchel, Season, Site, Skill, Soldier, Spire, Squad, Stock, Study, Tally, Standing, Laurel, Link, Task, Trial, Troop, Ware, Person, Ward, Learning, Gate, Envoy, Pact, Prisoner, Petition, Title, Letter, Shun, Mark, Milestone, Claim, Welcome, Stage, Road, Gear, Pattern,
};
use crate::rules::{self, Refusal};
use crate::store::{Seconds, Table, World};

/// Whose player a connection's identity is. The rules know players by
/// number alone; only the module knows identities. A player may play from
/// more than one device, each its own identity (`take_link`).
#[table(accessor = account)]
pub struct Account {
    #[primary_key]
    pub identity: Identity,
    #[index(btree)]
    pub player: u64,
}

/// How many connections an identity has open. A player's client keeps a
/// subscription open while it runs, and each thing it asks over HTTP is a
/// connection of its own that opens and closes: a player is here while
/// any of theirs is open.
#[table(accessor = presence)]
pub struct Presence {
    #[primary_key]
    pub identity: Identity,
    pub connections: u32,
}

/// What a player's client calls the device it runs on ("Mac", "iPhone"),
/// shown among their devices to them alone.
#[table(accessor = device_name)]
pub struct DeviceName {
    #[primary_key]
    pub identity: Identity,
    pub name: String,
}

/// Who published the module: the realm's owner, who alone sets its pace.
#[table(accessor = owner)]
pub struct Owner {
    #[primary_key]
    pub id: u8,
    pub identity: Identity,
}

/// What the rules have asked to happen later: the scheduler calls `fire`
/// with the row when its moment comes.
#[table(accessor = timer, scheduled(fire))]
pub struct Timer {
    #[primary_key]
    #[auto_inc]
    pub scheduled_id: u64,
    pub scheduled_at: ScheduleAt,
    pub kind: u8,
    pub subject: u64,
}

/// The database, as the rules see it.
struct Stdb<'a>(&'a ReducerContext);

impl World for Stdb<'_> {
    fn now(&self) -> Seconds {
        self.0.timestamp.to_micros_since_unix_epoch().div_euclid(1_000_000)
    }

    fn chance(&mut self) -> u64 {
        self.0.random()
    }

    fn after(&mut self, at: Seconds, kind: u8, subject: u64) -> u64 {
        let moment = Timestamp::from_micros_since_unix_epoch(at.saturating_mul(1_000_000));
        self.0.db.timer().insert(Timer { scheduled_id: 0, scheduled_at: moment.into(), kind, subject }).scheduled_id
    }

    fn cancel(&mut self, timer: u64) {
        self.0.db.timer().scheduled_id().delete(timer);
    }
}

/// A table of the database as the rules' table of its rows: its accessor,
/// its key, and its indexes in the order `rows!` lists them.
macro_rules! stored {
    ($row:ident in $accessor:ident by $key:ident $(, $index:ident)*) => {
        impl Table<$row> for Stdb<'_> {
            fn get(&self, key: u64) -> Option<$row> {
                self.0.db.$accessor().$key().find(key)
            }

            #[allow(unused_variables, unused_mut, unused_assignments)]
            fn by(&self, index: usize, value: u64) -> Vec<$row> {
                let mut at = 0;
                $(
                    if index == at {
                        return self.0.db.$accessor().$index().filter(value).collect();
                    }
                    at += 1;
                )*
                Vec::new()
            }

            fn all(&self) -> Vec<$row> {
                self.0.db.$accessor().iter().collect()
            }

            fn insert(&mut self, row: $row) -> $row {
                self.0.db.$accessor().insert(row)
            }

            fn update(&mut self, row: $row) {
                self.0.db.$accessor().$key().update(row);
            }

            fn delete(&mut self, key: u64) {
                self.0.db.$accessor().$key().delete(key);
            }
        }
    };
}

stored!(Realm in realm by id);
stored!(Player in player by id, name_key);
stored!(Pace in pace by player);
stored!(Land in land by chunk);
stored!(Place in place by hex);
stored!(Blueprint in blueprint by id);
stored!(City in city by id, owner);
stored!(Building in building by id, city);
stored!(Job in job by id, city);
stored!(Stock in stock by city);
stored!(Troop in troop by id, city);
stored!(Soldier in soldier by id);
stored!(Site in site by id);
stored!(March in march by id, owner, city);
stored!(Squad in squad by id, march);
stored!(Haul in haul by march, owner);
stored!(Barrow in barrow by id);
stored!(Hunt in hunt by player);
stored!(Report in report by id, player);
stored!(Alliance in alliance by id, name_key, tag_key);
stored!(Member in member by player, alliance);
stored!(Applicant in applicant by player, alliance);
stored!(RealmChat in realm_chat by id);
stored!(AllianceChat in alliance_chat by id, alliance);
stored!(Complaint in complaint by id, reporter);
stored!(Bar in bar by player);
stored!(Task in task by step);
stored!(Progress in progress by player);
stored!(Duty in duty by deed);
stored!(Chest in chest by id);
stored!(Daily in daily by player);
stored!(Grace in grace by level);
stored!(Favour in favour by player);
stored!(Fame in fame by player);
stored!(Boon in boon by id, player);
stored!(Cairn in cairn by id);
stored!(Find in find by id, player);
stored!(Honour in honour by player);
stored!(Price in price by item);
stored!(Ware in ware by item);
stored!(Person in person by number);
stored!(Satchel in satchel by id, player);
stored!(Trial in trial by id);
stored!(Prize in prize by id);
stored!(Tally in tally by id, player);
stored!(Standing in standing by id, contest_round);
stored!(Laurel in laurel by id);
stored!(Link in link by code, player);
stored!(Rally in rally by id, alliance);
stored!(Muster in muster by march, rally);
stored!(Plea in plea by job, alliance);
stored!(Helper in helper by id, job, player);
stored!(Spire in spire by alliance);
stored!(Season in season by number);
stored!(Gift in gift by player);
stored!(Skill in skill by id, commander, owner);
stored!(Bond in bond by commander, owner);
stored!(Keeper in keeper by player);
stored!(Ward in ward by id, alliance);
stored!(Learning in learning by id, alliance);
stored!(Gate in gate by id);
stored!(Envoy in envoy by id, sender, receiver);
stored!(Pact in pact by id, first, second);
stored!(Prisoner in prisoner by commander, owner, captor);
stored!(Petition in petition by asker, alliance);
stored!(Title in title by title);
stored!(Letter in letter by id, sender, receiver);
stored!(Shun in shun by key, player);
stored!(Mark in mark by id, alliance);
stored!(Milestone in milestone by id);
stored!(Claim in claim by key, player);
stored!(Welcome in welcome by player);
stored!(Stage in stage by id);
stored!(Road in road by player);
stored!(Gear in gear by id, owner, commander);
stored!(Pattern in pattern by piece);
stored!(Lore in lore by id, city);
stored!(Study in study by id);
stored!(Commander in commander by id, owner);

/// The player a caller is, by their identity.
fn caller(ctx: &ReducerContext) -> Result<u64, Refusal> {
    ctx.db.account().identity().find(ctx.sender()).map(|account| account.player).ok_or(Refusal::NotAPlayer)
}

/// A rule's answer as the caller hears it.
fn said<T>(result: Result<T, Refusal>) -> Result<(), String> {
    result.map(|_| ()).map_err(|refusal| refusal.to_string())
}

/// How many times faster than written the realm runs: 1, the realm
/// proper's pace.
const PACE: u32 = 1;
/// How many hexes the world reaches from the lake's heart: room for some
/// two thousand cities.
const RADIUS: u32 = 128;

/// The module is published: the realm opens, its land grown from a seed
/// drawn then.
#[reducer(init)]
pub fn init(ctx: &ReducerContext) {
    let seed: u64 = ctx.random();
    ctx.db.owner().insert(Owner { id: 0, identity: ctx.sender() });
    rules::open(&mut Stdb(ctx), seed, PACE, RADIUS);
    log::info!("The realm is open: seed {seed}, {RADIUS} hexes from heart to rim.");
}

/// Sets how many times faster than written the realm runs: its owner's
/// alone to ask, for a trial realm or a check.
#[reducer]
pub fn set_pace(ctx: &ReducerContext, pace: u32) -> Result<(), String> {
    if ctx.db.owner().id().find(0).is_none_or(|owner| owner.identity != ctx.sender()) {
        return said::<()>(Err(Refusal::NotTheOwner));
    }
    said(rules::repace(&mut Stdb(ctx), pace))
}

/// Counts one connection more or fewer for the caller, and gives how many
/// they now have open.
fn connections(ctx: &ReducerContext, opened: bool) -> u32 {
    let identity = ctx.sender();
    let had = ctx.db.presence().identity().find(identity).map(|presence| presence.connections).unwrap_or(0);
    let have = if opened { had + 1 } else { had.saturating_sub(1) };
    match (had, have) {
        (0, 0) => {}
        (0, _) => {
            ctx.db.presence().insert(Presence { identity, connections: have });
        }
        (_, 0) => {
            ctx.db.presence().identity().delete(identity);
        }
        _ => {
            ctx.db.presence().identity().update(Presence { identity, connections: have });
        }
    }
    have
}

/// A connection opens. A player's first means they are here.
#[reducer(client_connected)]
pub fn connected(ctx: &ReducerContext) {
    if connections(ctx, true) == 1 {
        if let Ok(player) = caller(ctx) {
            rules::seen(&mut Stdb(ctx), player, true);
        }
    }
}

/// A connection closes. A player's last, on every device of theirs, means
/// they are gone, until they come back: their city, their armies and
/// everything under way go on without them.
#[reducer(client_disconnected)]
pub fn disconnected(ctx: &ReducerContext) {
    if connections(ctx, false) == 0 {
        if let Ok(player) = caller(ctx) {
            let elsewhere = ctx.db.account().player().filter(player)
                .any(|account| account.identity != ctx.sender() && ctx.db.presence().identity().find(account.identity).is_some());
            if !elsewhere {
                rules::seen(&mut Stdb(ctx), player, false);
            }
        }
    }
}

/// Join the realm under a name.
#[reducer]
pub fn join(ctx: &ReducerContext, name: String) -> Result<(), String> {
    if caller(ctx).is_ok() {
        return said::<()>(Err(Refusal::AlreadyAPlayer));
    }
    let joined = rules::join(&mut Stdb(ctx), &name).map(|player| {
        ctx.db.account().insert(Account { identity: ctx.sender(), player: player.id });
    });
    said(joined)
}

/// Ask for a code to bring another device of the caller's into the realm
/// as them: shown in the caller's view of it, `my_link`.
#[reducer]
pub fn offer_link(ctx: &ReducerContext) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::offer_link(&mut Stdb(ctx), player)))
}

/// Take a code another device of a player's shows: this device, which
/// plays as no one yet, plays as them from now on.
#[reducer]
pub fn take_link(ctx: &ReducerContext, code: String) -> Result<(), String> {
    if caller(ctx).is_ok() {
        return said::<()>(Err(Refusal::AlreadyAPlayer));
    }
    let taken = rules::take_link(&mut Stdb(ctx), &code).map(|player| {
        ctx.db.account().insert(Account { identity: ctx.sender(), player });
        if ctx.db.presence().identity().find(ctx.sender()).is_some() {
            rules::seen(&mut Stdb(ctx), player, true);
        }
    });
    said(taken)
}

/// The longest name a device is given, in letters.
const DEVICE_LETTERS: usize = 24;

/// Name the device the caller plays from, as their client calls it, to be
/// told from their others; a name of nothing lets its name go.
#[reducer]
pub fn name_device(ctx: &ReducerContext, name: String) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::asking(&mut Stdb(ctx), player)))?;
    let name = rules::tidy(&rules::tidy(&name).chars().take(DEVICE_LETTERS).collect::<String>());
    let had = ctx.db.device_name().identity().find(ctx.sender()).is_some();
    match (had, name.is_empty()) {
        (true, true) => {
            ctx.db.device_name().identity().delete(ctx.sender());
        }
        (true, false) => {
            ctx.db.device_name().identity().update(DeviceName { identity: ctx.sender(), name });
        }
        (false, false) => {
            ctx.db.device_name().insert(DeviceName { identity: ctx.sender(), name });
        }
        (false, true) => {}
    }
    Ok(())
}

/// The number a device of a player's is shown and let go by: one for
/// each identity, never the identity itself, small enough for any
/// client's numbers.
fn device_number(identity: Identity) -> u64 {
    let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
    for byte in identity.to_byte_array() {
        hash ^= byte as u64;
        hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
    }
    hash & ((1 << 48) - 1)
}

/// Let go another of the caller's devices, by the number they see it
/// under: a phone lost, or a Mac given away. It plays as them no more,
/// and whoever has it would join anew. The device asked from is not let
/// go from itself, so a player never lets go of the last of theirs.
#[reducer]
pub fn let_go(ctx: &ReducerContext, device: u64) -> Result<(), String> {
    let player = caller(ctx).map_err(|refusal| refusal.to_string())?;
    said(rules::asking(&mut Stdb(ctx), player))?;
    let account = ctx.db.account().player().filter(player).find(|account| device_number(account.identity) == device);
    let account = account.ok_or(Refusal::NoSuchDevice).map_err(|refusal| refusal.to_string())?;
    if account.identity == ctx.sender() {
        return said::<()>(Err(Refusal::ThisDevice));
    }
    ctx.db.account().identity().delete(account.identity);
    ctx.db.device_name().identity().delete(account.identity);
    Ok(())
}

/// Leave the realm for good, the caller's own name typed to be sure they
/// mean it: out of their alliance, forgotten as the realm's owner forgets
/// a player who asks it, and every device of theirs let go, so whoever
/// comes back on one joins anew.
#[reducer]
pub fn leave_realm(ctx: &ReducerContext, name: String) -> Result<(), String> {
    let player = caller(ctx).map_err(|refusal| refusal.to_string())?;
    said(rules::leave_realm(&mut Stdb(ctx), player, &name))?;
    let_all_go(ctx, player);
    Ok(())
}

/// Every device of a player's let go, and their names with them.
fn let_all_go(ctx: &ReducerContext, player: u64) {
    for account in ctx.db.account().player().filter(player).collect::<Vec<_>>() {
        ctx.db.device_name().identity().delete(account.identity);
    }
    ctx.db.account().player().delete(player);
}

/// Build a building the caller's city has not got, by its kind's number.
#[reducer]
pub fn build(ctx: &ReducerContext, kind: u8) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::build(&mut Stdb(ctx), player, kind)))
}

/// Raise one of the caller's buildings a level.
#[reducer]
pub fn upgrade(ctx: &ReducerContext, building: u64) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::upgrade(&mut Stdb(ctx), player, building)))
}

/// Hasten a building being raised in the caller's city: a quarter of what
/// is left of it, for a speedup's goods.
#[reducer]
pub fn speed_up(ctx: &ReducerContext, job: u64) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::speed_up(&mut Stdb(ctx), player, job)))
}

/// Train a batch of troops of a tier in one of the caller's training
/// buildings.
#[reducer]
pub fn train(ctx: &ReducerContext, building: u64, tier: u32, count: u64) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::train(&mut Stdb(ctx), player, building, tier, count)))
}

/// Raise troops of a kind ready in the caller's city from one tier to a
/// higher, in the building that trains them.
#[reducer]
pub fn promote(ctx: &ReducerContext, building: u64, from: u32, to: u32, count: u64) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::promote(&mut Stdb(ctx), player, building, from, to, count)))
}

/// Soldiers of a kind and tier, as a client asks for them in a march.
#[derive(SpacetimeType)]
pub struct Soldiers {
    pub kind: u8,
    pub tier: u32,
    pub count: u64,
}

/// Send soldiers from the caller's city to a hex, to do an order there:
/// 1 to gather at a site, 2 to clear a barrow of the Unquiet, 3 to take
/// another player's city by storm. Under one of the caller's commanders,
/// by their number, or under none with 0.
#[reducer]
pub fn send(ctx: &ReducerContext, q: i32, r: i32, order: u8, soldiers: Vec<Soldiers>, leader: u64) -> Result<(), String> {
    let asked: Vec<rules::Asked> = soldiers.iter().map(|s| rules::Asked { kind: s.kind, tier: s.tier, count: s.count }).collect();
    said(caller(ctx).and_then(|player| rules::send_led(&mut Stdb(ctx), player, Hex::new(q, r), order, &asked, leader)))
}

/// Call a rally of the caller's alliance against the barrow or the city at a hex,
/// with an army of the caller's own, under one of their commanders or
/// under none with 0. It musters, and sets out when the muster ends.
#[reducer]
pub fn call_rally(ctx: &ReducerContext, q: i32, r: i32, soldiers: Vec<Soldiers>, leader: u64) -> Result<(), String> {
    let asked: Vec<rules::Asked> = soldiers.iter().map(|s| rules::Asked { kind: s.kind, tier: s.tier, count: s.count }).collect();
    said(caller(ctx).and_then(|player| rules::call_rally(&mut Stdb(ctx), player, Hex::new(q, r), &asked, leader)))
}

/// Join a rally of the caller's alliance that is still mustering, with an
/// army of the caller's own.
#[reducer]
pub fn join_rally(ctx: &ReducerContext, rally: u64, soldiers: Vec<Soldiers>, leader: u64) -> Result<(), String> {
    let asked: Vec<rules::Asked> = soldiers.iter().map(|s| rules::Asked { kind: s.kind, tier: s.tier, count: s.count }).collect();
    said(caller(ctx).and_then(|player| rules::join_rally(&mut Stdb(ctx), player, rally, &asked, leader)))
}

/// Raise a wardstone of the caller's alliance at a hex, as one of its
/// officers, paid for out of the caller's city.
#[reducer]
pub fn raise_ward(ctx: &ReducerContext, q: i32, r: i32) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::raise_ward(&mut Stdb(ctx), player, Hex::new(q, r))))
}

/// Move the caller's city to clear ground, with its buildings and troops,
/// paid for out of it; not while any of its armies is out.
#[reducer]
pub fn move_city(ctx: &ReducerContext, q: i32, r: i32) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::relocate(&mut Stdb(ctx), player, Hex::new(q, r))))
}

/// Take down one of the caller's alliance's wardstones, as one of its officers.
#[reducer]
pub fn raze_ward(ctx: &ReducerContext, ward: u64) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::raze_ward(&mut Stdb(ctx), player, ward)))
}

/// Give grain, timber and stone from the caller's city toward the next
/// level of a topic their alliance learns.
#[reducer]
pub fn give_to_learning(ctx: &ReducerContext, topic: u8, grain: u64, timber: u64, stone: u64) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::give_to_learning(&mut Stdb(ctx), player, topic, crate::catalog::Goods::of(grain, timber, stone, 0))))
}

/// Send another alliance an envoy with the terms of a pact (1 a truce, 2
/// passage) for so many days, as an officer of the caller's alliance.
#[reducer]
pub fn send_envoy(ctx: &ReducerContext, alliance: u64, terms: u8, days: u32) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::send_envoy(&mut Stdb(ctx), player, alliance, terms, days)))
}

/// Accept or turn away an envoy come to the caller's alliance, as an officer.
#[reducer]
pub fn answer_envoy(ctx: &ReducerContext, envoy: u64, accept: bool) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::answer_envoy(&mut Stdb(ctx), player, envoy, accept)))
}

/// Break a pact of the caller's alliance, as an officer: it holds a day more.
#[reducer]
pub fn break_pact(ctx: &ReducerContext, pact: u64) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::break_pact(&mut Stdb(ctx), player, pact)))
}

/// Ransom one of the caller's commanders held prisoner.
#[reducer]
pub fn ransom(ctx: &ReducerContext, commander: u64) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::ransom(&mut Stdb(ctx), player, commander)))
}

/// Let a commander the caller holds prisoner go, for nothing.
#[reducer]
pub fn release_prisoner(ctx: &ReducerContext, commander: u64) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::release_prisoner(&mut Stdb(ctx), player, commander)))
}

/// Petition the caller's alliance for goods.
#[reducer]
pub fn petition_alliance(ctx: &ReducerContext, grain: u64, timber: u64, stone: u64, moonsalt: u64) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::petition(&mut Stdb(ctx), player, crate::catalog::Goods::of(grain, timber, stone, moonsalt))))
}

/// Answer an ally's petition with goods from the caller's city.
#[reducer]
pub fn answer_petition(ctx: &ReducerContext, asker: u64, grain: u64, timber: u64, stone: u64, moonsalt: u64) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::answer_petition(&mut Stdb(ctx), player, asker, crate::catalog::Goods::of(grain, timber, stone, moonsalt))))
}

/// Withdraw the caller's petition.
#[reducer]
pub fn withdraw_petition(ctx: &ReducerContext) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::withdraw_petition(&mut Stdb(ctx), player)))
}

/// Bestow a title of the Mere on a player, as the Lord of the Mere.
#[reducer]
pub fn bestow_title(ctx: &ReducerContext, title: u8, player: u64) -> Result<(), String> {
    said(caller(ctx).and_then(|lord| rules::bestow_title(&mut Stdb(ctx), lord, title, player)))
}

/// Take a title of the Mere back from whoever holds it, as the Lord of the Mere.
#[reducer]
pub fn take_title(ctx: &ReducerContext, title: u8) -> Result<(), String> {
    said(caller(ctx).and_then(|lord| rules::take_title(&mut Stdb(ctx), lord, title)))
}

/// Have a piece of gear made at the caller's Forge.
#[reducer]
pub fn forge(ctx: &ReducerContext, piece: u8) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::forge(&mut Stdb(ctx), player, piece)))
}

/// Have one of the caller's commanders wear a piece of their gear.
#[reducer]
pub fn equip(ctx: &ReducerContext, gear: u64, commander: u64) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::equip(&mut Stdb(ctx), player, gear, commander)))
}

/// Take a piece of the caller's gear off whoever wears it.
#[reducer]
pub fn unequip(ctx: &ReducerContext, gear: u64) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::unequip(&mut Stdb(ctx), player, gear)))
}

/// Claim every gift waiting on the caller, for goods in their city.
#[reducer]
pub fn claim_boons(ctx: &ReducerContext) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::claim_boons(&mut Stdb(ctx), player)).map(|_| ()))
}

/// Write a letter to another player.
#[reducer]
pub fn send_letter(ctx: &ReducerContext, player: u64, words: String) -> Result<(), String> {
    said(caller(ctx).and_then(|writer| rules::send_letter(&mut Stdb(ctx), writer, player, &words)))
}

/// Write one letter to every other member of the caller's alliance, as an officer.
#[reducer]
pub fn send_alliance_letter(ctx: &ReducerContext, words: String) -> Result<(), String> {
    said(caller(ctx).and_then(|writer| rules::send_alliance_letter(&mut Stdb(ctx), writer, &words)))
}

/// Claim the day's welcome.
#[reducer]
pub fn claim_welcome(ctx: &ReducerContext) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::claim_welcome(&mut Stdb(ctx), player)))
}

/// Walk the next stage of the Barrow Road with soldiers of the caller's
/// city, under one of their commanders or under none with 0. None are lost.
#[reducer]
pub fn walk_road(ctx: &ReducerContext, soldiers: Vec<Soldiers>, leader: u64) -> Result<(), String> {
    let asked: Vec<rules::Asked> = soldiers.iter().map(|s| rules::Asked { kind: s.kind, tier: s.tier, count: s.count }).collect();
    said(caller(ctx).and_then(|player| rules::walk_road(&mut Stdb(ctx), player, &asked, leader)))
}

/// Claim what a milestone the realm has reached gives.
#[reducer]
pub fn claim_milestone(ctx: &ReducerContext, milestone: u64) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::claim_milestone(&mut Stdb(ctx), player, milestone)))
}

/// Set a mark of the caller's alliance on the map, as an officer.
#[reducer]
pub fn set_mark(ctx: &ReducerContext, q: i32, r: i32, words: String) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::set_mark(&mut Stdb(ctx), player, Hex::new(q, r), &words)))
}

/// Clear a mark of the caller's alliance, as an officer.
#[reducer]
pub fn clear_mark(ctx: &ReducerContext, mark: u64) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::clear_mark(&mut Stdb(ctx), player, mark)))
}

/// Shut out a player: their letters to the caller are no longer taken.
#[reducer]
pub fn shut_out(ctx: &ReducerContext, player: u64) -> Result<(), String> {
    said(caller(ctx).and_then(|keeper| rules::shut_out(&mut Stdb(ctx), keeper, player)))
}

/// Let back in a player the caller shut out.
#[reducer]
pub fn let_in(ctx: &ReducerContext, player: u64) -> Result<(), String> {
    said(caller(ctx).and_then(|keeper| rules::let_in(&mut Stdb(ctx), keeper, player)))
}

/// Mark a letter to the caller read.
#[reducer]
pub fn read_letter(ctx: &ReducerContext, letter: u64) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::read_letter(&mut Stdb(ctx), player, letter)))
}

/// Forget a letter to the caller.
#[reducer]
pub fn forget_letter(ctx: &ReducerContext, letter: u64) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::forget_letter(&mut Stdb(ctx), player, letter)))
}

/// Give goods from the caller's city toward their alliance's Moonspire.
#[reducer]
pub fn give_to_spire(ctx: &ReducerContext, grain: u64, timber: u64, stone: u64, moonsalt: u64) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::give_to_spire(&mut Stdb(ctx), player, crate::catalog::Goods::of(grain, timber, stone, moonsalt))))
}

/// Ask the caller's alliance to help with a work under way in their city.
#[reducer]
pub fn ask_help(ctx: &ReducerContext, job: u64) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::ask_help(&mut Stdb(ctx), player, job)))
}

/// Help with an ally's work, by its job's number; or with 0, with every
/// work of the alliance's the caller has not yet helped with.
#[reducer]
pub fn help(ctx: &ReducerContext, job: u64) -> Result<(), String> {
    let player = caller(ctx);
    if job == 0 {
        said(player.and_then(|player| rules::help_all(&mut Stdb(ctx), player)))
    } else {
        said(player.and_then(|player| rules::help(&mut Stdb(ctx), player, job)))
    }
}

/// Put one of a commander's points into a talent.
#[reducer]
pub fn learn_talent(ctx: &ReducerContext, commander: u64, talent: u8) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::learn_talent(&mut Stdb(ctx), player, commander, talent)))
}

/// Have a commander forget every talent, for goods.
#[reducer]
pub fn forget_talents(ctx: &ReducerContext, commander: u64) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::forget_talents(&mut Stdb(ctx), player, commander)))
}

/// Have one commander go out beside another; 0 for no one.
#[reducer]
pub fn pair(ctx: &ReducerContext, commander: u64, partner: u64) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::pair(&mut Stdb(ctx), player, commander, partner)))
}

/// Have a commander keep the caller's city; 0 for none.
#[reducer]
pub fn keep_city(ctx: &ReducerContext, commander: u64) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::keep_city(&mut Stdb(ctx), player, commander)))
}

/// Take on another commander.
#[reducer]
pub fn hire(ctx: &ReducerContext) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::hire(&mut Stdb(ctx), player)))
}

/// Take a summons to the caller's Tavern: today's free one, or one they
/// keep. Who came, or brought sigils, shows in their commanders.
#[reducer]
pub fn draw(ctx: &ReducerContext) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::draw(&mut Stdb(ctx), player)))
}

/// Raise one of the caller's commanders' gift a level with their sigils.
#[reducer]
pub fn raise_gift(ctx: &ReducerContext, commander: u64) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::raise_gift(&mut Stdb(ctx), player, commander)))
}

/// Call one of the caller's armies home.
#[reducer]
pub fn recall(ctx: &ReducerContext, march: u64) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::recall(&mut Stdb(ctx), player, march)))
}

/// Have some of the caller's wounded of a kind and tier healed.
#[reducer]
pub fn heal(ctx: &ReducerContext, kind: u8, tier: u32, count: u64) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::heal(&mut Stdb(ctx), player, kind, tier, count)))
}

/// Mark one of the caller's reports read.
#[reducer]
pub fn read_report(ctx: &ReducerContext, report: u64) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::read_report(&mut Stdb(ctx), player, report)))
}

/// Throw one of the caller's reports away.
#[reducer]
pub fn forget_report(ctx: &ReducerContext, report: u64) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::forget_report(&mut Stdb(ctx), player, report)))
}

/// Found an alliance under a name and a tag, with the caller its leader.
#[reducer]
pub fn found_alliance(ctx: &ReducerContext, name: String, tag: String) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::found_alliance(&mut Stdb(ctx), player, &name, &tag)))
}

/// Join an alliance, or ask to be let into one that is not open.
#[reducer]
pub fn join_alliance(ctx: &ReducerContext, alliance: u64) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::join_alliance(&mut Stdb(ctx), player, alliance)))
}

/// Leave the caller's alliance.
#[reducer]
pub fn leave_alliance(ctx: &ReducerContext) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::leave_alliance(&mut Stdb(ctx), player)))
}

/// Let in, or turn away, a player who asked to join the caller's alliance.
#[reducer]
pub fn answer_applicant(ctx: &ReducerContext, player: u64, admit: bool) -> Result<(), String> {
    said(caller(ctx).and_then(|officer| rules::answer_applicant(&mut Stdb(ctx), officer, player, admit)))
}

/// Put a member of lower rank out of the caller's alliance.
#[reducer]
pub fn expel(ctx: &ReducerContext, player: u64) -> Result<(), String> {
    said(caller(ctx).and_then(|officer| rules::expel(&mut Stdb(ctx), officer, player)))
}

/// Give a member of the caller's alliance a rank: 1 a member, 4 an
/// officer, 5 its leader in the caller's place.
#[reducer]
pub fn set_rank(ctx: &ReducerContext, player: u64, rank: u8) -> Result<(), String> {
    said(caller(ctx).and_then(|leader| rules::set_rank(&mut Stdb(ctx), leader, player, rank)))
}

/// Say whether anyone may join the caller's alliance without being let
/// in, and what it says of itself.
#[reducer]
pub fn set_alliance(ctx: &ReducerContext, open: bool, words: String) -> Result<(), String> {
    said(caller(ctx).and_then(|leader| rules::set_alliance(&mut Stdb(ctx), leader, open, &words)))
}

/// Say something: to the whole realm, or within the caller's alliance.
#[reducer]
pub fn say(ctx: &ReducerContext, within_alliance: bool, words: String) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::say(&mut Stdb(ctx), player, within_alliance, &words)))
}

/// Report a line said in the realm's chat, or within the caller's
/// alliance, to the realm's owner.
#[reducer]
pub fn report_line(ctx: &ReducerContext, line: u64, within_alliance: bool) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::report_line(&mut Stdb(ctx), player, line, within_alliance)))
}

/// Refused unless the caller published the module: the realm's owner.
fn owning(ctx: &ReducerContext) -> Result<(), Refusal> {
    match ctx.db.owner().id().find(0) {
        Some(owner) if owner.identity == ctx.sender() => Ok(()),
        _ => Err(Refusal::NotTheOwner),
    }
}

/// Take a line of chat away: the realm's owner's alone.
#[reducer]
pub fn take_away(ctx: &ReducerContext, line: u64, within_alliance: bool) -> Result<(), String> {
    said(owning(ctx).and_then(|_| rules::take_away(&mut Stdb(ctx), line, within_alliance)))
}

/// Bar a player from speaking for so many hours, or lift a bar with none:
/// the realm's owner's alone.
#[reducer]
pub fn bar_player(ctx: &ReducerContext, player: u64, hours: u64) -> Result<(), String> {
    said(owning(ctx).and_then(|_| rules::bar(&mut Stdb(ctx), player, hours)))
}

/// Let a report go: the realm's owner's alone.
#[reducer]
pub fn dismiss_report(ctx: &ReducerContext, complaint: u64) -> Result<(), String> {
    said(owning(ctx).and_then(|_| rules::dismiss(&mut Stdb(ctx), complaint)))
}

/// Forget a player who asks it: their name leaves the realm, and their
/// identity is let go, so whoever comes back with it joins anew. The
/// realm's owner's alone.
#[reducer]
pub fn forget_player(ctx: &ReducerContext, player: u64) -> Result<(), String> {
    owning(ctx).map_err(|refusal| refusal.to_string())?;
    said(rules::forget(&mut Stdb(ctx), player))?;
    let_all_go(ctx, player);
    Ok(())
}

/// Have the caller's Academy study the next level of a topic.
#[reducer]
pub fn learn(ctx: &ReducerContext, topic: u8) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::study(&mut Stdb(ctx), player, topic)))
}

/// Claim what the task the caller is on gives, if it is done.
#[reducer]
pub fn claim_task(ctx: &ReducerContext) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::claim_task(&mut Stdb(ctx), player)))
}

/// Have one of the caller's commanders read so many tomes of war.
#[reducer]
pub fn read_tome(ctx: &ReducerContext, commander: u64, item: u8, count: u64) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::read_tome(&mut Stdb(ctx), player, commander, item, count)).map(|_| ()))
}

/// Buy so many of a thing from the caller's alliance's stores with their honour.
#[reducer]
pub fn buy(ctx: &ReducerContext, item: u8, count: u64) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::buy(&mut Stdb(ctx), player, item, count)).map(|_| ()))
}

/// Use one of an item the caller keeps on a work under way in their city.
#[reducer]
pub fn use_item(ctx: &ReducerContext, item: u8, job: u64) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::use_item(&mut Stdb(ctx), player, item, job)))
}

/// Send a load of goods by cart to the city of an ally at a hex.
#[reducer]
pub fn send_goods(ctx: &ReducerContext, q: i32, r: i32, grain: u64, timber: u64, stone: u64, moonsalt: u64) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::send_goods(&mut Stdb(ctx), player, Hex::new(q, r), crate::catalog::Goods::of(grain, timber, stone, moonsalt))).map(|_| ()))
}

/// Open so many of a crate of goods the caller keeps into their city.
#[reducer]
pub fn open_crates(ctx: &ReducerContext, item: u8, count: u64) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::open_crates(&mut Stdb(ctx), player, item, count)).map(|_| ()))
}

/// Use one of an item of peace the caller keeps on their city.
#[reducer]
pub fn use_peace(ctx: &ReducerContext, item: u8) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::keep_peace(&mut Stdb(ctx), player, item)))
}

/// Claim a prize of a contest, if the caller has scored its points this round.
#[reducer]
pub fn claim_prize(ctx: &ReducerContext, contest: u8, place: u8) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::claim_prize(&mut Stdb(ctx), player, contest, place)))
}

/// Claim what the caller's place among the first three of a contest's
/// last round over gives.
#[reducer]
pub fn claim_place(ctx: &ReducerContext, contest: u8) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::claim_place(&mut Stdb(ctx), player, contest)))
}

/// Open one of the day's chests, if the caller has earned its marks today.
#[reducer]
pub fn open_chest(ctx: &ReducerContext, chest: u8) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::open_chest(&mut Stdb(ctx), player, chest)))
}

/// A timer the rules set has come due. Only the scheduler may call this.
#[reducer]
pub fn fire(ctx: &ReducerContext, timer: Timer) -> Result<(), String> {
    if ctx.sender() != ctx.database_identity() {
        return Err("Only the realm itself keeps its timers.".into());
    }
    let at = match timer.scheduled_at {
        ScheduleAt::Time(moment) => moment.to_micros_since_unix_epoch().div_euclid(1_000_000),
        ScheduleAt::Interval(_) => Stdb(ctx).now(),
    };
    rules::fire(&mut Stdb(ctx), &crate::store::Timer { at, kind: timer.kind, subject: timer.subject });
    Ok(())
}

/// The player a view's caller is, if they have joined.
fn viewer(ctx: &ViewContext) -> Option<u64> {
    ctx.db.account().identity().find(ctx.sender()).map(|account| account.player)
}

/// The caller's own player, if they have joined.
#[view(accessor = me, public)]
fn me(ctx: &ViewContext) -> Option<Player> {
    ctx.db.player().id().find(viewer(ctx)?)
}

/// The caller's own city.
#[view(accessor = my_city, public)]
fn my_city(ctx: &ViewContext) -> Option<City> {
    ctx.db.city().owner().filter(viewer(ctx)?).next()
}

/// What stands in the caller's city.
#[view(accessor = my_buildings, public)]
fn my_buildings(ctx: &ViewContext) -> Vec<Building> {
    my_city(ctx).map(|city| ctx.db.building().city().filter(city.id).collect()).unwrap_or_default()
}

/// What the caller's city has under way.
#[view(accessor = my_jobs, public)]
fn my_jobs(ctx: &ViewContext) -> Vec<Job> {
    my_city(ctx).map(|city| ctx.db.job().city().filter(city.id).collect()).unwrap_or_default()
}

/// The troops in the caller's city, ready and wounded.
#[view(accessor = my_troops, public)]
fn my_troops(ctx: &ViewContext) -> Vec<Troop> {
    my_city(ctx).map(|city| ctx.db.troop().city().filter(city.id).collect()).unwrap_or_default()
}

/// The soldiers in the caller's armies out of the city.
#[view(accessor = my_squads, public)]
fn my_squads(ctx: &ViewContext) -> Vec<Squad> {
    let Some(player) = viewer(ctx) else { return Vec::new() };
    ctx.db.march().owner().filter(player).flat_map(|march| ctx.db.squad().march().filter(march.id)).collect()
}

/// What the caller's armies carry home.
#[view(accessor = my_hauls, public)]
fn my_hauls(ctx: &ViewContext) -> Vec<Haul> {
    viewer(ctx).map(|player| ctx.db.haul().owner().filter(player).collect()).unwrap_or_default()
}

/// The caller's city's goods, as they stood when the realm last touched
/// them: the client reckons their growth since from the hourly rates.
#[view(accessor = my_stock, public)]
fn my_stock(ctx: &ViewContext) -> Option<Stock> {
    ctx.db.stock().city().find(my_city(ctx)?.id)
}

/// What the caller has for hunting the Unquiet: their energy as it stood
/// when the realm last touched it, and the strongest barrow they have
/// cleared.
#[view(accessor = my_hunt, public)]
fn my_hunt(ctx: &ViewContext) -> Option<Hunt> {
    ctx.db.hunt().player().find(viewer(ctx)?)
}

/// The caller's reports.
#[view(accessor = my_reports, public)]
fn my_reports(ctx: &ViewContext) -> Vec<Report> {
    viewer(ctx).map(|player| ctx.db.report().player().filter(player).collect()).unwrap_or_default()
}

/// What has been said within the caller's alliance.
#[view(accessor = my_alliance_chat, public)]
fn my_alliance_chat(ctx: &ViewContext) -> Vec<AllianceChat> {
    let Some(member) = viewer(ctx).and_then(|player| ctx.db.member().player().find(player)) else { return Vec::new() };
    ctx.db.alliance_chat().alliance().filter(member.alliance).collect()
}

/// Who has asked to join the caller's alliance, for its officers; and
/// for a caller in no alliance, their own asking, if they have asked.
#[view(accessor = my_applicants, public)]
fn my_applicants(ctx: &ViewContext) -> Vec<Applicant> {
    let Some(player) = viewer(ctx) else { return Vec::new() };
    match ctx.db.member().player().find(player) {
        Some(member) if member.rank >= Member::OFFICER => ctx.db.applicant().alliance().filter(member.alliance).collect(),
        Some(_) => Vec::new(),
        None => ctx.db.applicant().player().find(player).into_iter().collect(),
    }
}

/// The talents the caller's commanders have learnt.
#[view(accessor = my_skills, public)]
fn my_skills(ctx: &ViewContext) -> Vec<Skill> {
    viewer(ctx).map(|player| ctx.db.skill().owner().filter(player).collect()).unwrap_or_default()
}

/// Which of the caller's commanders go out beside which.
#[view(accessor = my_bonds, public)]
fn my_bonds(ctx: &ViewContext) -> Vec<Bond> {
    viewer(ctx).map(|player| ctx.db.bond().owner().filter(player).collect()).unwrap_or_default()
}

/// The commander keeping the caller's city.
#[view(accessor = my_keeper, public)]
fn my_keeper(ctx: &ViewContext) -> Option<Keeper> {
    ctx.db.keeper().player().find(viewer(ctx)?)
}

/// The gifts waiting on the caller, from their alliance's deeds.
#[view(accessor = my_boons, public)]
fn my_boons(ctx: &ViewContext) -> Vec<Boon> {
    viewer(ctx).map(|player| ctx.db.boon().player().filter(player).collect()).unwrap_or_default()
}

/// The caller's honour.
#[view(accessor = my_honour, public)]
fn my_honour(ctx: &ViewContext) -> Option<Honour> {
    ctx.db.honour().player().find(viewer(ctx)?)
}

/// The cairns whose hoards the caller's scouts have found.
#[view(accessor = my_finds, public)]
fn my_finds(ctx: &ViewContext) -> Vec<Find> {
    viewer(ctx).map(|player| ctx.db.find().player().filter(player).collect()).unwrap_or_default()
}

/// The caller's gear, and who of their commanders wears it.
#[view(accessor = my_gear, public)]
fn my_gear(ctx: &ViewContext) -> Vec<Gear> {
    viewer(ctx).map(|player| ctx.db.gear().owner().filter(player).collect()).unwrap_or_default()
}

/// The letters the caller has written and been written.
#[view(accessor = my_letters, public)]
fn my_letters(ctx: &ViewContext) -> Vec<Letter> {
    let Some(player) = viewer(ctx) else { return Vec::new() };
    ctx.db.letter().receiver().filter(player).chain(ctx.db.letter().sender().filter(player)).collect()
}

/// The caller's welcome: the day they last claimed it, and how many in a row.
#[view(accessor = my_welcome, public)]
fn my_welcome(ctx: &ViewContext) -> Option<Welcome> {
    ctx.db.welcome().player().find(viewer(ctx)?)
}

/// How far the caller has come along the Barrow Road.
#[view(accessor = my_road, public)]
fn my_road(ctx: &ViewContext) -> Option<Road> {
    ctx.db.road().player().find(viewer(ctx)?)
}

/// The milestones whose gifts the caller has claimed.
#[view(accessor = my_claims, public)]
fn my_claims(ctx: &ViewContext) -> Vec<Claim> {
    viewer(ctx).map(|player| ctx.db.claim().player().filter(player).collect()).unwrap_or_default()
}

/// The marks of the caller's alliance.
#[view(accessor = my_marks, public)]
fn my_marks(ctx: &ViewContext) -> Vec<Mark> {
    let Some(player) = viewer(ctx) else { return Vec::new() };
    ctx.db.member().player().find(player).map(|member| ctx.db.mark().alliance().filter(member.alliance).collect()).unwrap_or_default()
}

/// The players the caller has shut out.
#[view(accessor = my_shunned, public)]
fn my_shunned(ctx: &ViewContext) -> Vec<Shun> {
    viewer(ctx).map(|player| ctx.db.shun().player().filter(player).collect()).unwrap_or_default()
}

/// The petitions of the caller's alliance.
#[view(accessor = my_petitions, public)]
fn my_petitions(ctx: &ViewContext) -> Vec<Petition> {
    let Some(member) = viewer(ctx).and_then(|player| ctx.db.member().player().find(player)) else { return Vec::new() };
    ctx.db.petition().alliance().filter(member.alliance).collect()
}

/// The prisoners the caller holds, and the caller's commanders held.
#[view(accessor = my_prisoners, public)]
fn my_prisoners(ctx: &ViewContext) -> Vec<Prisoner> {
    let Some(player) = viewer(ctx) else { return Vec::new() };
    ctx.db.prisoner().owner().filter(player).chain(ctx.db.prisoner().captor().filter(player)).collect()
}

/// The envoys from or to the caller's alliance.
#[view(accessor = my_envoys, public)]
fn my_envoys(ctx: &ViewContext) -> Vec<Envoy> {
    let Some(alliance) = viewer(ctx).and_then(|player| ctx.db.member().player().find(player)).map(|member| member.alliance) else { return Vec::new() };
    ctx.db.envoy().sender().filter(alliance).chain(ctx.db.envoy().receiver().filter(alliance)).collect()
}

/// What the caller has given toward their alliance's Moonspire this season.
#[view(accessor = my_gift, public)]
fn my_gift(ctx: &ViewContext) -> Option<Gift> {
    ctx.db.gift().player().find(viewer(ctx)?)
}

/// The works the caller's alliance has been asked to help with.
#[view(accessor = my_pleas, public)]
fn my_pleas(ctx: &ViewContext) -> Vec<Plea> {
    let Some(member) = viewer(ctx).and_then(|player| ctx.db.member().player().find(player)) else { return Vec::new() };
    ctx.db.plea().alliance().filter(member.alliance).collect()
}

/// The works the caller has helped with, while they last.
#[view(accessor = my_helps, public)]
fn my_helps(ctx: &ViewContext) -> Vec<Helper> {
    viewer(ctx).map(|player| ctx.db.helper().player().filter(player).collect()).unwrap_or_default()
}

/// The rallies of the caller's alliance.
#[view(accessor = my_rallies, public)]
fn my_rallies(ctx: &ViewContext) -> Vec<Rally> {
    let Some(member) = viewer(ctx).and_then(|player| ctx.db.member().player().find(player)) else { return Vec::new() };
    ctx.db.rally().alliance().filter(member.alliance).collect()
}

/// The armies in those rallies.
#[view(accessor = my_musters, public)]
fn my_musters(ctx: &ViewContext) -> Vec<Muster> {
    my_rallies(ctx).iter().flat_map(|rally| ctx.db.muster().rally().filter(rally.id)).collect()
}

/// The code the caller has asked for, to bring another device of theirs in.
#[view(accessor = my_link, public)]
fn my_link(ctx: &ViewContext) -> Vec<Link> {
    viewer(ctx).map(|player| ctx.db.link().player().filter(player).collect()).unwrap_or_default()
}

/// One of a player's devices as they see it among theirs: the number it is
/// let go by, what its client calls it, whether it is here now, and
/// whether it is the one looking.
#[derive(SpacetimeType)]
pub struct Device {
    pub number: u64,
    pub name: String,
    pub here: bool,
    pub current: bool,
}

/// The caller's devices, each that plays as them.
#[view(accessor = my_devices, public)]
fn my_devices(ctx: &ViewContext) -> Vec<Device> {
    let Some(player) = viewer(ctx) else { return Vec::new() };
    let mut devices: Vec<Device> = ctx.db.account().player().filter(player)
        .map(|account| Device {
            number: device_number(account.identity),
            name: ctx.db.device_name().identity().find(account.identity).map(|named| named.name).unwrap_or_default(),
            here: ctx.db.presence().identity().find(account.identity).is_some(),
            current: account.identity == ctx.sender(),
        })
        .collect();
    devices.sort_by_key(|device| (!device.current, device.number));
    devices
}

/// Which of their first tasks the caller is on.
#[view(accessor = my_progress, public)]
fn my_progress(ctx: &ViewContext) -> Option<Progress> {
    ctx.db.progress().player().find(viewer(ctx)?)
}

/// What the caller has done of the day's work. It is of the day it
/// names: a client reads it as nothing done once that day is past.
#[view(accessor = my_daily, public)]
fn my_daily(ctx: &ViewContext) -> Option<Daily> {
    ctx.db.daily().player().find(viewer(ctx)?)
}

/// What the caller has scored in the realm's contests. Each is of the
/// round it names: a client reads it as nothing scored once that is past.
#[view(accessor = my_tallies, public)]
fn my_tallies(ctx: &ViewContext) -> Vec<Tally> {
    viewer(ctx).map(|player| ctx.db.tally().player().filter(player).collect()).unwrap_or_default()
}

/// What the caller keeps in their satchel.
#[view(accessor = my_satchel, public)]
fn my_satchel(ctx: &ViewContext) -> Vec<Satchel> {
    viewer(ctx).map(|player| ctx.db.satchel().player().filter(player).collect()).unwrap_or_default()
}

/// The favour the caller has earned: nothing, until they have earned some.
#[view(accessor = my_favour, public)]
fn my_favour(ctx: &ViewContext) -> Option<Favour> {
    ctx.db.favour().player().find(viewer(ctx)?)
}

/// What the caller's city has learnt.
#[view(accessor = my_lore, public)]
fn my_lore(ctx: &ViewContext) -> Vec<Lore> {
    my_city(ctx).map(|city| ctx.db.lore().city().filter(city.id).collect()).unwrap_or_default()
}

/// The caller's commanders.
#[view(accessor = my_commanders, public)]
fn my_commanders(ctx: &ViewContext) -> Vec<Commander> {
    viewer(ctx).map(|player| ctx.db.commander().owner().filter(player).collect()).unwrap_or_default()
}
