//! The rules of the game.
//!
//! Each public function here is one thing a player may ask of the realm, or
//! one thing the realm does of itself when a timer fires. It checks, then
//! changes rows, or refuses with the reason in plain words and changes
//! nothing.

mod alliance;
mod boons;
mod cairns;
mod carts;
mod honour;
mod army;
mod battle;
mod city;
mod gates;
mod command;
mod daily;
mod entry;
mod fame;
mod favour;
mod help;
mod forge;
mod items;
mod letters;
mod marks;
mod milestones;
mod links;
mod learning;
mod march;
mod pacts;
mod peace;
mod raid;
mod petitions;
mod prisoners;
mod rally;
mod road;
mod lists;
mod merits;
mod pedlar;
mod shrines;
mod shun;
mod siege;
mod spire;
mod study;
mod tavern;
mod titles;
mod tasks;
mod trials;
mod ward;

pub use alliance::*;
pub use boons::*;
pub use cairns::*;
pub use carts::*;
pub use honour::*;
pub use army::*;
pub use battle::*;
pub use city::*;
pub use gates::*;
pub use command::*;
pub use daily::*;
pub use entry::*;
pub use fame::*;
pub use favour::*;
pub use help::*;
pub use forge::*;
pub use items::*;
pub use letters::*;
pub use marks::*;
pub use milestones::*;
pub use links::*;
pub use learning::*;
pub use march::*;
pub use pacts::*;
pub use peace::*;
use raid::*;
pub use petitions::*;
pub use prisoners::*;
pub use rally::*;
pub use road::*;
pub use lists::*;
pub use merits::*;
pub use pedlar::*;
pub use shrines::*;
pub use shun::*;
pub use siege::*;
pub use spire::*;
pub use study::*;
pub use tavern::*;
pub use titles::*;
pub use tasks::*;
pub use trials::*;
pub use ward::*;

use crate::catalog::{Building, Goods, Topic, Troops};
use crate::rows::Db;
use crate::store::Timer;
use std::fmt;

/// A timer the rules set has come due: what it was set for is done.
pub fn fire(db: &mut impl Db, timer: &Timer) {
    match timer.kind {
        TIMER_JOB => finish(db, timer.subject),
        TIMER_MARCH => arrive(db, timer.subject),
        TIMER_SPIRE => spire_risen(db, timer.subject),
        TIMER_SEASON => turn_season(db, timer.subject),
        TIMER_LEARNING => learnt_together_now(db, timer.subject),
        TIMER_PRISON => prison_done(db, timer.subject),
        TIMER_BOON => boon_gone(db, timer.subject),
        _ => {}
    }
}

