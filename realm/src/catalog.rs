//! What can be built, what it costs, how long it takes and what it gives.
//!
//! These are the game's numbers, written once. The module copies them into
//! the `blueprint` table as the realm opens, so a client shows a cost or a
//! time by reading a row, never by carrying a second copy of the rules.

use std::fmt;

/// The four goods a city keeps.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Goods {
    pub grain: u64,
    pub timber: u64,
    pub stone: u64,
    pub moonsalt: u64,
}

impl Goods {
    pub const NONE: Goods = Goods { grain: 0, timber: 0, stone: 0, moonsalt: 0 };

    pub const fn of(grain: u64, timber: u64, stone: u64, moonsalt: u64) -> Goods {
        Goods { grain, timber, stone, moonsalt }
    }

    pub fn parts(self) -> [u64; 4] {
        [self.grain, self.timber, self.stone, self.moonsalt]
    }

    pub fn from_parts(parts: [u64; 4]) -> Goods {
        Goods::of(parts[0], parts[1], parts[2], parts[3])
    }

    pub fn is_none(self) -> bool {
        self == Goods::NONE
    }

    /// Whether these goods are enough to pay a cost.
    pub fn covers(self, cost: Goods) -> bool {
        self.short_of(cost).is_none()
    }

    /// What is missing to pay a cost.
    pub fn short_of(self, cost: Goods) -> Goods {
        let (have, want) = (self.parts(), cost.parts());
        Goods::from_parts([0, 1, 2, 3].map(|i| want[i].saturating_sub(have[i])))
    }

    pub fn minus(self, cost: Goods) -> Goods {
        let (have, want) = (self.parts(), cost.parts());
        Goods::from_parts([0, 1, 2, 3].map(|i| have[i].saturating_sub(want[i])))
    }

    pub fn plus(self, more: Goods) -> Goods {
        let (have, add) = (self.parts(), more.parts());
        Goods::from_parts([0, 1, 2, 3].map(|i| have[i].saturating_add(add[i])))
    }

    pub fn times(self, by: u64) -> Goods {
        Goods::from_parts(self.parts().map(|part| part.saturating_mul(by)))
    }
}

/// "320 timber and 100 stone".
impl fmt::Display for Goods {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let named: Vec<String> = self
            .parts()
            .iter()
            .zip(["grain", "timber", "stone", "moonsalt"])
            .filter(|(amount, _)| **amount > 0)
            .map(|(amount, name)| format!("{} {name}", grouped(*amount)))
            .collect();
        match named.len() {
            0 => f.write_str("nothing"),
            1 => f.write_str(&named[0]),
            count => write!(f, "{} and {}", named[..count - 1].join(", "), named[count - 1]),
        }
    }
}

/// A number with its thousands set apart: 12,500.
pub fn grouped(number: u64) -> String {
    let digits = number.to_string();
    let mut out = String::new();
    for (index, digit) in digits.chars().enumerate() {
        if index > 0 && (digits.len() - index) % 3 == 0 {
            out.push(',');
        }
        out.push(digit);
    }
    out
}

/// A length of time as a player reads it: "45 seconds", "3 hours 20 minutes".
pub fn spoken(seconds: i64) -> String {
    let seconds = seconds.max(0);
    let unit = |count: i64, name: &str| format!("{count} {name}{}", if count == 1 { "" } else { "s" });
    let (days, hours, minutes, rest) = (seconds / 86_400, seconds % 86_400 / 3_600, seconds % 3_600 / 60, seconds % 60);
    if days > 0 {
        return if hours > 0 { format!("{} {}", unit(days, "day"), unit(hours, "hour")) } else { unit(days, "day") };
    }
    if hours > 0 {
        return if minutes > 0 { format!("{} {}", unit(hours, "hour"), unit(minutes, "minute")) } else { unit(hours, "hour") };
    }
    if minutes > 0 {
        return if rest > 0 { format!("{} {}", unit(minutes, "minute"), unit(rest, "second")) } else { unit(minutes, "minute") };
    }
    unit(rest, "second")
}

/// What stands in a city. One of each.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
#[repr(u8)]
pub enum Building {
    /// The city's heart: nothing rises higher than it.
    Keep = 1,
    Farm = 2,
    Sawmill = 3,
    Quarry = 4,
    Saltworks = 5,
    /// How much of each good the city can keep.
    Storehouse = 6,
    Barracks = 7,
    Range = 8,
    Stable = 9,
    Workshop = 10,
    Hospital = 11,
    Wall = 12,
    Watchtower = 13,
    Academy = 14,
    Embassy = 15,
    Tavern = 16,
    Market = 17,
    ScoutCamp = 18,
    /// Where gear is made for commanders, from what the barrows yield.
    Forge = 19,
}

/// The highest level anything reaches.
pub const TOP_LEVEL: u32 = 25;

impl Building {
    pub const ALL: [Building; 19] = [
        Building::Keep,
        Building::Farm,
        Building::Sawmill,
        Building::Quarry,
        Building::Saltworks,
        Building::Storehouse,
        Building::Barracks,
        Building::Range,
        Building::Stable,
        Building::Workshop,
        Building::Hospital,
        Building::Wall,
        Building::Watchtower,
        Building::Academy,
        Building::Embassy,
        Building::Tavern,
        Building::Market,
        Building::ScoutCamp,
        Building::Forge,
    ];

    pub fn of(code: u8) -> Option<Building> {
        Building::ALL.into_iter().find(|building| *building as u8 == code)
    }

    pub fn name(self) -> &'static str {
        match self {
            Building::Keep => "Keep",
            Building::Farm => "Farm",
            Building::Sawmill => "Sawmill",
            Building::Quarry => "Quarry",
            Building::Saltworks => "Saltworks",
            Building::Storehouse => "Storehouse",
            Building::Barracks => "Barracks",
            Building::Range => "Archery Range",
            Building::Stable => "Stable",
            Building::Workshop => "Siege Workshop",
            Building::Hospital => "Hospital",
            Building::Wall => "Wall",
            Building::Watchtower => "Watchtower",
            Building::Academy => "Academy",
            Building::Embassy => "Embassy",
            Building::Tavern => "Tavern",
            Building::Market => "Market",
            Building::ScoutCamp => "Scout Camp",
            Building::Forge => "Forge",
        }
    }

    /// The Keep level at which it may first be built.
    pub fn opens_at(self) -> u32 {
        match self {
            Building::Keep | Building::Farm | Building::Sawmill => 1,
            Building::Quarry | Building::Storehouse | Building::Barracks => 2,
            Building::Wall | Building::Hospital | Building::ScoutCamp => 3,
            Building::Range | Building::Tavern => 4,
            Building::Academy | Building::Embassy | Building::Forge => 5,
            Building::Stable => 6,
            Building::Saltworks => 7,
            Building::Market | Building::Watchtower => 8,
            Building::Workshop => 10,
        }
    }

    /// What it costs to raise from nothing to its first level: grain,
    /// timber, stone. Each level after costs more by `GROWTH`.
    fn first_cost(self) -> [u64; 3] {
        match self {
            Building::Keep => [0, 400, 200],
            Building::Farm => [0, 80, 20],
            Building::Sawmill => [60, 20, 30],
            Building::Quarry => [80, 80, 0],
            Building::Saltworks => [300, 300, 300],
            Building::Storehouse => [0, 150, 100],
            Building::Barracks => [150, 200, 50],
            Building::Range => [150, 250, 50],
            Building::Stable => [300, 300, 100],
            Building::Workshop => [400, 600, 400],
            Building::Hospital => [200, 150, 100],
            Building::Wall => [0, 100, 300],
            Building::Watchtower => [0, 200, 300],
            Building::Academy => [200, 300, 300],
            Building::Embassy => [300, 300, 200],
            Building::Tavern => [300, 300, 0],
            Building::Market => [300, 400, 100],
            Building::ScoutCamp => [100, 150, 0],
            Building::Forge => [0, 300, 400],
        }
    }

    /// How long it takes to raise, in thousandths of the Keep's time to
    /// the same level.
    fn share_of_keep(self) -> i64 {
        match self {
            Building::Keep => 1000,
            Building::Farm | Building::Sawmill | Building::Quarry | Building::Saltworks => 300,
            Building::Storehouse => 350,
            Building::Barracks | Building::Range | Building::Stable | Building::Workshop => 500,
            Building::Hospital | Building::Watchtower | Building::Embassy => 400,
            Building::Wall | Building::Academy => 600,
            Building::Tavern | Building::Market => 300,
            Building::ScoutCamp => 250,
            Building::Forge => 400,
        }
    }

    /// How much its level counts toward its city's power.
    fn weight(self) -> u64 {
        match self {
            Building::Keep => 100,
            Building::Wall | Building::Academy => 40,
            Building::Barracks | Building::Range | Building::Stable | Building::Workshop => 30,
            _ => 20,
        }
    }
}

/// How much more each level costs than the last, in hundredths: 1.55 times.
const GROWTH: u64 = 155;

/// The seconds the Keep takes to reach each level from 2 to 25, as
/// written, before the realm's pace: eight seconds to two months.
const KEEP_SECONDS: [i64; 24] = [
    8, 45, 180, 600, 1_500, 3_600, 7_200, 14_400, 28_800, 43_200, 64_800, 86_400, 129_600, 172_800, 259_200, 345_600, 518_400, 691_200, 950_400,
    1_296_000, 1_728_000, 2_419_200, 3_456_000, 5_184_000,
];

/// A number kept to its two leading digits: 1,234 is 1,200.
fn rounded(number: u64) -> u64 {
    let mut unit = 1;
    while number / unit >= 100 {
        unit *= 10;
    }
    number / unit * unit
}

/// What it costs to raise a building to a level from the level below.
pub fn cost(building: Building, level: u32) -> Goods {
    let level = level.clamp(1, TOP_LEVEL);
    let mut parts = building.first_cost();
    for _ in 1..level {
        parts = parts.map(|part| part * GROWTH / 100);
    }
    // From the eleventh level the great works take moonsalt too.
    let moonsalt = if level > 10 { (level as u64 - 10) * (level as u64 - 10) * building.weight() } else { 0 };
    Goods::of(rounded(parts[0]), rounded(parts[1]), rounded(parts[2]), moonsalt)
}

/// How long raising a building to a level takes, in seconds as written.
pub fn seconds(building: Building, level: u32) -> i64 {
    let level = level.clamp(1, TOP_LEVEL);
    // Nothing takes less than three seconds, a first raising among them.
    if level == 1 {
        return 3;
    }
    (KEEP_SECONDS[level as usize - 2] * building.share_of_keep() / 1000).max(3)
}

/// How long something written to take `seconds` takes in a realm of a pace.
pub fn paced(seconds: i64, pace: u32) -> i64 {
    (seconds / pace.max(1) as i64).max(1)
}

