import Foundation

// What the screens list of the realm's depth, reckoned from the rows as
// the realm reckons it: the day's deeds and chests, a commander's
// talents, the alliance's learning, and its rallies and askings for help
// in words.

/// One of the day's deeds: how much of it the player has done today, how
/// much it asks, and the marks it gives once done.
public struct LiveDeedLine: Equatable, Identifiable, Sendable {
    public let id: Int
    public let words: String
    public let done: UInt64
    public let asks: UInt64
    public let marks: Int

    public var isDone: Bool { done >= asks }
    public var progress: Double { asks == 0 ? 1 : min(Double(done) / Double(asks), 1) }
}

/// A chest of the day's work: the marks it opens at, what it holds, and
/// whether it is opened today or may be now.
public struct LiveChestLine: Equatable, Identifiable, Sendable {
    public let id: Int
    public let marks: Int
    public let holds: String
    public let opened: Bool
    public let ready: Bool
}

/// One of a commander's talents: the points in it, and whether another
/// may go into it now.
public struct LiveTalentLine: Equatable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let points: Int
    public let canLearn: Bool
}

/// A topic the player's alliance learns: its level, what is given toward
/// the next and what that costs (none at the top), and till when it is
/// studied, if it is.
public struct LiveLearningLine: Equatable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let level: Int
    public let given: LiveGoods
    public let cost: LiveGoods?
    public let risesAt: Int
}

extension LiveWorld {
    /// The day of the realm it is at a moment, counted from its opening at
    /// its pace.
    public func today(at seconds: Double) -> UInt64 {
        guard let realm else { return 0 }
        let long = max(86_400 / max(realm.pace, 1), 1)
        return UInt64(max(Int(seconds) - realm.opened, 0) / long)
    }

    /// What the player has done today: nothing where what is kept is of an
    /// earlier day.
    public func doneToday(at seconds: Double) -> LiveDaily? {
        guard let daily, daily.day == today(at: seconds) else { return nil }
        return daily
    }

    /// The day's deeds, each with what the player has done of it today.
    public func deedLines(at seconds: Double) -> [LiveDeedLine] {
        let row = doneToday(at: seconds)
        return duties.map { LiveDeedLine(id: $0.deed, words: $0.words, done: row?.did($0.deed) ?? 0, asks: $0.asks, marks: $0.marks) }
    }

    /// The marks the player has today: each deed done gives its own.
    public func marksToday(at seconds: Double) -> Int {
        deedLines(at: seconds).filter(\.isDone).reduce(0) { $0 + $1.marks }
    }

    /// The day's chests, each with whether it is opened, or may be.
    public func chestLines(at seconds: Double) -> [LiveChestLine] {
        let row = doneToday(at: seconds)
        let marks = marksToday(at: seconds)
        return chests.map { chest in
            let opened = row?.hasOpened(chest.id) ?? false
            return LiveChestLine(id: chest.id, marks: chest.marks, holds: holdings(chest.goods, chest.hastes), opened: opened, ready: !opened && marks >= chest.marks)
        }
    }

    /// Goods and hastes in words: "5,000 grain and 5,000 timber, Five minutes' haste ×2".
    public func holdings(_ goods: LiveGoods, _ hastes: LiveHastes) -> String {
        var parts: [String] = goods.isNone ? [] : [goods.words]
        for (index, count) in hastes.enumerated() where count > 0 {
            let name = wares[index + 1]?.name ?? "haste"
            parts.append(count == 1 ? name : "\(name) ×\(count)")
        }
        return parts.isEmpty ? "nothing" : parts.joined(separator: ", ")
    }

    /// A commander's talents, each with its points and whether another may
    /// go into it.
    public func talentLines(of commander: LiveCommander) -> [LiveTalentLine] {
        let have = skills[commander.id] ?? [:]
        let left = talentPointsLeft(of: commander)
        return LiveTalent.names.keys.sorted().map { talent in
            let points = have[talent] ?? 0
            return LiveTalentLine(id: talent, name: LiveTalent.names[talent] ?? "", points: points, canLearn: left > 0 && points < LiveTalent.most)
        }
    }

    /// What the player's alliance learns, topic by topic; nothing where
    /// they are in none.
    public func learningLines() -> [LiveLearningLine] {
        guard let alliance = myMembership?.alliance else { return [] }
        return (1...15).compactMap { topic in
            guard let name = study(topic, level: 1)?.name else { return nil }
            let row = learnings[LiveLearning.key(alliance, topic)]
            let level = row?.level ?? 0
            let cost = level >= LiveLearning.topLevel ? nil : LiveLearning.cost(level: level + 1)
            return LiveLearningLine(id: topic, name: name, level: level, given: row?.given ?? LiveGoods(), cost: cost, risesAt: row?.risesAt ?? 0)
        }
    }

    /// A rally of the player's alliance in words: who called it, against
    /// what, how strong, and where it is at a moment.
    public func rallyWords(_ rally: LiveRally, at seconds: Double) -> String {
        let against: String
        if rally.isAgainstCity {
            against = cities[rally.city].map { "\(shownName(of: $0.owner) ?? $0.name)'s city" } ?? "a city"
        } else if rally.barrow == 0 {
            against = "a gate of the ridge"
        } else {
            against = "a level \(rally.level) barrow"
        }
        let when: String
        switch rally.state {
        case LiveRally.mustering: when = "sets out in \(LiveWords.spoken(max(rally.setsOut - Int(seconds), 0)))"
        case LiveRally.marching: when = "on its way"
        default: when = "fighting"
        }
        let armies = rally.armies == 1 ? "1 army" : "\(rally.armies) armies"
        return "\(rally.name)'s rally against \(against): \(armies), \(LiveWords.grouped(rally.soldiers)) soldiers; \(when)."
    }

    /// An ally's asking for help in words.
    public func pleaWords(_ plea: LivePlea) -> String {
        let work: String
        switch plea.work {
        case LiveJob.raise: work = "a building"
        case LiveJob.train: work = "training"
        case LiveJob.heal: work = "healing"
        default: work = "studies"
        }
        return "\(plea.name) asks help with \(work): \(plea.helped) of \(plea.most) have helped."
    }

    /// The askings for help the player may still help with: allies' own,
    /// not yet helped by the player, with room for more help.
    public var pleasToHelp: [LivePlea] {
        guard let me else { return [] }
        return pleas.filter { $0.asker != me.id && !helped.contains($0.job) && $0.helped < $0.most }
    }
}
