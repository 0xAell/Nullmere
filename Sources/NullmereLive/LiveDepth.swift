import Foundation
import NullmereRealm

// The realm's depth as a client reads it: the day's work and its chests,
// favour, items, the realm's contests, commanders' talents and pairs, the
// city's keeper, alliances' rallies, help, land and learning, and the
// Moonspire's seasons. Each row is read by its columns' places, in the
// module's order (`LiveSchema` lists them; `LiveSchemaTests` holds the
// lists to the module's source).

/// How many of each item a chest or a prize holds, by the item's number
/// less one: five minutes' haste, an hour's, eight hours', and eight
/// hours' peace.
public typealias LiveHastes = [UInt64]

/// One of the day's deeds, how much of it earns its marks, and how many.
public struct LiveDuty: Equatable, Sendable, Identifiable {
    /// The deeds as the module's catalogue numbers them.
    public static let train = 1, gather = 2, clear = 3, begin = 4, hasten = 5

    public let deed: Int
    public let asks: UInt64
    public let marks: Int
    public let words: String
    public var id: Int { deed }

    init?(_ row: [JSONValue]) {
        let cells = Cells(row: row)
        guard let deed = cells.whole(0), let asks = cells.unsigned(1), let marks = cells.whole(2), let words = cells.text(3) else { return nil }
        (self.deed, self.asks, self.marks, self.words) = (deed, asks, marks, words)
    }
}

/// A chest of the day's work: the marks it opens at and what it holds.
public struct LiveChest: Equatable, Sendable, Identifiable {
    public let id: Int
    public let marks: Int
    public let goods: LiveGoods
    public let hastes: LiveHastes

    init?(_ row: [JSONValue]) {
        let cells = Cells(row: row)
        guard let id = cells.whole(0), let marks = cells.whole(1) else { return nil }
        (self.id, self.marks) = (id, marks)
        goods = LiveGoods(grain: cells.unsigned(2) ?? 0, timber: cells.unsigned(3) ?? 0, stone: cells.unsigned(4) ?? 0, moonsalt: cells.unsigned(5) ?? 0)
        hastes = [cells.unsigned(6) ?? 0, cells.unsigned(7) ?? 0, cells.unsigned(8) ?? 0, cells.unsigned(9) ?? 0]
    }
}

/// A level of favour: the points it needs, and the hundredths sooner the
/// player's work is done at it.
public struct LiveGrace: Equatable, Sendable, Identifiable {
    public let level: Int
    public let points: UInt64
    public let sooner: Int
    public var id: Int { level }

    init?(_ row: [JSONValue]) {
        let cells = Cells(row: row)
        guard let level = cells.whole(0), let points = cells.unsigned(1), let sooner = cells.whole(2) else { return nil }
        (self.level, self.points, self.sooner) = (level, points, sooner)
    }
}

/// An item a player may hold: a haste, used on a work under way to make
/// it done sooner, or a peace, used on the city to keep it from attack;
/// what it is called, and how long it takes off or keeps.
public struct LiveWare: Equatable, Sendable, Identifiable {
    /// Its kinds, as the module numbers them.
    public static let haste = 1, peace = 2

    public let item: Int
    public let name: String
    public let words: String
    public let seconds: Int
    public let kind: Int
    public var id: Int { item }
    /// Whether it keeps the city at peace, rather than hastening a work.
    public var isPeace: Bool { kind == LiveWare.peace }

    init?(_ row: [JSONValue]) {
        let cells = Cells(row: row)
        guard let item = cells.whole(0), let name = cells.text(1), let words = cells.text(2), let seconds = cells.whole(3) else { return nil }
        (self.item, self.name, self.words, self.seconds, self.kind) = (item, name, words, seconds, cells.whole(4) ?? LiveWare.haste)
    }
}

/// One of the realm's contests: how often it comes round, in days, how
/// many days it runs, and on which day of its round it opens.
public struct LiveTrial: Equatable, Sendable, Identifiable {
    public let id: Int
    public let name: String
    public let words: String
    public let every: Int
    public let lasts: Int
    public let opens: Int

