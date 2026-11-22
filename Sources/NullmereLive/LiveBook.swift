import Foundation

/// The player's city as a screen lists it: each building with what its
/// next level costs and why it can't be raised yet, the troops and what
/// can be trained, the armies out and what each is doing. Everything
/// here is read from the realm's rows; nothing is decided. Where the
/// realm would refuse, the reason is given in the words the realm itself
/// would use (`LiveBookTests` holds them to the module's source), so a
/// player sees it before they ask.

/// Numbers and lengths of time as the realm words them.
public enum LiveWords {
    /// A number with its thousands set apart: 12,500.
    public static func grouped(_ number: UInt64) -> String {
        let digits = Array(String(number))
        var out = ""
        for (index, digit) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { out.append(",") }
            out.append(digit)
        }
        return out
    }

    /// A place in a ranking as a player reads it: "1st", "12th", "23rd".
    public static func ordinal(_ number: Int) -> String {
        let teen = (11...13).contains(number % 100)
        let suffix = teen ? "th" : (number % 10 == 1 ? "st" : number % 10 == 2 ? "nd" : number % 10 == 3 ? "rd" : "th")
        return "\(number)\(suffix)"
    }

    /// A length of time as a player reads it: "45 seconds", "3 hours 20 minutes".
    public static func spoken(_ seconds: Int) -> String {
        let seconds = max(seconds, 0)
        func unit(_ count: Int, _ name: String) -> String { "\(count) \(name)\(count == 1 ? "" : "s")" }
        let (days, hours, minutes, rest) = (seconds / 86_400, seconds % 86_400 / 3_600, seconds % 3_600 / 60, seconds % 60)
        if days > 0 { return hours > 0 ? "\(unit(days, "day")) \(unit(hours, "hour"))" : unit(days, "day") }
        if hours > 0 { return minutes > 0 ? "\(unit(hours, "hour")) \(unit(minutes, "minute"))" : unit(hours, "hour") }
        if minutes > 0 { return rest > 0 ? "\(unit(minutes, "minute")) \(unit(rest, "second"))" : unit(minutes, "minute") }
        return unit(rest, "second")
    }

    /// How long ago something was, in its largest unit alone, as a list
    /// beside its buttons has room for: "Just now", "45 seconds ago",
    /// "1 minute ago", "3 hours ago", "2 days ago".
    public static func ago(_ seconds: Int) -> String {
        let seconds = max(seconds, 0)
        func unit(_ count: Int, _ name: String) -> String { "\(count) \(name)\(count == 1 ? "" : "s") ago" }
        if seconds >= 86_400 { return unit(seconds / 86_400, "day") }
        if seconds >= 3_600 { return unit(seconds / 3_600, "hour") }
        if seconds >= 60 { return unit(seconds / 60, "minute") }
        return seconds < 5 ? "Just now" : unit(seconds, "second")
    }

    /// A length of time as a clock counts it down: 0:45, 3:20:05, 2d 4h.
    public static func clock(_ seconds: Int) -> String {
        let seconds = max(seconds, 0)
        let (days, hours, minutes, rest) = (seconds / 86_400, seconds % 86_400 / 3_600, seconds % 3_600 / 60, seconds % 60)
        func two(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours):\(two(minutes)):\(two(rest))" }
        return "\(minutes):\(two(rest))"
    }

    /// The goods' names, in the order the realm keeps them.
    public static let goods = ["grain", "timber", "stone", "moonsalt"]
}

extension LiveGoods {
    /// These goods in words: "620 timber and 310 stone".
    public var words: String {
        let named = zip(parts, LiveWords.goods).filter { $0.0 > 0 }.map { "\(LiveWords.grouped($0.0)) \($0.1)" }
        switch named.count {
        case 0: return "nothing"
        case 1: return named[0]
        default: return named.dropLast().joined(separator: ", ") + " and " + named[named.count - 1]
        }
    }

    /// The same to begin a line with: "620 timber and 310 stone", "Nothing".
    public var sentence: String {
        let words = self.words
        return words.prefix(1).uppercased() + String(words.dropFirst())
    }

