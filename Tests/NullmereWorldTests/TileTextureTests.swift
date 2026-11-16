import NullmereLand
import NullmereTestSupport
@testable import NullmereWorld
import XCTest

final class TileTextureTests: XCTestCase {
    func testEachTileLandsAtItsAxialTexel() throws {
        let world = TestWorld(seedText: "tile texture", houses: 3, radius: 14)
        let side = TileTexture.side(for: world.map)
        let ground = TileTexture.Ground(map: world.map)
        let bytes = ground.bytes
        XCTAssertEqual(side, 29)
        XCTAssertEqual(bytes.count, side * side * 4)
        for (index, hex) in world.map.hexes.enumerated() {
            let offset = ((hex.r + 14) * side + (hex.q + 14)) * 4
            XCTAssertEqual(ground.offsets[index], offset)
            XCTAssertEqual(Int(TileTexture.terrain(bytes[offset])), Terrain.allCases.firstIndex(of: world.map[index].terrain))
            XCTAssertEqual(TileTexture.seen(bytes[offset + 1]), 0, "Nothing known of it until the stage says so")
            XCTAssertEqual(TileTexture.owner(bytes, at: offset), 0, "Nobody's")
        }
    }

    /// What the keeper knows of a tile and whether a hold stands on it
    /// share the feature byte, each in bits of its own; whose land it is
    /// has twelve bits, room for every House a lake seats.
    func testEveryHouseOfTheWidestLakeWashesItsLandInItsOwnColour() throws {
        XCTAssertLessThan(Feature.allCases.count + 1, Int(TileTexture.seenStep), "Features below the knowledge bits")
        XCTAssertEqual(TileTexture.seen(0), 0)
        XCTAssertEqual(TileTexture.seen(TileTexture.seenStep + 3), 1)
        XCTAssertEqual(TileTexture.seen(2 * TileTexture.seenStep | TileTexture.holdFlag | 5), 2)
        XCTAssertGreaterThanOrEqual(TileTexture.mostOwner, WorldGenerator.mostHouses, "A tile can name every House a lake seats")
        XCTAssertLessThan(Terrain.allCases.count, 16, "The terrain's code in the first byte's low half, under the owner's")
        let world = TestWorld(seedText: "every colour", houses: 48, radius: 72)
        let ground = TileTexture.Ground(map: world.map)
        var bytes = ground.bytes
        for hold in world.holds {
            let index = try XCTUnwrap(world.map.index(of: hold.position))
            TileTexture.name(hold.owner + 1, in: &bytes, at: ground.offsets[index])
        }
        var owners: Set<Int> = []
        for hold in world.holds where hold.isSeat {
            let index = try XCTUnwrap(world.map.index(of: hold.position))
            let offset = ground.offsets[index]
            XCTAssertEqual(TileTexture.owner(bytes, at: offset), hold.owner + 1)
            owners.insert(TileTexture.owner(bytes, at: offset))
        }
        XCTAssertEqual(owners.count, 48, "Forty-eight seats, forty-eight colours")
        XCTAssertGreaterThan(owners.max() ?? 0, 16, "Past the old sixteen")
    }

    /// A House of a realm of a thousand names its land as plainly as one of
    /// twelve: its sigil plus one over both bytes, past the fourth byte's
    /// 255, the terrain's code under it as it was; a sigil no tile can
    /// name, none the realm seats, names no other House's instead.
    func testATileNamesAHouseOfARealmOfAThousand() throws {
        let world = TestWorld(seedText: "a thousand", houses: 3, radius: 14)
        let seat = world.holds[0].position
        let ground = TileTexture.Ground(map: world.map)
        let index = try XCTUnwrap(world.map.index(of: seat))
        let offset = ground.offsets[index]
        let terrain = try XCTUnwrap(world.map[seat]).terrain.code
        var bytes = ground.bytes
        let most: Int = TileTexture.mostOwner
        let sigils: [(sigil: Int, named: Int)] = [(1_000, 1_001), (255, 256), (1_023, 1_024), (most - 1, most), (5_000, most), (0, 1)]
        for (sigil, named) in sigils {
            TileTexture.name(sigil + 1, in: &bytes, at: offset)
            XCTAssertEqual(TileTexture.owner(bytes, at: offset), named, "Sigil \(sigil)")
            XCTAssertEqual(TileTexture.terrain(bytes[offset]), terrain, "The terrain as it was, under sigil \(sigil)")
        }
    }
}