    init?(_ row: [JSONValue]) {
        let cells = Cells(row: row)
        guard let id = cells.whole(0), let name = cells.text(1), let words = cells.text(2), let every = cells.whole(3), let lasts = cells.whole(4) else { return nil }
        (self.id, self.name, self.words, self.every, self.lasts, self.opens) = (id, name, words, every, lasts, cells.whole(5) ?? 0)
    }

    /// Whether it runs on a day of the realm.
    public func runs(on day: UInt64) -> Bool {
        let into = Int(day % UInt64(max(every, 1)))
        return into >= opens && into < opens + lasts
    }
}

/// A prize of a contest: the points it is for, and what it gives.
public struct LivePrize: Equatable, Sendable, Identifiable {
    public let id: UInt64
    public let trial: Int
    public let place: Int
    public let points: UInt64
    public let goods: LiveGoods
    public let hastes: LiveHastes

    init?(_ row: [JSONValue]) {
        let cells = Cells(row: row)
        guard let id = cells.unsigned(0), let trial = cells.whole(1), let place = cells.whole(2), let points = cells.unsigned(3) else { return nil }
        (self.id, self.trial, self.place, self.points) = (id, trial, place, points)
        goods = LiveGoods(grain: cells.unsigned(4) ?? 0, timber: cells.unsigned(5) ?? 0, stone: cells.unsigned(6) ?? 0, moonsalt: cells.unsigned(7) ?? 0)
        hastes = [cells.unsigned(8) ?? 0, cells.unsigned(9) ?? 0, cells.unsigned(10) ?? 0, cells.unsigned(11) ?? 0]
    }
}

/// What the player has done of the day's work, the day it was done on,
/// and which chests they have opened.
public struct LiveDaily: Equatable, Sendable {
    public let day: UInt64
    /// So much of each deed, in the order the deeds are numbered.
    public let done: [UInt64]
    public let opened: Int

    init?(_ row: [JSONValue]) {
        let cells = Cells(row: row)
        guard let day = cells.unsigned(1), let opened = cells.whole(7) else { return nil }
        (self.day, self.opened) = (day, opened)
        done = (2...6).map { cells.unsigned($0) ?? 0 }
    }

    /// How much of a deed the player has done today.
    public func did(_ deed: Int) -> UInt64 { done.indices.contains(deed - 1) ? done[deed - 1] : 0 }

    /// Whether the player has opened a chest today.
    public func hasOpened(_ chest: Int) -> Bool { chest >= 1 && opened & (1 << (chest - 1)) != 0 }
}

/// The player's favour: the points earned and the level they stand at.
public struct LiveFavour: Equatable, Sendable {
    public let points: UInt64
    public let level: Int

    init?(_ row: [JSONValue]) {
        let cells = Cells(row: row)
        guard let points = cells.unsigned(1), let level = cells.whole(2) else { return nil }
        (self.points, self.level) = (points, level)
    }
}

/// What the player has scored in a round of a contest, and which of its
/// prizes they have claimed.
public struct LiveTally: Equatable, Sendable, Identifiable {
    public let id: UInt64
    public let trial: Int
    public let round: UInt64
    public let points: UInt64
    public let claimed: Int

    init?(_ row: [JSONValue]) {
        let cells = Cells(row: row)
        guard let id = cells.unsigned(0), let trial = cells.whole(2), let round = cells.unsigned(3), let points = cells.unsigned(4),
              let claimed = cells.whole(5) else { return nil }
        (self.id, self.trial, self.round, self.points, self.claimed) = (id, trial, round, points, claimed)
    }

    /// Whether the player has claimed a prize, by its place.
    public func hasClaimed(_ place: Int) -> Bool { place >= 1 && claimed & (1 << (place - 1)) != 0 }
}

/// A commander's talents, as the module's catalogue numbers and words them.
public enum LiveTalent {
    public static let names: [Int: String] = [
        1: "Spearmen", 2: "Archers", 3: "Riders", 4: "Mangonels", 5: "Shields", 6: "Haste", 7: "Gathering", 8: "Carrying", 9: "Breaching",
    ]
    /// The most points one talent takes.
    public static let most = 10