    /// What of a cost these goods fall short by.
    public func short(of cost: LiveGoods) -> LiveGoods {
        let lacking = zip(parts, cost.parts).map { $1 > $0 ? $1 - $0 : 0 }
        return LiveGoods(grain: lacking[0], timber: lacking[1], stone: lacking[2], moonsalt: lacking[3])
    }
}

/// Why the realm would not do something yet.
public enum LiveBlock: Equatable, Sendable {
    case needsKeep(Int)
    case needsOther(String, Int)
    case rising(String)
    case training(String)
    case alreadyTraining(String)
    case buildersBusy
    case short(LiveGoods)
    case top(String)
    case studying
    case learntAll(String)
    case commandersFull
    /// A study opens once another is learnt to a level.
    case studyFirst(String, Int)
    /// Too few of the materials a piece of gear takes, in words.
    case materials(String)

    /// As the realm says it.
    public var words: String {
        switch self {
        case .needsKeep(let level): return "Raise your Keep to level \(level) first."
        case .needsOther(let name, let level): return "Raise your \(name) to level \(level) first."
        case .rising(let name): return "Your \(name) is already being built."
        case .training(let name): return "Your \(name) is training troops. Wait for them to finish."
        case .alreadyTraining(let name): return "Your \(name) is already training troops."
        case .buildersBusy: return "Your builders are busy. Wait for them to finish."
        case .short(let goods): return "You need \(goods.words) more."
        case .top(let name): return "Your \(name) is at its highest level."
        case .studying: return "Your Academy is already at its studies. Wait for them to finish."
        case .learntAll(let name): return "You have learnt all there is of \(name)."
        case .commandersFull: return "Your city keeps as many commanders as it can."
        case .studyFirst(let name, let level): return "Learn \(name) to level \(level) first."
        case .materials(let words): return "You need \(words) more."
        }
    }
}

/// One building of the catalogue as the player's city has it, or could.
public struct LiveBuildingLine: Equatable, Identifiable, Sendable {
    public let kind: Int
    public var id: Int { kind }
    public let name: String
    /// The city's own, if it has one; its level, 0 where it has none or
    /// it is first being raised.
    public let building: LiveBuilding?
    public let level: Int
    /// The work raising it now.
    public let job: LiveJob?
    /// What its next level costs and gives: its first where the city has
    /// none; nil at its highest.
    public let next: LiveBlueprint?
    public let current: LiveBlueprint?
    /// Why it can't be built or raised now; nil where it can be asked.
    public let block: LiveBlock?
    /// Shortage in stored goods, even when another prerequisite comes first.
    public let missing: LiveGoods

    public var shortageWords: String? {
        missing.isNone ? nil : LiveBlock.short(missing).words
    }

    /// The gains from the catalogue for finishing the next level.
    public var completionWords: String? {
        guard let next, level == 0 || current != nil else { return nil }
        let hourly = (current?.hourly ?? LiveGoods()).short(of: next.hourly)
        let power = current?.power ?? 0
        var gains: [String] = []
        if next.power > power { gains.append("+\(LiveWords.grouped(next.power - power)) city power") }
        if !hourly.isNone { gains.append("+\(hourly.words) per hour") }
        return gains.isEmpty ? nil : "On completion: " + gains.joined(separator: ", ")
    }
}

/// The soldiers of one kind and tier a city has, wherever they are.
public struct LiveTroopLine: Equatable, Identifiable, Sendable {
    public let kind: Int
    public let tier: Int
    public var id: Int { kind << 8 | tier }
    public let name: String
    public let ready: UInt64
    public let wounded: UInt64
    /// Out of the city in its armies.
    public let out: UInt64
}

/// Soldiers ready in the city that a training building could raise to a
/// higher tier: so many, what each costs beyond what the lower tier did,
/// and why none can be raised now, where none can.
public struct LivePromotion: Equatable, Sendable {
    public let from: Int
    public let to: Int
    public let count: UInt64
    public let each: LiveGoods
    public let block: LiveBlock?
}

