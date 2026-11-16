/// What a hold can build. Each building rises through levels; every level
/// costs more and takes longer, and each completed level adds its effect.
public enum BuildingKind: String, CaseIterable, Codable, Sendable, PlainCases {
    case granary
    case sawpit
    case quarry
    case saltworks
    case musterHall
    case walls
    case beacon
    /// Where a House's fallen companies of war are carried from the field
    /// and laid in its beds, to be healed for stores rather than lost.
    case infirmary
    /// Where a House's studies are pursued: the higher it stands, the
    /// deeper the circle of studies open to the House, and the sooner each
    /// is done.
    case archive
    /// The great work: a white tower of moonsalt and stone. A House that
    /// raises it to its fifth level is ascendant over the whole lake.
    case moonspire
    /// Where a House's smiths work the makings its companies bring in into
    /// gear of its own sets for its commanders: the higher it stands, the
    /// finer the gear and the fewer the makings it takes.
    case forge
    /// Where a House's roads begin: post-riders and fresh horses, guides
    /// and maps of the ways. Each level sends one more kind of the House's
    /// companies a step further every watch. Stewards raise none.
    case wayhouse
    /// Where a House's masons are trained and its works drawn out before a
    /// stone is laid: each level raises every work of the House sooner.
    /// Stewards raise none.
    case lodge

    public var maxLevel: Int {
        switch self {
        case .beacon: return 3
        default: return 5
        }
    }

    /// Watches it takes to raise this building to `level`.
    public func buildWatches(toLevel level: Int) -> Int {
        precondition((1...maxLevel).contains(level), "level out of range")
        return self == .moonspire ? 3 + level * 3 : 1 + level
    }
}