/// What a building gives its city each hour at a level, as written.
pub fn yields(building: Building, level: u32) -> Goods {
    let level = level.min(TOP_LEVEL) as u64;
    let grown = |first: u64| first * level * (level + 4) / 5;
    match building {
        // A city's own folk bring in a little whatever stands in it.
        Building::Keep if level > 0 => Goods::of(400, 400, 300, 0),
        Building::Farm => Goods::of(grown(900), 0, 0, 0),
        Building::Sawmill => Goods::of(0, grown(900), 0, 0),
        Building::Quarry => Goods::of(0, 0, grown(600), 0),
        Building::Saltworks => Goods::of(0, 0, 0, grown(150)),
        _ => Goods::NONE,
    }
}

/// How much of each good a city can keep, by its Storehouse's level; none
/// built is level 0.
pub fn holds(storehouse: u32) -> u64 {
    let level = storehouse.min(TOP_LEVEL) as u64;
    30_000 + 40_000 * level * level
}

/// What a building at a level adds to its city's power.
pub fn power(building: Building, level: u32) -> u64 {
    building.weight() * level as u64 * level as u64
}

/// The other building, and its level, that must stand before a building
/// can be raised to a level: the Keep waits on the Wall.
pub fn needs(building: Building, level: u32) -> Option<(Building, u32)> {
    match building {
        Building::Keep if level >= 4 => Some((Building::Wall, level - 1)),
        _ => None,
    }
}

/// What a new city starts with.
pub const STARTING_GOODS: Goods = Goods::of(6_000, 8_000, 6_000, 0);

/// The four kinds of troops, each trained in a building of its own.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
#[repr(u8)]
pub enum Troops {
    /// Foot with spear and shield: they stand.
    Spearmen = 1,
    /// Bows: they strike hardest and stand least.
    Archers = 2,
    /// Horse: they are fastest.
    Riders = 3,
    /// Siege engines: slow, weak in the field, and they carry the most.
    Mangonels = 4,
}

/// The highest tier of troops.
pub const TOP_TIER: u32 = 5;

/// What a soldier struck down in a battle between cities is worth to the
/// one who struck them down, by tier: the realm's kill points.
pub fn kill_points(tier: u32) -> u64 {
    [1, 2, 4, 10, 20][tier.clamp(1, TOP_TIER) as usize - 1]
}

/// What one soldier of a kind and tier is and costs.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Soldier {
    pub attack: u64,
    pub defence: u64,
    pub health: u64,
    /// Tenths of a second to cross one hex, as written.
    pub pace: u64,
    /// How much of any goods one carries home.
    pub load: u64,
    pub power: u64,
    pub cost: Goods,
    /// Seconds to train one, as written.
    pub seconds: i64,
    /// The level their building must have reached.
    pub needs_level: u32,
}

impl Troops {
    pub const ALL: [Troops; 4] = [Troops::Spearmen, Troops::Archers, Troops::Riders, Troops::Mangonels];

    pub fn of(code: u8) -> Option<Troops> {
        Troops::ALL.into_iter().find(|troops| *troops as u8 == code)
    }

    pub fn name(self) -> &'static str {
        match self {
            Troops::Spearmen => "Spearmen",
            Troops::Archers => "Archers",
            Troops::Riders => "Riders",
            Troops::Mangonels => "Mangonels",
        }
    }

    /// Where they are trained.
    pub fn trained_in(self) -> Building {
        match self {
            Troops::Spearmen => Building::Barracks,
            Troops::Archers => Building::Range,
            Troops::Riders => Building::Stable,
            Troops::Mangonels => Building::Workshop,
        }
    }

    /// The kind a building trains, if it trains any.
    pub fn trained_by(building: Building) -> Option<Troops> {
        Troops::ALL.into_iter().find(|troops| troops.trained_in() == building)
    }

    /// One soldier of this kind at a tier, 1 to 5.
    pub fn soldier(self, tier: u32) -> Soldier {
        let tier = tier.clamp(1, TOP_TIER) as usize;
        // Each tier's strength and cost against the first's, in hundredths.
        let strength = [100, 135, 180, 240, 320][tier - 1];
        let dearer = [100, 200, 350, 600, 1_000][tier - 1];
        let (attack, defence, health, pace, load, cost) = match self {
            Troops::Spearmen => (90, 110, 110, 60, 12, [50, 50, 0]),
            Troops::Archers => (110, 90, 95, 60, 10, [40, 70, 0]),
            Troops::Riders => (105, 100, 100, 35, 8, [80, 30, 20]),
            Troops::Mangonels => (60, 60, 90, 90, 30, [0, 80, 60]),
        };
        Soldier {
            attack: attack * strength / 100,
            defence: defence * strength / 100,
            health: health * strength / 100,
            pace,
            load: load * (100 + 20 * (tier as u64 - 1)) / 100,
            power: [1, 2, 3, 4, 10][tier - 1],
            cost: Goods::of(cost[0] * dearer / 100, cost[1] * dearer / 100, cost[2] * dearer / 100, [0, 0, 0, 4, 10][tier - 1]),
            seconds: [8, 16, 30, 50, 80][tier - 1],
            needs_level: [1, 5, 10, 17, 25][tier - 1],
        }
    }
}

/// The most soldiers a training building takes in one batch at a level.
pub fn batch(level: u32) -> u64 {
    10 + 40 * level.min(TOP_LEVEL) as u64
}

/// How many buildings a city may raise at once, by its Keep's level: a
/// second builder from the eighth.
pub fn builders(keep: u32) -> u32 {
    if keep >= 8 {
        2
    } else {
        1
    }
}

/// How many armies a city may have out at once, by its Keep's level.
pub fn marches(keep: u32) -> u32 {
    match keep {
        0..=4 => 1,
        5..=10 => 2,
        11..=16 => 3,
        17..=21 => 4,
        _ => 5,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn goods_are_counted_paid_and_said() {
        let have = Goods::of(100, 500, 0, 3);
        let cost = Goods::of(80, 820, 100, 0);
        assert!(!have.covers(cost));
        assert_eq!(have.short_of(cost), Goods::of(0, 320, 100, 0));
        assert_eq!(have.short_of(cost).to_string(), "320 timber and 100 stone");
        assert!(have.plus(Goods::of(0, 320, 100, 0)).covers(cost));
        assert_eq!(have.plus(Goods::of(0, 320, 100, 0)).minus(cost), Goods::of(20, 0, 0, 3));
        assert_eq!(Goods::of(1_250_000, 9, 12_000, 1).to_string(), "1,250,000 grain, 9 timber, 12,000 stone and 1 moonsalt");
        assert_eq!(Goods::NONE.to_string(), "nothing");
        assert_eq!(Goods::of(0, 0, 7, 0).to_string(), "7 stone");
        assert_eq!(Goods::of(1, 2, 3, 4).times(3), Goods::of(3, 6, 9, 12));
        assert_eq!(grouped(0), "0");
        assert_eq!(grouped(999), "999");
        assert_eq!(grouped(1_000), "1,000");
    }

    #[test]
    fn time_is_said_plainly() {
        assert_eq!(spoken(0), "0 seconds");
        assert_eq!(spoken(1), "1 second");
        assert_eq!(spoken(45), "45 seconds");
        assert_eq!(spoken(60), "1 minute");
        assert_eq!(spoken(185), "3 minutes 5 seconds");
        assert_eq!(spoken(7_200), "2 hours");
        assert_eq!(spoken(12_000), "3 hours 20 minutes");
        assert_eq!(spoken(86_400), "1 day");
        assert_eq!(spoken(5_184_000), "60 days");
        assert_eq!(spoken(93_600), "1 day 2 hours");
    }

    #[test]
    fn every_building_grows_dearer_and_slower_level_by_level() {
        assert_eq!(Building::ALL.len(), 19);
        for (index, building) in Building::ALL.into_iter().enumerate() {
            assert_eq!(building as u8 as usize, index + 1);
            assert_eq!(Building::of(building as u8), Some(building));
            assert!(!building.name().is_empty());
            assert!((1..=10).contains(&building.opens_at()));
            for level in 2..=TOP_LEVEL {
                let (before, now) = (cost(building, level - 1), cost(building, level));
                assert!(now.parts().iter().zip(before.parts()).all(|(now, before)| *now >= before), "{building:?} {level}");
                assert!(now.grain + now.timber + now.stone > before.grain + before.timber + before.stone, "{building:?} {level}");
                assert!(seconds(building, level) >= seconds(building, level - 1), "{building:?} {level}");
                assert!(power(building, level) > power(building, level - 1));
            }
            assert_eq!(cost(building, 5).moonsalt, 0, "no moonsalt before the eleventh level");
            assert!(cost(building, 11).moonsalt > 0);
        }
        assert_eq!(Building::of(0), None);
        assert_eq!(Building::of(20), None);
        assert_eq!(cost(Building::Keep, 2), Goods::of(0, 620, 310, 0));
        assert_eq!(seconds(Building::Keep, 2), 8);
        assert_eq!(seconds(Building::Keep, 25), 5_184_000, "two months, as written");
        assert_eq!(seconds(Building::Farm, 1), 3);
        assert_eq!(seconds(Building::Farm, 2), 3);
        assert_eq!(seconds(Building::Farm, 10), 28_800 * 3 / 10);
        assert_eq!(paced(3_600, 60), 60);
        assert_eq!(paced(5, 100), 1, "never less than a second");
        assert_eq!(paced(5, 0), 5);
    }

    #[test]
    fn troops_grow_stronger_and_dearer_tier_by_tier() {
        for (index, troops) in Troops::ALL.into_iter().enumerate() {
            assert_eq!(troops as u8 as usize, index + 1);
            assert_eq!(Troops::of(troops as u8), Some(troops));
            assert_eq!(Troops::trained_by(troops.trained_in()), Some(troops));
            for tier in 2..=TOP_TIER {
                let (before, now) = (troops.soldier(tier - 1), troops.soldier(tier));
                assert!(now.attack > before.attack && now.defence > before.defence && now.health > before.health, "{troops:?} {tier}");
                assert!(now.power > before.power && now.seconds > before.seconds && now.needs_level > before.needs_level);
                assert!(now.cost.parts().iter().sum::<u64>() > before.cost.parts().iter().sum::<u64>());
                assert!(now.load >= before.load);
                assert_eq!(now.pace, before.pace, "a tier marches no faster");
            }
            assert_eq!(troops.soldier(0), troops.soldier(1));
            assert_eq!(troops.soldier(9), troops.soldier(TOP_TIER));
        }
        assert_eq!(Troops::of(0), None);
        assert_eq!(Troops::trained_by(Building::Farm), None);
        let (spear, bow, horse, engine) = (Troops::Spearmen.soldier(1), Troops::Archers.soldier(1), Troops::Riders.soldier(1), Troops::Mangonels.soldier(1));
        assert!(bow.attack > horse.attack && horse.attack > spear.attack, "bows strike hardest");
        assert!(spear.defence > horse.defence && horse.defence > bow.defence, "spears stand best");
        assert!(horse.pace < spear.pace && spear.pace < engine.pace, "horse is fastest, engines slowest");
        assert!(engine.load > spear.load, "engines carry the most");
        assert_eq!(spear.cost, Goods::of(50, 50, 0, 0));
        assert_eq!(Troops::Spearmen.soldier(5).cost, Goods::of(500, 500, 0, 10));
        assert_eq!((batch(1), batch(25), batch(99)), (50, 1_010, 1_010));
        assert_eq!([1, 4, 5, 10, 11, 17, 22, 25].map(marches), [1, 1, 2, 2, 3, 4, 5, 5]);
    }

    #[test]
    fn works_yield_more_as_they_rise_and_the_storehouse_holds_more() {
        assert_eq!(yields(Building::Farm, 1), Goods::of(900, 0, 0, 0));
        assert_eq!(yields(Building::Farm, 0), Goods::NONE);
        assert_eq!(yields(Building::Keep, 3), Goods::of(400, 400, 300, 0));
        assert_eq!(yields(Building::Wall, 9), Goods::NONE);
        for building in [Building::Farm, Building::Sawmill, Building::Quarry, Building::Saltworks] {
            for level in 1..=TOP_LEVEL {
                let (before, now) = (yields(building, level - 1), yields(building, level));
                assert!(now.parts().iter().sum::<u64>() > before.parts().iter().sum::<u64>(), "{building:?} {level}");
            }
        }
        assert_eq!(holds(0), 30_000);
        assert!(holds(1) > holds(0));
        assert_eq!(holds(25), holds(40), "no higher than the top");
        assert_eq!(needs(Building::Keep, 3), None);
        assert_eq!(needs(Building::Keep, 4), Some((Building::Wall, 3)));
        assert_eq!(needs(Building::Farm, 9), None);
        assert!(STARTING_GOODS.covers(cost(Building::Keep, 2)), "a new city can raise its Keep at once");
    }
}

/// Soldiers of one kind and tier, counted.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Unit {
    pub kind: Troops,
    pub tier: u32,
    pub count: u64,
}

