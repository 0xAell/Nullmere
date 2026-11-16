/// Who a House can send out from its holds.
public enum UnitKind: String, CaseIterable, Codable, Sendable, PlainCases {
    /// A scout carrying light into the dark country.
    case lantern
    case spear
    case bow
    case rider
    /// Engines of timber and rope that hurl stones from two tiles away:
    /// three times as hard as any other company on walls and wards, slow
    /// to learn and soft in the field, and no riders' match.
    case mangonel
    /// Settlers who found a new hold where they stand.
    case founder

    public var isMilitary: Bool { self != .lantern && self != .founder }
}