/// What one of the city's training buildings can train.
public struct LiveTrainLine: Equatable, Identifiable, Sendable {
    public struct Tier: Equatable, Sendable {
        public let tier: Int
        public let soldier: LiveSoldier
        /// Why this tier can't be trained now; nil where it can be asked.
        public let block: LiveBlock?
    }

    public let building: LiveBuilding
    public var id: UInt64 { building.id }
    public let name: String
    /// The kind of troops it trains.
    public let kind: Int
    public let tiers: [Tier]
    /// The most it takes in one batch.
    public let most: UInt64
    /// The batch in training now.
    public let job: LiveJob?
}

/// One of the player's armies out of the city, as a list tells it.
public struct LiveMarchLine: Equatable, Identifiable, Sendable {
    public let march: LiveMarch
    public var id: UInt64 { march.id }
    /// What it is doing, in plain words.
    public let doing: String
    public let soldiers: UInt64
    /// What it is doing, with how many soldiers go with it; carts have none.
    public var withSoldiers: String { march.kind == LiveMarch.carts ? doing : "\(doing), \(LiveWords.grouped(soldiers)) soldiers" }
    public let wounded: UInt64
    public let carrying: LiveGoods
    /// Whether it can be called home now.
    public let canRecall: Bool
}

extension LiveWorld {
    /// The highest level anything reaches, and the most soldiers a
    /// training building takes at a level, as the module's catalogue has
    /// them.
    public static let topLevel = 25
    /// The energy an attack on a barrow takes, as the module's catalogue has it.
    public static let energyAnAttack = 50
    public static func batch(level: Int) -> UInt64 { UInt64(10 + 40 * min(max(level, 0), topLevel)) }

    /// How many buildings the city is raising now.
    private var raising: Int { jobs.filter { $0.kind == LiveJob.raise }.count }

    /// Every building of the catalogue: those the city has first, each
    /// group by kind.
    public func buildingLines(at seconds: Double) -> [LiveBuildingLine] {
        guard let city else { return [] }
        let have = stock?.goods(at: seconds) ?? LiveGoods()
        let busy = raising >= city.builders
        let lines = (1...64).compactMap { kind -> LiveBuildingLine? in
            guard let first = blueprint(kind, level: 1) else { return nil }
            guard let building = building(kind) else {
                var block: LiveBlock?
                if city.keep < first.opensAt {
                    block = .needsKeep(first.opensAt)
                } else if busy {
                    block = .buildersBusy
                } else if !have.covers(first.cost) {
                    block = .short(have.short(of: first.cost))
                }
                return LiveBuildingLine(kind: kind, name: first.name, building: nil, level: 0, job: nil, next: first, current: nil, block: block, missing: have.short(of: first.cost))
            }
            let job = jobs.first { $0.kind == LiveJob.raise && $0.subject == building.id }
            let next = blueprint(kind, level: building.level + 1)
            var block: LiveBlock?
            if building.level == 0 || job != nil {
                block = .rising(first.name)
            } else if building.level >= LiveWorld.topLevel {
                block = .top(first.name)
            } else if kind != 1, building.level + 1 > city.keep {
                block = .needsKeep(building.level + 1)
            } else if let next, next.needsBuilding != 0, (self.building(next.needsBuilding)?.level ?? 0) < next.needsLevel {
                block = .needsOther(blueprint(next.needsBuilding, level: 1)?.name ?? "other building", next.needsLevel)
            } else if jobs.contains(where: { $0.kind == LiveJob.train && $0.subject == building.id }) {
                block = .training(first.name)
            } else if busy {
                block = .buildersBusy
            } else if let next, !have.covers(next.cost) {
                block = .short(have.short(of: next.cost))
            }
            return LiveBuildingLine(kind: kind, name: first.name, building: building, level: building.level, job: job, next: next,
                                    current: blueprint(kind, level: building.level), block: block,
                                    missing: next.map { have.short(of: $0.cost) } ?? LiveGoods())
        }
        return lines.filter { $0.building != nil } + lines.filter { $0.building == nil }
    }