/// The highest level a barrow of the Unquiet reaches.
pub const TOP_BARROW: u32 = 25;

/// Who stands in a barrow of the Unquiet at a level: foot at first, bows
/// among them from the fourth level, riders from the eighth, a tier
/// stronger every five levels.
pub fn barrow(level: u32) -> Vec<Unit> {
    let level = level.clamp(1, TOP_BARROW) as u64;
    let tier = (1 + (level - 1) / 5) as u32;
    let heads = 20 * level + 5 * level * level;
    let bows = if level >= 4 { heads * 30 / 100 } else { 0 };
    let riders = if level >= 8 { heads * 20 / 100 } else { 0 };
    [(Troops::Spearmen, heads - bows - riders), (Troops::Archers, bows), (Troops::Riders, riders)]
        .into_iter()
        .filter(|(_, count)| *count > 0)
        .map(|(kind, count)| Unit { kind, tier, count })
        .collect()
}

/// What lies in a barrow of a level for whoever clears it.
pub fn spoils(level: u32) -> Goods {
    let level = level.clamp(1, TOP_BARROW) as u64;
    Goods::of(800 * level, 800 * level, if level >= 3 { 300 * level } else { 0 }, if level >= 6 { 30 * level } else { 0 })
}

/// The most energy a player keeps, what attacking a barrow takes, and how
/// many seconds bring one point back, as written.
pub const ENERGY_MOST: u32 = 1_000;
pub const ENERGY_A_HUNT: u32 = 50;
pub const ENERGY_SECONDS: u64 = 8;

/// How long a fight at a barrow lasts, as written.
pub const FIGHT_SECONDS: i64 = 15;

/// A number as a word of order: first, second, and so on.
pub fn ordinal(number: u32) -> String {
    match number {
        1 => "first".into(),
        2 => "second".into(),
        3 => "third".into(),
        4 => "fourth".into(),
        5 => "fifth".into(),
        n => format!("{n}th"),
    }
}

/// The stages of an alliance's Moonspire.
pub const SPIRE_STAGES: u32 = 5;

/// What each stage of a Moonspire asks of its alliance's members, all
/// told, before it is raised: a hundred thousand of each good times the
/// stage squared, and moonsalt from the third.
pub fn spire_cost(stage: u32) -> Goods {
    let each = 100_000 * (stage as u64).pow(2);
    Goods::of(each, each, each, if stage >= 3 { each / 10 } else { 0 })
}

/// How long a stage takes to raise once it is paid for, at the written pace.
pub fn spire_seconds(stage: u32) -> i64 {
    4 * 3_600 * stage as i64
}

/// By how many hundredths each stage of an alliance's Moonspire lifts what
/// every member's works bring in.
pub const SPIRE_YIELD: u64 = 3;

/// How many days of the realm a season lasts, at the written pace.
pub const SEASON_DAYS: i64 = 28;

/// How far an alliance's wardstone claims the land: every hex within so
/// many steps of it.
pub const WARD_REACH: u32 = 3;

/// What raising a wardstone costs, out of the raiser's city.
pub const WARD_COST: Goods = Goods::of(0, 30_000, 30_000, 0);

/// How long a wardstone takes to raise, at the realm's first pace.
pub const WARD_SECONDS: i64 = 3_600;

/// Hundredths faster an alliance's members gather on its own land.
pub const WARD_GATHERING: u64 = 25;

/// The days into each season, at the realm's pace, from which the gates
/// of the ridge may be stormed: the lake country opens a week in.
pub const GATES_OPEN_DAYS: i64 = 7;

/// Who holds a gate of the ridge: twice the Unquiet of the strongest
/// barrow, and whoever takes the gate holds it with as many.
pub fn gate_garrison() -> Vec<Unit> {
    barrow(TOP_BARROW).into_iter().map(|unit| Unit { count: unit.count * 2, ..unit }).collect()
}

/// The most characters a letter holds, and how many letters a player
/// keeps: the oldest go as new ones come.
pub const LETTER_LONGEST: usize = 1_000;
pub const LETTERS_KEPT: usize = 100;

/// A title the Lord of the Mere bestows: each held by one player at a
/// time, lending them what so many levels of a study would.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u8)]
pub enum Title {
    /// Their armies gather faster.
    Forager = 1,
    /// Their soldiers are trained sooner.
    Marshal = 2,
    /// Their buildings are raised sooner.
    Mason = 3,
    /// Everyone they send or keep is harder to bring down.
    Warden = 4,
    /// Their armies march faster.
    Herald = 5,
}

impl Title {
    pub const ALL: [Title; 5] = [Title::Forager, Title::Marshal, Title::Mason, Title::Warden, Title::Herald];

    pub fn of(code: u8) -> Option<Title> {
        Title::ALL.into_iter().find(|title| *title as u8 == code)
    }

    pub fn name(self) -> &'static str {
        match self {
            Title::Forager => "Forager of the Mere",
            Title::Marshal => "Marshal of the Mere",
            Title::Mason => "Mason of the Mere",
            Title::Warden => "Warden of the Mere",
            Title::Herald => "Herald of the Mere",
        }
    }

    /// The study it lends, and as many levels of it as.
    pub fn lends(self) -> (Topic, u32) {
        match self {
            Title::Forager => (Topic::Gathering, 2),
            Title::Marshal => (Topic::Drill, 4),
            Title::Mason => (Topic::Building, 4),
            Title::Warden => (Topic::Shields, 3),
            Title::Herald => (Topic::Marching, 3),
        }
    }
}

/// The most of each good a petition may ask of an alliance, how long it
/// stands, at the realm's pace, and the hundredths of what allies send
/// that the road takes.
pub const PETITION_MOST: u64 = 500_000;
pub const PETITION_STANDS: i64 = DAY;
pub const PETITION_TOLL: u64 = 10;

/// What a Watchtower of a level adds to how hard every defender of its
/// city strikes when the city is stormed, in hundredths: one a level, its
/// watchers loosing from above with them. The Watchtower's whole work.
pub fn watch(level: u32) -> u64 {
    level as u64
}

/// The hundredths of what is sent in answer to a petition that the road
/// takes, from a city with a Market of a level: a tenth with none, one
/// hundredth less for every three levels begun, never less than two. The
/// Market's whole work: its carters know the roads.
pub fn petition_toll(market: u32) -> u64 {
    PETITION_TOLL.saturating_sub((market as u64).div_ceil(3)).max(2)
}

/// How many days, at the realm's pace, a commander taken prisoner is held
/// before they go free of themselves.
pub const PRISON_DAYS: i64 = 3;

/// What a commander's freedom costs: five thousand each of grain, timber
/// and stone for each level.
pub fn ransom(level: u32) -> Goods {
    let each = 5_000 * level.max(1) as u64;
    Goods::of(each, each, each, 0)
}

/// The most days an alliance's envoy may offer a pact for, and how long
/// an envoy waits for an answer before it is gone; how long a pact goes on
/// once broken, at the realm's pace.
pub const PACT_MOST_DAYS: u32 = 14;
pub const ENVOY_WAITS: i64 = DAY;
pub const PACT_NOTICE: i64 = DAY;

/// Who keeps a wardstone against a rally sent to take it down: as many as
/// keep a barrow of the twelfth level.
pub fn ward_garrison() -> Vec<Unit> {
    barrow(12)
}

/// How much a wardstone's ring of stones shelters its keepers: as a Wall
/// of the fifth level does a city's.
pub fn ward_shelter() -> u64 {
    shelter(5)
}

/// How much a gate's walls shelter its garrison: as a Wall of the tenth
/// level does a city's.
pub fn gate_shelter() -> u64 {
    shelter(10)
}

/// The highest level an alliance learns a topic to: each level gives its
/// members what a level of it learnt in their own city does.
pub const TOP_ALLIANCE_STUDY: u32 = 5;

/// What an alliance's members give together for it to learn a topic to a
/// level: a hundred thousand each of grain, timber and stone, times the
/// level squared.
pub fn alliance_study_cost(level: u32) -> Goods {
    let each = 100_000 * level.max(1) as u64 * level.max(1) as u64;
    Goods::of(each, each, each, 0)
}

/// How long an alliance takes to learn a topic to a level once it is paid
/// for, at the realm's first pace: two hours times the level.
pub fn alliance_study_seconds(level: u32) -> i64 {
    7_200 * level.max(1) as i64
}

/// The wardstones an alliance may have: one, and one more for every five
/// members, twenty at most.
pub fn wards_for(members: u32) -> u32 {
    (1 + members / 5).min(20)
}

/// How many allies may help with one work: more with a higher Embassy.
pub fn helps(embassy: u32) -> u32 {
    (4 + embassy).min(30)
}

/// The least a help takes off a work, at the written pace; it takes a
/// hundredth of what is left where that is more.
pub const HELP_SECONDS: i64 = 60;

/// How long a rally musters before it sets out, at the written pace.
pub const RALLY_MUSTER: i64 = 300;
/// How many levels above the strongest barrow its caller may attack alone
/// a rally may go against.
pub const RALLY_REACH: u32 = 3;
/// The most armies in a rally, its caller's among them.
pub const RALLY_ARMIES: u32 = 5;

/// How many wounded a city can tend, by its Hospital's level: a few even
/// with none.
pub fn tends(hospital: u32) -> u64 {
    let level = hospital.min(TOP_LEVEL) as u64;
    50 + 150 * level + 10 * level * level
}

