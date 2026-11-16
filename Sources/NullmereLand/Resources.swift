/// The four resources of the shore. Grain, timber and stone are common;
/// moonsalt, the pale crust that forms where moonlight lies on the dead
/// water's edge, is rare and feeds every great work.
public enum Resource: String, CaseIterable, Codable, Sendable, PlainCases {
    case grain
    case timber
    case stone
    case moonsalt

    public var title: String {
        switch self {
        case .grain: return "Grain"
        case .timber: return "Timber"
        case .stone: return "Stone"
        case .moonsalt: return "Moonsalt"
        }
    }
}