    /// The city's soldiers, kind by kind and tier by tier: ready, wounded,
    /// and out in its armies.
    public func troopLines() -> [LiveTroopLine] {
        var counts: [Int: (ready: UInt64, wounded: UInt64, out: UInt64)] = [:]
        for troop in troops { counts[troop.kind << 8 | troop.tier, default: (0, 0, 0)].ready += troop.ready }
        for troop in troops { counts[troop.kind << 8 | troop.tier, default: (0, 0, 0)].wounded += troop.wounded }
        for squad in squads { counts[squad.kind << 8 | squad.tier, default: (0, 0, 0)].out += squad.count }
        return counts.keys.sorted().map { key in
            let (kind, tier) = (key >> 8, key & 0xFF)
            let count = counts[key] ?? (0, 0, 0)
            return LiveTroopLine(kind: kind, tier: tier, name: soldier(kind, tier: tier)?.name ?? "Troops", ready: count.ready,
                                 wounded: count.wounded, out: count.out)
        }
    }

    /// What each of the city's training buildings can train, tier by tier.
    public func trainLines(at seconds: Double) -> [LiveTrainLine] {
        let have = stock?.goods(at: seconds) ?? LiveGoods()
        return buildings.compactMap { building -> LiveTrainLine? in
            let kinds = (1...16).filter { soldier($0, tier: 1)?.building == building.kind }
            guard let kind = kinds.first, let name = blueprint(building.kind, level: 1)?.name else { return nil }
            let rising = building.level == 0 || jobs.contains { $0.kind == LiveJob.raise && $0.subject == building.id }
            let job = jobs.first { $0.kind == LiveJob.train && $0.subject == building.id }
            let tiers = (1...8).compactMap { tier -> LiveTrainLine.Tier? in
                guard let soldier = soldier(kind, tier: tier) else { return nil }
                var block: LiveBlock?
                if rising {
                    block = .rising(name)
                } else if job != nil {
                    block = .alreadyTraining(name)
                } else if building.level < soldier.needsLevel {
                    block = .needsOther(name, soldier.needsLevel)
                } else if !have.covers(soldier.cost) {
                    block = .short(have.short(of: soldier.cost))
                }
                return LiveTrainLine.Tier(tier: tier, soldier: soldier, block: block)
            }
            return LiveTrainLine(building: building, name: name, kind: kind, tiers: tiers, most: LiveWorld.batch(level: building.level), job: job)
        }
    }

    /// How many of a tier a training building could train now: as many as
    /// a batch holds and the stock pays for.
    public func mostTrainable(_ line: LiveTrainLine, tier: Int, at seconds: Double) -> UInt64 {
        guard let soldier = soldier(line.kind, tier: tier) else { return 0 }
        let have = stock?.goods(at: seconds) ?? LiveGoods()
        let each: [UInt64] = zip(have.parts, soldier.cost.parts).filter { $0.1 > 0 }.map { $0.0 / $0.1 }
        return min(line.most, each.min() ?? line.most)
    }

    /// What a training building could raise to a higher tier now: the
    /// soldiers of the lowest tier that stand ready below the highest it
    /// trains, raised to that highest, as many as a batch holds, stand
    /// ready and the stock pays for. Nil where it trains nothing higher
    /// than all that stand ready, or is busy.
    public func promotion(_ line: LiveTrainLine, at seconds: Double) -> LivePromotion? {
        let rising = line.building.level == 0 || jobs.contains { $0.kind == LiveJob.raise && $0.subject == line.building.id }
        guard line.job == nil, !rising, let top = line.tiers.last(where: { $0.soldier.needsLevel <= line.building.level }) else { return nil }
        let lowest = troops.filter { $0.kind == line.kind && $0.tier < top.tier && $0.ready > 0 }.min { $0.tier < $1.tier }
        guard let from = lowest, let lower = soldier(line.kind, tier: from.tier) else { return nil }
        let each = lower.cost.short(of: top.soldier.cost)
        let have = stock?.goods(at: seconds) ?? LiveGoods()
        let afford: [UInt64] = zip(have.parts, each.parts).filter { $0.1 > 0 }.map { $0.0 / $0.1 }
        let count = min(line.most, from.ready, afford.min() ?? line.most)
        return LivePromotion(from: from.tier, to: top.tier, count: count, each: each, block: count > 0 ? nil : .short(have.short(of: each)))
    }

