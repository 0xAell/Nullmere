
/// A House's settlement: its seat, or a hold founded later. A hold works
/// the land around it, builds, trains, and has a ward that attackers must
/// break before they can take it.
public struct Hold: Codable, Equatable, Identifiable, Sendable {
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

        /// The tier it musters at.
        public var musteredTier: Int { tier ?? 1 }
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

    // Written in a fixed order, as a dictionary would be in any order: the
    // steward sends a keeper's view only when its words change.
    private enum CodingKeys: String, CodingKey {
        case id, name, owner, position, isSeat, levels, project, training, ward, struck, foundedWatch, wounded, places, raisedAnew
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(owner, forKey: .owner)
        try container.encode(position, forKey: .position)
        try container.encode(isSeat, forKey: .isSeat)
        var built = container.nestedUnkeyedContainer(forKey: .levels)
        for kind in BuildingKind.allCases {
            if let level = levels[kind] {
                try built.encode(kind)
                try built.encode(level)
            }
        }
        try container.encodeIfPresent(project, forKey: .project)
        try container.encodeIfPresent(training, forKey: .training)
        try container.encode(ward, forKey: .ward)
        try container.encode(struck, forKey: .struck)
        try container.encode(foundedWatch, forKey: .foundedWatch)
        try container.encodeIfPresent(wounded, forKey: .wounded)
        if let places {
            var set = container.nestedUnkeyedContainer(forKey: .places)
            for kind in BuildingKind.allCases {
                if let place = places[kind] {
                    try set.encode(kind)
                    try set.encode(place)
                }
            }
        }
        try container.encodeIfPresent(raisedAnew, forKey: .raisedAnew)
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

    /// Where a work stands if its keeper has set it.
    public func place(of kind: BuildingKind) -> Int? {
        places?[kind]
    }
}
