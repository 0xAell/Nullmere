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
}
