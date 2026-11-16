import Foundation
import NullmereLand
import NullmereLive

/// The whole realm small: its grounds a pixel to each hex across, the lake
/// at its heart, for a map in the corner to be drawn from; and where any
/// hex of the realm falls on it, from 0 to 1 either way.
public struct LiveMinimap: Equatable, Sendable {
    /// How many pixels across and down.
    public let width: Int
    public let height: Int
    /// Each pixel's ground, rows from the top, as the module numbers
    /// grounds; `unknown` where no ground is told.
    public let grounds: [UInt8]
    /// The realm's radius, in hexes from its heart to its rim.
    public let radius: Int

    public static let unknown: UInt8 = 255

    /// The realm's grounds sampled a pixel to each hex across: the map is
    /// as wide as the realm's diameter in hexes, and as tall as its rows'
    /// spacing makes it.
    public init(world: LiveWorld) {
        let radius = max(world.realm?.radius ?? 0, 1)
        let width = 2 * radius + 1
        let height = Int((Double(width) * 1.5 / 3.0.squareRoot()).rounded())
        let layout = HexLayout(size: 1)
        var grounds = [UInt8](repeating: LiveMinimap.unknown, count: width * height)
        for row in 0..<height {
            for column in 0..<width {
                let (x, y) = LiveMinimap.worldPoint(u: (Double(column) + 0.5) / Double(width), v: (Double(row) + 0.5) / Double(height), radius: radius)
                let hex = layout.hex(atX: x, y: y)
                if let ground = world.ground(at: LiveHex(q: hex.q, r: hex.r)) {
                    grounds[row * width + column] = ground
                }
            }
        }
        (self.width, self.height, self.grounds, self.radius) = (width, height, grounds, radius)
    }

    /// The point of the world's flat map at a place on the minimap.
    static func worldPoint(u: Double, v: Double, radius: Int) -> (x: Double, y: Double) {
        let halfWidth = 3.0.squareRoot() * (Double(radius) + 0.5)
        let halfHeight = 1.5 * (Double(radius) + 0.5)
        return ((u * 2 - 1) * halfWidth, (v * 2 - 1) * halfHeight)
    }

    /// Where a hex of the realm falls on the minimap, from 0 to 1 either way.
    public func place(of hex: LiveHex) -> (u: Double, v: Double) {
        let (x, y) = hex.centre
        let halfWidth = 3.0.squareRoot() * (Double(radius) + 0.5)
        let halfHeight = 1.5 * (Double(radius) + 0.5)
        return ((x / halfWidth + 1) / 2, (y / halfHeight + 1) / 2)
    }

    /// The hex of the realm at a place on the minimap.
    public func hex(atU u: Double, v: Double) -> LiveHex {
        let (x, y) = LiveMinimap.worldPoint(u: u, v: v, radius: radius)
        let hex = HexLayout(size: 1).hex(atX: x, y: y)
        return LiveHex(q: hex.q, r: hex.r)
    }
}
