import NullmereLand

// What the rules make of the land, kept with them: what working a tile
// yields, and a map as a House knows it.

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