/// What healing one wounded soldier costs, and the seconds it takes as
/// written: a third of training one, in a quarter of the time.
pub fn healing(soldier: Soldier) -> (Goods, i64) {
    let [grain, timber, stone, moonsalt] = soldier.cost.parts();
    (Goods::of(grain / 3, timber / 3, stone / 3, moonsalt / 3), (soldier.seconds / 4).max(1))
}

/// How long a new city is kept from attack, how long a city beaten
/// within its own walls is, and how long an assault on a city lasts, as
/// written.
pub const NEW_CITY_PEACE: i64 = 3 * 86_400;
/// What one speedup costs: it cuts a quarter of what is left of a
/// building's raising, and is paid in goods.
pub const SPEEDUP: Goods = Goods::of(300, 300, 300, 0);
/// What a city pays to move to new ground: its goods, and its people go with it.
pub const RELOCATION: Goods = Goods::of(3_000, 3_000, 3_000, 0);
pub const BEATEN_PEACE: i64 = 4 * 3_600;
pub const ASSAULT_SECONDS: i64 = 30;

/// How much harder a city's defenders are to bring down behind its Wall,
/// in hundredths: three for each of the Wall's levels.
pub fn shelter(wall: u32) -> u64 {
    3 * wall.min(TOP_LEVEL) as u64
}

/// How much of each good a city keeps safe from plunder, by its
/// Storehouse's level.
pub fn kept_safe(storehouse: u32) -> u64 {
    2_000 + 1_000 * storehouse.min(TOP_LEVEL) as u64
}

/// The most members an alliance has, how many of its words and the
/// realm's are kept, the longest thing that can be said, and the seconds
/// a player waits between saying one thing and the next.
pub const ALLIANCE_MOST: u32 = 100;
pub const ALLIANCE_CHAT_KEPT: usize = 200;
pub const REALM_CHAT_KEPT: u64 = 300;
pub const SAID_LONGEST: usize = 200;
pub const SAID_EVERY: i64 = 2;

/// What a task asks of a player's city.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Goal {
    /// The Keep at a level.
    Keep(u32),
    /// A building standing at a level.
    Raised(Building, u32),
    /// So many soldiers, wherever they are.
    Soldiers(u64),
    /// A barrow of a level cleared.
    Cleared(u32),
    /// In an alliance.
    Allied,
    /// So much power.
    Power(u64),
    /// So many cairns whose hoards the player's scouts have found.
    Found(u64),
}

impl Goal {
    /// The goal as three numbers, for a row: its kind and two amounts.
    pub fn numbers(self) -> (u8, u64, u64) {
        match self {
            Goal::Keep(level) => (1, level as u64, 0),
            Goal::Raised(building, level) => (2, building as u64, level as u64),
            Goal::Soldiers(count) => (3, count, 0),
            Goal::Cleared(level) => (4, level as u64, 0),
            Goal::Allied => (5, 0, 0),
            Goal::Power(power) => (6, power, 0),
            Goal::Found(count) => (7, count, 0),
        }
    }

    /// The goal in a player's words.
    pub fn words(self) -> String {
        match self {
            Goal::Keep(level) => format!("Raise your Keep to level {level}."),
            Goal::Raised(building, 1) => format!("Build {} {}.", if building.name().starts_with(['A', 'E', 'I', 'O', 'U']) { "an" } else { "a" }, building.name()),
            Goal::Raised(building, level) => format!("Raise your {} to level {level}.", building.name()),
            Goal::Soldiers(count) => format!("Have {} soldiers.", grouped(count)),
            Goal::Cleared(level) => format!("Clear a level {level} barrow of the Unquiet."),
            Goal::Allied => "Join an alliance, or found one.".to_string(),
            Goal::Power(power) => format!("Reach {} power.", grouped(power)),
            Goal::Found(1) => "Send a scout to find what a cairn holds.".to_string(),
            Goal::Found(count) => format!("Have your scouts find what {count} cairns hold."),
        }
    }
}

/// A player's first tasks, in the order they are set: what each asks and
/// what it gives when it is done. They lead a new city through its
/// first buildings, its first soldiers and its first fights.
pub fn tasks() -> Vec<(Goal, Goods)> {
    let give = |grain: u64, timber: u64, stone: u64| Goods::of(grain, timber, stone, 0);
    vec![
        (Goal::Keep(2), give(1_000, 1_000, 0)),
        (Goal::Raised(Building::Barracks, 1), give(1_000, 1_000, 0)),
        (Goal::Soldiers(20), give(1_500, 1_500, 0)),
        (Goal::Cleared(1), give(2_000, 2_000, 500)),
        (Goal::Raised(Building::Farm, 2), give(1_000, 1_500, 0)),
        (Goal::Raised(Building::Sawmill, 2), give(1_500, 1_000, 0)),
        (Goal::Raised(Building::Quarry, 1), give(1_000, 1_000, 1_000)),
        (Goal::Raised(Building::Storehouse, 1), give(2_000, 2_000, 1_000)),
        (Goal::Keep(3), give(3_000, 3_000, 1_500)),
        (Goal::Raised(Building::Wall, 1), give(2_000, 2_000, 2_000)),
        (Goal::Raised(Building::Hospital, 1), give(3_000, 3_000, 1_000)),
        (Goal::Raised(Building::ScoutCamp, 1), give(2_000, 2_000, 1_000)),
        (Goal::Found(1), give(3_000, 3_000, 1_500)),
        (Goal::Soldiers(100), give(4_000, 4_000, 1_000)),
        (Goal::Cleared(2), give(4_000, 4_000, 2_000)),
        (Goal::Keep(4), give(6_000, 6_000, 3_000)),
        (Goal::Raised(Building::Range, 1), give(5_000, 5_000, 2_000)),
        (Goal::Cleared(3), give(6_000, 6_000, 3_000)),
        (Goal::Keep(5), give(10_000, 10_000, 5_000)),
        (Goal::Raised(Building::Embassy, 1), give(6_000, 6_000, 4_000)),
        (Goal::Allied, give(10_000, 10_000, 5_000)),
        (Goal::Soldiers(500), give(12_000, 12_000, 6_000)),
        (Goal::Cleared(5), give(15_000, 15_000, 8_000)),
        (Goal::Power(5_000), Goods::of(20_000, 20_000, 10_000, 500)),
    ]
}

/// What a first task gives besides goods, by its step: hastes as a new
/// city's works grow long, and tomes of war as its commanders first fight.
pub fn task_items(step: u64) -> Vec<(Item, u64)> {
    match step {
        2 => vec![(Item::Haste5, 2)],
        3 => vec![(Item::Haste5, 3)],
        4 => vec![(Item::Tome, 1)],
        7 => vec![(Item::Haste5, 2)],
        9 => vec![(Item::Haste60, 1)],
        10 => vec![(Item::Haste5, 3)],
        13 => vec![(Item::Tome, 1)],
        14 => vec![(Item::Haste5, 5)],
        15 => vec![(Item::Tome, 2)],
        16 => vec![(Item::Haste60, 2)],
        18 => vec![(Item::Tome, 2)],
        19 => vec![(Item::Haste480, 1)],
        21 => vec![(Item::Haste60, 2)],
        22 => vec![(Item::Haste60, 1)],
        23 => vec![(Item::Tome, 3)],
        24 => vec![(Item::Haste480, 1), (Item::Tome, 3)],
        _ => Vec::new(),
    }
}

/// A deed of the day's work: something every player may do each day of
/// the realm, counted from the day's beginning.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Deed {
    /// Soldiers set to train.
    Train = 1,
    /// Goods brought home from the land.
    Gather = 2,
    /// Barrows of the Unquiet cleared.
    Clear = 3,
    /// Works begun: a building raised or a study taken up.
    Begin = 4,
    /// Works hastened, one's own or an ally's.
    Hasten = 5,
}

impl Deed {
    pub const ALL: [Deed; 5] = [Deed::Train, Deed::Gather, Deed::Clear, Deed::Begin, Deed::Hasten];

    pub fn of(code: u8) -> Option<Deed> {
        Deed::ALL.into_iter().find(|deed| *deed as u8 == code)
    }

    /// How much of it the day asks.
    pub fn asks(self) -> u64 {
        match self {
            Deed::Train => 50,
            Deed::Gather => 5_000,
            Deed::Clear => 1,
            Deed::Begin => 2,
            Deed::Hasten => 1,
        }
    }

    /// The marks it earns when done: all five make a hundred.
    pub fn marks(self) -> u32 {
        20
    }

    /// The deed in a player's words.
    pub fn words(self) -> String {
        match self {
            Deed::Train => format!("Set {} soldiers to train.", grouped(self.asks())),
            Deed::Gather => format!("Bring home {} goods from the land.", grouped(self.asks())),
            Deed::Clear => "Clear a barrow of the Unquiet.".to_string(),
            Deed::Begin => "Begin two works: raise a building, or take up a study.".to_string(),
            Deed::Hasten => "Hasten a work, your own or an ally's.".to_string(),
        }
    }
}

/// How long a day of the realm lasts, at the written pace.
pub const DAY: i64 = 86_400;

/// The day's chests: the marks each asks, and what it holds.
pub fn chests() -> [(u32, Goods); 3] {
    [(40, Goods::of(2_000, 2_000, 1_000, 0)), (70, Goods::of(5_000, 5_000, 2_500, 0)), (100, Goods::of(10_000, 10_000, 5_000, 200))]
}

/// Something a player keeps in their satchel until they use it: so much
/// time taken off a work in their city.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Item {
    Haste5 = 1,
    Haste60 = 2,
    Haste480 = 3,
    /// Eight hours' peace for the city it is used on.
    Peace8 = 4,
    /// What the barrows yield, worked at the Forge into gear.
    Iron = 5,
    Leather = 6,
    Bone = 7,
    Silver = 8,
    /// Read by a commander: so much more seen of war (`Item::seen`).
    Tome = 9,
    GreatTome = 10,
    /// Taken to the Tavern: one of the realm's commanders, or sigils for
    /// one of the player's own.
    Summons = 11,
    /// So much of one good (`Item::goods`), kept in the satchel, where no
    /// army can carry it off, until it is opened into the city.
    GrainCrate = 12,
    TimberCrate = 13,
    StoneCrate = 14,
    MoonsaltCrate = 15,
}

impl Item {
    pub const ALL: [Item; 15] = [
        Item::Haste5,
        Item::Haste60,
        Item::Haste480,
        Item::Peace8,
        Item::Iron,
        Item::Leather,
        Item::Bone,
        Item::Silver,
        Item::Tome,
        Item::GreatTome,
        Item::Summons,
        Item::GrainCrate,
        Item::TimberCrate,
        Item::StoneCrate,
        Item::MoonsaltCrate,
    ];

    /// The materials, in the order a piece's cost names them.
    pub const MATERIALS: [Item; 4] = [Item::Iron, Item::Leather, Item::Bone, Item::Silver];

    /// The crates of goods, in the order of the goods.
    pub const CRATES: [Item; 4] = [Item::GrainCrate, Item::TimberCrate, Item::StoneCrate, Item::MoonsaltCrate];

