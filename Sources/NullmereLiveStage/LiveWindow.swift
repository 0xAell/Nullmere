import Foundation
import NullmereLand
import NullmereLive
import NullmereModels
import NullmereWorld

/// A window on the realm's world, as the renderer takes one: the land for
/// some hexes about a hex, as a map of its own with that hex at its
/// heart, and what stands and moves on it as the stage's holds and
/// companies.
///
/// The realm's world is far larger than a view. A client draws the window
/// about where it looks and takes another as the view moves on.
public struct LiveWindow: Sendable {
    /// The hex of the world at the window's heart, and how far it reaches.
    public let centre: LiveHex
    public let radius: Int
    /// The window's land: the world's ground, hex for hex. It is made of
    /// the land alone, which never changes, so a window need be made only
    /// once for where it lies; what stands on it is staged apart.
    public let map: WorldMap

    /// The window about a hex of a world. Ground the client has not been
    /// told, and ground beyond the world's rim, is mountain.
    public init(world: LiveWorld, centre: LiveHex, radius: Int) {
        self.centre = centre
        self.radius = max(radius, 1)
        var map = WorldMap(radius: self.radius, fill: Tile(terrain: .spine))
        let reach = world.realm?.radius ?? Int.max
        let origin = LiveHex(q: 0, r: 0)
        for hex in map.hexes {
            let there = LiveHex(q: hex.q + centre.q, r: hex.r + centre.r)
            guard there.distance(to: origin) <= reach, let code = world.ground(at: there), Int(code) < LiveWindow.terrains.count else { continue }
            map.set(hex, Tile(terrain: LiveWindow.terrains[Int(code)]))
        }
        self.map = map
    }

    /// The module's grounds, in the order of their codes: the renderer's
    /// terrains by the same numbers (`LiveSchemaTests` holds them so).
    static let terrains: [Terrain] = [.still, .shallows, .strand, .saltFlat, .greyfield, .blackwood, .barrow, .spine]

    /// A hex of the world as the window's own, if it lies in the window.
    public func local(_ hex: LiveHex) -> Hex? {
        let here = Hex(hex.q - centre.q, hex.r - centre.r)
        return map.index(of: here) == nil ? nil : here
    }

    /// A point of the world's flat map in the window's own: the window's
    /// heart is its origin.
    public func local(x: Double, y: Double) -> (x: Float, z: Float) {
        let heart = centre.centre
        return (Float(x - heart.x), Float(y - heart.y))
    }

    /// Which of the Houses' colours a player's things are drawn in.
    public static func sigil(of player: UInt64) -> Int { Int(player % 1_024) }

    /// The cities in the window as the stage's holds: each a seat, its
    /// works standing by its Keep's level; the player's own by what
    /// truly stands in it, and whatever it has rising, with the envoys
    /// come to their alliance waiting at its gate and a petitioner while
    /// an ally's petition waits on them. Then the gates of the ridge, each
    /// a walled hold in its holder's colour, or the Unquiet's dark; and
    /// the wardstones, each a beacon in its alliance's colour.
    public func holds(in world: LiveWorld, colours: [Vec4], at seconds: Double) -> [HoldSight] {
        cityHolds(in: world, colours: colours, at: seconds) + markHolds(in: world, colours: colours, at: seconds)
    }

    /// The colour of what no alliance holds: the Unquiet's.
    static let unquiet = Vec4(0.16, 0.15, 0.17, 1)

    /// Where the gates' and wardstones' holds are numbered from, past any
    /// city's number.
    static let marks = 1 << 40

    private func markHolds(in world: LiveWorld, colours: [Vec4], at seconds: Double) -> [HoldSight] {
        let gates = world.gates.values.sorted { $0.id < $1.id }.compactMap { gate -> HoldSight? in
            guard let hex = local(gate.hex) else { return nil }
            let owner = gate.holder == 0 ? 0 : LiveWindow.allianceSigil(of: gate.holder)
            var hold = Hold(id: LiveWindow.marks + Int(gate.id), name: "Gate of the ridge", owner: owner, position: hex, isSeat: false, foundedWatch: 0)
            hold.levels[.walls] = 5
            hold.ward = Hold.maximumWard(wallLevel: 5, isSeat: false)
            return HoldSight(hold: hold, colour: gate.holder == 0 ? LiveWindow.unquiet : WorldStage.colour(colours, sigil: owner))
        }
        let wards = world.wards.values.sorted { $0.id < $1.id }.compactMap { ward -> HoldSight? in
            guard let hex = local(ward.hex) else { return nil }
            let owner = LiveWindow.allianceSigil(of: ward.alliance)
            var hold = Hold(id: LiveWindow.marks * 2 + Int(ward.id), name: "Wardstone", owner: owner, position: hex, isSeat: false, foundedWatch: 0)
            hold.levels[.beacon] = 1
            // Raised but not yet standing: its beacon still rising.
            let rising = ward.stands(at: seconds) ? nil : Float(0.5)
            return HoldSight(hold: hold, colour: WorldStage.colour(colours, sigil: owner), progress: rising)
        }
        return gates + wards
    }

