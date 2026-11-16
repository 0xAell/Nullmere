/// What a find of the land is: a hamlet of free folk, or a barrow.
public enum FindKind: String, Codable, CaseIterable, Sendable, PlainCases {
    /// A few homes of free folk about a well.
    case hamlet
    /// An old grave open to the sky.
    case barrow

    /// What one is called, unnamed.
    public var title: String {
        switch self {
        case .hamlet: return "hamlet"
        case .barrow: return "barrow"
        }
    }
}