    pub fn of(code: u8) -> Option<Item> {
        Item::ALL.into_iter().find(|item| *item as u8 == code)
    }

    /// The time it takes off a work, or the peace it keeps, at the
    /// written pace.
    pub fn seconds(self) -> i64 {
        match self {
            Item::Haste5 => 300,
            Item::Haste60 => 3_600,
            Item::Haste480 | Item::Peace8 => 28_800,
            _ => 0,
        }
    }

    /// What a crate holds: ten thousand grain or timber, five thousand
    /// stone or five hundred moonsalt. Nothing for anything else.
    pub fn goods(self) -> Goods {
        match self {
            Item::GrainCrate => Goods::of(10_000, 0, 0, 0),
            Item::TimberCrate => Goods::of(0, 10_000, 0, 0),
            Item::StoneCrate => Goods::of(0, 0, 5_000, 0),
            Item::MoonsaltCrate => Goods::of(0, 0, 0, 500),
            _ => Goods::NONE,
        }
    }

    /// Whether it is a crate of goods, opened into the city rather than used.
    pub fn is_crate(self) -> bool {
        Item::CRATES.contains(&self)
    }

    /// Whether it is a material, worked at the Forge rather than used.
    pub fn is_material(self) -> bool {
        Item::MATERIALS.contains(&self)
    }

    /// Whether it keeps the city at peace, rather than hastening a work.
    pub fn is_peace(self) -> bool {
        self == Item::Peace8
    }

    /// Whether it is taken to the Tavern, rather than used.
    pub fn is_summons(self) -> bool {
        self == Item::Summons
    }

    /// Whether a commander reads it, rather than it hastening a work.
    pub fn is_tome(self) -> bool {
        self.seen() > 0
    }

    /// What a commander who reads it has seen of war the more.
    pub fn seen(self) -> u64 {
        match self {
            Item::Tome => 500,
            Item::GreatTome => 5_000,
            _ => 0,
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Item::Haste5 => "Five minutes' haste",
            Item::Haste60 => "An hour's haste",
            Item::Haste480 => "Eight hours' haste",
            Item::Peace8 => "Eight hours' peace",
            Item::Iron => "Iron",
            Item::Leather => "Leather",
            Item::Bone => "Bone",
            Item::Silver => "Silver",
            Item::Tome => "Tome of war",
            Item::GreatTome => "Great tome of war",
            Item::Summons => "Summons to the Tavern",
            Item::GrainCrate => "Crate of grain",
            Item::TimberCrate => "Crate of timber",
            Item::StoneCrate => "Crate of stone",
            Item::MoonsaltCrate => "Crate of moonsalt",
        }
    }

    /// What it does, in a player's words.
    pub fn words(self) -> String {
        if self.is_peace() {
            return format!("Keeps your city at peace for {}: no army may attack it. Sending an army against a city ends it.", spoken(self.seconds()));
        }
        if self.is_material() {
            return "Worked at the Forge into gear for your commanders. The barrows of the Unquiet yield it.".to_string();
        }
        if self.is_tome() {
            return format!("Read by one of your commanders: {} more seen of war, toward their next level.", grouped(self.seen()));
        }
        if self.is_crate() {
            return format!("Holds {}. Kept in your satchel no army can carry it off; opened, it goes into your city.", self.goods());
        }
        if self.is_summons() {
            return format!("Taken to your Tavern: one of the realm's commanders comes, or {SIGILS_A_DRAW} sigils for one of yours, toward their gift's next level.");
        }
        format!("Takes {} off a work under way in your city.", spoken(self.seconds()))
    }
}

/// What each of the day's chests holds besides goods, in their order.
pub fn chest_items(chest: u8) -> Vec<(Item, u64)> {
    match chest {
        1 => vec![(Item::Haste5, 2)],
        2 => vec![(Item::Haste5, 3), (Item::Haste60, 1)],
        3 => vec![(Item::Haste60, 2), (Item::Haste480, 1), (Item::Peace8, 1), (Item::Summons, 1)],
        _ => Vec::new(),
    }
}

/// A contest of the realm: something every player may score in while it
/// runs, with prizes for those who score enough. It comes round again
/// every so many days and lasts the first few of them.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Contest {
    /// Barrows of the Unquiet cleared: ten points for each level of each.
    Hunt = 1,
    /// Goods brought home: a point for each hundred.
    Harvest = 2,
    /// Soldiers trained: a point for each, times their tier.
    Arms = 3,
    /// Buildings raised: a point for each power they gain.
    Works = 4,
    /// Soldiers struck down in battles between cities: a point for each kill point.
    Valour = 5,
}

impl Contest {
    pub const ALL: [Contest; 5] = [Contest::Hunt, Contest::Harvest, Contest::Arms, Contest::Works, Contest::Valour];

    pub fn of(code: u8) -> Option<Contest> {
        Contest::ALL.into_iter().find(|contest| *contest as u8 == code)
    }

    pub fn name(self) -> &'static str {
        match self {
            Contest::Hunt => "The Long Hunt",
            Contest::Harvest => "The Harvest Moon",
            Contest::Arms => "The Call to Arms",
            Contest::Works => "The Raising",
            Contest::Valour => "The Red Field",
        }
    }

    /// How it is scored, in a player's words.
    pub fn words(self) -> &'static str {
        match self {
            Contest::Hunt => "Clear barrows of the Unquiet: ten points for each level of each one you clear.",
            Contest::Harvest => "Bring goods home from the land: a point for every hundred your armies carry back.",
            Contest::Arms => "Train soldiers: a point for each one you set to training, times their tier.",
            Contest::Works => "Raise your buildings: a point for each power a building gains as it is raised a level.",
            Contest::Valour => "Strike down soldiers in battles between cities: a point for each kill point.",
        }
    }

    /// Every how many days of the realm it comes round, for how many of
    /// them it runs, and on which day of its round it opens: the week's
    /// contests overlap, each opening on the last day of the one before,
    /// and the Raising and the Red Field run over them, from the second
    /// day to the fourth and on the last two.
    pub fn round(self) -> (u64, u64, u64) {
        match self {
            Contest::Hunt => (7, 3, 0),
            Contest::Harvest => (7, 3, 2),
            Contest::Arms => (7, 3, 4),
            Contest::Works => (7, 3, 1),
            Contest::Valour => (7, 2, 5),
        }
    }

    /// Its prizes, least first: the points each asks, the goods and the
    /// items it gives; the greatest a peace among them.
    pub fn prizes(self) -> Vec<(u64, Goods, Vec<(Item, u64)>)> {
        match self {
            Contest::Hunt => vec![
                (100, Goods::of(3_000, 3_000, 1_500, 0), vec![(Item::Haste5, 2)]),
                (400, Goods::of(8_000, 8_000, 4_000, 0), vec![(Item::Haste60, 1)]),
                (1_000, Goods::of(20_000, 20_000, 10_000, 300), vec![(Item::Haste480, 1), (Item::Peace8, 1)]),
            ],
            Contest::Harvest => vec![
                (200, Goods::of(0, 0, 3_000, 0), vec![(Item::Haste5, 2)]),
                (1_000, Goods::of(0, 0, 8_000, 100), vec![(Item::Haste60, 1)]),
                (4_000, Goods::of(10_000, 10_000, 20_000, 400), vec![(Item::Haste480, 1), (Item::Peace8, 1)]),
            ],
            Contest::Arms => vec![
                (300, Goods::of(5_000, 2_000, 0, 0), vec![(Item::Haste5, 2)]),
                (1_500, Goods::of(12_000, 6_000, 0, 0), vec![(Item::Haste60, 1)]),
                (6_000, Goods::of(30_000, 15_000, 5_000, 300), vec![(Item::Haste480, 1), (Item::Peace8, 1)]),
            ],
            Contest::Works => vec![
                (300, Goods::of(4_000, 4_000, 2_000, 0), vec![(Item::Haste5, 3)]),
                (1_500, Goods::of(10_000, 10_000, 6_000, 0), vec![(Item::Haste60, 2)]),
                (6_000, Goods::of(25_000, 25_000, 15_000, 300), vec![(Item::Haste480, 1), (Item::Peace8, 1)]),
            ],
            Contest::Valour => vec![
                (500, Goods::of(5_000, 5_000, 0, 0), vec![(Item::Haste5, 2)]),
                (3_000, Goods::of(12_000, 12_000, 4_000, 0), vec![(Item::Haste60, 1)]),
                (15_000, Goods::of(30_000, 30_000, 10_000, 400), vec![(Item::Haste480, 1), (Item::Peace8, 1)]),
            ],
        }
    }

    /// What the first three of a round get for their places once it is
    /// over, the first first: its greatest prize's goods three times over,
    /// twice and once, and eight hours' hastes, three, two and one.
    pub fn laurels(self) -> [(Goods, Vec<(Item, u64)>); 3] {
        let greatest = self.prizes()[2].1;
        [
            (greatest.times(3), vec![(Item::Haste480, 3)]),
            (greatest.times(2), vec![(Item::Haste480, 2)]),
            (greatest, vec![(Item::Haste480, 1)]),
        ]
    }
}

/// The highest favour rises.
pub const TOP_FAVOUR: u32 = 10;

/// The favour a player must have earned to stand at a level of it.
pub fn favour_needs(level: u32) -> u64 {
    [0, 50, 150, 350, 700, 1_200, 2_000, 3_200, 5_000, 7_500, 11_000][level.min(TOP_FAVOUR) as usize]
}

/// The level of favour that so much of it earned stands at.
pub fn favour_level(points: u64) -> u32 {
    (0..=TOP_FAVOUR).rev().find(|level| points >= favour_needs(*level)).unwrap_or(0)
}

/// The levels of a study favour lends at a level of it, beside whatever
/// the player's city has learnt, as a title lends them: gathering from the
/// second level and again from the sixth, what the Farm, Sawmill and
/// Quarry bring in from the third and the ninth, marching from the fourth
/// and the eighth, storage from the fifth, shields from the seventh and
/// the tenth.
pub fn favour_lends(level: u32, topic: Topic) -> u32 {
    let level = level.min(TOP_FAVOUR);
    let from = |at: u32| u32::from(level >= at);
    match topic {
        Topic::Gathering => from(2) + from(6),
        Topic::Tillage | Topic::Forestry | Topic::Masonry => from(3) + from(9),
        Topic::Marching => from(4) + from(8),
        Topic::Storage => from(5),
        Topic::Shields => from(7) + from(10),
        _ => 0,
    }
}

/// The favour each of the day's chests adds when it is opened, in their
/// order: seventy a day for one who does all the day's work.
pub fn chest_favour(chest: u8) -> u64 {
    [10, 20, 40].get((chest as usize).wrapping_sub(1)).copied().unwrap_or(0)
}

