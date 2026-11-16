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

    /// Its people, as a line names them: "the Saltborn".
    public var title: String {
        switch self {
        case .saltborn: return "the Saltborn"
        case .fenfolk: return "the Fenfolk"
        case .blackwood: return "the Blackwood Kin"
        case .spinewardens: return "the Spinewardens"
        case .moundClans: return "the Mound Clans"
        case .strandfolk: return "the Strandfolk"
        }
    }

    /// Its people as a heading names them: "The Saltborn".
    public var name: String { title.prefix(1).uppercased() + title.dropFirst() }

    /// Who its people are, in a line.
    public var origin: String {
        switch self {
        case .saltborn: return "Salt-rakers of the white flats, who read the moon in the brine"
        case .fenfolk: return "Reed-cutters of the shallows, who see far over still water"
        case .blackwood: return "Woodwards of the old trees, who ride the dark paths"
        case .spinewardens: return "Quarriers of the spine, who hold a line like its rock"
        case .moundClans: return "Keepers of the barrows, who forget no lesson of the dead"
        case .strandfolk: return "Fisher-farmers of the strand, who bring in every harvest"
        }
    }

    /// Its two strengths, in words.
    public var strengths: [String] {
        switch self {
        case .saltborn: return ["half again the moonsalt from its holds", "its wards mend half again as fast"]
        case .fenfolk: return ["its Bows strike a tenth harder", "its companies see a tile further"]
        case .blackwood: return ["a quarter more timber from its holds", "its Riders strike a tenth harder"]
        case .spinewardens: return ["a quarter more stone from its holds", "its Spears stand a tenth firmer"]
        case .moundClans: return ["its commanders learn a quarter faster", "its studies are done a tenth sooner"]
        case .strandfolk: return ["a quarter more grain from its holds", "a fifth more gathered at the land's sites"]
        }
    }

    /// The kind of its own company, at the fifth tier.
    public var signature: UnitKind {
        switch self {
        case .saltborn, .spinewardens: return .spear
        case .fenfolk, .strandfolk: return .bow
        case .blackwood, .moundClans: return .rider
        }
    }

    /// Its own company's name.
    public var signatureTitle: String {
        switch self {
        case .saltborn: return "Salt Wardens"
        case .fenfolk: return "Reed Bows"
        case .blackwood: return "Wood Riders"
        case .spinewardens: return "Spine Guard"
        case .moundClans: return "Barrow Riders"
        case .strandfolk: return "Strand Bows"
        }
    }

    /// What its own company strikes and stands beyond others of its kind
    /// and tier, in percent.
    public static let signatureEdge = 5
    /// What taking up another heritage costs, once one has been taken up.
    public static let changeCost = Stock(moonsalt: 30)

}