    /// The player's armies out of the city, and what each is doing.
    public func marchLines() -> [LiveMarchLine] {
        myMarches.map { march in
            let own = squads.filter { $0.march == march.id }
            let haul = hauls.first { $0.march == march.id }?.goods ?? LiveGoods()
            let good = sites[march.target].flatMap { LiveWords.goods.indices.contains($0.kind - 1) ? LiveWords.goods[$0.kind - 1] : nil }
            let level = barrows[march.target]?.level
            let doing: String
            switch (march.kind, march.state) {
            case (LiveMarch.gather, LiveMarch.going): doing = good.map { "On its way to gather \($0)" } ?? "On its way to gather"
            case (LiveMarch.gather, LiveMarch.working): doing = good.map { "Gathering \($0)" } ?? "Gathering"
            case (LiveMarch.hunt, LiveMarch.going): doing = level.map { "On its way to a level \($0) barrow" } ?? "On its way to a barrow"
            case (LiveMarch.hunt, LiveMarch.fighting): doing = level.map { "Fighting at a level \($0) barrow" } ?? "Fighting at a barrow"
            case (LiveMarch.attack, LiveMarch.going): doing = "On its way to \(cities[march.target].map { "\($0.name)'s city" } ?? "a city")"
            case (LiveMarch.attack, LiveMarch.fighting): doing = "Attacking \(cities[march.target].map { "\($0.name)'s city" } ?? "a city")"
            case (LiveMarch.explore, LiveMarch.going): doing = cairns[march.target].map { "Scouting a level \($0.level) cairn" } ?? "Scouting a cairn"
            case (LiveMarch.raid, LiveMarch.going): doing = good.map { "On its way to fall on the army gathering \($0)" } ?? "On its way to fall on an army gathering"
            case (LiveMarch.carts, _):
                let to = cities[march.target].map { "\($0.name)'s city" } ?? "an ally's city"
                doing = haul.isNone ? "Carts on their way to \(to)" : "Carts on their way to \(to) with \(haul.words)"
            default: doing = haul.isNone ? "Coming home" : "Coming home with \(haul.words)"
            }
            return LiveMarchLine(march: march, doing: doing, soldiers: march.soldiers, wounded: own.reduce(0) { $0 + $1.wounded }, carrying: haul,
                                 canRecall: march.kind != LiveMarch.carts && (march.state == LiveMarch.going || march.state == LiveMarch.working))
        }
    }

    /// How many armies the city may have out at once, by its Keep's
    /// level, as the module's catalogue has it.
    public static func marches(keep: Int) -> Int {
        switch keep {
        case ...4: return 1
        case 5...10: return 2
        case 11...16: return 3
        case 17...21: return 4
        default: return 5
        }
    }

    /// How many more wounded the city can take in: what it tends by its
    /// Hospital's level, less those lying there and those its armies
    /// carry home, as the module reckons it.
    public var roomForWounded: UInt64 {
        let level = UInt64(min(building(11)?.level ?? 0, LiveWorld.topLevel))
        let tends = 50 + 150 * level + 10 * level * level
        let held = troops.reduce(0) { $0 + $1.wounded } + squads.reduce(0) { $0 + $1.wounded }
        return tends > held ? tends - held : 0
    }
}

/// One of the Academy's topics as the player's city has it.
public struct LiveStudyLine: Equatable, Identifiable, Sendable {
    public let topic: Int
    public var id: Int { topic }
    public let name: String
    /// What it does, and what the city has of it so far: "Your Farm
    /// brings in 5% more grain.", "15% so far".
    public let words: String
    public let level: Int
    /// The study learning it now.
    public let job: LiveJob?
    /// What its next level costs; nil when all of it is learnt.
    public let next: LiveStudy?
    /// Why it can't be studied now; nil where it can be asked.
    public let block: LiveBlock?

