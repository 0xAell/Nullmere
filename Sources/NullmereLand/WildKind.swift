/// The hostile things of the far country, raised by the realm itself far
/// from every hold. They never march and take no hold; they stand where
/// they rose until some House strikes them down, and what falls with them
/// is stores for that House and lessons for its commander.
public enum WildKind: String, CaseIterable, Codable, Sendable, PlainCases {
    /// Pale husks that crawl out of the salt flats.
    case saltwights
    /// Outlaw bands of the blackwood.
    case reavers
    /// The restless dead of the barrows.
    case barrowkin
    /// Raiders come down from the Spine.
    case spineHunters
    /// The drowned, who walk the strand by night.
    case drowned

    public var title: String {
        switch self {
        case .saltwights: return "Saltwights"
        case .reavers: return "Blackwood Reavers"
        case .barrowkin: return "Barrowkin"
        case .spineHunters: return "Spine Hunters"
        case .drowned: return "the Drowned"
        }
    }

    /// Those that rise from a kind of ground.
    package static func of(_ terrain: Terrain) -> WildKind {
        switch terrain {
        case .saltFlat: return .saltwights
        case .blackwood: return .reavers
        case .barrow: return .barrowkin
        case .strand, .shallows, .still, .ford, .stream, .shoal: return .drowned
        case .greyfield, .spine: return .spineHunters
        }
    }

    /// Attack and defence at the first level.
    public var attack: Int {
        switch self {
        case .saltwights: return 4
        case .reavers: return 6
        case .barrowkin: return 5
        case .spineHunters: return 7
        case .drowned: return 5
        }
    }

    public var defense: Int {
        switch self {
        case .saltwights: return 4
        case .reavers: return 4
        case .barrowkin: return 7
        case .spineHunters: return 5
        case .drowned: return 5
        }
    }

    /// What falls with one of the first level.
    package var spoils: Stock {
        switch self {
        case .saltwights: return Stock(grain: 5, moonsalt: 6)
        case .reavers: return Stock(grain: 15, timber: 20)
        case .barrowkin: return Stock(stone: 25, moonsalt: 2)
        case .spineHunters: return Stock(grain: 20, stone: 10)
        case .drowned: return Stock(grain: 10, timber: 10, stone: 10, moonsalt: 2)
        }
    }
}