    private func cityHolds(in world: LiveWorld, colours: [Vec4], at seconds: Double) -> [HoldSight] {
        world.cities.values.sorted { $0.id < $1.id }.compactMap { city -> HoldSight? in
            guard let hex = local(city.hex) else { return nil }
            var hold = Hold(id: Int(city.id), name: city.name, owner: LiveWindow.sigil(of: city.owner), position: hex, isSeat: true,
                            foundedWatch: 0)
            let own = world.city?.id == city.id
            for kind in BuildingKind.allCases {
                guard let building = LiveWindow.building(for: kind) else { continue }
                let level: Int
                if own {
                    level = world.building(building)?.level ?? 0
                } else {
                    // What a city of its Keep's level has most likely raised.
                    level = city.keep >= LiveWindow.opensAt(building) ? max(city.keep - 1, 1) : 0
                }
                if level > 0 { hold.levels[kind] = LiveWindow.shown(level) }
            }
            hold.ward = Hold.maximumWard(wallLevel: hold.level(.walls), isSeat: true)
            var sight = HoldSight(hold: hold, colour: WorldStage.colour(colours, sigil: LiveWindow.sigil(of: city.owner)))
            sight.keep = LiveWindow.keepLook(city.keep)
            if own {
                sight.envoys = world.envoysWaiting(at: seconds).map { WorldStage.colour(colours, sigil: LiveWindow.allianceSigil(of: $0.sender)) }
                let waiting = world.petitionsStanding(at: seconds).contains { $0.asker != world.me?.id }
                sight.petitioner = waiting ? 0 : nil
            }
            return sight
        }
    }

    /// The sites in the window, as the stage's own: each good's site
    /// standing on its hex.
    public func sites(in world: LiveWorld) -> [(store: Resource, hex: Hex)] {
        world.sites.values.sorted { $0.id < $1.id }.compactMap { site in
            guard let hex = local(site.hex), let store = LiveWindow.store(of: site.kind) else { return nil }
            return (store, hex)
        }
    }

    /// The good a kind of site holds.
    static func store(of kind: Int) -> Resource? {
        [1: .grain, 2: .timber, 3: .stone, 4: .moonsalt][kind]
    }

    /// The Unquiet's barrows in the window, as the stage's lairs of the
    /// restless dead.
    public func barrows(in world: LiveWorld) -> [(kind: WildKind, hex: Hex)] {
        world.barrows.values.sorted { $0.id < $1.id }.compactMap { barrow in
            local(barrow.hex).map { (.barrowkin, $0) }
        }
    }

    /// The old folk's cairns in the window, as the stage's found barrows:
    /// a great grassed mound, the stones of its open mouth before it.
    public func cairns(in world: LiveWorld) -> [(kind: FindKind, hex: Hex)] {
        world.cairns.values.sorted { $0.id < $1.id }.compactMap { cairn in
            local(cairn.hex).map { (.barrow, $0) }
        }
    }

    /// The holy sites in the window, each drawn as its kind, its pennant in
    /// its holder's colour, the Unquiet's own while they keep it.
    public func shrines(in world: LiveWorld, colours: [Vec4]) -> [(kind: ShrineKind, hex: Hex, colour: Vec4?)] {
        world.shrines.values.sorted { $0.id < $1.id }.compactMap { shrine in
            guard let hex = local(shrine.hex), let kind = LiveWindow.shrineKind(of: shrine.kind) else { return nil }
            let colour = shrine.holder == 0 ? LiveWindow.unquiet : WorldStage.colour(colours, sigil: LiveWindow.allianceSigil(of: shrine.holder))
            return (kind, hex, colour)
        }
    }

