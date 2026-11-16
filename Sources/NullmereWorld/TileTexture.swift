import NullmereLand

/// Packs what the world shader needs to know about each tile into four
/// bytes, laid out as a square texture indexed by axial coordinates:
/// terrain; feature, with what the viewer knows of the tile (whether it
/// is unknown, remembered or watched) and whether a hold stands there;
/// relief; and the House whose territory it is, its sigil plus one, so
/// that every House a lake seats has its own. That takes twelve bits, for
/// a realm of a thousand Houses and more: the low eight are the fourth
/// byte, the high four the first byte's high half, over the terrain's
/// code, which needs no more than the low half.
public enum TileTexture {
    /// Set in the feature byte where a hold stands.
    public static let holdFlag: UInt8 = 0x80
    /// In the feature byte, what the viewer knows of a tile, sixteen for
    /// each step: none, remembered, watched.
    public static let seenStep: UInt8 = 16

    /// What the viewer knows of a tile from its feature byte: 0 nothing,
    /// 1 remembered, 2 watched.
    public static func seen(_ feature: UInt8) -> Int {
        Int((feature & ~holdFlag) / seenStep)
    }

    /// The most a tile can name: the sigil of the last House it holds, plus one.
    public static let mostOwner = 0xFFF

    /// The terrain's code in a tile's first byte.
    public static func terrain(_ first: UInt8) -> UInt8 {
        first & 0x0F
    }

    /// Whose territory a tile is, from its four bytes at `offset`: a
    /// House's sigil plus one, or none.
    public static func owner(_ bytes: [UInt8], at offset: Int) -> Int {
        Int(bytes[offset + 3]) | Int(bytes[offset] >> 4) << 8
    }

    public static func side(for map: WorldMap) -> Int {
        2 * map.radius + 1
    }

    /// What never changes from watch to watch: each tile's terrain, feature
    /// and relief, and where in the texture each tile lies. Made once for a
    /// map; each change of the world fills in only what the keeper knows.
    public struct Ground: Sendable {
        public let map: WorldMap
        public let bytes: [UInt8]
        public let offsets: [Int]

        public init(map: WorldMap) {
            self.map = map
            let side = TileTexture.side(for: map)
            var bytes = [UInt8](repeating: 0, count: side * side * 4)
            var offsets: [Int] = []
            offsets.reserveCapacity(map.count)
            for (index, hex) in map.hexes.enumerated() {
                let tile = map[index]
                let offset = ((hex.r + map.radius) * side + (hex.q + map.radius)) * 4
                offsets.append(offset)
                bytes[offset] = tile.terrain.code
                bytes[offset + 1] = tile.feature.map { $0.code + 1 } ?? 0
                bytes[offset + 2] = UInt8(clamping: tile.relief * 255 / 100)
            }
            self.bytes = bytes
            self.offsets = offsets
        }
    }

}
