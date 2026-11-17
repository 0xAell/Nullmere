import Foundation
import NullmereLive

/// What one of the player's commanders knows and may say in counsel,
/// grounded on the realm's rows as the session holds them at a moment:
/// who they are and how they speak, what they know as counsel begins,
/// what more they may look at, and what they may put forward, which is
/// only ever one of the things the player can do now (`commands(at:)`),
/// put to the player and never done by the commander. The voice that
/// speaks it (on a Mac, Apple's own model) reads these; nothing here asks
/// one.
public struct LiveCounsel: Sendable {
    public let commander: LiveCommander
    let world: LiveWorld
    let seconds: Double
    /// What the player can do now, as the palette offers it.
    let commands: [LiveCommand]

    /// The most deeds the briefing names.
    public static let deedsTold = 14

    /// How a commander of each way of war counsels.
    static let bents: [Int: String] = [
        1: "You lead the spears at the front: you counsel bold attacks and holding the field.",
        2: "You lead the bows: you counsel striking from afar and never fighting on poor ground.",
        3: "You ride fast and see far: you counsel scouting, the cairns of the old folk, and hunting the barrows.",
        4: "You break walls: you counsel sieges, and the engines and the patience they want.",
        5: "You hold the line: you counsel patience, walls, the Hospital and keeping the city.",
        6: "You work the land: you counsel gathering, building and good husbandry.",
    ]

    /// What the voice speaks by: who the commander is, how they speak, and
    /// what they must hold to.
    public var instructions: String {
        let lord = world.me?.name ?? "your lord"
        let bent = LiveCounsel.bents[commander.way] ?? "You counsel as an old soldier does."
        let way = commander.wayName.lowercased()
        let article = way.first.map { "aeiou".contains($0) } == true ? "an" : "a"
        return """
        You are \(commander.name), \(article) \(way) of level \(commander.level), counselling \(lord), \
        whose city stands in Nullmere, a realm of cities about a vast black lake. \(bent) Speak as yourself to your lord: \
        grave, spare and plain, as an old soldier speaks, in at most three sentences and seventy words, with no \
        exclamation marks and no modern words. Know only what you are told here and what your looks tell you: never \
        invent a number, a name, a place or an event. To learn more, look: at the city, at its armies out, at the \
        alliance, at the realm, or at yourself. You may put a deed to your lord only by proposing it, in the words of \
        one of the deeds you are told can be done now, and you never do it yourself: say that you have put it \
        forward, and that your lord decides. Never speak of games, players, rules, models or tools.
        """
    }

    /// What the commander knows as counsel begins: themself, the city and
    /// its works under way, its armies, what threatens it and stands idle,
    /// the task in hand, and the deeds that can be done now.
    public var briefing: String {
        var lines = [yourselfSaid]
        if let city = world.city {
            lines.append("Your lord's city: Keep level \(city.keep), power \(LiveWords.grouped(city.power)).")
        }
        let works = world.works(at: seconds)
        if !works.isEmpty {
            lines.append("Works under way: " + works.map { "\($0.words), \(LiveWords.spoken(Int($0.job.left(at: seconds).rounded(.up)))) left" }.joined(separator: "; ") + ".")
        }
        lines += world.threats(at: seconds).map(\.words)
        let out = world.marchLines()
        if !out.isEmpty {
            lines.append("Armies out: " + out.map { "\($0.doing), \(LiveWords.grouped($0.soldiers)) soldiers" }.joined(separator: "; ") + ".")
        }
        let idle = world.idle(at: seconds)
        if !idle.isEmpty {
            lines.append("Standing idle: " + idle.map(\.words).joined(separator: "; ") + ".")
        }
        if let task = world.task {
            lines.append("The task in hand: \(task.words) It gives \(world.holdings(task.gives, task.items))" + (world.isDone(task) ? ", and it is done." : "."))
        }
        lines.append(deedsSaid)
        return lines.joined(separator: "\n")
    }

