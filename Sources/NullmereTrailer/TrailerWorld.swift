import Foundation
import NullmereLand
import NullmereLive
import NullmereLiveStage
import NullmereModels
import NullmereRealm
import NullmereWorld

/// The world the trailer is shot in: the rebuilt realm about its lake, a
/// dozen players' cities about the lake country's shore, raised from the
/// twenty-fifth Keep down to the third, as the realm's own rules keep them
/// (`realm/tests/trailer_rows.rs` writes the rows, kept as
/// TrailerRows.json). One city is shown raised whole, its Moonspire
/// crowned, for the trailer's heart; another's Moonspire at its third
/// stage, its crane at work; and a city of another player walled in stone,
/// for the heart's to besiege. The realm itself is left as it was made:
/// those three are dressed only as the trailer draws them.
public struct TrailerWorld {
    /// The land, the window of the realm about the heart.
    public let map: WorldMap
    /// Every city as the trailer draws it, the two seats and the besieged
    /// dressed.
    public let holds: [Hold]
    public let relief: Relief
    public let terrain: TerrainMesh
    public let stage: WorldStage
    /// The players' colours by sigil, as the renderer reads them.
    public let houses: [Vec4]
    /// The city at the trailer's heart, every work raised whole.
    public let seat: Hold
    /// Another player's city, its Moonspire rising.
    public let rising: Hold
    /// A great city for the town's shot, and one on the shore for the rain.
    public let town: Hold
    public let shore: Hold
    /// Another player's city near the heart, walled in stone, under siege.
    public let besieged: Hold
    /// The land's furniture, laid out once.
    public let furniture: [ModelBatch]
    /// The ways the carts go between neighbouring cities.
    public let ways: [WorldStage.Way]
    /// The sites gathered from and the barrows of the Unquiet, where they lie.
    public let sites: [(store: Resource, position: Hex)]
    public let lairs: [(kind: WildKind, position: Hex)]
    /// The land's tiles as the world's shader takes them, all of it known.
    public let tiles: [UInt8]

    /// How far about the heart the trailer's land runs.
    public static let radius = 26

