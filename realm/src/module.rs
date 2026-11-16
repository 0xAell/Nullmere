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
    chest as _, daily as _, daily__view as _, duty as _, favour as _, favour__view as _, grace as _, satchel as _, satchel__view as _, ware as _, prize as _, tally as _, tally__view as _, trial as _, muster as _, muster__view as _, rally as _, rally__view as _, helper as _, helper__view as _, plea as _, plea__view as _, gift as _, gift__view as _, season as _, spire as _, bond as _, bond__view as _, keeper as _, keeper__view as _, skill as _, skill__view as _, ward as _, learning as _, gate as _, envoy as _, envoy__view as _, pact as _, prisoner as _, prisoner__view as _, petition as _, petition__view as _,
    building__view as _, city as _, city__view as _, commander as _, commander__view as _, haul as _, haul__view as _, hunt as _, hunt__view as _, job as _, job__view as _, land as _, lore as _, lore__view as _,
    march as _, march__view as _, member as _, member__view as _, pace as _, place as _, player as _, player__view as _, progress as _, progress__view as _, realm as _,
    realm_chat as _, report as _, report__view as _, site as _, soldier as _, squad as _, squad__view as _, stock as _, stock__view as _, study as _, task as _,
    troop as _, troop__view as _, Alliance, AllianceChat, Applicant, Barrow, Blueprint, Bond, Building, Chest, City, Commander, Daily, Duty, Favour, Gift, Grace, Haul, Helper, Hunt, Job, Keeper, Land, Lore, March, Member, Muster, Rally,
    Pace, Place, Player, Plea, Prize, Progress, Realm, RealmChat, Report, Satchel, Season, Site, Skill, Soldier, Spire, Squad, Stock, Study, Tally, Task, Trial, Troop, Ware, Ward, Learning, Gate, Envoy, Pact, Prisoner, Petition,
};
use crate::rules::{self, Refusal};
use crate::store::{Seconds, Table, World};

/// Whose player a connection's identity is. The rules know players by
/// number alone; only the module knows identities.
#[table(accessor = account)]
pub struct Account {
    #[primary_key]
    pub identity: Identity,
    #[unique]
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
stored!(Task in task by step);
stored!(Progress in progress by player);
stored!(Duty in duty by deed);
stored!(Chest in chest by id);
stored!(Daily in daily by player);
stored!(Grace in grace by level);
stored!(Favour in favour by player);
stored!(Ware in ware by item);
stored!(Satchel in satchel by id, player);
stored!(Trial in trial by id);
stored!(Prize in prize by id);
stored!(Tally in tally by id, player);
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

/// A connection closes. A player's last means they are gone, until they
/// come back: their city, their armies and everything under way go on
/// without them.
#[reducer(client_disconnected)]
pub fn disconnected(ctx: &ReducerContext) {
    if connections(ctx, false) == 0 {
        if let Ok(player) = caller(ctx) {
            rules::seen(&mut Stdb(ctx), player, false);
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

/// Use one of an item the caller keeps on a work under way in their city.
#[reducer]
pub fn use_item(ctx: &ReducerContext, item: u8, job: u64) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::use_item(&mut Stdb(ctx), player, item, job)))
}

/// Claim a prize of a contest, if the caller has scored its points this round.
#[reducer]
pub fn claim_prize(ctx: &ReducerContext, contest: u8, place: u8) -> Result<(), String> {
    said(caller(ctx).and_then(|player| rules::claim_prize(&mut Stdb(ctx), player, contest, place)))
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
