import NullmereLand
import XCTest

/// The map: every hex within its radius, each with its tile, found by its
/// index; and the deepest of its open water, kept while its ground is as it
/// is.
final class WorldMapTests: XCTestCase {
    func testAMapHoldsEveryHexWithinItsRadiusRowByRow() {
        let map = WorldMap(radius: 3, fill: Tile(terrain: .greyfield))
        XCTAssertEqual(map.radius, 3)
        XCTAssertEqual(map.count, 37)
        XCTAssertEqual(WorldMap.count(radius: 3), 37)
        XCTAssertEqual(map.tiles.count, 37)
        XCTAssertEqual(Set(map.hexes), Set(Hex(0, 0).spiral(3)), "Every hex within three, and no other")
        XCTAssertEqual(map.hexes, map.hexes.sorted(), "Row by row")
        for (index, hex) in map.hexes.enumerated() {
            XCTAssertEqual(map.index(of: hex), index)
            XCTAssertEqual(map[hex], Tile(terrain: .greyfield))
            XCTAssertTrue(map.contains(hex))
        }
        for outside in [Hex(4, 0), Hex(2, 2), Hex(-3, -1), Hex(Int.max / 2, Int.min / 2), Hex(Int.min, 0), Hex(0, Int.max)] {
            XCTAssertFalse(map.contains(outside), "\(outside)")
            XCTAssertNil(map.index(of: outside))
            XCTAssertNil(map[outside])
        }
    }

    func testEachTileKnowsItsNeighboursInTheMap() throws {
        let map = WorldMap(radius: 2, fill: Tile(terrain: .greyfield))
        XCTAssertEqual(map.neighbors(of: Hex(0, 0)).count, 6)
        XCTAssertEqual(map.neighbors(of: Hex(2, 0)).count, 3, "A corner has three")
        XCTAssertEqual(map.neighbors(of: Hex(1, 1)).count, 4, "An edge four")
        XCTAssertEqual(map.neighbours.count, map.count * 6)
        for (index, hex) in map.hexes.enumerated() {
            for (side, direction) in Hex.directions.enumerated() {
                let next = map.neighbours[index * 6 + side]
                XCTAssertEqual(next, map.index(of: hex + direction).map { Int32($0) } ?? -1, "\(hex) toward \(direction)")
            }
        }
    }

    func testSettingATileChangesThatTileAloneAndNothingOutside() {
        var map = WorldMap(radius: 2, fill: Tile(terrain: .greyfield))
        let before = map
        map.set(Hex(1, -1), Tile(terrain: .blackwood, feature: .elderGrove, relief: 40))
        XCTAssertEqual(map[Hex(1, -1)], Tile(terrain: .blackwood, feature: .elderGrove, relief: 40))
        XCTAssertNotEqual(map, before)
        XCTAssertEqual(map.hexes.filter { map[$0] != before[$0] }, [Hex(1, -1)])
        map.set(Hex(5, 5), Tile(terrain: .still))
        XCTAssertEqual(map.hexes.filter { map[$0] != before[$0] }, [Hex(1, -1)], "Nothing set past the edge")
        let index = map.index(of: Hex(0, 0))!
        map[index] = Tile(terrain: .spine)
        XCTAssertEqual(map[index].terrain, .spine)
        var again = before
        again.set(Hex(1, -1), Tile(terrain: .blackwood, feature: .elderGrove, relief: 40))
        again[index] = Tile(terrain: .spine)
        XCTAssertEqual(again, map, "Maps of the same tiles are the same")
        XCTAssertNotEqual(WorldMap(radius: 3, fill: Tile(terrain: .greyfield)), WorldMap(radius: 2, fill: Tile(terrain: .greyfield)))
    }

    func testTheDeepestWaterLiesFarthestFromAnyShore() throws {
        var lake = WorldMap(radius: 4, fill: Tile(terrain: .still))
        for hex in Hex(0, 0).ring(4) { lake.set(hex, Tile(terrain: .strand)) }
        XCTAssertEqual(lake.deepestWater(), DeepWater(hex: Hex(0, 0), depth: 4))
        XCTAssertEqual(lake.deepestWater(), lake.seekDeepestWater(), "As kept, as sought")
        // Its ground changed, a copy seeks again; the map it was copied from
        // keeps what it found.
        var shoaled = lake
        shoaled.set(Hex(0, 0), Tile(terrain: .strand))
        let deepest = try XCTUnwrap(shoaled.deepestWater())
        XCTAssertEqual(deepest.depth, 2)
        XCTAssertEqual(deepest.hex.length, 2, "Between the shoal and the shore")
        XCTAssertEqual(lake.deepestWater(), DeepWater(hex: Hex(0, 0), depth: 4))
        XCTAssertNil(WorldMap(radius: 3, fill: Tile(terrain: .greyfield)).deepestWater(), "No open water")
        XCTAssertNil(WorldMap(radius: 3, fill: Tile(terrain: .still)).deepestWater(), "No shore to be far from")
    }

    func testTerrainsAndFeaturesAreCodedInTheOrderTheyAreTold() {
        for (index, terrain) in Terrain.allCases.enumerated() {
            XCTAssertEqual(Int(terrain.code), index)
        }
        for (index, feature) in Feature.allCases.enumerated() {
            XCTAssertEqual(Int(feature.code), index)
        }
    }

    func testWhatCanBeWalkedAndRaisedOnHangsTogether() {
        for terrain in Terrain.allCases {
            if terrain.isSettleable {
                XCTAssertTrue(terrain.isPassable, "\(terrain): what is raised on is walked to")
                XCTAssertFalse(terrain.isWater, "\(terrain): nothing is raised on water")
            }
        }
        XCTAssertEqual(Set(Terrain.allCases.filter(\.isWater)), [.still, .shallows, .ford, .stream, .shoal])
        XCTAssertEqual(Set(Terrain.allCases.filter { !$0.isPassable }), [.still, .spine, .stream])
        XCTAssertEqual(Set(Terrain.allCases.filter(\.isSettleable)), [.strand, .saltFlat, .greyfield, .blackwood, .barrow])
        XCTAssertEqual(Tile(terrain: .barrow), Tile(terrain: .barrow, feature: nil, relief: 0))
    }
}