    /// The points a commander has to spend at a level: one for each past
    /// the first.
    public static func points(level: Int) -> Int { min(max(level, 1), LiveCommander.topLevel) - 1 }
}

/// A rally of the player's alliance: what it goes against (a barrow, or a
/// city), when it sets out, and how strong it is.
public struct LiveRally: Equatable, Sendable, Identifiable {
    public static let mustering = 1, marching = 2, fighting = 3

    public let id: UInt64
    public let alliance: UInt64
    public let caller: UInt64
    public let name: String
    public let barrow: UInt64
    public let city: UInt64
    public let hex: LiveHex
    public let level: Int
    public let setsOut: Int
    public let state: Int
    public let armies: Int
    public let soldiers: UInt64

    init?(_ row: [JSONValue]) {
        let cells = Cells(row: row)
        guard let id = cells.unsigned(0), let alliance = cells.unsigned(1), let caller = cells.unsigned(2), let name = cells.text(3),
              let barrow = cells.unsigned(4), let city = cells.unsigned(5), let hex = cells.unsigned(6), let level = cells.whole(7),
              let setsOut = cells.whole(8), let state = cells.whole(9), let armies = cells.whole(10), let soldiers = cells.unsigned(11) else { return nil }
        (self.id, self.alliance, self.caller, self.name, self.barrow, self.city) = (id, alliance, caller, name, barrow, city)
        (self.hex, self.level, self.setsOut, self.state, self.armies, self.soldiers) = (LiveHex(packed: hex), level, setsOut, state, armies, soldiers)
    }

    /// Whether it goes against another player's city.
    public var isAgainstCity: Bool { city != 0 }
}

/// An army's place in a rally of the player's alliance.
public struct LiveMuster: Equatable, Sendable, Identifiable {
    public let march: UInt64
    public let rally: UInt64
    public let player: UInt64
    public let arrived: Bool
    public var id: UInt64 { march }

    init?(_ row: [JSONValue]) {
        let cells = Cells(row: row)
        guard let march = cells.unsigned(0), let rally = cells.unsigned(1), let player = cells.unsigned(2), let arrived = cells.flag(3) else { return nil }
        (self.march, self.rally, self.player, self.arrived) = (march, rally, player, arrived)
    }
}

/// An ally's asking for help with a work in their city.
public struct LivePlea: Equatable, Sendable, Identifiable {
    public let job: UInt64
    public let alliance: UInt64
    public let asker: UInt64
    public let name: String
    /// What kind of work it is: `LiveJob`'s kinds.
    public let work: Int
    public let helped: Int
    public let most: Int
    public var id: UInt64 { job }

    init?(_ row: [JSONValue]) {
        let cells = Cells(row: row)
        guard let job = cells.unsigned(0), let alliance = cells.unsigned(1), let asker = cells.unsigned(2), let name = cells.text(3),
              let work = cells.whole(4), let helped = cells.whole(5), let most = cells.whole(6) else { return nil }
        (self.job, self.alliance, self.asker, self.name, self.work, self.helped, self.most) = (job, alliance, asker, name, work, helped, most)
    }
}

/// An alliance's Moonspire this season: the stage it stands at, till when
/// the next is being raised, and what is given toward it.
public struct LiveSpire: Equatable, Sendable, Identifiable {
    /// The stages a Moonspire has.
    public static let stages = 5

    public let alliance: UInt64
    public let name: String
    public let season: UInt64
    public let stage: Int
    /// When the stage being raised stands; 0 when none is.
    public let risesAt: Int
    public let given: LiveGoods
    public var id: UInt64 { alliance }

    init?(_ row: [JSONValue]) {
        let cells = Cells(row: row)
        guard let alliance = cells.unsigned(0), let name = cells.text(1), let season = cells.unsigned(2), let stage = cells.whole(3),
              let risesAt = cells.whole(4) else { return nil }
        (self.alliance, self.name, self.season, self.stage, self.risesAt) = (alliance, name, season, stage, risesAt)
        given = LiveGoods(grain: cells.unsigned(6) ?? 0, timber: cells.unsigned(7) ?? 0, stone: cells.unsigned(8) ?? 0, moonsalt: cells.unsigned(9) ?? 0)
    }