/// What an Academy studies. Each topic is learnt level by level, and
/// each level adds the same again to what it gives.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Topic {
    Tillage = 1,
    Forestry = 2,
    Masonry = 3,
    Saltcraft = 4,
    Building = 5,
    Storage = 6,
    Gathering = 7,
    Spearcraft = 8,
    Archery = 9,
    Horsemanship = 10,
    Siegecraft = 11,
    Shields = 12,
    Medicine = 13,
    Marching = 14,
    Drill = 15,
}

/// The highest level a topic is learnt to.
pub const TOP_STUDY: u32 = 10;

impl Topic {
    pub const ALL: [Topic; 15] = [
        Topic::Tillage,
        Topic::Forestry,
        Topic::Masonry,
        Topic::Saltcraft,
        Topic::Building,
        Topic::Storage,
        Topic::Gathering,
        Topic::Spearcraft,
        Topic::Archery,
        Topic::Horsemanship,
        Topic::Siegecraft,
        Topic::Shields,
        Topic::Medicine,
        Topic::Marching,
        Topic::Drill,
    ];

    pub fn of(code: u8) -> Option<Topic> {
        Topic::ALL.into_iter().find(|topic| *topic as u8 == code)
    }

    pub fn name(self) -> &'static str {
        match self {
            Topic::Tillage => "Tillage",
            Topic::Forestry => "Forestry",
            Topic::Masonry => "Masonry",
            Topic::Saltcraft => "Saltcraft",
            Topic::Building => "Building",
            Topic::Storage => "Storage",
            Topic::Gathering => "Gathering",
            Topic::Spearcraft => "Spearcraft",
            Topic::Archery => "Archery",
            Topic::Horsemanship => "Horsemanship",
            Topic::Siegecraft => "Siegecraft",
            Topic::Shields => "Shields",
            Topic::Medicine => "Field medicine",
            Topic::Marching => "Marching",
            Topic::Drill => "Drill",
        }
    }

    /// Whether it is of the city's works, or of its armies.
    pub fn is_of_war(self) -> bool {
        self >= Topic::Spearcraft
    }

    /// What each level gives, in hundredths.
    pub fn each(self) -> u64 {
        match self {
            Topic::Tillage | Topic::Forestry | Topic::Masonry | Topic::Saltcraft | Topic::Marching => 5,
            Topic::Storage | Topic::Gathering | Topic::Medicine => 10,
            _ => 3,
        }
    }

    /// What it does, in a player's words.
    pub fn words(self) -> String {
        let each = self.each();
        match self {
            Topic::Tillage => format!("Your Farm brings in {each}% more grain."),
            Topic::Forestry => format!("Your Sawmill brings in {each}% more timber."),
            Topic::Masonry => format!("Your Quarry brings in {each}% more stone."),
            Topic::Saltcraft => format!("Your Saltworks brings in {each}% more moonsalt."),
            Topic::Building => format!("Buildings are raised {each}% sooner."),
            Topic::Storage => format!("Your city holds {each}% more of each good."),
            Topic::Gathering => format!("Your armies gather {each}% faster."),
            Topic::Spearcraft => format!("Your Spearmen strike {each}% harder."),
            Topic::Archery => format!("Your Archers strike {each}% harder."),
            Topic::Horsemanship => format!("Your Riders strike {each}% harder."),
            Topic::Siegecraft => format!("Your Mangonels strike {each}% harder."),
            Topic::Shields => format!("All your soldiers are {each}% harder to bring down."),
            Topic::Medicine => format!("Your city tends {each}% more wounded."),
            Topic::Marching => format!("Your armies march {each}% faster."),
            Topic::Drill => format!("Soldiers are trained {each}% sooner."),
        }
    }

    /// The study that opens this one, and the level it must be learnt to:
    /// none for the first of each tree, Tillage for the city's works and
    /// Drill for its arms.
    pub fn opened_by(self) -> Option<(Topic, u32)> {
        match self {
            Topic::Tillage | Topic::Drill => None,
            Topic::Forestry | Topic::Building => Some((Topic::Tillage, 1)),
            Topic::Masonry => Some((Topic::Forestry, 1)),
            Topic::Saltcraft => Some((Topic::Masonry, 2)),
            Topic::Storage => Some((Topic::Tillage, 2)),
            Topic::Gathering => Some((Topic::Storage, 2)),
            Topic::Spearcraft | Topic::Archery => Some((Topic::Drill, 1)),
            Topic::Horsemanship => Some((Topic::Spearcraft, 2)),
            Topic::Siegecraft => Some((Topic::Archery, 2)),
            Topic::Shields => Some((Topic::Spearcraft, 3)),
            Topic::Medicine => Some((Topic::Drill, 2)),
            Topic::Marching => Some((Topic::Horsemanship, 1)),
        }
    }

    /// The topic that makes a kind of soldier strike harder.
    pub fn sharpens(kind: Troops) -> Topic {
        match kind {
            Troops::Spearmen => Topic::Spearcraft,
            Troops::Archers => Topic::Archery,
            Troops::Riders => Topic::Horsemanship,
            Troops::Mangonels => Topic::Siegecraft,
        }
    }
}

/// What learning a topic's level costs: the city's works are paid for in
/// grain and timber, its arms in timber and stone, and from the fifth
/// level both in moonsalt as well.
pub fn study_cost(topic: Topic, level: u32) -> Goods {
    let level = level.clamp(1, TOP_STUDY) as u64;
    let base = 300 * level * level + 200 * level;
    let moonsalt = if level >= 5 { 30 * level } else { 0 };
    if topic.is_of_war() {
        Goods::of(0, base, base * 2 / 3, moonsalt)
    } else {
        Goods::of(base, base * 2 / 3, 0, moonsalt)
    }
}

/// The seconds learning a topic's level takes, as written: two minutes
/// for the first, a little over three hours for the tenth.
pub fn study_seconds(level: u32) -> i64 {
    let level = level.clamp(1, TOP_STUDY) as i64;
    120 * level * level
}

/// The Academy level a topic's level asks for: its own first level for
/// the first, and two more for each after.
pub fn study_needs(level: u32) -> u32 {
    (2 * level.clamp(1, TOP_STUDY)).saturating_sub(1).min(TOP_LEVEL)
}

/// The way of war a commander has: what they are best at leading.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Way {
    /// Leads spearmen in the front of a fight.
    Vanguard = 1,
    /// Leads archers.
    Fletcher = 2,
    /// Leads riders, and marches fast.
    Outrider = 3,
    /// Leads mangonels, and makes less of a city's Wall.
    Wallbreaker = 4,
    /// Keeps those they lead standing.
    Warden = 5,
    /// Gathers fast and carries much.
    Gleaner = 6,
}

/// The highest level a commander reaches.
pub const TOP_COMMAND: u32 = 30;

/// What a commander adds to the army they lead, in hundredths: how much
/// harder each kind strikes (by the kind's number less one), how much
/// harder all are to bring down, how much faster it marches and gathers,
/// how much more it carries, and how much less a Wall shelters those it
/// attacks; and their skill in a fight, which every fourth round has
/// their army strike so much harder (`surge`) or stand so much harder to
/// bring down (`stand`).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Leading {
    pub strikes: [u64; 4],
    pub shields: u64,
    pub haste: u64,
    pub gathers: u64,
    pub carries: u64,
    pub breaches: u64,
    pub surge: u64,
    pub stand: u64,
    /// Above nought, their army's skill comes every third round of a
    /// fight, not every fourth.
    pub quick: u64,
    /// Hundredths of their army's dead carried home wounded after all.
    pub mercy: u64,
    /// Hundredths harder their army strikes the Unquiet.
    pub bane: u64,
}

impl Way {
    pub const ALL: [Way; 6] = [Way::Vanguard, Way::Fletcher, Way::Outrider, Way::Wallbreaker, Way::Warden, Way::Gleaner];

    pub fn of(code: u8) -> Option<Way> {
        Way::ALL.into_iter().find(|way| *way as u8 == code)
    }

    pub fn name(self) -> &'static str {
        match self {
            Way::Vanguard => "Vanguard",
            Way::Fletcher => "Fletcher",
            Way::Outrider => "Outrider",
            Way::Wallbreaker => "Wallbreaker",
            Way::Warden => "Warden",
            Way::Gleaner => "Gleaner",
        }
    }

    /// What they are best at, in a player's words.
    pub fn words(self) -> &'static str {
        match self {
            Way::Vanguard => "Spearmen they lead strike harder; every fourth round of a fight, their army charges.",
            Way::Fletcher => "Archers they lead strike harder; every fourth round of a fight, their army looses a volley.",
            Way::Outrider => "Riders they lead strike harder, and their army marches faster; every fourth round of a fight, it rides its foe down.",
            Way::Wallbreaker => "Mangonels they lead strike harder, and a Wall shelters its city less from them; every fourth round of a fight, they bombard.",
            Way::Warden => "Everyone they lead is harder to bring down, and every fourth round of a fight harder still.",
            Way::Gleaner => "Their army gathers faster and carries more.",
        }
    }

    /// What a commander of this way adds at a level, 1 to 30: five
    /// hundredths and one more a level for what they are best at, and
    /// about half that for what else they bring.
    pub fn leading(self, level: u32) -> Leading {
        let level = level.clamp(1, TOP_COMMAND) as u64;
        let best = 5 + level;
        let also = 3 + level / 2;
        // Their skill in a fight: a fifth more and two hundredths a level,
        // every fourth round. A gleaner's skill is in gathering.
        let skill = 20 + 2 * level;
        let mut leading = Leading::default();
        match self {
            Way::Warden => leading.stand = skill,
            Way::Gleaner => {}
            _ => leading.surge = skill,
        }
        match self {
            Way::Vanguard => leading.strikes[Troops::Spearmen as usize - 1] = best,
            Way::Fletcher => leading.strikes[Troops::Archers as usize - 1] = best,
            Way::Outrider => {
                leading.strikes[Troops::Riders as usize - 1] = best;
                leading.haste = also;
            }
            Way::Wallbreaker => {
                leading.strikes[Troops::Mangonels as usize - 1] = best;
                leading.breaches = 10 + level;
            }
            Way::Warden => leading.shields = best,
            Way::Gleaner => {
                leading.gathers = 2 * best;
                leading.carries = best;
            }
        }
        leading
    }
}

impl Leading {
    /// Two commanders' additions together.
    pub fn plus(self, other: Leading) -> Leading {
        let mut strikes = self.strikes;
        for (mine, theirs) in strikes.iter_mut().zip(other.strikes) {
            *mine += theirs;
        }
        Leading {
            strikes,
            shields: self.shields + other.shields,
            haste: self.haste + other.haste,
            gathers: self.gathers + other.gathers,
            carries: self.carries + other.carries,
            breaches: self.breaches + other.breaches,
            surge: self.surge + other.surge,
            stand: self.stand + other.stand,
            quick: self.quick + other.quick,
            mercy: self.mercy + other.mercy,
            bane: self.bane + other.bane,
        }
    }

    /// Half of each: what a commander adds who goes out beside another.
    pub fn halved(self) -> Leading {
        Leading {
            strikes: self.strikes.map(|strike| strike / 2),
            shields: self.shields / 2,
            haste: self.haste / 2,
            gathers: self.gathers / 2,
            carries: self.carries / 2,
            breaches: self.breaches / 2,
            surge: self.surge / 2,
            stand: self.stand / 2,
            quick: self.quick / 2,
            mercy: self.mercy / 2,
            bane: self.bane / 2,
        }
    }

