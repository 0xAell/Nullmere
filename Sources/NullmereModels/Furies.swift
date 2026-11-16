/// How a commander's skill looks as it fires: a ward of pale light, fire
/// thrown out, shafts of light falling, a ring of gold, or the ground
/// breaking.
public enum FuryLook: String, CaseIterable, Sendable {
    case ward, blaze, volley, ring, quake

    /// The light it gives the ground about it, at its brightest.
    public var glow: Vec3 {
        switch self {
        case .ward: return Vec3(0.9, 1.3, 2.2)
        case .blaze: return Vec3(2.6, 1.2, 0.4)
        case .volley: return Vec3(2.0, 1.8, 1.3)
        case .ring: return Vec3(2.0, 1.8, 1.1)
        case .quake: return Vec3(1.2, 0.8, 0.5)
        }
    }
}
