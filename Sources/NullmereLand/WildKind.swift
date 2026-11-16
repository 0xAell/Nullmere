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
}