    /// The rows the trailer's world is read from, as a client reads them.
    public static func rows() -> [String: [[JSONValue]]] {
        guard let url = Bundle.module.url(forResource: "TrailerRows", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rows = try? JSONDecoder().decode([String: [[JSONValue]]].self, from: data) else { return [:] }
        return rows
    }

    public init(houses: [Vec4], rows: [String: [[JSONValue]]] = TrailerWorld.rows()) {
        let live = LiveWorld(snapshot: rows)
        // The heart: the city with the greatest Keep.
        let greatest = live.cities.values.max { ($0.keep, -Int($0.id)) < ($1.keep, -Int($1.id)) }
        // About the lake, as the trailer's shots stand: the cities ring its
        // shore.
        let window = LiveWindow(world: live, centre: LiveHex(q: 0, r: 0), radius: TrailerWorld.radius)
        let map = window.map
        let sights = window.holds(in: live, colours: houses, at: 0)
        let found = sights.map(\.hold)
        let heartID = greatest.map { Int($0.id) }

        var heart = found.first { $0.id == heartID } ?? found.first ?? Hold(id: 0, name: "", owner: 0, position: Hex(0, 0), isSeat: true, foundedWatch: 0)
        for kind in BuildingKind.allCases {
            heart.levels[kind] = kind.maxLevel
        }
        heart.project = nil
        heart.training = nil
        // Another player's city, as near the heart as any, its Moonspire at
        // its third stage and its works well raised.
        let others = found.filter { $0.isSeat && $0.owner != heart.owner }
        var second = others.min { ($0.position.distance(to: heart.position), $0.id) < ($1.position.distance(to: heart.position), $1.id) } ?? heart
        if second.id != heart.id {
            for kind in BuildingKind.allCases where kind != .moonspire {
                second.levels[kind] = max(second.level(kind), min(kind.maxLevel, 3))
            }
            second.levels[.moonspire] = 3
            second.project = nil
        }
        var dressed = [heart.id: heart, second.id: second]
        let drawn = found.map { dressed[$0.id] ?? $0 }
        self.map = map
        self.houses = houses
        let relief = Relief(map: map, origin: Hex(window.centre.q, window.centre.r))
        self.relief = relief
        terrain = TerrainMesh(relief: relief)
        stage = WorldStage(map: map, relief: relief)
        seat = heart
        rising = second
        // The town: the city with the most raised, other than the two seats.
        let rest = drawn.filter { $0.id != heart.id && $0.id != second.id }
        func raised(_ hold: Hold) -> Int { hold.levels.values.reduce(0, +) }
        let great = rest.max { (raised($0), -$0.id) < (raised($1), -$1.id) } ?? heart
        town = great
        // The shore: a city with still water beside it, nearest the heart.
        let onShore = rest.filter { hold in hold.position.neighbors.contains { map[$0]?.terrain.isWater == true } }
        let still = onShore.min { ($0.position.distance(to: heart.position), $0.id) < ($1.position.distance(to: heart.position), $1.id) } ?? great
        shore = still
        // The besieged: of the other players' cities, neither the town's
        // nor the shore's, the nearest the heart with open ground before its
        // gate for the besiegers to stand on, its walls raised in stone.
        let taken = Set(found.map(\.position))
        func standing(_ hex: Hex) -> Bool {
            guard let tile = map[hex] else { return false }
            return tile.terrain.isPassable && !tile.terrain.isWater && !taken.contains(hex)
        }
        func room(_ hold: Hold) -> Int {
            let centre = Relief.centre(of: hold.position), gate = HoldLayout.gate(of: hold.position)
            let out = Vec3(gate.x - centre.x, 0, gate.z - centre.z).normalized
            return hold.position.spiral(3).filter { hex in
                guard hex.distance(to: hold.position) >= 2, standing(hex) else { return false }
                let c = Relief.centre(of: hex)
                let along = Vec3(c.x - centre.x, 0, c.z - centre.z).normalized
                return along.x * out.x + along.z * out.z > 0.5
            }.count
        }
        let candidates = rest.filter { $0.owner != heart.owner && $0.id != great.id && $0.id != still.id && room($0) >= 4 }
        var walled = candidates.min { ($0.position.distance(to: heart.position), $0.id) < ($1.position.distance(to: heart.position), $1.id) } ?? second
        walled.levels[.walls] = max(walled.level(.walls), 4)
        walled.project = nil
        besieged = walled
        dressed[walled.id] = walled
        holds = found.map { dressed[$0.id] ?? $0 }
        let all = holds
        let sites = window.sites(in: live).map { (store: $0.store, position: $0.hex) }
        let lairs = window.barrows(in: live).map { (kind: $0.kind, position: $0.hex) }
        self.sites = sites
        self.lairs = lairs
        furniture = stage.furnish(occupied: Set(sites.map(\.position) + lairs.map(\.position) + window.cairns(in: live).map(\.hex)),
                                  holds: Set(all.map(\.position)))
        // Each city to its nearest neighbour within seven hexes, once, along
        // open ground: the ways the carts go.
        var ways: [WorldStage.Way] = []
        var joined: Set<[Int]> = []
        for hold in all {
            let near = all.filter { $0.id != hold.id && $0.position.distance(to: hold.position) <= 7 }
            guard let other = near.min(by: { ($0.position.distance(to: hold.position), $0.id) < ($1.position.distance(to: hold.position), $1.id) }),
                  joined.insert([min(hold.id, other.id), max(hold.id, other.id)]).inserted else { continue }
            let line = hold.position.line(to: other.position)
            guard line.allSatisfy({ map[$0].map { $0.terrain.isPassable && !$0.terrain.isWater } ?? false }) else { continue }
            ways.append(WorldStage.Way(hexes: line, colour: WorldStage.colour(houses, sigil: hold.owner), salt: hold.id &* 7 &+ other.id))
        }
        self.ways = ways
        tiles = window.tiles(holds: sights, in: live, at: 0)
    }

    /// Where a hex's heart lies on the land.
    public func ground(_ hex: Hex) -> Vec3 {
        let centre = Relief.centre(of: hex)
        return Vec3(centre.x, max(relief.height(of: hex), Relief.waterline), centre.z)
    }

    /// Where a point of the map lies on the land, or on the water's face.
    public func ground(x: Float, z: Float) -> Vec3 {
        Vec3(x, max(relief.height(atX: x, z: z), Relief.waterline), z)
    }

    /// A player's colour, as the renderer reads it: a city's owner is its
    /// sigil.
    public func colour(of owner: Int) -> Vec4 {
        WorldStage.colour(houses, sigil: owner)
    }

    /// The people a player's city and armies are drawn as: the rebuilt
    /// realm keeps none yet, so each sigil its own, round the peoples.
    public func heritage(of owner: Int) -> Heritage {
        Heritage.allCases[((owner % Heritage.allCases.count) + Heritage.allCases.count) % Heritage.allCases.count]
    }

    /// The cities a player holds.
    public func holds(of owner: Int) -> [Hold] {
        holds.filter { $0.owner == owner }
    }

    /// Whether a hex is open ground a company could stand on.
    public func isOpen(_ hex: Hex) -> Bool {
        guard let tile = map[hex] else { return false }
        return tile.terrain.isPassable && !tile.terrain.isWater && !holds.contains { $0.position == hex }
    }
}