    /// So many hundredths of each: a commander's way as their renown
    /// makes it.
    pub fn scaled(self, hundredths: u64) -> Leading {
        let by = |amount: u64| amount * hundredths / 100;
        Leading {
            strikes: self.strikes.map(by),
            shields: by(self.shields),
            haste: by(self.haste),
            gathers: by(self.gathers),
            carries: by(self.carries),
            breaches: by(self.breaches),
            surge: by(self.surge),
            stand: by(self.stand),
            quick: by(self.quick),
            mercy: by(self.mercy),
            bane: by(self.bane),
        }
    }
}

/// How widely a commander is known: most are steady, some famed, a few
/// storied; the better known lead the better for it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Renown {
    Steady = 1,
    Famed = 2,
    Storied = 3,
}

impl Renown {
    pub const ALL: [Renown; 3] = [Renown::Steady, Renown::Famed, Renown::Storied];

    pub fn of(code: u8) -> Option<Renown> {
        Renown::ALL.into_iter().find(|renown| *renown as u8 == code)
    }

    pub fn name(self) -> &'static str {
        match self {
            Renown::Steady => "Steady",
            Renown::Famed => "Famed",
            Renown::Storied => "Storied",
        }
    }

    /// How much of their way a commander of this renown brings, in
    /// hundredths of a steady one's.
    pub fn weight(self) -> u64 {
        match self {
            Renown::Steady => 100,
            Renown::Famed => 110,
            Renown::Storied => 125,
        }
    }

    /// In how many of a hundred the Tavern's next commander is of this
    /// renown.
    pub fn odds(self) -> u64 {
        match self {
            Renown::Steady => 70,
            Renown::Famed => 25,
            Renown::Storied => 5,
        }
    }
}

/// A gift a commander has of their own, beside their way of war.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Gift {
    /// Their army's skill comes every third round of a fight.
    Quick = 1,
    /// Some of their army's dead are carried home wounded after all.
    Mercy = 2,
    /// Their army strikes the Unquiet harder.
    Bane = 3,
    /// Their army marches faster.
    Swift = 4,
    /// Their army carries more home.
    Hoard = 5,
    /// Their army is harder to bring down.
    Bulwark = 6,
}

/// The highest level a gift rises to.
pub const TOP_GIFT: u32 = 5;

/// The sigils a commander drawn again at the Tavern brings to the one a
/// player has.
pub const SIGILS_A_DRAW: u32 = 10;

/// How many free summonses the Tavern gives each day of the realm.
pub const FREE_DRAWS: u8 = 1;

/// The sigils a gift asks to rise from a level to the next: ten, then
/// twice as many each level.
pub fn gift_needs(level: u32) -> u32 {
    10 << (level.clamp(1, TOP_GIFT) - 1)
}

impl Gift {
    pub const ALL: [Gift; 6] = [Gift::Quick, Gift::Mercy, Gift::Bane, Gift::Swift, Gift::Hoard, Gift::Bulwark];

    pub fn of(code: u8) -> Option<Gift> {
        Gift::ALL.into_iter().find(|gift| *gift as u8 == code)
    }

    pub fn name(self) -> &'static str {
        match self {
            Gift::Quick => "Quick",
            Gift::Mercy => "Mercy",
            Gift::Bane => "Bane of the Unquiet",
            Gift::Swift => "Swift",
            Gift::Hoard => "Hoard",
            Gift::Bulwark => "Bulwark",
        }
    }

    /// What the gift adds at a level, 1 to 5: its skill every third round
    /// and two hundredths a level more to it, for a quick commander; so
    /// many hundredths for the rest.
    pub fn leading(self, level: u32) -> Leading {
        let level = level.clamp(1, TOP_GIFT) as u64;
        let mut leading = Leading::default();
        match self {
            Gift::Quick => {
                leading.quick = 1;
                leading.surge = 2 * level;
                leading.stand = 2 * level;
            }
            Gift::Mercy => leading.mercy = 8 + 4 * level,
            Gift::Bane => leading.bane = 6 + 3 * level,
            Gift::Swift => leading.haste = 6 + 3 * level,
            Gift::Hoard => leading.carries = 8 + 4 * level,
            Gift::Bulwark => leading.shields = 4 + 2 * level,
        }
        leading
    }

    /// What the gift does at a level, in a player's words.
    pub fn words(self, level: u32) -> String {
        let at = self.leading(level);
        match self {
            Gift::Quick => format!("Their army's skill comes every third round of a fight, not every fourth, and {} hundredths stronger.", at.surge),
            Gift::Mercy => format!("{} in a hundred of their army's dead are carried home wounded after all.", at.mercy),
            Gift::Bane => format!("Their army strikes the Unquiet {} hundredths harder.", at.bane),
            Gift::Swift => format!("Their army marches {} hundredths faster.", at.haste),
            Gift::Hoard => format!("Their army carries {} hundredths more home.", at.carries),
            Gift::Bulwark => format!("Their army is {} hundredths harder to bring down.", at.shields),
        }
    }
}

/// One of the realm's commanders: who they are, their way of war, how
/// widely they are known, and their gift.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Person {
    pub name: &'static str,
    pub way: Way,
    pub renown: Renown,
    pub gift: Gift,
}

const fn person(name: &'static str, way: Way, renown: Renown, gift: Gift) -> Person {
    Person { name, way, renown, gift }
}

/// The realm's commanders, four of each way: one storied, one famed and
/// two steady. A player has each at most once; their number is their
/// place here, from 1.
pub const PEOPLE: [Person; 24] = [
    person("Hallam Ironsworn", Way::Vanguard, Renown::Storied, Gift::Quick),
    person("Bree of the Ford", Way::Vanguard, Renown::Famed, Gift::Bulwark),
    person("Corran Ash", Way::Vanguard, Renown::Steady, Gift::Mercy),
    person("Dunmore Hale", Way::Vanguard, Renown::Steady, Gift::Swift),
    person("Ysolde Lanternhand", Way::Fletcher, Renown::Storied, Gift::Bane),
    person("Wren Halloway", Way::Fletcher, Renown::Famed, Gift::Quick),
    person("Tamsin Reedy", Way::Fletcher, Renown::Steady, Gift::Hoard),
    person("Pell Marsh", Way::Fletcher, Renown::Steady, Gift::Mercy),
    person("Odric Stormwake", Way::Outrider, Renown::Storied, Gift::Swift),
    person("Sabine Coldwater", Way::Outrider, Renown::Famed, Gift::Quick),
    person("Garet Holt", Way::Outrider, Renown::Steady, Gift::Bane),
    person("Linnet Fell", Way::Outrider, Renown::Steady, Gift::Hoard),
    person("Brannoc the Mason", Way::Wallbreaker, Renown::Storied, Gift::Bulwark),
    person("Ilse Cinder", Way::Wallbreaker, Renown::Famed, Gift::Bane),
    person("Hob Tallow", Way::Wallbreaker, Renown::Steady, Gift::Swift),
    person("Rook Ashby", Way::Wallbreaker, Renown::Steady, Gift::Mercy),
    person("Maren of the Black Glass", Way::Warden, Renown::Storied, Gift::Mercy),
    person("Aldous Thorne", Way::Warden, Renown::Famed, Gift::Bulwark),
    person("Edda Rush", Way::Warden, Renown::Steady, Gift::Quick),
    person("Fenn Lowe", Way::Warden, Renown::Steady, Gift::Bane),
    person("Nan Saltmarsh", Way::Gleaner, Renown::Storied, Gift::Hoard),
    person("Kestrel Vane", Way::Gleaner, Renown::Famed, Gift::Swift),
    person("Mabry Field", Way::Gleaner, Renown::Steady, Gift::Hoard),
    person("Oswin Reed", Way::Gleaner, Renown::Steady, Gift::Mercy),
];

/// One of the realm's commanders by their number, from 1.
pub fn person_of(number: u8) -> Option<Person> {
    (number as usize).checked_sub(1).and_then(|at| PEOPLE.get(at)).copied()
}

/// Something a commander may be trained in, with the points their levels
/// bring.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Talent {
    Spearmen = 1,
    Archers = 2,
    Riders = 3,
    Mangonels = 4,
    Shields = 5,
    Haste = 6,
    Gathering = 7,
    Carrying = 8,
    Breaching = 9,
}

/// The most points a commander may put into one talent.
pub const TALENT_MOST: u32 = 10;

/// What forgetting all a commander's talents costs.
pub const FORGET_COST: Goods = Goods::of(20_000, 20_000, 20_000, 0);

/// The talent points a commander has from their level: one for each past the first.
pub fn talent_points(level: u32) -> u32 {
    level.clamp(1, TOP_COMMAND) - 1
}

impl Talent {
    pub const ALL: [Talent; 9] = [
        Talent::Spearmen,
        Talent::Archers,
        Talent::Riders,
        Talent::Mangonels,
        Talent::Shields,
        Talent::Haste,
        Talent::Gathering,
        Talent::Carrying,
        Talent::Breaching,
    ];

    pub fn of(code: u8) -> Option<Talent> {
        Talent::ALL.into_iter().find(|talent| *talent as u8 == code)
    }

    /// Hundredths each point adds: one to a fight, two to anything else.
    pub fn each(self) -> u64 {
        match self {
            Talent::Spearmen | Talent::Archers | Talent::Riders | Talent::Mangonels | Talent::Shields => 1,
            _ => 2,
        }
    }

    /// What so many points of it add to an army.
    pub fn leading(self, points: u32) -> Leading {
        let amount = self.each() * points.min(TALENT_MOST) as u64;
        let mut leading = Leading::default();
        match self {
            Talent::Spearmen => leading.strikes[Troops::Spearmen as usize - 1] = amount,
            Talent::Archers => leading.strikes[Troops::Archers as usize - 1] = amount,
            Talent::Riders => leading.strikes[Troops::Riders as usize - 1] = amount,
            Talent::Mangonels => leading.strikes[Troops::Mangonels as usize - 1] = amount,
            Talent::Shields => leading.shields = amount,
            Talent::Haste => leading.haste = amount,
            Talent::Gathering => leading.gathers = amount,
            Talent::Carrying => leading.carries = amount,
            Talent::Breaching => leading.breaches = amount,
        }
        leading
    }

    /// What a point of it does, in a player's words.
    pub fn words(self) -> String {
        let each = self.each();
        match self {
            Talent::Spearmen => format!("Spearmen they lead strike {each}% harder."),
            Talent::Archers => format!("Archers they lead strike {each}% harder."),
            Talent::Riders => format!("Riders they lead strike {each}% harder."),
            Talent::Mangonels => format!("Mangonels they lead strike {each}% harder."),
            Talent::Shields => format!("Everyone they lead is {each}% harder to bring down."),
            Talent::Haste => format!("Their army marches {each}% faster."),
            Talent::Gathering => format!("Their army gathers {each}% faster."),
            Talent::Carrying => format!("Their army carries {each}% more."),
            Talent::Breaching => format!("A Wall shelters its city {each}% less from them."),
        }
    }
}