    /// The stage's kind for a holy site of the realm's numbering.
    static func shrineKind(of kind: Int) -> ShrineKind? {
        [LiveShrine.moonwell: .moonwell, LiveShrine.stillStone: .stillStone, LiveShrine.saltAltar: .saltAltar,
         LiveShrine.brokenSpire: .brokenSpire, LiveShrine.heartstone: .heartstone][kind]
    }

    /// The window's tiles as the world's shader takes them: every hex
    /// known and watched, since the realm keeps nothing of its land from
    /// anyone; a hold where a city stands; and, where a world is given,
    /// the land its alliances' wardstones claim at a moment, each tinted in
    /// its alliance's colour (`allianceSigil`). A city holds no land of its
    /// own in the realm.
    public func tiles(holds: [HoldSight], in world: LiveWorld? = nil, at seconds: Double = 0) -> [UInt8] {
        let ground = TileTexture.Ground(map: map)
        var bytes = ground.bytes
        let stood = Set(holds.compactMap { map.index(of: $0.hold.position) })
        let claiming = world.map { world in world.wards.values.filter { $0.stands(at: seconds) } } ?? []
        for (index, offset) in ground.offsets.enumerated() {
            bytes[offset + 1] |= 2 * TileTexture.seenStep
            if stood.contains(index) { bytes[offset + 1] |= TileTexture.holdFlag }
            guard !claiming.isEmpty, let world else { continue }
            let local = map.hexes[index]
            let hex = LiveHex(q: local.q + centre.q, r: local.r + centre.r)
            guard let alliance = world.landOf(hex, at: seconds) else { continue }
            TileTexture.name(LiveWindow.allianceSigil(of: alliance) + 1, in: &bytes, at: offset)
        }
        return bytes
    }

    /// Which colour an alliance's land is tinted in: its own, apart from
    /// its members' (players' run from the first, alliances' from the
    /// five hundred and twelfth).
    public static func allianceSigil(of alliance: UInt64) -> Int { 512 + Int(alliance % 512) }

    /// A building's level, 1 to 25, as one of the five the stage's works
    /// are drawn at.
    static func shown(_ level: Int) -> Int { min(max(1 + (level - 1) / 5, 1), 5) }

    /// How a city's keep stands by its Keep's level: a tower of timber on
    /// its motte while the Keep is below the fifth level, the hold's keep of
    /// stone to the eleventh, and the seat's, its round towers either side,
    /// from the twelfth.
    static func keepLook(_ level: Int) -> HoldLayout.KeepLook {
        level < 5 ? .young : level < 12 ? .hold : .seat
    }

    /// The realm's building that one of the stage's works shows, by its
    /// number in the module's catalogue; nil for works the realm has not.
    static func building(for kind: BuildingKind) -> Int? {
        switch kind {
        case .granary: return 2
        case .sawpit: return 3
        case .quarry: return 4
        case .saltworks: return 5
        case .musterHall: return 7
        case .walls: return 12
        case .beacon: return 13
        case .infirmary: return 11
        case .archive: return 14
        // The smiths' Forge; the Wayhouse, with its horses, the Stable; the
        // masons' Lodge, where works are drawn out, the Workshop's engines.
        case .forge: return 19
        case .wayhouse: return 9
        case .lodge: return 10
        case .storehouse: return 6
        case .range: return 8
        case .embassy: return 15
        case .tavern: return 16
        case .market: return 17
        case .scoutCamp: return 18
        default: return nil
        }
    }

    /// The Keep level a building opens at, as the module's catalogue has it.
    static func opensAt(_ building: Int) -> Int {
        switch building {
        case 2, 3: return 1
        case 4, 6, 7: return 2
        case 11, 12, 18: return 3
        case 8, 16: return 4
        case 14, 15, 19: return 5
        case 9: return 6
        case 5: return 7
        case 13, 17: return 8
        case 10: return 10
        default: return 99
        }
    }

