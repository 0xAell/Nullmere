/// The kind of a holy site of the lake, and what it gives the side that holds it.
public enum ShrineKind: String, CaseIterable, Codable, Sendable, PlainCases {
    /// A well that holds the moon: the blows of its holders' companies fall harder.
    case moonwell
    /// A stone that never stirs in the wind: its holders' companies stand firmer.
    case stillStone
    /// An altar of moonsalt: its holders gather more from the land's sites.
    case saltAltar
    /// The Moonspire the age before raised, standing broken where it stood:
    /// its stones raise its holders' works for less, and sooner.
    case brokenSpire
    /// The stone in the heart of the Marches' Crown: each watch it is held,
    /// its holder's kingdom scores at the Frontier.
    case heartstone

    /// The kinds the lake raises as an age opens, in turn; the Broken
    /// Spire is only ever the last age's.
    public static let raised: [ShrineKind] = [.moonwell, .stillStone, .saltAltar]

    public var title: String {
        switch self {
        case .moonwell: return "Moonwell"
        case .stillStone: return "Still Stone"
        case .saltAltar: return "Salt Altar"
        case .brokenSpire: return "Broken Spire"
        case .heartstone: return "Heartstone"
        }
    }
}