/// What a commander must have seen to rise from a level to the next.
pub fn command_needs(level: u32) -> u64 {
    100 * level.max(1) as u64 * level.max(1) as u64
}

/// How many commanders a city keeps, by its Tavern's level: one without
/// a Tavern, another with one, and one more every five levels after, to
/// six.
pub fn commanders(tavern: u32) -> u32 {
    if tavern == 0 {
        1
    } else {
        (2 + tavern / 5).min(6)
    }
}

/// What taking on a city's next commander costs, by how many it has.
pub fn hire_cost(have: u32) -> Goods {
    let n = have.max(1) as u64;
    Goods::of(2_000 * n * n, 2_000 * n * n, 1_000 * n * n, if n >= 2 { 50 * n } else { 0 })
}

/// Where a commander wears a piece of gear: one piece in each.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Slot {
    Weapon = 1,
    Helm = 2,
    Armour = 3,
    Boots = 4,
}

/// A piece of gear the Forge makes: four kinds, a weapon, a helm, armour
/// and boots, each in three grades.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Piece {
    IronSword = 1,
    SteelSword = 2,
    SilverSword = 3,
    LeatherCap = 4,
    IronHelm = 5,
    SilverHelm = 6,
    LeatherCoat = 7,
    MailCoat = 8,
    SilverMail = 9,
    LeatherBoots = 10,
    RidingBoots = 11,
    SilverGreaves = 12,
}

impl Piece {
    pub const ALL: [Piece; 12] = [
        Piece::IronSword,
        Piece::SteelSword,
        Piece::SilverSword,
        Piece::LeatherCap,
        Piece::IronHelm,
        Piece::SilverHelm,
        Piece::LeatherCoat,
        Piece::MailCoat,
        Piece::SilverMail,
        Piece::LeatherBoots,
        Piece::RidingBoots,
        Piece::SilverGreaves,
    ];

    pub fn of(code: u8) -> Option<Piece> {
        Piece::ALL.into_iter().find(|piece| *piece as u8 == code)
    }

    /// Where it is worn: three grades to each slot, in order.
    pub fn slot(self) -> Slot {
        match (self as u8 - 1) / 3 {
            0 => Slot::Weapon,
            1 => Slot::Helm,
            2 => Slot::Armour,
            _ => Slot::Boots,
        }
    }

    /// Its grade, 1 to 3.
    pub fn grade(self) -> u64 {
        (self as u64 - 1) % 3 + 1
    }

    pub fn name(self) -> &'static str {
        match self {
            Piece::IronSword => "Iron sword",
            Piece::SteelSword => "Steel sword",
            Piece::SilverSword => "Silver sword",
            Piece::LeatherCap => "Leather cap",
            Piece::IronHelm => "Iron helm",
            Piece::SilverHelm => "Silver helm",
            Piece::LeatherCoat => "Leather coat",
            Piece::MailCoat => "Mail coat",
            Piece::SilverMail => "Silver mail",
            Piece::LeatherBoots => "Leather boots",
            Piece::RidingBoots => "Riding boots",
            Piece::SilverGreaves => "Silver greaves",
        }
    }

    /// What it adds to the army its wearer leads: a weapon has every kind
    /// strike harder, a helm and armour have everyone harder to bring
    /// down, boots have the army march faster; more for each grade.
    pub fn leading(self) -> Leading {
        let grade = self.grade();
        let mut leading = Leading::default();
        match self.slot() {
            Slot::Weapon => leading.strikes = [3 * grade; 4],
            Slot::Helm => leading.shields = 2 * grade,
            Slot::Armour => leading.shields = 3 * grade,
            Slot::Boots => leading.haste = 4 * grade,
        }
        leading
    }

    /// What it does, in a player's words.
    pub fn words(self) -> String {
        let grade = self.grade();
        match self.slot() {
            Slot::Weapon => format!("Everyone its wearer leads strikes {}% harder.", 3 * grade),
            Slot::Helm => format!("Everyone its wearer leads is {}% harder to bring down.", 2 * grade),
            Slot::Armour => format!("Everyone its wearer leads is {}% harder to bring down.", 3 * grade),
            Slot::Boots => format!("Its wearer's army marches {}% faster.", 4 * grade),
        }
    }

    /// What it takes to make: so many of each material, iron, leather,
    /// bone and silver, and goods.
    pub fn cost(self) -> ([u64; 4], Goods) {
        match self.grade() {
            1 => ([4, 4, 0, 0], Goods::of(0, 5_000, 5_000, 0)),
            2 => ([10, 6, 4, 0], Goods::of(0, 20_000, 20_000, 200)),
            _ => ([20, 10, 10, 6], Goods::of(0, 60_000, 60_000, 1_000)),
        }
    }

    /// The Forge level it is made at.
    pub fn forge_level(self) -> u32 {
        match self.grade() {
            1 => 1,
            2 => 8,
            _ => 16,
        }
    }
}

/// What clearing a barrow of a level yields of materials: one for each
/// level, iron, leather and bone by chance, and from the tenth level one
/// in four of them silver.
pub fn spoils_of(level: u32, mut chance: impl FnMut() -> u64) -> [u64; 4] {
    let mut yielded = [0u64; 4];
    for _ in 0..level {
        let roll = chance();
        let kind = if level >= 10 && roll % 4 == 0 { 3 } else { (roll / 4 % 3) as usize };
        yielded[kind] += 1;
    }
    yielded
}

/// What the whole realm does together, counted toward its milestones.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Feat {
    /// A city founded.
    Founded = 1,
    /// A barrow of the Unquiet cleared, alone or by a rally.
    Cleared = 2,
    /// An alliance founded.
    Allied = 3,
    /// A cairn of the old folk found by a player's scouts.
    Found = 4,
}

/// The realm's milestones, by number: the feat each counts, how many of it
/// reach it, its words, and what every player may claim once it is reached.
pub fn milestones() -> [(u64, Feat, u64, &'static str, Goods, Item, u64); 6] {
    [
        (1, Feat::Founded, 50, "Fifty cities founded in the realm.", Goods::of(20_000, 20_000, 20_000, 0), Item::Haste60, 1),
        (2, Feat::Allied, 10, "Ten alliances founded.", Goods::of(20_000, 20_000, 20_000, 0), Item::Haste60, 2),
        (3, Feat::Cleared, 100, "A hundred barrows of the Unquiet cleared.", Goods::of(30_000, 30_000, 30_000, 0), Item::Tome, 1),
        (4, Feat::Found, 100, "A hundred cairns of the old folk found.", Goods::of(30_000, 30_000, 30_000, 0), Item::Summons, 1),
        (5, Feat::Founded, 200, "Two hundred cities founded in the realm.", Goods::of(50_000, 50_000, 50_000, 0), Item::Haste60, 3),
        (6, Feat::Cleared, 1_000, "A thousand barrows of the Unquiet cleared.", Goods::of(100_000, 100_000, 100_000, 0), Item::Haste480, 1),
    ]
}

/// How many days in a row the day's welcome grows over, then begins again.
pub const WELCOME_DAYS: u64 = 7;

/// What the day's welcome gives on a day of so many in a row (1 to
/// `WELCOME_DAYS`): more goods each day, and on the last an hour's haste.
pub fn welcome(streak: u64) -> (Goods, Option<(Item, u64)>) {
    let day = streak.clamp(1, WELCOME_DAYS);
    let goods = Goods::of(1_000 * day, 1_000 * day, 500 * day, 0);
    (goods, (day == WELCOME_DAYS).then_some((Item::Haste60, 1)))
}

/// How many stages the Barrow Road has.
pub const ROAD_STAGES: u64 = 30;

/// How long a player's soldiers rest after walking the Barrow Road before
/// they may walk it again, as written.
pub const ROAD_REST: i64 = 60;

/// The host of the Unquiet met at a stage of the Barrow Road (1 to
/// `ROAD_STAGES`), and the most soldiers a player may bring against it:
/// as many as it has. Each host leans on one kind, in turn riders,
/// spearmen and archers, so the soldiers that best it change from stage
/// to stage; every sixth stage its tier rises.
pub fn road_host(stage: u64) -> (Vec<Unit>, u64) {
    let stage = stage.clamp(1, ROAD_STAGES);
    let tier = (1 + (stage - 1) / 6) as u32;
    let heads = 30 * stage + 6 * stage * stage;
    let (most, rest) = match stage % 3 {
        1 => (Troops::Riders, Troops::Spearmen),
        2 => (Troops::Spearmen, Troops::Archers),
        _ => (Troops::Archers, Troops::Riders),
    };
    let leaning = heads * 60 / 100;
    (vec![Unit { kind: most, tier, count: leaning }, Unit { kind: rest, tier, count: heads - leaning }], heads)
}

/// What clearing a stage of the Barrow Road the first time gives: goods
/// that grow with the stage, moonsalt from the tenth, and on every fifth
/// an item besides.
pub fn road_gives(stage: u64) -> (Goods, Option<(Item, u64)>) {
    let stage = stage.clamp(1, ROAD_STAGES);
    let goods = Goods::of(1_200 * stage, 1_200 * stage, 500 * stage, if stage >= 10 { 40 * stage } else { 0 });
    let item = match stage {
        5 => Some((Item::Haste60, 2)),
        10 => Some((Item::Tome, 3)),
        15 => Some((Item::Haste480, 1)),
        20 => Some((Item::GreatTome, 1)),
        25 => Some((Item::Summons, 1)),
        30 => Some((Item::Summons, 2)),
        _ => None,
    };
    (goods, item)
}

/// How many challenges a player makes in the Lists each day of the realm.
pub const LISTS_TRIES: u64 = 5;

/// How many places above their own a player may challenge in the Lists.
pub const LISTS_REACH: u64 = 10;

/// The most soldiers a player's band in the Lists holds, by their Keep's
/// level.
pub fn lists_most(keep: u32) -> u64 {
    200 * keep.max(1) as u64
}

/// What the Lists' purse gives each day of the realm, by place: the first
/// and last place of each part of the standing, and the goods and honour
/// it gives.
pub fn lists_purses() -> [(u64, u64, Goods, u64); 5] {
    [
        (1, 1, Goods::of(30_000, 30_000, 30_000, 0), 300),
        (2, 3, Goods::of(20_000, 20_000, 20_000, 0), 200),
        (4, 10, Goods::of(12_000, 12_000, 12_000, 0), 120),
        (11, 50, Goods::of(6_000, 6_000, 6_000, 0), 60),
        (51, u64::MAX, Goods::of(2_000, 2_000, 2_000, 0), 20),
    ]
}

/// The purse of a place in the Lists.
pub fn lists_purse(place: u64) -> (Goods, u64) {
    let purses = lists_purses();
    let (_, _, goods, honour) = purses.iter().copied().find(|(first, last, _, _)| (*first..=*last).contains(&place)).unwrap_or(purses[4]);
    (goods, honour)
}
