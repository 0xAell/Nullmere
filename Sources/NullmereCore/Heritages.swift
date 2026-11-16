import NullmereLand
extension Heritage {
    /// What it adds to a figure of its House's.
    func bonus(_ bonus: Bonus) -> Int {
        switch (self, bonus) {
        case (.saltborn, .yield(.moonsalt)): return 50
        case (.saltborn, .wardMending): return 50
        case (.fenfolk, .attack(.bow)): return 10
        case (.fenfolk, .sight): return 1
        case (.blackwood, .yield(.timber)): return 25
        case (.blackwood, .attack(.rider)): return 10
        case (.spinewardens, .yield(.stone)): return 25
        case (.spinewardens, .defense(.spear)): return 10
        case (.moundClans, .commanderExperience): return 25
        case (.moundClans, .studySpeed): return 10
        case (.strandfolk, .yield(.grain)): return 25
        case (.strandfolk, .gathering): return 20
        default: return 0
        }
    }

    /// Every heritage, in the turn they are dealt round the lake: made once,
    /// for every rule that weighs a company asks after its House's.
    private static let round = allCases

    /// The heritage the realm deals a seat as an age begins: round the lake
    /// in turn, from one the seed chooses, so every heritage has its seats.
    static func dealt(seat: Int, seed: UInt64) -> Heritage {
        dealt(seat: seat, from: start(seed: seed))
    }

    /// The heritage dealt a seat, the round begun at `start`.
    static func dealt(seat: Int, from start: Int) -> Heritage {
        round[(start + seat) % round.count]
    }

    /// Where in the round a world's seed has the dealing begin.
    static func start(seed: UInt64) -> Int {
        Int(Seed.finalize(seed ^ 0x4E7A_5EED_D1A1_0000) % UInt64(round.count))
    }
}

extension GameState {
    /// A House's heritage: the one it took up, or the one the realm dealt it.
    public func heritage(of house: Int) -> Heritage {
        guard houses.indices.contains(house), let taken = houses[house].heritage else {
            return Heritage.dealt(seat: house, from: dealing?.firstHeritage ?? Heritage.start(seed: settings.seed))
        }
        return taken
    }

    /// Whether a company is its House's own: the fifth tier of its
    /// heritage's kind.
    public func isSignature(_ unit: Unit) -> Bool {
        unit.tier == Unit.highestTier && unit.kind == heritage(of: unit.owner).signature
    }

    /// A company's name: its House's own company's, or its kind's.
    public func title(of unit: Unit) -> String {
        isSignature(unit) ? heritage(of: unit.owner).signatureTitle : unit.kind.title
    }

    /// A company as every line names it, on the Mac and the phone alike
    /// and in the briefings the on-device model reads: its people's own
    /// name for their finest ("Salt Wardens"), or its kind and tier
    /// ("Spears V", "Lanterns").
    public func named(_ kind: UnitKind, tier: Int, of owner: Int) -> String {
        houses.indices.contains(owner) && tier == Unit.highestTier && kind == heritage(of: owner).signature
            ? heritage(of: owner).signatureTitle : kind.named(tier: tier)
    }

    /// A company as every line names it (`named(_:tier:of:)`).
    public func named(_ unit: Unit) -> String { named(unit.kind, tier: unit.tier, of: unit.owner) }

    /// Why a House can't take up a heritage, if it can't.
    func heritageRefusal(_ heritage: Heritage, for house: Int) -> RuleError? {
        guard heritage != self.heritage(of: house) else { return .alreadyOfHeritage }
        guard houses[house].heritage != nil else { return nil }
        let stock = houses[house].stock
        return stock.covers(Heritage.changeCost) ? nil : .shortOf(stock.shortfall(for: Heritage.changeCost))
    }

    /// A House takes up a heritage: the first time freely, after that for
    /// moonsalt.
    mutating func takeUp(_ heritage: Heritage, as house: Int) throws(RuleError) -> [GameEvent] {
        if let refusal = heritageRefusal(heritage, for: house) { throw refusal }
        if houses[house].heritage != nil { houses[house].stock.debit(Heritage.changeCost) }
        houses[house].heritage = heritage
        record(.seating, [house], "\(houses[house].title) takes up the ways of \(heritage.title).")
        return [.heritageTaken(house: house, heritage: heritage)]
    }
}

/// Where a realm's rounds begin, as its seed sets them: the heritage dealt
/// the first seat, and the kind of happening that opens the age.
struct Dealing: Codable, Equatable, Sendable {
    var firstHeritage: Int
    var firstHappening: Int

    init(seed: UInt64) {
        firstHeritage = Heritage.start(seed: seed)
        firstHappening = Happening.start(seed: seed)
    }
}
