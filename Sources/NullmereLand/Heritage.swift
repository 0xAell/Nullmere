/// A House's heritage: the people of the lake it comes of, each with two
/// strengths of its own and a company of its own at the fifth tier. As an
/// age begins the realm deals every seat one, evenly round the lake; a
/// keeper may take up another, the first time freely and after that for
/// moonsalt.
public enum Heritage: String, CaseIterable, Codable, Sendable, PlainCases {
    /// Of the salt flats: moonsalt, and wards that mend.
    case saltborn
    /// Of the reeds and the shallows: bows, and far sight.
    case fenfolk
    /// Of the old woods: timber, and riders.
    case blackwood
    /// Of the spine's quarries: stone, and spears that hold.
    case spinewardens
    /// Of the barrows: commanders, and studies.
    case moundClans
    /// Of the strand: grain, and gathering.
    case strandfolk

    /// The kind of its own company, at the fifth tier.
    public var signature: UnitKind {
        switch self {
        case .saltborn, .spinewardens: return .spear
        case .fenfolk, .strandfolk: return .bow
        case .blackwood, .moundClans: return .rider
        }
    }
}