    /// The ways of the armies in the window still on the move, as the stage
    /// lights them on the land: from where each is now along the rest of
    /// its way, as far as the window holds it, in its side's hue (the
    /// player's own; an ally's; a foe's, marching on the player's city; or
    /// another's), with where the player's own is bound.
    public func marchWays(in world: LiveWorld, at seconds: Double) -> [(from: Vec3, route: [Hex], side: WorldStage.MarchSide, bound: Hex?)] {
        world.marches.values.sorted { $0.id < $1.id }.compactMap { march in
            guard !march.stands, march.route.count > 1 else { return nil }
            let along = march.progress(at: seconds) * Double(march.route.count - 1)
            let next = min(Int(along) + 1, march.route.count - 1)
            var route: [Hex] = []
            for hex in march.route[next...] {
                guard let here = local(hex) else { break }
                route.append(here)
            }
            guard !route.isEmpty else { return nil }
            let at = march.position(at: seconds)
            let from = local(x: at.x, y: at.y)
            let side: WorldStage.MarchSide
            if march.owner == world.me?.id {
                side = .own
            } else if world.isAlly(march.owner) {
                side = .ally
            } else if [LiveMarch.attack, LiveMarch.scout, LiveMarch.rally].contains(march.kind), march.to == world.city?.hex {
                side = .foe
            } else {
                side = .other
            }
            return (Vec3(from.x, 0, from.z), route, side, side == .own ? local(march.to) : nil)
        }
    }

    /// The armies in the window as the stage's companies, each where it is
    /// at a moment: along its way, facing the way it goes, marching; or
    /// standing where it came to, at work on its site or striking at the
    /// barrow it fights.
    public func companies(in world: LiveWorld, relief: Relief, at seconds: Double) -> [CompanyPose] {
        world.marches.values.sorted { $0.id < $1.id }.compactMap { march -> CompanyPose? in
            let at = march.position(at: seconds)
            let place = local(x: at.x, y: at.y)
            let layout = HexLayout(size: 1)
            let hex = layout.hex(atX: Double(place.x), y: Double(place.z))
            guard map.index(of: hex) != nil else { return nil }
            // Which way it goes: toward where it will be a moment on.
            let ahead = march.position(at: seconds + 1)
            let (dx, dy) = (ahead.x - at.x, ahead.y - at.y)
            let moving = !march.stands && (dx * dx + dy * dy) > 1e-12
            // Standing, it faces the way it came by: toward what it came for.
            var heading: Float = 0
            if moving {
                heading = Float(atan2(dx, dy))
            } else if march.route.count >= 2 {
                let (last, before) = (march.route[march.route.count - 1].centre, march.route[march.route.count - 2].centre)
                heading = Float(atan2(last.x - before.x, last.y - before.y))
            }
            let clip: Clip = moving ? .march : (march.state == LiveMarch.fighting ? .attack : .idle)
            let own = world.me?.id == march.owner
            let (kind, tier) = LiveWindow.figure(of: march, squads: own ? world.squads : [])
            // Carts carry no army: a carter and their handcart go with them.
            let key: ModelKey = march.kind == LiveMarch.carts ? .folk(variant: Folk.timberCarter) : .figure(kind, tier: tier)
            let ground = max(relief.height(atX: place.x, z: place.z), Relief.waterline)
            var pose = CompanyPose(unit: Int(march.id), key: key, sigil: LiveWindow.sigil(of: march.owner), health: 100,
                                   hex: hex, position: Vec3(place.x, ground, place.z), heading: heading, clip: clip,
                                   clipTime: Float(seconds.truncatingRemainder(dividingBy: 3_600)), isOwn: own)
            if march.state == LiveMarch.fighting {
                // In a fight it stands massed, a figure for so many of its
                // soldiers, its ranks striking and reeling by turns under the
                // foe's blows (`Formation.throngCount`, `Clip.hit`).
                pose.throng = Formation.throngCount(key, troops: Int(min(march.soldiers, UInt64(Int32.max))))
                pose.struck = true
            }
            return pose
        }
    }

    /// The figure an army is drawn as: for the player's own, the kind it
    /// has most of at that kind's highest tier; for another's, spearmen,
    /// since what an army is made of is its owner's alone to know.
    static func figure(of march: LiveMarch, squads: [LiveSquad]) -> (UnitKind, Int) {
        let mine = squads.filter { $0.march == march.id }
        guard let most = Dictionary(grouping: mine, by: \.kind).max(by: { a, b in
            let (x, y) = (a.value.reduce(0) { $0 + $1.count }, b.value.reduce(0) { $0 + $1.count })
            return (x, b.key) < (y, a.key)
        }) else { return (.spear, 1) }
        let kind: UnitKind = [1: .spear, 2: .bow, 3: .rider, 4: .mangonel][most.key] ?? .spear
        let tier = most.value.map(\.tier).max() ?? 1
        return (kind, min(max(tier, 1), ModelKey.tiers(of: kind)))
    }
}
