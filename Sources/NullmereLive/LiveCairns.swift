import Foundation
import NullmereRealm

/// A cairn of the old folk on the land: the first time a player's scouts
/// come to it they find what was laid in it, and each player finds each
/// once.
public struct LiveCairn: Equatable, Sendable, Identifiable {
    public let id: UInt64
    public let hex: LiveHex
    /// One to five.
    public let level: Int

    public static let topLevel = 5

    init?(_ row: [JSONValue]) {
        let cells = Cells(row: row)
        guard let id = cells.unsigned(0), let hex = cells.unsigned(1), let level = cells.whole(2) else { return nil }
        (self.id, self.hex, self.level) = (id, LiveHex(packed: hex), level)
    }

    /// The cairn a row of the player's finds names.
    static func found(_ row: [JSONValue]) -> UInt64? {
        Cells(row: row).unsigned(2)
    }

    /// What a cairn of a level holds, as the module has it: a thousand of
    /// each of grain, timber and stone times the level and the next, five
    /// hundred moonsalt a level past the third, and a haste from the third
    /// level, an hour's at the top; and the haste in words.
    public static func hoard(level: Int) -> (goods: LiveGoods, haste: String?) {
        let each = UInt64(1_000 * level * (level + 1))
        let goods = LiveGoods(grain: each, timber: each, stone: each, moonsalt: UInt64(500 * max(level - 3, 0)))
        switch level {
        case ...2: return (goods, nil)
        case 3, 4: return (goods, "a five minutes' haste")
        default: return (goods, "an hour's haste")
        }
    }

    /// What it holds in a sentence: "12,000 grain, 12,000 timber and
    /// 12,000 stone, and a five minutes' haste".
    public var hoardWords: String {
        let (goods, haste) = LiveCairn.hoard(level: level)
        return haste.map { "\(goods.words), and \($0)" } ?? goods.words
    }
}

extension LiveWorld {
    /// The cairn at a hex, if one stands there.
    public func cairn(at hex: LiveHex) -> LiveCairn? {
        guard let place = places[hex], place.kind == LivePlace.cairn else { return nil }
        return cairns[place.id]
    }

    /// Whether the player's scouts have found what a cairn held.
    public func hasFound(_ cairn: LiveCairn) -> Bool { finds.contains(cairn.id) }

    /// Whether scouts of the player's are on their way to a cairn now.
    public func scouting(_ cairn: LiveCairn) -> Bool {
        myMarches.contains { $0.kind == LiveMarch.explore && $0.target == cairn.id && $0.state == LiveMarch.going }
    }
}
