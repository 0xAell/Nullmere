import Foundation

/// The player's honour, earned helping allies and giving toward what
/// their alliance learns, and spent in its stores.
public struct LiveHonour: Equatable, Sendable {
    public let honour: UInt64
    /// The day of the realm `fromHelp` was earned on.
    public let day: UInt64
    public let fromHelp: UInt64

    /// Honour for each help given, and the most of it from helping in a
    /// day, as the module has them.
    public static let aHelp: UInt64 = 20
    public static let fromHelpADay: UInt64 = 1_000
    /// The most of one thing bought at once.
    public static let mostBought: UInt64 = 100

    init?(_ row: [JSONValue]) {
        let cells = Cells(row: row)
        guard let honour = cells.unsigned(1), let day = cells.unsigned(2), let fromHelp = cells.unsigned(3) else { return nil }
        (self.honour, self.day, self.fromHelp) = (honour, day, fromHelp)
    }

    /// A row of the stores' prices.
    static func price(_ row: [JSONValue]) -> (item: Int, honour: UInt64)? {
        let cells = Cells(row: row)
        guard let item = cells.whole(0), let honour = cells.unsigned(1) else { return nil }
        return (item, honour)
    }
}

/// One thing the alliance's stores sell, as the player may buy it now.
public struct LiveStoreLine: Equatable, Identifiable, Sendable {
    public let ware: LiveWare
    public var id: Int { ware.item }
    /// Its price in honour.
    public let honour: UInt64
    /// Why it can't be bought now; nil where it can.
    public let block: String?
}

extension LiveWorld {
    /// The player's honour now.
    public var honourHeld: UInt64 { honour?.honour ?? 0 }

    /// What of today's honour from helping the player may still earn.
    public func honourFromHelpLeft(at seconds: Double) -> UInt64 {
        guard let honour, honour.day == today(at: seconds) else { return LiveHonour.fromHelpADay }
        return LiveHonour.fromHelpADay > honour.fromHelp ? LiveHonour.fromHelpADay - honour.fromHelp : 0
    }

    /// What the alliance's stores sell, cheapest first, each with why it
    /// can't be bought now: none to one in no alliance.
    public func storeLines() -> [LiveStoreLine] {
        guard myMembership != nil else { return [] }
        let held = honourHeld
        return prices.compactMap { item, honour -> LiveStoreLine? in
            guard let ware = wares[item] else { return nil }
            let block = held < honour ? "It costs \(LiveWords.grouped(honour)) honour. You have \(LiveWords.grouped(held))." : nil
            return LiveStoreLine(ware: ware, honour: honour, block: block)
        }.sorted { ($0.honour, $0.ware.item) < ($1.honour, $1.ware.item) }
    }
}