    /// What raising a stage costs, as the module's catalogue has it: a
    /// hundred thousand of each good times the stage squared, moonsalt a
    /// tenth of that from the third.
    public static func cost(stage: Int) -> LiveGoods {
        let each = 100_000 * UInt64(max(stage, 1)) * UInt64(max(stage, 1))
        return LiveGoods(grain: each, timber: each, stone: each, moonsalt: stage >= 3 ? each / 10 : 0)
    }
}

/// A season of the realm, and who won it, if anyone has.
public struct LiveSeason: Equatable, Sendable, Identifiable {
    public let number: UInt64
    public let began: Int
    public let ends: Int
    public let victor: UInt64
    public let victorName: String
    public let wonAt: Int
    public var id: UInt64 { number }

    init?(_ row: [JSONValue]) {
        let cells = Cells(row: row)
        guard let number = cells.unsigned(0), let began = cells.whole(1), let ends = cells.whole(2), let victor = cells.unsigned(3),
              let victorName = cells.text(4), let wonAt = cells.whole(5) else { return nil }
        (self.number, self.began, self.ends, self.victor, self.victorName, self.wonAt) = (number, began, ends, victor, victorName, wonAt)
    }

    /// The seconds the season has left at a moment.
    public func left(at seconds: Double) -> Int { max(ends - Int(seconds), 0) }
}

/// What the player has given toward their alliance's Moonspire, and in
/// which season.
public struct LiveGift: Equatable, Sendable {
    public let season: UInt64
    public let given: UInt64

    init?(_ row: [JSONValue]) {
        let cells = Cells(row: row)
        guard let season = cells.unsigned(1), let given = cells.unsigned(2) else { return nil }
        (self.season, self.given) = (season, given)
    }
}

/// A wardstone of an alliance's: where it stands, and from when it claims
/// the land about it.
public struct LiveWard: Equatable, Sendable, Identifiable {
    /// How many steps of land about it a wardstone claims.
    public static let reach = 3

    public let id: UInt64
    public let alliance: UInt64
    public let hex: LiveHex
    public let raisedBy: UInt64
    public let standsAt: Int

    init?(_ row: [JSONValue]) {
        let cells = Cells(row: row)
        guard let id = cells.unsigned(0), let alliance = cells.unsigned(1), let hex = cells.unsigned(2), let raisedBy = cells.unsigned(3),
              let standsAt = cells.whole(4) else { return nil }
        (self.id, self.alliance, self.hex, self.raisedBy, self.standsAt) = (id, alliance, LiveHex(packed: hex), raisedBy, standsAt)
    }

    /// Whether it stands at a moment, and so claims its land.
    public func stands(at seconds: Double) -> Bool { Double(standsAt) <= seconds }
}

/// A gate in one of the ridge's passes: who holds it (0 for the Unquiet),
/// since when, and whether a rally is at it.
public struct LiveGate: Equatable, Sendable, Identifiable {
    public let id: UInt64
    public let hex: LiveHex
    public let holder: UInt64
    public let holderName: String
    public let takenAt: Int
    public let fighter: UInt64

    init?(_ row: [JSONValue]) {
        let cells = Cells(row: row)
        guard let id = cells.unsigned(0), let hex = cells.unsigned(1), let holder = cells.unsigned(2), let holderName = cells.text(3),
              let takenAt = cells.whole(4), let fighter = cells.unsigned(5) else { return nil }
        (self.id, self.hex, self.holder, self.holderName, self.takenAt, self.fighter) = (id, LiveHex(packed: hex), holder, holderName, takenAt, fighter)
    }
}

/// What an alliance has learnt of a topic, and what is given toward its
/// next level, or till when it is studied.
public struct LiveLearning: Equatable, Sendable, Identifiable {
    /// The most levels an alliance learns of a topic.
    public static let topLevel = 5

