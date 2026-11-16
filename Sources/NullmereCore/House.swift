import Foundation
import NullmereLand
/// How a rival House tends to play.
public enum Temperament: String, CaseIterable, Codable, Sendable, PlainCases {
    /// Expands fast and strikes when stronger.
    case ambitious
    /// Builds, fortifies and reaches for the Moonspire.
    case steadfast
    /// Keeps its word and fights only when wronged.
    case wary
    /// Makes pacts, then breaks them when it pays.
    case cunning

    public var title: String {
        switch self {
        case .ambitious: return "Ambitious"
        case .steadfast: return "Steadfast"
        case .wary: return "Wary"
        case .cunning: return "Cunning"
        }
    }
}

/// One of the great Houses around the lake.
public struct House: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public var name: String
    /// Index into the House colours.
    public var sigil: Int
    /// Held by a keeper, a person, rather than played by a steward.
    public var isPlayer: Bool
    public var temperament: Temperament
    public var stock: Stock
    /// Tiles this House has ever seen, by map index, a bit to a tile.
    public var explored: Explored
    public var isEliminated: Bool
    /// The House this one has sworn fealty to, if any.
    public var liege: Int?
    /// What it has studied, and what it studies now.
    public var research = Research()
    /// The heritage it took up; none while it keeps the one the realm
    /// dealt its seat (see `GameState.heritage(of:)`).
    public var heritage: Heritage?
    /// The level of favour it stands at, I to X: its keeper's (see
    /// `Favour`); none for a steward's House.
    public var favour: Int?
    /// The crest its keeper chose this age; none while it bears the one
    /// the lake gave it (see `GameState.crest(of:)`).
    public var crest: Crest?
    /// A keeper's House's companies of war lost in battle since its keeper
    /// last kept a vigil for them; none while none is (see `Vigil`). Its
    /// own to know.
    public var unmourned: Int?
    /// The times other Houses have honoured its vigils this age, which
    /// count toward its keeper's renown as the age ends; none before the
    /// first.
    public var honoured: Int?
    /// The fields of dead it has buried this age, which count toward its
    /// keeper's renown as the age ends; none before the first.
    public var buried: Int?

    public var title: String { "House \(name)" }

    public init(id: Int, name: String, sigil: Int, isPlayer: Bool, temperament: Temperament, tileCount: Int) {
        self.id = id
        self.name = name
        self.sigil = sigil
        self.isPlayer = isPlayer
        self.temperament = temperament
        self.stock = Stock(grain: 60, timber: 50, stone: 40, moonsalt: 5)
        self.explored = Explored(repeating: false, count: tileCount)
        self.isEliminated = false
    }

    // The explored ground travels as bits, eight tiles to a byte: a keeper's
    // view goes across the network whenever it changes.
    private enum CodingKeys: String, CodingKey {
        case id, name, sigil, isPlayer, temperament, stock, explored, exploredBits, isEliminated, liege, research, heritage, favour, crest,
             unmourned, honoured
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        sigil = try container.decode(Int.self, forKey: .sigil)
        isPlayer = try container.decode(Bool.self, forKey: .isPlayer)
        temperament = try container.decode(Temperament.self, forKey: .temperament)
        stock = try container.decode(Stock.self, forKey: .stock)
        if let bits = try container.decodeIfPresent(String.self, forKey: .exploredBits) {
            guard let explored = Bits.decode(bits) else {
                throw DecodingError.dataCorruptedError(forKey: .exploredBits, in: container, debugDescription: "Unreadable explored ground")
            }
            self.explored = explored
        } else {
            explored = Explored(try container.decode([Bool].self, forKey: .explored))
        }
        isEliminated = try container.decode(Bool.self, forKey: .isEliminated)
        liege = try container.decodeIfPresent(Int.self, forKey: .liege)
        // Saves from before studies know none.
        research = try container.decodeIfPresent(Research.self, forKey: .research) ?? Research()
        heritage = try container.decodeIfPresent(Heritage.self, forKey: .heritage)
        favour = try container.decodeIfPresent(Int.self, forKey: .favour)
        crest = try container.decodeIfPresent(Crest.self, forKey: .crest)
        unmourned = try container.decodeIfPresent(Int.self, forKey: .unmourned)
        honoured = try container.decodeIfPresent(Int.self, forKey: .honoured)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(sigil, forKey: .sigil)
        try container.encode(isPlayer, forKey: .isPlayer)
        try container.encode(temperament, forKey: .temperament)
        try container.encode(stock, forKey: .stock)
        try container.encode(Bits.encode(explored), forKey: .exploredBits)
        try container.encode(isEliminated, forKey: .isEliminated)
        try container.encodeIfPresent(liege, forKey: .liege)
        if !research.isEmpty { try container.encode(research, forKey: .research) }
        try container.encodeIfPresent(heritage, forKey: .heritage)
        try container.encodeIfPresent(favour, forKey: .favour)
        try container.encodeIfPresent(crest, forKey: .crest)
        try container.encodeIfPresent(unmourned, forKey: .unmourned)
        try container.encodeIfPresent(honoured, forKey: .honoured)
    }
}