    /// What the city has of it so far, in words.
    public var soFar: String {
        guard let each = next?.each ?? last?.each, level > 0 else { return "Not yet learnt" }
        return "Level \(level): \(each * level)% so far"
    }

    /// The level learnt last, where none is left to learn.
    let last: LiveStudy?
}

extension LiveWorld {
    /// The highest level a topic is learnt to, as the module's catalogue has it.
    public static let topStudy = 10

    /// Every topic of the Academy: what the city has learnt of it, what
    /// its next level costs, and why it can't be studied now.
    public func studyLines(at seconds: Double) -> [LiveStudyLine] {
        let have = stock?.goods(at: seconds) ?? LiveGoods()
        let academy = building(14)
        let rising = academy.map { building in building.level == 0 || jobs.contains { $0.kind == LiveJob.raise && $0.subject == building.id } } ?? false
        let studying = jobs.first { $0.kind == LiveJob.study }
        return (1...64).compactMap { topic -> LiveStudyLine? in
            guard let first = study(topic, level: 1) else { return nil }
            let level = lore[topic] ?? 0
            let next = study(topic, level: level + 1)
            var block: LiveBlock?
            if academy == nil {
                block = .needsOther("Academy", 1)
            } else if level >= LiveWorld.topStudy || next == nil {
                // Learnt as far as it goes, whatever the Academy is about now.
                block = .learntAll(first.name)
            } else if rising {
                block = .rising("Academy")
            } else if studying != nil {
                block = .studying
            } else if let next, (academy?.level ?? 0) < next.needsLevel {
                block = .needsOther("Academy", next.needsLevel)
            } else if let next, next.afterTopic > 0, (lore[next.afterTopic] ?? 0) < next.afterLevel {
                block = .studyFirst(study(next.afterTopic, level: 1)?.name ?? "another study", next.afterLevel)
            } else if let next, !have.covers(next.cost) {
                block = .short(have.short(of: next.cost))
            }
            let job = studying.flatMap { Int($0.subject) == topic ? $0 : nil }
            return LiveStudyLine(topic: topic, name: first.name, words: first.words, level: level, job: job, next: next, block: block,
                                 last: study(topic, level: level))
        }
    }
}

/// An alliance as a list offers it to the player.
public struct LiveAllianceLine: Equatable, Identifiable, Sendable {
    public let alliance: LiveAlliance
    public var id: UInt64 { alliance.id }
    /// What the player can do about it: "Join", "Ask to join", or nothing
    /// where it is their own or they have asked already.
    public let offer: String?
    /// Where they stand with it, where there is something to say:
    /// "Your alliance", "You have asked to join".
    public let standing: String?
    /// Why the offer can't be taken up now; nil where it can.
    public let why: String?
}

/// One thing said, as a list shows it.
public struct LiveChatLine: Equatable, Identifiable, Sendable {
    public let id: UInt64
    public let name: String
    public let words: String
    /// Whether the player said it themselves.
    public let own: Bool
    /// Whether the realm's owner took its words away.
    public let takenAway: Bool

    /// What a line taken away shows in place of its words.
    public static let takenAwayWords = "Taken away by the realm's owner."

    /// Whether the player may report it: another's, and still standing.
    public var reportable: Bool { !own && !takenAway }
}

extension LiveWorld {
    /// The most members an alliance has, the longest thing that can be
    /// said, and the letters an alliance's name may have, as the module
    /// has them.
    public static let allianceMost = 100
    public static let saidLongest = 200
    public static let allianceName = 3...20

