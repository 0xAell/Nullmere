import Foundation

extension Terrain {
    /// Its place among the terrains: the case it is, as it is held, which
    /// is its place in the order they are told in.
    public var code: UInt8 { caseNumber }
}

extension Feature {
    /// Its place among the features: the case it is, as it is held, which
    /// is its place in the order they are told in.
    public var code: UInt8 { caseNumber }
}

/// One tile of the world.
public struct Tile: Codable, Equatable, Sendable {
    public var terrain: Terrain
    public var feature: Feature?
    /// 0...100, for shading only; it never affects the rules.
    public var relief: Int

    public init(terrain: Terrain, feature: Feature? = nil, relief: Int = 0) {
        self.terrain = terrain
        self.feature = feature
        self.relief = relief
    }
}

/// The hexagonal world: every hex within `radius` of the origin, stored row
/// by row so a hex's index is computed rather than looked up.
public struct WorldMap: Equatable, Sendable {

    public let radius: Int
    public private(set) var tiles: [Tile]
    /// Index of the first hex in each row, from `-radius` to `radius`.
    private let rowStarts: [Int]
    /// Every hex in index order, laid out once.
    private let hexList: [Hex]
    /// Each tile's neighbours' indices, six to a tile in the order of
    /// `Hex.directions`, -1 past the world's edge: laid out once, for the
    /// generator's searches over the land.
    package let neighbours: [Int32]
    /// The deepest of its open water, kept while the ground is as it is:
    /// shared by the map's copies, and let go of by any copy whose ground
    /// changes.
    package private(set) var deep = Deepest()

    public init(radius: Int, fill: Tile) {
        precondition(radius >= 1, "radius must be positive")
        self.radius = radius
        self.tiles = Array(repeating: fill, count: WorldMap.count(radius: radius))
        self.rowStarts = WorldMap.rowStarts(radius: radius)
        hexList = WorldMap.hexes(radius: radius)
        neighbours = WorldMap.neighbours(radius: radius, of: hexList)
    }

    // The rest of a map is laid out from its radius.
    public static func == (a: WorldMap, b: WorldMap) -> Bool {
        a.radius == b.radius && a.tiles == b.tiles
    }

    private static func rowStarts(radius: Int) -> [Int] {
        var starts: [Int] = []
        var start = 0
        for row in -radius...radius {
            starts.append(start)
            start += 2 * radius + 1 - abs(row)
        }
        return starts
    }

    /// Number of hexes within `radius` of the origin.
    public static func count(radius: Int) -> Int {
        3 * radius * (radius + 1) + 1
    }

    public var count: Int { tiles.count }

    public func contains(_ hex: Hex) -> Bool {
        // A hex of the world has each coordinate within the radius. Reject
        // anything past that by comparison alone, before `length`: a hex
        // from a keeper's order carries client-chosen coordinates, and ones
        // near the limits of Int would overflow the sum in `Hex.distance`.
        guard hex.q >= -radius, hex.q <= radius, hex.r >= -radius, hex.r <= radius else { return false }
        return hex.length <= radius
    }

    /// The tile index of a hex, or nil outside the world.
    public func index(of hex: Hex) -> Int? {
        guard contains(hex) else { return nil }
        let r = hex.r
        let qMin = max(-radius, -r - radius)
        return rowStarts[r + radius] + hex.q - qMin
    }

    /// Every hex in index order.
    public var hexes: [Hex] { hexList }

    private static func neighbours(radius: Int, of hexes: [Hex]) -> [Int32] {
        let starts = rowStarts(radius: radius)
        var neighbours: [Int32] = []
        neighbours.reserveCapacity(hexes.count * 6)
        for hex in hexes {
            for direction in Hex.directions {
                let next = hex + direction
                guard next.q >= -radius, next.q <= radius, next.r >= -radius, next.r <= radius, next.length <= radius else {
                    neighbours.append(-1)
                    continue
                }
                neighbours.append(Int32(starts[next.r + radius] + next.q - max(-radius, -next.r - radius)))
            }
        }
        return neighbours
    }

    private static func hexes(radius: Int) -> [Hex] {
        var result: [Hex] = []
        result.reserveCapacity(count(radius: radius))
        for r in -radius...radius {
            let qMin = max(-radius, -r - radius)
            let qMax = min(radius, -r + radius)
            for q in qMin...qMax {
                result.append(Hex(q, r))
            }
        }
        return result
    }

    public subscript(hex: Hex) -> Tile? {
        guard let index = index(of: hex) else { return nil }
        return tiles[index]
    }

    public subscript(index: Int) -> Tile {
        get { tiles[index] }
        set { set(index: index, newValue) }
    }

    package mutating func set(index: Int, _ tile: Tile) {
        tiles[index] = tile
        // What its other copies still keep of their ground is theirs.
        if isKnownUniquelyReferenced(&deep) { deep.clear() } else { deep = Deepest() }
    }

    public mutating func set(_ hex: Hex, _ tile: Tile) {
        guard let index = index(of: hex) else { return }
        set(index: index, tile)
    }

    public func neighbors(of hex: Hex) -> [Hex] {
        hex.neighbors.filter(contains)
    }
}

/// The open water farthest from any shore, and how far: where the full
/// moon's reflection lies.
public struct DeepWater: Codable, Equatable, Sendable {
    public let hex: Hex
    public let depth: Int

    public init(hex: Hex, depth: Int) {
        self.hex = hex
        self.depth = depth
    }
}

extension WorldMap {
    /// The hex of open water farthest from any shore; of equals, the
    /// nearest the middle of the world. Nil when there is no open water.
    public func deepestWater() -> DeepWater? {
        if let kept = deep.water { return kept }
        let found = seekDeepestWater()
        deep.keep(found)
        return found
    }

    /// The deepest water, sought through every tile of the lake.
    package func seekDeepestWater() -> DeepWater? {
        // Hexes of open water, by their distance from anything that isn't.
        var depth = [Int](repeating: -1, count: count)
        var frontier: [Int] = []
        for index in 0..<count where self[index].terrain != .still {
            depth[index] = 0
            frontier.append(index)
        }
        let hexes = self.hexes
        var head = 0
        while head < frontier.count {
            let index = frontier[head]
            head += 1
            for neighbour in neighbors(of: hexes[index]) {
                guard let next = self.index(of: neighbour), depth[next] < 0 else { continue }
                depth[next] = depth[index] + 1
                frontier.append(next)
            }
        }
        guard let deepest = depth.indices.max(by: { a, b in
            (depth[a], -hexes[a].length, -a) < (depth[b], -hexes[b].length, -b)
        }), depth[deepest] > 0 else { return nil }
        return DeepWater(hex: hexes[deepest], depth: depth[deepest])
    }
}
