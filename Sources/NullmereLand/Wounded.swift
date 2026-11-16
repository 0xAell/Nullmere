/// A company of war carried from the field to an Infirmary: kept in one of
/// its beds until its House pays for its healing, and lost if its hold
/// falls first.
public struct Wounded: Codable, Equatable, Sendable {
    public let kind: UnitKind
    public let tier: Int
    /// The battles it had lived through: it rises with its rank.
    public let experience: Int
    /// The watch it was carried in.
    public let since: Int
    /// Its healing is paid for: it rises whole as the watch turns.
    public package(set) var healing: Bool

    public init(kind: UnitKind, tier: Int, experience: Int, since: Int, healing: Bool = false) {
        self.kind = kind
        self.tier = tier
        self.experience = experience
        self.since = since
        self.healing = healing
    }
}