    public let id: UInt64
    public let alliance: UInt64
    public let topic: Int
    public let level: Int
    public let risesAt: Int
    public let given: LiveGoods

    init?(_ row: [JSONValue]) {
        let cells = Cells(row: row)
        guard let id = cells.unsigned(0), let alliance = cells.unsigned(1), let topic = cells.whole(2), let level = cells.whole(3),
              let risesAt = cells.whole(4) else { return nil }
        (self.id, self.alliance, self.topic, self.level, self.risesAt) = (id, alliance, topic, level, risesAt)
        given = LiveGoods(grain: cells.unsigned(6) ?? 0, timber: cells.unsigned(7) ?? 0, stone: cells.unsigned(8) ?? 0)
    }

    /// The row's number for an alliance and a topic, as the module keys it.
    public static func key(_ alliance: UInt64, _ topic: Int) -> UInt64 { alliance << 8 | UInt64(topic) }

    /// What an alliance's next level of a topic costs: a hundred thousand
    /// each of grain, timber and stone, times the level squared.
    public static func cost(level: Int) -> LiveGoods {
        let each = 100_000 * UInt64(max(level, 1)) * UInt64(max(level, 1))
        return LiveGoods(grain: each, timber: each, stone: each)
    }
}

/// A pact between two alliances, and until when it holds.
public struct LivePact: Equatable, Sendable, Identifiable {
    /// A truce, and passage through one another's gates, as the module numbers them.
    public static let truce = 1, passage = 2

    public let id: UInt64
    public let first: UInt64
    public let second: UInt64
    public let terms: Int
    public let began: Int
    public let ends: Int

    init?(_ row: [JSONValue]) {
        let cells = Cells(row: row)
        guard let id = cells.unsigned(0), let first = cells.unsigned(1), let second = cells.unsigned(2), let terms = cells.whole(3),
              let began = cells.whole(4), let ends = cells.whole(5) else { return nil }
        (self.id, self.first, self.second, self.terms, self.began, self.ends) = (id, first, second, terms, began, ends)
    }

    /// Whether it holds at a moment.
    public func holds(at seconds: Double) -> Bool { Double(ends) > seconds }

    /// The other alliance of the pact, to one of its two.
    public func other(than alliance: UInt64) -> UInt64 { first == alliance ? second : first }
}

/// An envoy from or to the player's alliance, with the terms it carries.
public struct LiveEnvoy: Equatable, Sendable, Identifiable {
    /// How long an envoy waits for its answer.
    public static let waits = 86_400

    public let id: UInt64
    public let sender: UInt64
    public let receiver: UInt64
    public let name: String
    public let terms: Int
    public let days: Int
    public let sentAt: Int

    init?(_ row: [JSONValue]) {
        let cells = Cells(row: row)
        guard let id = cells.unsigned(0), let sender = cells.unsigned(1), let receiver = cells.unsigned(2), let name = cells.text(3),
              let terms = cells.whole(4), let days = cells.whole(5), let sentAt = cells.whole(6) else { return nil }
        (self.id, self.sender, self.receiver, self.name, self.terms, self.days, self.sentAt) = (id, sender, receiver, name, terms, days, sentAt)
    }

    /// Its terms in words: "a truce of 3 days".
    public var words: String {
        let span = days == 1 ? "a day" : "\(days) days"
        return terms == LivePact.truce ? "a truce of \(span)" : "passage through one another's gates for \(span)"
    }
}

/// A commander held prisoner: whose, by whom, the ransom asked, and when
/// they go free of themselves.
public struct LivePrisoner: Equatable, Sendable, Identifiable {
    public let commander: UInt64
    public let owner: UInt64
    public let captor: UInt64
    public let name: String
    public let ransom: LiveGoods
    public let freedAt: Int
    public var id: UInt64 { commander }