    /// Every alliance, the player's own first, then the largest.
    public func allianceLines() -> [LiveAllianceLine] {
        let mine = myMembership?.alliance
        let asked = mine == nil ? applicants.first { $0.player == me?.id }?.alliance : nil
        return alliances.values.sorted { a, b in
            if (a.id == mine) != (b.id == mine) { return a.id == mine }
            return (b.members, a.id) < (a.members, b.id)
        }.map { alliance in
            if alliance.id == mine {
                return LiveAllianceLine(alliance: alliance, offer: nil, standing: "Your alliance", why: nil)
            }
            if alliance.id == asked {
                return LiveAllianceLine(alliance: alliance, offer: nil, standing: "You have asked to join", why: nil)
            }
            var why: String?
            if mine != nil {
                why = "You are in an alliance already. Leave it first."
            } else if alliance.members >= LiveWorld.allianceMost {
                why = "That alliance is full."
            }
            return LiveAllianceLine(alliance: alliance, offer: alliance.open ? "Join" : "Ask to join", standing: nil, why: why)
        }
    }

    /// Why the player can't found an alliance now; nil where they can.
    public var foundingBlock: String? {
        if myMembership != nil { return "You are in an alliance already. Leave it first." }
        if (building(15)?.level ?? 0) < 1 { return "Raise your Embassy to level 1 first." }
        return nil
    }

    /// Whether an alliance's name and tag are of a shape the realm takes:
    /// the realm has the last word, on these and on whether they are
    /// taken.
    public static func allianceNameFits(_ name: String) -> Bool {
        let tidy = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let allowed = tidy.allSatisfy { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" || $0 == "'" }
        let ends = (tidy.first.map { $0.isLetter || $0.isNumber } ?? false) && (tidy.last.map { $0.isLetter || $0.isNumber } ?? false)
        return allianceName.contains(tidy.count) && allowed && ends
    }

    public static func tagFits(_ tag: String) -> Bool {
        let tidy = tag.trimmingCharacters(in: .whitespaces)
        return (3...4).contains(tidy.count) && tidy.allSatisfy { $0.isLetter || $0.isNumber }
    }

    /// Whether something can be said as it stands: not nothing, and not
    /// too long.
    public static func sayingFits(_ words: String) -> Bool {
        let tidy = words.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return !tidy.isEmpty && tidy.count <= saidLongest
    }

    /// What has been said, the oldest first: in the realm, or within the
    /// player's alliance.
    public func chatLines(withinAlliance: Bool) -> [LiveChatLine] {
        (withinAlliance ? allianceChat : realmChat).map { said in
            LiveChatLine(id: said.id, name: said.name, words: said.words.isEmpty ? LiveChatLine.takenAwayWords : said.words,
                         own: said.player == me?.id, takenAway: said.words.isEmpty)
        }
    }

    /// Whether the player may let applicants in, put members out and the
    /// like: an officer of their alliance, or its leader.
    public var isOfficer: Bool { (myMembership?.rank ?? 0) >= LiveMember.officer }
    public var isLeader: Bool { myMembership?.rank == LiveMember.leader }
}

extension LiveWorld {
    /// What a building does, in a few plain words, by its number in the
    /// module's catalogue, as the realm's rules have it; nil for a number
    /// the catalogue has not.
    public static func buildingWords(_ kind: Int) -> String? {
        switch kind {
        case 1: return "The city's heart: no other building rises past its level."
        case 2: return "Brings in grain."
        case 3: return "Brings in timber."
        case 4: return "Brings in stone."
        case 5: return "Brings in moonsalt."
        case 6: return "Holds the city's goods, and keeps some of each safe from plunder."
        case 7: return "Trains spearmen."
        case 8: return "Trains archers."
        case 9: return "Trains riders."
        case 10: return "Builds mangonels."
        case 11: return "Tends the city's wounded, to be healed rather than lost."
        case 12: return "Shelters the city's defenders when it is stormed."
        case 13: return "Its archers loose with the city's defenders when it is stormed."
        case 14: return "Studies what makes the city stronger, one topic at a time."
        case 15: return "Opens the city to alliances, and draws more of their help."
        case 16: return "Takes on commanders to lead the city's armies."
        case 17: return "Its carters lose less on the road of what is sent to allies."
        case 18: return "Sends scouts to see other cities and to explore cairns."
        case 19: return "Makes commanders' gear from what the barrows yield."
        default: return nil
        }
    }
}
