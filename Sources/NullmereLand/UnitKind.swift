/// Who a House can send out from its holds.
public enum UnitKind: String, CaseIterable, Codable, Sendable, PlainCases {
    /// A scout carrying light into the dark country.
    case lantern
    case spear
    case bow
    case rider
    /// Engines of timber and rope that hurl stones from two tiles away:
    /// three times as hard as any other company on walls and wards, slow
    /// to learn and soft in the field, and no riders' match.
    case mangonel
    /// Settlers who found a new hold where they stand.
    case founder

    /// Its place among the kinds, for what is kept kind by kind in a list.
    package var ordinal: Int {
        switch self {
        case .lantern: return 0
        case .spear: return 1
        case .bow: return 2
        case .rider: return 3
        case .mangonel: return 4
        case .founder: return 5
        }
    }

    /// How many kinds there are.
    package static let count = allCases.count

    public var title: String {
        switch self {
        case .lantern: return "Lanterns"
        case .spear: return "Spears"
        case .bow: return "Bows"
        case .rider: return "Riders"
        case .mangonel: return "Mangonels"
        case .founder: return "Founders"
        }
    }

    public var attack: Int {
        switch self {
        case .lantern: return 1
        case .spear: return 6
        case .bow: return 5
        case .rider: return 8
        case .mangonel: return 4
        case .founder: return 0
        }
    }

    public var defense: Int {
        switch self {
        case .lantern: return 2
        case .spear: return 7
        case .bow: return 4
        case .rider: return 5
        case .mangonel: return 3
        case .founder: return 1
        }
    }

    public var movement: Int {
        switch self {
        case .lantern, .rider: return 4
        case .spear, .bow, .mangonel, .founder: return 2
        }
    }

    public var sight: Int {
        switch self {
        case .lantern: return 3
        default: return 2
        }
    }

    /// Bows and Mangonels strike from two tiles away and take no blow in return.
    public var range: Int { self == .bow || self == .mangonel ? 2 : 1 }

    public var isMilitary: Bool { attack > 1 }

    /// Military units that can take a hold once its ward falls.
    public var canCapture: Bool { self == .spear || self == .rider }

    /// Muster Hall level needed to train this; zero needs none.
    public var requiredMuster: Int {
        switch self {
        case .lantern, .founder: return 0
        case .spear: return 1
        case .bow: return 2
        case .rider: return 3
        case .mangonel: return 4
        }
    }

    public var cost: Stock {
        switch self {
        case .lantern: return Stock(grain: 15, timber: 10)
        case .spear: return Stock(grain: 25, timber: 15, stone: 10)
        case .bow: return Stock(grain: 25, timber: 30)
        case .rider: return Stock(grain: 40, timber: 15, stone: 10, moonsalt: 8)
        case .mangonel: return Stock(grain: 20, timber: 50, stone: 30, moonsalt: 6)
        case .founder: return Stock(grain: 60, timber: 40, stone: 30)
        }
    }

    public var trainWatches: Int {
        switch self {
        case .lantern: return 1
        case .spear, .bow: return 2
        case .rider, .mangonel, .founder: return 3
        }
    }

    /// Grain eaten each watch.
    public var upkeep: Int { self == .lantern ? 0 : 1 }

    /// Percent bonus when fighting riders.
    public var bonusAgainstRiders: Int { self == .spear ? 50 : 0 }

    /// Percent bonus when fighting Mangonels: riders fall on them.
    public var bonusAgainstMangonels: Int { self == .rider ? 50 : 0 }

    /// What its blows take from walls and wards, in percent of what
    /// another company's of its strength would.
    public var wardPercent: Int { self == .mangonel ? 300 : 100 }

    // MARK: Tiers

    /// Whether it musters in tiers, I to V: the companies of war do;
    /// Lanterns and Founders muster in one.
    public var hasTiers: Bool { self == .spear || self == .bow || self == .rider || self == .mangonel }

    /// A company of this kind at a tier, as every line names it, on the
    /// Mac and the phone alike: "Spears II", but "Lanterns" and
    /// "Founders", who muster in one and have no tier to tell.
    public func named(tier: Int) -> String { hasTiers ? "\(title) \(BuildingKind.numeral(tier))" : title }

    /// The Muster Hall level a tier of this kind needs: the kind's own, and
    /// for a tier beyond the first, as high as the tier.
    public func requiredMuster(tier: Int) -> Int {
        tier <= 1 ? requiredMuster : max(requiredMuster, tier)
    }
}
