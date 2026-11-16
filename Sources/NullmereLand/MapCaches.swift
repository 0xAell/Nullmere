import Foundation

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