/// Booleans as they travel: "count:base64", eight to a byte; or, where it
/// is shorter, as a House's explored ground mostly is, "count;base64" of
/// its runs (`Explored.runs`), each a number seven bits to a byte, the
/// last byte of each without its high bit.
enum Bits {
    /// Bits none of which is set, as they travel: their count alone, as a
    /// keeper's view carries every other House's explored ground.
    static let noneSet = "-"

    static func encode(_ values: Explored) -> String {
        guard values.contains(true) else { return "\(values.count):\(noneSet)" }
        var runs: [UInt8] = []
        for run in values.runs { Varint.append(run, to: &runs) }
        // Runs when they are fewer bytes than the tiles, eight to a byte.
        if runs.count < (values.count + 7) / 8 {
            return "\(values.count);" + Data(runs).base64EncodedString()
        }
        return "\(values.count):" + Data(values.bytes).base64EncodedString()
    }

    static func decode(_ text: String) -> Explored? {
        guard let mark = text.firstIndex(where: { $0 == ":" || $0 == ";" }), let count = Int(text[..<mark]), count >= 0 else { return nil }
        let rest = String(text[text.index(after: mark)...])
        if text[mark] == ";" {
            // Runs tell of any number of tiles in a few bytes: no more than
            // the widest lake has.
            guard count <= WorldMap.count(radius: GameState.MapPages.widest), let data = Data(base64Encoded: rest) else { return nil }
            var read = Varint.Reader([UInt8](data)), runs: [Int] = []
            while !read.isAtEnd {
                guard let run = read.count() else { return nil }
                runs.append(run)
            }
            return Explored(count: count, runs: runs)
        }
        if rest == noneSet { return Explored(repeating: false, count: count) }
        guard let data = Data(base64Encoded: rest), data.count == (count + 7) / 8 else { return nil }
        return Explored(count: count, bytes: [UInt8](data))
    }
}

extension Hold {
    /// The hold as every keeper is told it but its own House's: what it
    /// raises and trains, and who lies in its beds, its House's to know.
    public func toldAlike() -> Hold {
        var told = self
        told.project = nil
        told.training = nil
        told.wounded = nil
        return told
    }

    /// Whether the hold is as every keeper is told it (`toldAlike`): asked
    /// of it where it lies, with nothing copied.
    var isToldAlike: Bool {
        project == nil && training == nil && wounded == nil
    }
}

extension House {
    /// The House as every keeper is told it but its own: its stores, the
    /// ground it has explored, its studies and its fallen unmourned its own
    /// to know.
    public func toldAlike(unknown: Explored) -> House {
        var told = self
        told.stock = .zero
        told.explored = unknown
        told.research = Research()
        told.unmourned = nil
        return told
    }

    /// Whether the House is as every keeper but its own is told it
    /// (`toldAlike(unknown:)`): asked of it where it lies, with nothing
    /// copied, the ground it has explored the very nothing known if it is
    /// told none.
    func isToldAlike(unknown: Explored) -> Bool {
        stock == .zero && research == Research() && explored == unknown && unmourned == nil
    }
}
