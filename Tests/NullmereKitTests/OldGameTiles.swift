import Foundation
import NullmereCore
import NullmereWorld

// The tile texture of the turn-based game's world, as the world drew it
// for a keeper of that game: kept beside the tests that still build their
// worlds from its rules, until they and the rules go (docs/core-split.md,
// step 5; the world's own tests keep the same in OldGameStaging.swift).

extension TileTexture {
    /// The tile texture's bytes for a keeper of the old game: its map, what
    /// it has seen and sees, and whose land each tile is. `visible` and
    /// `owners` may be passed when already worked out, and `ground` when
    /// the map hasn't changed, as the session did on every change.
    static func bytes(for state: GameState, viewer: Int, visible: [Bool]? = nil, owners: [Int?]? = nil,
                      ground: Ground? = nil) -> [UInt8] {
        let map = state.map
        let ground = ground.flatMap { $0.map == map ? $0 : nil } ?? Ground(map: map)
        var bytes = ground.bytes
        let visible = visible ?? state.visibility(for: viewer)
        let explored = state.houses[viewer].explored
        let owners = owners ?? state.territory()
        let holdTiles = Set(state.holds.compactMap { map.index(of: $0.position) })
        // Each hold's colour, found once rather than for every tile.
        var colourOf: [Int: Int] = [:]
        for hold in state.holds { colourOf[hold.id] = state.houses[hold.owner].sigil + 1 }
        for index in 0..<map.count {
            let seen = visible[index] ? 2 : (explored[index] ? 1 : 0)
            guard seen > 0 else { continue }
            let offset = ground.offsets[index]
            var owner = 0
            if let holdID = owners[index], let colour = colourOf[holdID] {
                owner = colour
            }
            // A known hold lights the country round it: the feature byte's top bit.
            if holdTiles.contains(index) {
                bytes[offset + 1] |= TileTexture.holdFlag
            }
            bytes[offset + 1] |= UInt8(seen) * TileTexture.seenStep
            let named = min(owner, TileTexture.mostOwner)
            bytes[offset + 3] = UInt8(truncatingIfNeeded: named)
            bytes[offset] |= UInt8(truncatingIfNeeded: named >> 8) << 4
        }
        return bytes
    }
}
