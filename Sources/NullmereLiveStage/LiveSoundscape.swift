import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import NullmereLand
import NullmereLive
import NullmereModels
import NullmereWorld

/// What the world sounds like about where the player looks: each kind of
/// place heard, how near (0, out of hearing, to 1, all about the middle of
/// the view) and from where across the view (-1 its left edge to 1 its
/// right); how great the fights heard are; and of the towns heard, how much
/// of each kind of work is at it.
public struct LiveSoundscape: Equatable, Sendable {
    public struct Heard: Equatable, Sendable {
        public var level: Float
        public var pan: Float
        public init(level: Float, pan: Float) {
            self.level = level
            self.pan = pan
        }
        public static let none = Heard(level: 0, pan: 0)
    }

    /// The cities' towns, the lake's edge, the fights, and the Unquiet's
    /// barrows.
    public var town = Heard.none, shore = Heard.none, din = Heard.none, keening = Heard.none
    /// How great the fights heard are, 0 to 1.
    public var host: Float = 0
    /// Of the towns heard, the share of each kind of work at it, by the
    /// kind a work is drawn as; together they come to one.
    public var works: [BuildingKind: Float] = [:]

    public init() {}

    /// The share of the towns heard that is a kind of work at it.
    public func share(_ kind: BuildingKind) -> Float { works[kind] ?? 0 }
}

extension LiveSession {
    /// How far from where the player looks a place is heard, in the
    /// window's units (a hex is about one and three quarters across).
    public static let hearing: Float = 7

    /// What is heard about where the player looks, in a view of a size:
    /// each city, the lake's edge, each fight and each barrow nearer the
    /// louder and from where it lies across the view. Nothing in a view of
    /// no size, or before there is a window.
    public func soundscape(in size: CGSize) -> LiveSoundscape {
        var scape = LiveSoundscape()
        guard let window, size.width > 0, size.height > 0 else { return scape }
        let focus = camera.focus
        let seconds = now
        func near(_ x: Float, _ z: Float) -> Float {
            let dx = x - focus.x, dz = z - focus.z
            return max(0, 1 - (dx * dx + dz * dz).squareRoot() / LiveSession.hearing)
        }
        func across(_ x: Float, _ z: Float) -> Float {
            let at = camera.viewPoint(worldX: Double(x), worldY: Double(z), in: size)
            return Float(min(max(Double(at.x) / Double(size.width) * 2 - 1, -1), 1))
        }
        /// So much heard from so near, and from where, summed.
        struct Sum {
            var weight: Float = 0
            var pans: Float = 0
            mutating func add(_ weight: Float, at pan: Float) {
                self.weight += weight
                pans += weight * pan
            }
            func heard(gain: Float) -> LiveSoundscape.Heard {
                weight > 0 ? .init(level: min(weight * gain, 1), pan: pans / weight) : .none
            }
        }
        var towns = Sum(), shore = Sum(), din = Sum(), keening = Sum()
        var works: [BuildingKind: Float] = [:]
        for sight in window.holds(in: world, colours: LiveSession.colours, at: seconds) where sight.hold.isSeat {
            let centre = Relief.centre(of: sight.hold.position)
            let weight = near(centre.x, centre.z)
            guard weight > 0 else { continue }
            towns.add(weight, at: across(centre.x, centre.z))
            for (kind, level) in sight.hold.levels where level > 0 && kind != .walls {
                works[kind, default: 0] += weight
            }
        }
        // The lake's edge: water beside land.
        for hex in window.map.hexes where window.map[hex]?.terrain.isWater == true {
            let centre = Relief.centre(of: hex)
            let weight = near(centre.x, centre.z)
            guard weight > 0, hex.neighbors.contains(where: { window.map[$0].map { !$0.terrain.isWater } ?? false }) else { continue }
            shore.add(weight, at: across(centre.x, centre.z))
        }
        // Fights: armies at a barrow or a city, the more soldiers the louder.
        var fighting: Float = 0
        for march in world.marches.values where march.state == LiveMarch.fighting {
            let at = march.position(at: seconds)
            let local = window.local(x: at.x, y: at.y)
            let weight = near(local.x, local.z)
            guard weight > 0 else { continue }
            let soldiers = Float(march.soldiers)
            din.add(weight * min(soldiers / 500, 1), at: across(local.x, local.z))
            fighting += weight * soldiers
        }
        for barrow in window.barrows(in: world) {
            let centre = Relief.centre(of: barrow.hex)
            let weight = near(centre.x, centre.z)
            if weight > 0 { keening.add(weight, at: across(centre.x, centre.z)) }
        }
        scape.town = towns.heard(gain: 0.8)
        scape.shore = shore.heard(gain: 0.15)
        scape.din = din.heard(gain: 1)
        scape.keening = keening.heard(gain: 0.6)
        scape.host = min(fighting / 5_000, 1)
        let allWorks = works.values.reduce(0, +)
        if allWorks > 0 { scape.works = works.mapValues { $0 / allWorks } }
        return scape
    }
}
