import NullmereLand

// What the rules make of the land, kept with them: what working a tile
// yields, a map as a House knows it, what a work does at its next level,
// a company's tiers, and stock as a line says it.

extension Terrain {
    /// What one worked tile yields each watch.
    public var yield: Stock {
        switch self {
        case .still, .shallows, .spine, .ford, .stream, .shoal: return .zero
        case .strand: return Stock(grain: 1)
        case .saltFlat: return Stock(moonsalt: 1)
        case .greyfield: return Stock(grain: 2)
        case .blackwood: return Stock(timber: 2)
        case .barrow: return Stock(stone: 2)
        }
    }
}

extension Feature {
    /// Added to the tile's yield when worked.
    public var yield: Stock {
        switch self {
        case .moonsaltBed: return Stock(moonsalt: 2)
        case .elderGrove: return Stock(timber: 4)
        case .stoneSeam: return Stock(stone: 4)
        case .darkLoam: return Stock(grain: 4)
        case .drownedRuin: return .zero
        }
    }
}

extension Tile {
    /// What a hold gets from working this tile each watch.
    public var yield: Stock {
        terrain.yield + (feature?.yield ?? .zero)
    }
}

extension WorldMap {
    /// This map as one who has explored none of it knows it: every tile as
    /// `GameState.unknown` tells it.
    public var unexplored: WorldMap { unexplored(as: GameState.unknown) }

    /// This map as one who has explored the tiles `known` marks knows it:
    /// `unexplored`, this map as `unexplored` gives it, with each tile known
    /// as it is here. Worked out from the tiles known alone, so a House
    /// that has explored a little of a wide lake costs a little.
    func known(by known: Explored, from unexplored: WorldMap) -> WorldMap {
        self.known(seen: { body in known.forEachSeen(body) }, from: unexplored)
    }
}

/// A stock as a line says it, its stores listed: "40 grain and 5 stone",
/// its thousands set apart, the empty ones left out.
extension Stock {
    public var listedSaid: String {
        listed(Resource.allCases.filter { self[$0] > 0 }.map { "\(GameState.counted(self[$0])) \($0.title.lowercased())" })
    }
}

extension BuildingKind {
    /// One line on what the next level does.
    public func effect(atLevel level: Int, isSeat: Bool = false) -> String {
        switch self {
        case .granary, .sawpit, .quarry, .saltworks:
            let resource = boostedResource!.title.lowercased()
            return "+\(BuildingKind.yieldBoostPerLevel * level)% to the \(resource) this hold yields"
        case .musterHall:
            var gains = UnitKind.allCases.filter { $0.requiredMuster == level }.map(\.title)
            // The first three halls open their tiers with their companies,
            // the fourth its tier with the Mangonels, the fifth its tier alone.
            if level > Hold.fasterTrainingAt {
                gains.append("companies of war of tier \(BuildingKind.numeral(level)), once studied")
            }
            if level == Hold.fasterTrainingAt {
                gains.append("all but Lanterns a watch sooner")
            }
            return gains.isEmpty ? "No new company" : "Trains " + gains.joined(separator: "; ")
        case .walls:
            return "Ward \(Hold.maximumWard(wallLevel: level, isSeat: isSeat)), garrison +\(Hold.garrisonBonus(wallLevel: level))% defence"
        case .beacon:
            let wider = Hold.territoryRadius(isSeat: isSeat, beaconLevel: level) > Hold.territoryRadius(isSeat: isSeat, beaconLevel: level - 1)
            let warns = ["warns of marches bound here", "and tells whose and what", "and how many, and when"][min(max(level, 1), 3) - 1]
            return "Sight \(Hold.sight(beaconLevel: level)); \(warns)" + (wider ? "; its land reaches a tile further" : "")
        case .infirmary:
            return "Beds for \(Hold.beds(infirmaryLevel: level)) of the House's fallen companies of war"
        case .archive:
            let circle = min(level, BuildingKind.deepestCircle)
            return "Studies of the \(ordinal(circle)) circle; every study \(GameState.archivePace * level)% sooner"
        case .moonspire:
            return level == maxLevel ? "Ascendancy over the lake" : "Stage \(level) of \(maxLevel)"
        case .forge:
            let finest = GearQuality.forged(atLevel: level)?.title.lowercased() ?? "no"
            let thrift = GameState.forgeThrift * (level - 1)
            return "Forges \(finest) gear of the three sets" + (thrift > 0 ? ", for \(thrift)% fewer makings" : "")
        case .wayhouse:
            let kinds = UnitKind.allCases.filter { BuildingKind.roadLevel(for: $0) == level }.map(\.title)
            return listed(kinds) + " of the House a step further every watch"
        case .lodge:
            return "Every work of the House \(GameState.lodgePace * level)% sooner"
        }
    }
}

extension UnitKind {
    /// Its highest tier: V for a company of war, I for the rest.
    public var highestTier: Int { hasTiers ? Unit.highestTier : 1 }

    /// What a company of this kind costs at a tier, before its House's
    /// studies: dearer with each tier, and moonsalt from the third.
    public func cost(tier: Int) -> Stock {
        let index = Unit.tierIndex(tier, of: self)
        var price = cost.scaled(percent: Unit.tierCost[index])
        price.moonsalt += Unit.tierMoonsalt[index]
        return price
    }

    /// Attack at a tier, as a keeper reads it, rounded.
    public func attack(tier: Int) -> Int {
        (attack * Unit.tierMight[Unit.tierIndex(tier, of: self)] + 50) / 100
    }

    /// Defence at a tier, as a keeper reads it, rounded.
    public func defense(tier: Int) -> Int {
        (defense * Unit.tierMight[Unit.tierIndex(tier, of: self)] + 50) / 100
    }

    /// Grain a company of this tier eats each watch.
    public func upkeep(tier: Int) -> Int {
        upkeep == 0 ? 0 : Unit.tierUpkeep[Unit.tierIndex(tier, of: self)]
    }

    /// Watches a company of this tier takes to train, before a Muster Hall
    /// or studies hasten it.
    public func trainWatches(tier: Int) -> Int {
        trainWatches + Unit.tierWatches[Unit.tierIndex(tier, of: self)]
    }
}

extension Hold {
    /// Watches a company takes to train at this hold, before its House's
    /// studies hasten it.
    public func trainingWatches(for kind: UnitKind, tier: Int = 1) -> Int {
        let watches = kind.trainWatches(tier: tier)
        return watches - (level(.musterHall) >= Hold.fasterTrainingAt && watches > 1 ? 1 : 0)
    }
}
