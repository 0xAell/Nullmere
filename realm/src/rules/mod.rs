//! The rules of the game.
//!
//! Each public function here is one thing a player may ask of the realm, or
//! one thing the realm does of itself when a timer fires. It checks, then
//! changes rows, or refuses with the reason in plain words and changes
//! nothing.

mod alliance;
mod boons;
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
mod learning;
mod march;
mod pacts;
mod petitions;
mod prisoners;
mod rally;
mod siege;
mod spire;
mod study;
mod titles;
mod tasks;
mod trials;
mod ward;

pub use alliance::*;
pub use boons::*;
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
pub use learning::*;
pub use march::*;
pub use pacts::*;
pub use petitions::*;
pub use prisoners::*;
pub use rally::*;
pub use siege::*;
pub use spire::*;
pub use study::*;
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
}

impl fmt::Display for Refusal {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Refusal::AlreadyBuilt(building) => return write!(f, "Your city already has a {}.", building.name()),
            Refusal::AlreadyRising(building) => return write!(f, "Your {} is already being built.", building.name()),
            Refusal::AtTopLevel(building) => return write!(f, "Your {} is at its highest level.", building.name()),
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
            Refusal::LetterTooLong(most) => return write!(f, "A letter holds {} characters at most, and nothing unprintable.", crate::catalog::grouped(*most as u64)),
            Refusal::PetitionTooLarge(most) => return write!(f, "A petition asks {} of each good at most.", crate::catalog::grouped(*most)),
            Refusal::NoSuchTerms(most) => return write!(f, "A pact is a truce or passage, for a day to {most} days."),
            Refusal::GatesShut(left) => return write!(f, "The gates of the ridge may be stormed in {}.", crate::catalog::spoken(*left)),
            Refusal::NothingMoreToLearn(topic) => return write!(f, "You have learnt all there is of {}.", topic.name()),
            Refusal::StudyFirst(topic, level) => return write!(f, "Learn {} to level {level} first.", topic.name()),
            Refusal::TaskNotDone(words) => return write!(f, "Not done yet: {words}"),
            Refusal::ChestNotEarned(marks) => return write!(f, "That chest opens at {marks} marks of the day's work."),
            Refusal::PrizeNotEarned(points) => return write!(f, "That prize is for {} points.", crate::catalog::grouped(*points)),
            Refusal::RallyTooStrong(level) => return write!(f, "A rally of yours may go against a barrow of level {level} at most."),
            Refusal::AtPeace(left) => return write!(f, "That city is at peace for another {}.", crate::catalog::spoken(*left)),
            Refusal::AtPeaceLonger(left) => return write!(f, "Your city is at peace for another {} already.", crate::catalog::spoken(*left)),
            Refusal::ShortOfMaterials(words) => return write!(f, "You need {words} more."),
            Refusal::HeldPrisoner(name) => return write!(f, "{name} is held prisoner."),
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
            Refusal::NoSuchOrder => "The realm knows no such order.",
            Refusal::NothingThere => "There is nothing to gather there.",
            Refusal::SiteTaken => "Another army is gathering there.",
            Refusal::NoWay => "There is no way there over open ground.",
            Refusal::NoSuchMarch => "There is no such army.",
            Refusal::AlreadyReturning => "That army is already on its way home.",
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
            Refusal::NotTheLord => "Only the Lord of the Mere bestows its titles: the leader of the alliance that won the last season won.",
            Refusal::NoSuchTitle => "There is no such title held.",
            Refusal::TitleHeld => "They hold that title already.",
            Refusal::NoSuchPlayer => "There is no such player.",
            Refusal::OwnLetter => "A letter goes to another player.",
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
            _ => "",
        })
    }
}