    init?(_ row: [JSONValue]) {
        let cells = Cells(row: row)
        guard let commander = cells.unsigned(0), let owner = cells.unsigned(1), let captor = cells.unsigned(2), let name = cells.text(3),
              let freedAt = cells.whole(7) else { return nil }
        (self.commander, self.owner, self.captor, self.name, self.freedAt) = (commander, owner, captor, name, freedAt)
        ransom = LiveGoods(grain: cells.unsigned(4) ?? 0, timber: cells.unsigned(5) ?? 0, stone: cells.unsigned(6) ?? 0)
    }
}

/// A member's petition to the player's alliance for goods: what it asks,
/// what allies have sent, and when it was made.
public struct LivePetition: Equatable, Sendable, Identifiable {
    /// How long a petition stands, the most of each good it asks, and the
    /// hundredths of what is sent the road takes.
    public static let stands = 86_400, most: UInt64 = 500_000, toll: UInt64 = 10

    public let asker: UInt64
    public let alliance: UInt64
    public let name: String
    public let asked: LiveGoods
    public let sent: LiveGoods
    public let madeAt: Int
    public var id: UInt64 { asker }

    init?(_ row: [JSONValue]) {
        let cells = Cells(row: row)
        guard let asker = cells.unsigned(0), let alliance = cells.unsigned(1), let name = cells.text(2), let madeAt = cells.whole(11) else { return nil }
        (self.asker, self.alliance, self.name, self.madeAt) = (asker, alliance, name, madeAt)
        asked = LiveGoods(grain: cells.unsigned(3) ?? 0, timber: cells.unsigned(4) ?? 0, stone: cells.unsigned(5) ?? 0, moonsalt: cells.unsigned(6) ?? 0)
        sent = LiveGoods(grain: cells.unsigned(7) ?? 0, timber: cells.unsigned(8) ?? 0, stone: cells.unsigned(9) ?? 0, moonsalt: cells.unsigned(10) ?? 0)
    }

    /// What it still asks.
    public var still: LiveGoods {
        LiveGoods(grain: asked.grain - min(sent.grain, asked.grain), timber: asked.timber - min(sent.timber, asked.timber),
                  stone: asked.stone - min(sent.stone, asked.stone), moonsalt: asked.moonsalt - min(sent.moonsalt, asked.moonsalt))
    }
}

/// A title of the Mere and who holds it.
public struct LiveTitle: Equatable, Sendable, Identifiable {
    /// The titles, as the module's catalogue numbers and names them, with
    /// what each lends.
    public static let names: [Int: (name: String, lends: String)] = [
        1: ("Steward of the Mere", "Their armies gather faster, as two levels of Gathering."),
        2: ("Marshal of the Mere", "Their soldiers are trained sooner, as four levels of Drill."),
        3: ("Mason of the Mere", "Their buildings are raised sooner, as four levels of Building."),
        4: ("Warden of the Mere", "Everyone they send or keep is harder to bring down, as three levels of Shields."),
        5: ("Herald of the Mere", "Their armies march faster, as three levels of Marching."),
    ]

    public let title: Int
    public let holder: UInt64
    public let name: String
    public let since: Int
    public var id: Int { title }

    init?(_ row: [JSONValue]) {
        let cells = Cells(row: row)
        guard let title = cells.whole(0), let holder = cells.unsigned(1), let name = cells.text(2), let since = cells.whole(3) else { return nil }
        (self.title, self.holder, self.name, self.since) = (title, holder, name, since)
    }
}

/// A letter the player has written or been written.
public struct LiveLetter: Equatable, Sendable, Identifiable {
    /// The most characters a letter holds.
    public static let longest = 1_000

    public let id: UInt64
    public let sender: UInt64
    public let receiver: UInt64
    public let name: String
    public let words: String
    public let at: Int
    public let read: Bool

    init?(_ row: [JSONValue]) {
        let cells = Cells(row: row)
        guard let id = cells.unsigned(0), let sender = cells.unsigned(1), let receiver = cells.unsigned(2), let name = cells.text(3),
              let words = cells.text(4), let at = cells.whole(5), let read = cells.flag(6) else { return nil }
        (self.id, self.sender, self.receiver, self.name, self.words, self.at, self.read) = (id, sender, receiver, name, words, at, read)
    }
}