    /// The commander themself: their way, their level and how far toward
    /// the next, their renown and gift if they are one of the realm's own,
    /// and where they are.
    var yourselfSaid: String {
        var told = "You are \(commander.name), \(commander.wayName.lowercased()) of level \(commander.level)"
        if commander.level < LiveCommander.topLevel {
            told += ", \(LiveWords.grouped(commander.seen)) of \(LiveWords.grouped(commander.needs)) seen toward the next"
        }
        told += "."
        if let known = commander.person(in: world.people) {
            let does = known.giftWords(at: commander.gift)
            told += " You are \(known.renownName.lowercased()) among the realm's commanders, and your gift is \(known.giftName), at level \(max(commander.gift, 1))"
            told += does.isEmpty ? "." : ": \(does.prefix(1).lowercased() + does.dropFirst())"
        }
        if world.prisoners[commander.id] != nil {
            told += " You are held prisoner."
        } else if !commander.isFree, let line = world.marchLines().first(where: { $0.march.id == commander.march }) {
            told += " You are out with an army: \(line.doing.prefix(1).lowercased() + line.doing.dropFirst())."
        } else if world.keeper == commander.id {
            told += " You keep the city."
        } else {
            told += " You are in the city."
        }
        return told
    }

    /// The deeds the player can do now, as they may be put forward: every
    /// command but opening a part or going to a place, to so many.
    public var deeds: [LiveCommand] {
        commands.filter { command in
            switch command.act {
            case .open, .go: return false
            default: return true
            }
        }
    }

    var deedsSaid: String {
        let named = deeds.prefix(LiveCounsel.deedsTold).map(\.title)
        guard !named.isEmpty else { return "Nothing can be done now that you may put forward." }
        return "Deeds that can be done now, in the words you put them forward by: " + named.joined(separator: "; ") + "."
    }

    // MARK: What the commander may look at

    /// The commander themself, as they are told it.
    public var yourselfLook: String { yourselfSaid }

    /// The city: its buildings that may be raised now and its works under way.
    public var cityLook: String {
        guard let city = world.city else { return "Your lord has no city." }
        var lines = ["Keep level \(city.keep), power \(LiveWords.grouped(city.power))."]
        let rising = world.buildingLines(at: seconds).filter { $0.job != nil }.map { "\($0.name) to level \($0.level + 1)" }
        if !rising.isEmpty { lines.append("Being raised: " + rising.joined(separator: ", ") + ".") }
        let ready = world.buildingLines(at: seconds).filter { $0.block == nil && $0.next != nil }.map(\.name)
        lines.append(ready.isEmpty ? "Nothing can be built or raised now." : "May be built or raised now: " + ready.joined(separator: ", ") + ".")
        let soldiers = world.troops.reduce(0) { $0 + $1.ready }
        let wounded = world.troops.reduce(0) { $0 + $1.wounded }
        lines.append("\(LiveWords.grouped(soldiers)) soldiers stand ready, \(LiveWords.grouped(wounded)) lie wounded.")
        return lines.joined(separator: " ")
    }

    /// The armies out, each in plain words.
    public var armiesLook: String {
        let out = world.marchLines()
        guard !out.isEmpty else { return "No army of your lord's is out." }
        return out.map { line in
            var told = "\(line.doing), \(LiveWords.grouped(line.soldiers)) soldiers"
            if line.wounded > 0 { told += ", \(LiveWords.grouped(line.wounded)) wounded" }
            return told + "."
        }.joined(separator: " ")
    }

    /// The alliance: which, and what it asks.
    public var allianceLook: String {
        guard let member = world.myMembership, let alliance = world.alliances[member.alliance] else {
            return "Your lord is in no alliance."
        }
        var lines = ["Your lord is of [\(alliance.tag)] \(alliance.name), \(alliance.members) strong."]
        let pleas = world.pleasToHelp.count
        if pleas > 0 { lines.append("Allies ask help with \(pleas) \(pleas == 1 ? "work" : "works").") }
        if let rally = world.myRally { lines.append("Your lord has an army in a rally: \(world.rallyWords(rally, at: seconds))") }
        if !world.boons.isEmpty { lines.append("Gifts wait: \(world.boonGoods.words).") }
        return lines.joined(separator: " ")
    }

