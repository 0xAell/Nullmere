/// The shape of the black water. Each age of the realm lies on a lake of
/// its own shape, in turn.
public enum Lake: String, Codable, CaseIterable, Sendable, PlainCases {
    /// One round lake: the Nullmere as the first age knew it.
    case round
    /// Two lakes side by side, with a neck of land between.
    case twin
    /// A crescent, the land pushing in from one shore.
    case crescent
    /// A wider lake, crowded with drowned isles.
    case isles
    /// The Frontier's own: four meres at its quarters, where the realms'
    /// shores reach it, and the land between them all to be fought over.
    case marches

    public var title: String {
        switch self {
        case .round: return "the Nullmere"
        case .twin: return "the Twin Waters"
        case .crescent: return "the Sickle"
        case .isles: return "the Drowned Isles"
        case .marches: return "the Marches"
        }
    }

    /// The lakes a realm's ages lie on, in turn; the Marches are the
    /// Frontier's alone.
    public static let ofTheRealm: [Lake] = [.round, .twin, .crescent, .isles]

    /// The lake of an age of the realm: the round lake first, then each
    /// shape in turn.
    public static func of(age: Int) -> Lake {
        ofTheRealm[(max(age, 1) - 1) % ofTheRealm.count]
    }
}
