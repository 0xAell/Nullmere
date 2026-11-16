import Foundation

/// The nearest hex of a terrain to the hexes it was sought from: kept with
/// the map while its ground stays as it is, the oldest let go of first.
package final class Nearest: @unchecked Sendable {
    package init() {}

    package struct Key: Hashable {
        package let terrain: Terrain
        package let from: Hex
    }

    private let lock = NSLock()
    private var kept: [Key: Hex?] = [:]
    /// How many are kept before all are let go.
    package static let most = 256

    /// What was found, if it was sought before: a hex, or none at all.
    package func hex(of terrain: Terrain, near hex: Hex) -> Hex?? {
        lock.lock()
        defer { lock.unlock() }
        return kept[Key(terrain: terrain, from: hex)]
    }

    package func keep(_ found: Hex?, of terrain: Terrain, near hex: Hex) {
        lock.lock()
        defer { lock.unlock() }
        if kept.count >= Nearest.most { kept.removeAll() }
        kept[Key(terrain: terrain, from: hex)] = .some(found)
    }

    /// Lets go of what was kept, as the ground has changed.
    package func clear() {
        lock.lock()
        defer { lock.unlock() }
        kept.removeAll()
    }
}

/// The open water farthest from any shore, kept with the map while its
/// ground stays as it is: sought through every tile of the lake the first
/// time it is asked, given again every time after. A wide lake's every
/// steward asks it at every pace of the full moon's walks on the mirror.
package final class Deepest: @unchecked Sendable {
    package init() {}

    private let lock = NSLock()
    /// Unasked, or what was found: the deepest water, or none at all.
    private var kept: DeepWater??

    package var water: DeepWater?? {
        lock.lock()
        defer { lock.unlock() }
        return kept
    }

    package func keep(_ found: DeepWater?) {
        lock.lock()
        defer { lock.unlock() }
        kept = .some(found)
    }

    /// Lets go of what was kept, as the ground has changed.
    package func clear() {
        lock.lock()
        defer { lock.unlock() }
        kept = nil
    }
}
