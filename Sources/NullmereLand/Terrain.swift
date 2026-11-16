/// The ground of the basin around the Nullmere, from the dead water outward
/// to the mountains that wall it in.
public enum Terrain: String, CaseIterable, Codable, Sendable, PlainCases {
    /// The open lake: black, deep and perfectly still. Nothing crosses it.
    case still
    /// Dead shallows near the shore. Wadeable, slowly; nothing grows or lives here.
    case shallows
    /// Pale shingle at the water's edge.
    case strand
    /// White crust where moonsalt forms.
    case saltFlat
    /// Grey grassland, the basin's farmland.
    case greyfield
    /// Dark old forest.
    case blackwood
    /// Low hills full of old graves and good stone.
    case barrow
    /// The mountains that ring the basin. Impassable.
    case spine
    /// The Moonford: the lake's bed laid bare along the moon's road while
    /// the moon is full, shingle under a skin of water from shore to shore.
    /// Walked a step a move; nothing is raised on it, for the water comes
    /// back over it as the moon wanes.
    case ford
    /// A stream running from the Spine down to the lake, cold and quick
    /// between steep banks: no company wades it, and nothing is raised on
    /// it. It is crossed at its shoals.
    case stream
    /// Where a stream runs wide and shallow over stones: its ford, waded a
    /// step at a time, and a poor place to stand and fight.
    case shoal

    // These ask by case, not `==`, which for an enum of strings can come
    // to comparing the strings: the search for ways asks them of every
    // tile it looks at.
    public var isWater: Bool {
        switch self {
        case .still, .shallows, .ford, .stream, .shoal: return true
        case .strand, .saltFlat, .greyfield, .blackwood, .barrow, .spine: return false
        }
    }

    /// Whether units can enter it.
    public var isPassable: Bool {
        switch self {
        case .still, .spine, .stream: return false
        case .shallows, .strand, .saltFlat, .greyfield, .blackwood, .barrow, .ford, .shoal: return true
        }
    }

    /// Whether a hold can be founded on it.
    public var isSettleable: Bool {
        switch self {
        case .strand, .saltFlat, .greyfield, .blackwood, .barrow: return true
        case .still, .shallows, .spine, .ford, .stream, .shoal: return false
        }
    }
}

/// Something notable on a tile.
public enum Feature: String, CaseIterable, Codable, Sendable, PlainCases {
    /// A thick bed of moonsalt.
    case moonsaltBed
    /// Ancient trees, vast and dense.
    case elderGrove
    /// A seam of cut-ready stone.
    case stoneSeam
    /// Black, rich soil.
    case darkLoam
    /// A half-sunken ruin of whoever was here before. The first to reach it
    /// finds what remains.
    case drownedRuin
}