    /// The realm: where the player stands in it, and in the contests that
    /// run today, and what a place in one's last round gave them to claim.
    public var realmLook: String {
        var lines: [String] = []
        if let place = world.powerPlace { lines.append("Your lord stands \(LiveWords.ordinal(place)) in power in the realm.") }
        if let season = world.season {
            lines.append("Season \(season.number), \(LiveWords.spoken(season.left(at: seconds))) left.")
        }
        let day = world.today(at: seconds)
        for trial in world.trials.values.sorted(by: { $0.id < $1.id }) {
            if trial.runs(on: day) {
                let standings = world.standings(of: trial.id, round: world.contestRound(of: trial, day: day))
                if let me = world.me?.id, let index = standings.firstIndex(where: { $0.player == me }) {
                    lines.append("\(trial.name) runs: your lord stands \(LiveWords.ordinal(index + 1)) of \(standings.count), with \(LiveWords.grouped(standings[index].points)) points.")
                } else {
                    lines.append("\(trial.name) runs: your lord has scored nothing in it yet.")
                }
            }
            if let laurel = world.laurelToClaim(of: trial, day: day) {
                lines.append("Your lord was \(LiveWords.ordinal(laurel.place)) in \(trial.name) when its last round ended, and may claim \(world.holdings(laurel.goods, laurel.hastes)).")
            }
        }
        return lines.isEmpty ? "Little is known of the realm beyond the city." : lines.joined(separator: " ")
    }

    // MARK: What the commander may say

    /// Every number written in figures in some words, as it would be
    /// counted: "1,600" and "1600" alike are "1600".
    static func numbers(in text: String) -> [String] {
        let characters = Array(text)
        var found: [String] = []
        var index = 0
        while index < characters.count {
            guard characters[index].isASCII, characters[index].isNumber else {
                index += 1
                continue
            }
            var number = ""
            while index < characters.count {
                let character = characters[index]
                if character.isASCII, character.isNumber {
                    number.append(character)
                } else if character == ",", index + 1 < characters.count, characters[index + 1].isASCII, characters[index + 1].isNumber {
                    // A thousands mark between figures.
                } else {
                    break
                }
                index += 1
            }
            found.append(number)
        }
        return found
    }

    /// The numbers in an answer that nothing the commander was told holds:
    /// neither their instructions and briefing nor the looks they took. A
    /// commander invents no number; one that does is caught here, every
    /// answer, before the player reads it as true.
    public func strayNumbers(in answer: String, looks: [String] = []) -> [String] {
        let told = Set(LiveCounsel.numbers(in: ([instructions, briefing] + looks).joined(separator: "\n")))
        var stray: [String] = []
        for number in LiveCounsel.numbers(in: answer) where !told.contains(number) && !stray.contains(number) {
            stray.append(number)
        }
        return stray
    }

    // MARK: What the commander may put forward

    /// A deed put forward in words: the one deed that can be done now
    /// whose words they are, or that holds every word of them, put to the
    /// player; or what to say where there is none, or more than one.
    public func propose(_ words: String) -> LiveProposal {
        let asked = words.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if let exact = deeds.first(where: { $0.title.caseInsensitiveCompare(asked) == .orderedSame }) {
            return LiveProposal(command: exact, answer: "Put to your lord: \(exact.title). Your lord decides.")
        }
        let wanted = asked.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let matching = wanted.isEmpty ? [] : deeds.filter { deed in
            let title = deed.title.lowercased()
            return wanted.allSatisfy { title.contains($0) }
        }
        switch matching.count {
        case 1: return LiveProposal(command: matching[0], answer: "Put to your lord: \(matching[0].title). Your lord decides.")
        case 0: return LiveProposal(command: nil, answer: "That cannot be done now. Put forward only a deed you were told can be done.")
        default:
            return LiveProposal(command: nil, answer: "Say which: " + matching.prefix(4).map(\.title).joined(separator: "; ") + ".")
        }
    }
}

/// A deed a commander put forward: the command, where it is one the
/// player can do now, and what the commander is told.
public struct LiveProposal: Equatable, Sendable {
    public let command: LiveCommand?
    public let answer: String
}

extension LiveSession {
    /// Counsel of one of the player's commanders, as the realm stands now.
    public func counsel(of commander: UInt64) -> LiveCounsel? {
        guard let found = world.commanders.first(where: { $0.id == commander }) else { return nil }
        let seconds = now
        return LiveCounsel(commander: found, world: world, seconds: seconds, commands: commands(at: seconds))
    }
}