/// Why the realm will not do what was asked: said to the player as it is.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Refusal {
    /// The realm has not been opened.
    NotOpen,
    /// Someone unknown to the realm asked for something only a player may.
    NotAPlayer,
    AlreadyAPlayer,
    NameTooShort,
    NameTooLong,
    NameNotAllowed,
    NameTaken,
    /// Too many players joined in the last minute.
    Crowded,
    /// One player asking too much too quickly.
    TooFast,
    /// No clear ground is left for a new city.
    NoRoom,
    NoCity,
    NoSuchBuilding,
    /// Something of another player's.
    NotYours,
    AlreadyBuilt(Building),
    /// It is being raised already.
    AlreadyRising(Building),
    AtTopLevel(Building),
    /// The Keep must reach this level first.
    NeedsKeep(u32),
    /// Another building must reach a level first.
    NeedsOther(Building, u32),
    BuildersBusy,
    /// What the city's stock is short by.
    CannotAfford(Goods),
    /// The building trains no troops.
    TrainsNothing(Building),
    NoSuchTroops,
    OnlyHigher,
    NothingAsked,
    NoBoons,
    NoCairnThere,
    /// The player's scouts found what that cairn held already.
    FoundAlready,
    ScoutsOnTheWay,
    NoSuchWare,
    NotATome,
    /// Opened, not used: that is not a crate of goods.
    NotACrate,
    /// A crate is opened into the city, not used on a work.
    ToBeOpened,
    ForACommander,
    /// A summons is taken to the Tavern.
    AtTheTavern,
    /// No free summons is left today and none is kept.
    NoSummons,
    /// A commander of no renown has no gift to raise.
    NoGift,
    /// A gift at its last level.
    GiftAtTop(String),
    /// So many more sigils a gift asks.
    TooFewSigils(String, u32),
    /// The commander, at the top of what may be seen.
    SeenAll(String),
    /// How much honour the player has.
    NotEnoughHonour(u64),
    /// The most that may be asked for at once.
    TooMany(u64),
    AlreadyTraining(Building),
    /// It can't be raised while troops train in it.
    BusyTraining(Building),
    /// An order the realm does not know.
    NoSuchOrder,
    /// Nothing to gather at the hex named.
    NothingThere,
    /// Another army is gathering there.
    SiteTaken,
    /// The city has fewer ready than were asked for: which, and how many.
    NotEnoughTroops(Troops, u32, u64),
    /// Every army the city may send is out: how many that is.
    NoFreeMarch(u32),
    /// No way over open ground.
    NoWay,
    NoSuchMarch,
    AlreadyReturning,
    /// More goods than a load of carts takes.
    TooMuchForCarts(u64),
    /// As many loads of carts on the road as the city may send.
    CartsOnTheRoad(u32),
    /// Carts are not called back.
    CartsGoOn,
    NoCityForCarts,
    CartsToAlliesOnly,
    /// No barrow stands at the hex named.
    NothingToFight,
    /// Another army is fighting there.
    BarrowTaken,
    /// The barrow is more than a level above the strongest the player has
    /// cleared: the level they must clear first.
    TooStrong(u32),
    /// Too little energy for an attack: how much the player has.
    NoEnergy(u32),
    /// The army is in a fight, and can't be called away.
    Fighting,
    /// The city has fewer wounded than were asked for: which, and how many.
    NotEnoughWounded(Troops, u32, u64),
    AlreadyHealing,
    NoSuchReport,
    /// No city stands at the hex named.
    NoCityThere,
    /// The player's own city.
    OwnCity,
    /// The city is at peace: for how many seconds more.
    AtPeace(i64),
    /// A city of the player's own alliance.
    AllysCity,
    /// Only an ally's city may be reinforced.
    NotAnAlly,
    /// No city can stand on the hex named: it is not buildable land, or
    /// another city is too near.
    NoSiteThere,
    /// Armies are out: they must come home before the city moves.
    ArmyOut,
    /// No building is being raised by the city under that number.
    NoSuchJob,
    /// The raising is nearly done: nothing to hasten.
    NothingToSpeed,
    AlreadyAllied,
    NotAllied,
    NoSuchAlliance,
    AllianceFull,
    AllianceNameNotAllowed,
    AllianceNameTaken,
    TagNotAllowed,
    TagTaken,
    /// Something only an alliance's officers may do, or only its leader.
    NotAnOfficer,
    NotTheLeader,
    /// The leader can't leave an alliance that has other members.
    LeaderMustHandOver,
    NoSuchApplicant,
    /// Not a member of the player's alliance.
    NotAMember,
    OutranksYou,
    NoSuchRank,
    NothingSaid,
    SaidTooLong,
    SayingTooFast,
    NoSuchCommander,
    /// The commander named is out with another army: their name.
    CommanderAway(String),
    NoMoreCommanders,
    NoSuchTalent,
    /// A commander has put the most points there are into this talent.
    TalentFull(String),
    /// A commander has spent every point their level brings: whose.
    NoTalentPoints(String),
    NothingToForget,
    SameCommander,
    /// A commander already goes out beside another, or has one beside them: whose.
    AlreadyPaired(String),
    /// An alliance has all the wardstones it may: so many.
    WardsAll(u32),
    NoWardThere,
    /// Land another alliance holds: theirs, by tag and name.
    OthersLand(String),
    OffOwnLand,
    NoSuchWard,
    LearntTogether,
    StudiedTogether,
    NothingNeeded,
    /// The gates may be stormed in so many seconds.
    GatesShut(i64),
    OwnGate,
    GateFought,
    /// The holy sites may not be stormed for so many seconds yet.
    ShrinesShut(i64),
    OwnShrine,
    ShrineFought,
    /// A holy site was taken lately: so many seconds until it may be stormed.
    ShrineGuarded(i64),
    LakelandShut,
    OwnWard,
    OwnAlliance,
    /// Terms that are not a truce or passage, or of more days than so many.
    NoSuchTerms(u32),
    PactHolds,
    EnvoySent,
    NoSuchEnvoy,
    NoSuchPact,
    AtTruce,
    NoSuchPrisoner,
    /// A petition asks no more than so much of each good.
    PetitionTooLarge(u64),
    PetitionStands,
    NoSuchPetition,
    NotTheLord,
    NoSuchTitle,
    TitleHeld,
    NoSuchPlayer,
    /// A letter holds so many characters at most.
    LetterTooLong(usize),
    OwnLetter,
    /// A letter to one who has shut its writer out.
    LettersShutOut,
    OwnShun,
    /// A mark says so many characters at most.
    MarkTooLong(usize),
    BeyondTheRealm,
    /// An alliance keeps so many marks at most.
    MarksAll(usize),
    NoSuchMark,
    NoSuchMilestone,
    MilestoneNotReached,
    MilestoneClaimed,
    WelcomeClaimed,
    RoadWalked,
    RoadResting(i64),
    RoadNarrow(u64),
    BandTooBig(u64),
    NotInTheLists,
    NoSuchEntrant,
    NotAbove,
    TooFarAbove(u64),
    NoChallengesLeft(u64),
    PurseClaimed,
    NoSuchMerit,
    MilestoneBeforeYou,
    NoSuchDeal,
    NotOfferedToday,
    DealTaken,
    MeritsClaimed,
    MeritNotReached(u64, u64),
    ShutOutAlready,
    NotShutOut,
    /// A player shuts out so many others at most.
    TooManyShutOut(usize),
    NoSuchLetter,
    NoSuchTopic,
    AlreadyStudying,
    /// The Academy can't be raised while it studies.
    BusyStudying,
    NothingMoreToLearn(Topic),
    /// A study opens once another is learnt to a level.
    StudyFirst(Topic, u32),
    /// The task the player is on is not done: what it asks.
    TaskNotDone(String),
    NoTasksLeft,
    NoSuchChest,
    NoSuchItem,
    NoSuchPrize,
    SpireComplete,
    HelpAsked,
    NoSuchPlea,
    YourOwnWork,
    AlreadyHelped,
    HelpedEnough,
    /// A rally may go no further above what its caller may attack alone: the level it may reach.
    RallyTooStrong(u32),
    AlreadyRallying,
    RallyCalled,
    NoSuchRally,
    RallyFull,
    RallySetOut,
    RallyUnderWay,
    /// The prize asks more points than the player has scored this round: how many it asks.
    PrizeNotEarned(u64),
    PrizeClaimed,
    /// No round of the contest is over yet.
    NoRoundOver,
    /// The player was not among the first three of the contest's last round over.
    NotPlaced,
    PlaceClaimed,
    /// No code of a player's other device reads so, or it has been taken.
    NoSuchLink,
    /// The code was good for ten minutes, and they are past.
    LinkTooOld,
    /// The player has none of the item they would use.
    NoneLeft,
    /// An item of peace is used on the city, not on a work.
    NotAHaste,
    /// A material is worked at the Forge, not used.
    AtTheForge,
    /// No such piece of gear is made, or is the player's.
    NoSuchPiece,
    NoSuchGear,
    /// Too few of the materials a piece takes.
    ShortOfMaterials(String),
    /// A commander held prisoner is given no gear.
    HeldPrisoner(String),
    /// Only an item of peace keeps the peace.
    NotPeace,
    /// No peace while the player's armies are out against a city.
    AttacksUnderWay,
    /// The city is already at peace for longer than the item would keep it.
    AtPeaceLonger(i64),
    /// The chest asks more marks than the player has earned today: how many it asks.
    ChestNotEarned(u32),
    ChestOpened,
    /// Something only the realm's owner may do.
    NotTheOwner,
    /// No such line of chat, or none the player may report.
    NoSuchLine,
    TakenAwayAlready,
    OwnWords,
    ReportedAlready,
    /// The most reports a player may have waiting at once.
    TooManyReports(u64),
    NoSuchComplaint,
    /// Barred from speaking: for how much longer.
    Barred(i64),
    /// The longest bar, in hours.
    BarTooLong(u64),
    ForgottenAlready,
    /// A player leaving the realm types their name as it knows it.
    NotYourName,
    /// No device of the player's is the one named.
    NoSuchDevice,
    /// The device a player asks from is not one to let go from itself.
    ThisDevice,
    /// No army gathers at the site named.
    NoOneGathering,
    OwnArmy,
    AllysArmy,
}

