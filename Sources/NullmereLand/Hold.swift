
/// A House's settlement: its seat, or a hold founded later. A hold works
/// the land around it, builds, trains, and has a ward that attackers must
/// break before they can take it.
public struct Hold: Equatable, Identifiable, Sendable {
    public struct Project: Codable, Equatable, Sendable {
        public var kind: BuildingKind
        public var targetLevel: Int
        public var watchesLeft: Int
        /// The allied Houses that have helped it, if any.
        public var helpers: [Int]? = nil
        /// The watches it was to take as it was begun, its House's hastening
        /// counted (`GameState.buildWatches`); absent in older saves, where
        /// the work's own length stands in.
        public var watches: Int? = nil

        public init(kind: BuildingKind, targetLevel: Int, watchesLeft: Int, helpers: [Int]? = nil, watches: Int? = nil) {
            self.kind = kind
            self.targetLevel = targetLevel
            self.watchesLeft = watchesLeft
            self.helpers = helpers
            self.watches = watches
        }

        /// How much of it is done, from nothing as it was begun to the
        /// whole: its watches bring it on, and so do its allies' help and
        /// hourglasses, which take watches off it.
        public var progress: Double {
            let whole = max(watches ?? kind.buildWatches(toLevel: targetLevel), watchesLeft, 1)
            return 1 - Double(watchesLeft) / Double(whole)
        }
    }

    public struct Training: Codable, Equatable, Sendable {
        public var kind: UnitKind
        public var watchesLeft: Int
        /// The tier it musters at; absent for the first, as in older saves.
        public var tier: Int?
        /// The allied Houses that have helped it, if any.
        public var helpers: [Int]?

        public init(kind: UnitKind, watchesLeft: Int, tier: Int? = nil) {
            self.kind = kind
            self.watchesLeft = watchesLeft
            self.tier = tier.flatMap { $0 > 1 ? $0 : nil }
            self.helpers = nil
        }
    }

    public let id: Int
    public var name: String
    public var owner: Int
    /// Where it stands: where it was founded, or, a seat raised anew,
    /// where its keeper raised it.
    public package(set) var position: Hex
    public var isSeat: Bool
    public var levels: [BuildingKind: Int]
    public var project: Project?
    public var training: Training?
    public var ward: Int
    /// Struck this watch, so its ward doesn't recover.
    public var struck: Bool
    public let foundedWatch: Int
    /// Its House's companies of war carried here from the field, in the
    /// beds of its Infirmary until they are healed; absent while none are.
    public var wounded: [Wounded]?
    /// Where its keeper has set its works round the keep, each by its
    /// place; absent until one is set, the works then standing where the
    /// hold's ground suits them.
    public var places: [BuildingKind: Int]?
    /// The watch its keeper last raised it anew elsewhere; absent if never.
    public package(set) var raisedAnew: Int?

    public init(id: Int, name: String, owner: Int, position: Hex, isSeat: Bool, foundedWatch: Int) {
        self.id = id
        self.name = name
        self.owner = owner
        self.position = position
        self.isSeat = isSeat
        self.levels = [:]
        self.project = nil
        self.training = nil
        self.ward = Hold.maximumWard(wallLevel: 0, isSeat: isSeat)
        self.struck = false
        self.foundedWatch = foundedWatch
        self.wounded = nil
    }

    public func level(_ kind: BuildingKind) -> Int {
        levels[kind] ?? 0
    }

    public var maximumWard: Int { Hold.maximumWard(wallLevel: level(.walls), isSeat: isSeat) }

    public static func maximumWard(wallLevel: Int, isSeat: Bool = false) -> Int {
        30 + 30 * wallLevel + (isSeat ? 20 : 0)
    }
}

extension Hold {
    /// How many places a hold's works may be set in round its keep: twelve
    /// about it, and six further out.
    public static let placeCount = 18
}