impl fmt::Display for Refusal {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Refusal::AlreadyBuilt(building) => return write!(f, "Your city already has a {}.", building.name()),
            Refusal::AlreadyRising(building) => return write!(f, "Your {} is already being built.", building.name()),
            Refusal::AtTopLevel(building) => return write!(f, "Your {} is at its highest level.", building.name()),
            Refusal::TooMuchForCarts(most) => return write!(f, "A load of carts takes at most {} goods; raise your Storehouse for more.", crate::catalog::grouped(*most)),
            Refusal::CartsOnTheRoad(1) => return f.write_str("You have a load of carts on the road already, as many as your Keep allows."),
            Refusal::CartsOnTheRoad(most) => return write!(f, "You have {most} loads of carts on the road already, as many as your Keep allows."),
            Refusal::NeedsKeep(level) => return write!(f, "Raise your Keep to level {level} first."),
            Refusal::NeedsOther(building, level) => return write!(f, "Raise your {} to level {level} first.", building.name()),
            Refusal::CannotAfford(short) => return write!(f, "You need {short} more."),
            Refusal::TrainsNothing(building) => return write!(f, "No troops are trained in a {}.", building.name()),
            Refusal::TooMany(most) => return write!(f, "At most {} at once.", crate::catalog::grouped(*most)),
            Refusal::AlreadyTraining(building) => return write!(f, "Your {} is already training troops.", building.name()),
            Refusal::BusyTraining(building) => return write!(f, "Your {} is training troops. Wait for them to finish.", building.name()),
            Refusal::NotEnoughTroops(troops, tier, ready) => {
                return write!(f, "You have only {} tier {tier} {} ready.", crate::catalog::grouped(*ready), troops.name());
            }
            Refusal::TooStrong(level) => return write!(f, "Clear a level {level} barrow first."),
            Refusal::NotEnoughHonour(honour) => return write!(f, "You have only {} honour.", crate::catalog::grouped(*honour)),
            Refusal::NoEnergy(energy) => {
                return write!(f, "An attack takes {} energy. You have {energy}.", crate::catalog::ENERGY_A_HUNT);
            }
            Refusal::NotEnoughWounded(troops, tier, wounded) => {
                return write!(f, "You have only {} wounded tier {tier} {}.", crate::catalog::grouped(*wounded), troops.name());
            }
            Refusal::CommanderAway(name) => return write!(f, "{name} is out with another army."),
            Refusal::TalentFull(name) => return write!(f, "{name} has learnt all there is of that."),
            Refusal::NoTalentPoints(name) => return write!(f, "{name} has no points left to spend. They gain one with each level."),
            Refusal::AlreadyPaired(name) => return write!(f, "{name} already goes out with another commander."),
            Refusal::WardsAll(most) => return write!(f, "Your alliance has all the wardstones it may: {most}. It may raise one more for every five members, twenty at most."),
            Refusal::OthersLand(theirs) => return write!(f, "That land is {theirs}'s."),
            Refusal::MarkTooLong(most) => return write!(f, "A mark says {most} characters at most, and nothing unprintable."),
            Refusal::MarksAll(most) => return write!(f, "Your alliance has all the marks it may: {most}. Clear one first."),
            Refusal::TooManyShutOut(most) => return write!(f, "You may shut out {most} players at most. Let one back in first."),
            Refusal::LetterTooLong(most) => return write!(f, "A letter holds {} characters at most, and nothing unprintable.", crate::catalog::grouped(*most as u64)),
            Refusal::PetitionTooLarge(most) => return write!(f, "A petition asks {} of each good at most.", crate::catalog::grouped(*most)),
            Refusal::NoSuchTerms(most) => return write!(f, "A pact is a truce or passage, for a day to {most} days."),
            Refusal::GatesShut(left) => return write!(f, "The gates of the ridge may be stormed in {}.", crate::catalog::spoken(*left)),
            Refusal::ShrinesShut(left) => return write!(f, "The holy sites may be stormed in {}.", crate::catalog::spoken(*left)),
            Refusal::ShrineGuarded(left) => return write!(f, "That holy site was taken lately. It may be stormed again in {}.", crate::catalog::spoken(*left)),
            Refusal::NothingMoreToLearn(topic) => return write!(f, "You have learnt all there is of {}.", topic.name()),
            Refusal::StudyFirst(topic, level) => return write!(f, "Learn {} to level {level} first.", topic.name()),
            Refusal::TaskNotDone(words) => return write!(f, "Not done yet: {words}"),
            Refusal::ChestNotEarned(marks) => return write!(f, "That chest opens at {marks} marks of the day's work."),
            Refusal::PrizeNotEarned(points) => return write!(f, "That prize is for {} points.", crate::catalog::grouped(*points)),
            Refusal::RallyTooStrong(level) => return write!(f, "A rally of yours may go against a barrow of level {level} at most."),
            Refusal::AtPeace(left) => return write!(f, "That city is at peace for another {}.", crate::catalog::spoken(*left)),
            Refusal::RoadResting(left) => return write!(f, "Your soldiers rest from the road another {}.", crate::catalog::spoken(*left)),
            Refusal::MeritNotReached(done, goal) => {
                return write!(f, "You have done {} of the {} its next tier asks.", crate::catalog::grouped(*done), crate::catalog::grouped(*goal))
            }
            Refusal::BandTooBig(most) => return write!(f, "Your band holds no more than {} soldiers. Raise your Keep for more.", crate::catalog::grouped(*most)),
            Refusal::TooFarAbove(reach) => return write!(f, "You may challenge only those up to {reach} places above you."),
            Refusal::NoChallengesLeft(tries) => return write!(f, "You have made all {tries} of today's challenges. Come again tomorrow."),
            Refusal::RoadNarrow(most) => return write!(f, "The road is narrow there: no more than {} soldiers may go.", crate::catalog::grouped(*most)),
            Refusal::AtPeaceLonger(left) => return write!(f, "Your city is at peace for another {} already.", crate::catalog::spoken(*left)),
            Refusal::TooManyReports(most) => return write!(f, "You have {most} reports waiting already. Wait for the realm's owner to read them."),
            Refusal::Barred(left) => return write!(f, "You may not speak for another {}.", crate::catalog::spoken(*left)),
            Refusal::BarTooLong(hours) => return write!(f, "A player is barred for {hours} hours at most."),
            Refusal::GiftAtTop(name) => return write!(f, "{name}'s gift is at its last level."),
            Refusal::TooFewSigils(name, more) => return write!(f, "{name} needs {more} more sigils to raise their gift."),
            Refusal::ShortOfMaterials(words) => return write!(f, "You need {words} more."),
            Refusal::HeldPrisoner(name) => return write!(f, "{name} is held prisoner."),
            Refusal::SeenAll(name) => return write!(f, "{name} has seen all there is to see of war."),
            Refusal::NoFreeMarch(1) => return write!(f, "Your one army is out. Raise your Keep to send more."),
            Refusal::NoFreeMarch(most) => return write!(f, "All {most} of your armies are out."),
            _ => {}
        }
        f.write_str(match self {
            Refusal::NotOpen => "The realm is not open yet.",
            Refusal::NotAPlayer => "Join the realm first.",
            Refusal::AlreadyAPlayer => "You have already joined the realm.",
            Refusal::NameTooShort => "A name needs at least 3 letters.",
            Refusal::NameTooLong => "A name can have at most 16 letters.",
            Refusal::NameNotAllowed => "A name can use letters, digits, spaces, hyphens and apostrophes, and must start and end with a letter or digit.",
            Refusal::NameTaken => "Another player has that name.",
            Refusal::Crowded => "Many players are joining right now. Try again in a minute.",
            Refusal::TooFast => "You are doing that too quickly. Wait a few seconds.",
            Refusal::NoRoom => "The realm has no clear ground left for a new city.",
            Refusal::NoCity => "You have no city.",
            Refusal::NoSuchBuilding => "There is no such building.",
            Refusal::NotYours => "That is not yours.",
            Refusal::BuildersBusy => "Your builders are busy. Wait for them to finish.",
            Refusal::NoSuchTroops => "There are no such troops.",
            Refusal::OnlyHigher => "Troops are raised only to a higher tier.",
            Refusal::NothingAsked => "Ask for at least one.",
            Refusal::NoBoons => "No gift is waiting on you.",
            Refusal::NoCairnThere => "No cairn stands there.",
            Refusal::FoundAlready => "Your scouts have found what that cairn held already.",
            Refusal::ScoutsOnTheWay => "Your scouts are on their way to that cairn already.",
            Refusal::NoSuchWare => "The alliance's stores sell no such thing.",
            Refusal::NotATome => "That is not a tome.",
            Refusal::NotACrate => "That is not a crate of goods.",
            Refusal::ToBeOpened => "A crate is opened into your city; it hastens no work.",
            Refusal::ForACommander => "A tome is read by one of your commanders.",
            Refusal::AtTheTavern => "A summons is taken to your Tavern.",
            Refusal::NoSummons => "The Tavern's free summons is taken for today, and you have no summons to bring it.",
            Refusal::NoGift => "That commander has no gift of their own.",
            Refusal::NoSuchOrder => "The realm knows no such order.",
            Refusal::NothingThere => "There is nothing to gather there.",
            Refusal::SiteTaken => "Another army is gathering there.",
            Refusal::NoWay => "There is no way there over open ground.",
            Refusal::NoSuchMarch => "There is no such army.",
            Refusal::AlreadyReturning => "That army is already on its way home.",
            Refusal::CartsGoOn => "Carts go on to the city they were sent to; they are not called back.",
            Refusal::NoCityForCarts => "There is no city there to send carts to.",
            Refusal::CartsToAlliesOnly => "Carts go only to an ally's city.",
            Refusal::NothingToFight => "There is nothing to fight there.",
            Refusal::BarrowTaken => "Another army is fighting there.",
            Refusal::Fighting => "That army is fighting. Wait for the fight to end.",
            Refusal::AlreadyHealing => "Your wounded are already being healed. Wait for them to finish.",
            Refusal::NoSuchReport => "There is no such report.",
            Refusal::AllysCity => "That city is your ally's.",
            Refusal::AlreadyAllied => "You are in an alliance already. Leave it first.",
            Refusal::NotAllied => "You are in no alliance.",
            Refusal::NoSuchAlliance => "There is no such alliance.",
            Refusal::AllianceFull => "That alliance is full.",
            Refusal::AllianceNameNotAllowed => {
                "An alliance's name has 3 to 20 letters, digits, spaces, hyphens and apostrophes, and starts and ends with a letter or digit."
            }
            Refusal::AllianceNameTaken => "Another alliance has that name.",
            Refusal::TagNotAllowed => "A tag is 3 or 4 letters or digits.",
            Refusal::TagTaken => "Another alliance has that tag.",
            Refusal::NotAnOfficer => "Only your alliance's officers may do that.",
            Refusal::NotTheLeader => "Only your alliance's leader may do that.",
            Refusal::LeaderMustHandOver => "Hand the alliance over to another member before you leave it.",
            Refusal::NoSuchApplicant => "No one of that name has asked to join.",
            Refusal::NotAMember => "They are not a member of your alliance.",
            Refusal::OutranksYou => "They are of your rank or above it.",
            Refusal::NoSuchRank => "There is no such rank.",
            Refusal::NothingSaid => "Say something first.",
            Refusal::SaidTooLong => "That is too long to say at once: 200 letters at most.",
            Refusal::SayingTooFast => "Wait a moment before you say more.",
            Refusal::NoTasksLeft => "You have done every task there is.",
            Refusal::NoSuchChest => "There is no such chest.",
            Refusal::NoSuchItem => "There is no such thing to use.",
            Refusal::NoSuchPrize => "There is no such prize.",
            Refusal::SpireComplete => "Your alliance's Moonspire stands whole this season.",
            Refusal::HelpAsked => "You have asked your alliance's help with that already.",
            Refusal::NoSuchPlea => "Your alliance has no such work to help with.",
            Refusal::YourOwnWork => "That work is your own. Your allies help with it.",
            Refusal::AlreadyHelped => "You have helped with that already.",
            Refusal::HelpedEnough => "That work has had all the help it may.",
            Refusal::AlreadyRallying => "You have an army in a rally already.",
            Refusal::RallyCalled => "Your alliance has called a rally there already. Join it.",
            Refusal::NoSuchRally => "Your alliance has no such rally.",
            Refusal::RallyFull => "That rally has all the armies it can take.",
            Refusal::RallySetOut => "That rally has set out.",
            Refusal::RallyUnderWay => "An army in a rally under way can't be called home.",
            Refusal::PrizeClaimed => "You have claimed that prize this round.",
            Refusal::NoRoundOver => "No round of that contest is over yet.",
            Refusal::NotPlaced => "You were not among the first three when its last round ended.",
            Refusal::PlaceClaimed => "You have claimed what your place gave.",
            Refusal::NoSuchLink => "No code of yours reads so, or it has been used. Ask your other device for a new one.",
            Refusal::LinkTooOld => "That code is more than ten minutes old. Ask your other device for a new one.",
            Refusal::NoneLeft => "You have none of that left.",
            Refusal::NotAHaste => "That keeps your city at peace; it hastens no work.",
            Refusal::AtTheForge => "That is worked at the Forge into gear.",
            Refusal::NoSuchPiece => "The Forge makes no such thing.",
            Refusal::NoSuchGear => "You have no such gear.",
            Refusal::NotPeace => "That hastens a work; it keeps no peace.",
            Refusal::AttacksUnderWay => "Call home your armies sent against cities first.",
            Refusal::ChestOpened => "You have opened that chest today.",
            Refusal::NoSuchTopic => "There is no such study.",
            Refusal::NoSuchCommander => "You have no such commander.",
            Refusal::NoMoreCommanders => "Your city keeps as many commanders as it can.",
            Refusal::NoSuchTalent => "There is no such talent.",
            Refusal::NothingToForget => "That commander has learnt no talents to forget.",
            Refusal::SameCommander => "A commander can't go out beside themselves.",
            Refusal::NoWardThere => "No wardstone can stand there: it needs clear ground.",
            Refusal::OffOwnLand => "A wardstone after the first must stand on your alliance's own land.",
            Refusal::NoSuchWard => "Your alliance has no such wardstone.",
            Refusal::LearntTogether => "Your alliance has learnt all there is of that.",
            Refusal::StudiedTogether => "Your alliance is studying that now. Give toward it again when it is learnt.",
            Refusal::NothingNeeded => "Nothing more of those goods is needed for that.",
            Refusal::OwnGate => "Your alliance holds that gate.",
            Refusal::GateFought => "Another rally is at that gate.",
            Refusal::OwnShrine => "Your alliance holds that holy site.",
            Refusal::ShrineFought => "Another rally is at that holy site.",
            Refusal::LakelandShut => "Only an alliance that holds a gate of the ridge may move into the lake country.",
            Refusal::OwnWard => "That wardstone is your alliance's.",
            Refusal::OwnAlliance => "That is your own alliance.",
            Refusal::PactHolds => "Such a pact holds between your alliances already.",
            Refusal::EnvoySent => "Your alliance's envoy with those terms is waiting on their answer.",
            Refusal::NoSuchEnvoy => "That envoy is gone.",
            Refusal::NoSuchPact => "Your alliance has no such pact.",
            Refusal::AtTruce => "Your alliances are at truce.",
            Refusal::NoSuchPrisoner => "There is no such prisoner of yours.",
            Refusal::PetitionStands => "Your petition stands already. Withdraw it to ask anew.",
            Refusal::NoSuchPetition => "There is no such petition.",
            Refusal::NotTheLord => "Only the Lord of the Mere bestows its titles: the leader of the alliance that won the last season.",
            Refusal::NoSuchTitle => "There is no such title held.",
            Refusal::TitleHeld => "They hold that title already.",
            Refusal::NoSuchPlayer => "There is no such player.",
            Refusal::OwnLetter => "A letter goes to another player.",
            Refusal::LettersShutOut => "They take no letters from you.",
            Refusal::OwnShun => "You can't shut yourself out.",
            Refusal::BeyondTheRealm => "That lies beyond the realm.",
            Refusal::NoSuchMark => "Your alliance has no such mark.",
            Refusal::NoSuchMilestone => "The realm has no such milestone.",
            Refusal::MilestoneNotReached => "The realm has not reached that milestone yet.",
            Refusal::MilestoneClaimed => "You have claimed what that milestone gave.",
            Refusal::WelcomeClaimed => "You have claimed today's welcome. Come again tomorrow.",
            Refusal::RoadWalked => "You have walked the whole of the Barrow Road.",
            Refusal::NotInTheLists => "Enter the Lists first: set your band.",
            Refusal::NoSuchEntrant => "They are not in the Lists.",
            Refusal::NotAbove => "Challenge one above you in the Lists.",
            Refusal::PurseClaimed => "You have claimed today's purse. Come again tomorrow.",
            Refusal::NoSuchMerit => "There is no such merit.",
            Refusal::MilestoneBeforeYou => "The realm reached that milestone before you had been a day in it.",
            Refusal::NoSuchDeal => "The pedlar has no such deal.",
            Refusal::NotOfferedToday => "The pedlar does not offer that today.",
            Refusal::DealTaken => "You have taken that deal today. Come again tomorrow.",
            Refusal::MeritsClaimed => "You have claimed every tier of that merit.",
            Refusal::ShutOutAlready => "You have shut them out already.",
            Refusal::NotShutOut => "You haven't shut them out.",
            Refusal::NoSuchLetter => "There is no such letter of yours.",
            Refusal::AlreadyStudying => "Your Academy is already at its studies. Wait for them to finish.",
            Refusal::BusyStudying => "Your Academy is at its studies. Wait for them to finish.",
            Refusal::NoCityThere => "There is no city to attack there.",
            Refusal::OwnCity => "That is your own city.",
            Refusal::NotAnAlly => "Only an ally's city can be reinforced.",
            Refusal::NoSiteThere => "No city can stand there.",
            Refusal::ArmyOut => "Bring your armies home before your city moves.",
            Refusal::NoSuchJob => "No such work is under way in your city.",
            Refusal::NothingToSpeed => "That is nearly done. There is nothing to hasten.",
            Refusal::NotTheOwner => "Only the realm's owner may do that.",
            Refusal::NoSuchLine => "There is no such line to report.",
            Refusal::TakenAwayAlready => "That line was taken away already.",
            Refusal::OwnWords => "Those are your own words.",
            Refusal::ReportedAlready => "You have reported that line already.",
            Refusal::NoSuchComplaint => "No such report is waiting.",
            Refusal::ForgottenAlready => "That player is forgotten already.",
            Refusal::NotYourName => "Type your name as the realm knows it to leave.",
            Refusal::NoSuchDevice => "No device of yours is that one.",
            Refusal::ThisDevice => "That is the device you are on. Let it go from another of yours.",
            Refusal::NoOneGathering => "No army is gathering there.",
            Refusal::OwnArmy => "That is your own army.",
            Refusal::AllysArmy => "That army is your ally's.",
            _ => "",
        })
    }
}

/// Whether a character has no place in words a player writes: one that
/// controls, or one unseen or that turns the writing about (spaces and
/// joiners of no width, marks of direction and their overrides, the
/// byte-order mark, the line and paragraph separators, a soft hyphen).
pub fn unseen(c: char) -> bool {
    c.is_control()
        || matches!(c, '\u{00AD}' | '\u{061C}' | '\u{180E}' | '\u{200B}'..='\u{200F}' | '\u{2028}'..='\u{202E}' | '\u{2060}'..='\u{206F}' | '\u{FEFF}' | '\u{FFF9}'..='\u{FFFB}')
}

/// Whether words heap more than two combining marks on one letter.
pub fn piled(words: &str) -> bool {
    let combining = |c: char| matches!(c, '\u{0300}'..='\u{036F}' | '\u{1AB0}'..='\u{1AFF}' | '\u{1DC0}'..='\u{1DFF}' | '\u{20D0}'..='\u{20FF}' | '\u{FE20}'..='\u{FE2F}');
    let mut run = 0;
    for c in words.chars() {
        run = if combining(c) { run + 1 } else { 0 };
        if run > 2 {
            return true;
        }
    }
    false
}
