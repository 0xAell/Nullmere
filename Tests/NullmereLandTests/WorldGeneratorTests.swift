import NullmereLand
import XCTest

/// The world's maker: a lake of each shape walled by the Spine, its seats
/// on the shore, the Marches' Crown and gates, and streams down to the
/// lake; the same seed always the same world.
final class WorldGeneratorTests: XCTestCase {
    func testTheSameSeedMakesTheSameWorldAndAnotherAnother() {
        let one = WorldGenerator(seed: Seed.from("a lake"), radius: 16, houseCount: 4).generate()
        let again = WorldGenerator(seed: Seed.from("a lake"), radius: 16, houseCount: 4).generate()
        let other = WorldGenerator(seed: Seed.from("another lake"), radius: 16, houseCount: 4).generate()
        XCTAssertEqual(one.map, again.map)
        XCTAssertEqual(one.seats, again.seats)
        XCTAssertNotEqual(one.map, other.map)
    }

    func testEveryLakeIsWalledBySpineWithItsSeatsOnTheShore() throws {
        for lake in Lake.allCases {
            let world = WorldGenerator(seed: Seed.from("every lake"), radius: 18, houseCount: 4, lake: lake).generate()
            let map = world.map
            XCTAssertEqual(map.radius, 18)
            XCTAssertTrue(map.hexes.filter { $0.length == 18 }.allSatisfy { map[$0]?.terrain == .spine }, "\(lake): the Spine about it")
            XCTAssertTrue(map.hexes.contains { map[$0]?.terrain == .still }, "\(lake): the Still in it")
            XCTAssertNotNil(map.deepestWater(), "\(lake): open water")
            XCTAssertEqual(world.seats.count, 4, "\(lake)")
            XCTAssertEqual(Set(world.seats).count, 4, "\(lake): four seats, none shared")
            for seat in world.seats {
                XCTAssertEqual(map[seat]?.terrain.isSettleable, true, "\(lake): \(seat) on ground a seat stands on")
            }
            XCTAssertTrue(world.streams.isEmpty, "\(lake): no streams unless asked")
            XCTAssertEqual(world.gates.isEmpty, lake != .marches, "\(lake): gates in the Marches alone")
            XCTAssertTrue(map.tiles.allSatisfy { (0...100).contains($0.relief) }, "\(lake): relief within its range")
        }
    }

    func testTheMarchesCrownIsARingOfSpineWithFourOpenGates() throws {
        let radius = 24
        let world = WorldGenerator(seed: Seed.from("the marches"), radius: radius, houseCount: 4, lake: .marches).generate()
        let crown = WorldGenerator.crown(radius: radius)
        XCTAssertEqual(crown, 4)
        XCTAssertEqual(world.gates.count, 4)
        XCTAssertEqual(Set(world.gates).count, 4)
        for gate in world.gates {
            let tile = try XCTUnwrap(world.map[gate])
            XCTAssertEqual(gate.length, crown, "\(gate) in the Crown's ring")
            XCTAssertTrue(tile.terrain.isPassable && !tile.terrain.isWater, "\(gate) walked through")
            XCTAssertNil(tile.feature, "\(gate) bare ground")
        }
        let ring = world.map.hexes.filter { $0.length == crown && !world.gates.contains($0) }
        XCTAssertTrue(ring.allSatisfy { world.map[$0]?.terrain == .spine }, "The rest of the ring the Spine")
        XCTAssertTrue(world.seats.allSatisfy { $0.length > crown + 2 }, "No seat within the Crown or at its gates")
        XCTAssertEqual([12, 24, 30, 48].map(WorldGenerator.crown(radius:)), [3, 4, 5, 8], "A sixth of the way out, three at the least")
    }

    func testStreamsRunDownToTheLakeWhenAsked() throws {
        let world = WorldGenerator(seed: Seed.from("streams"), radius: 20, houseCount: 6, rivers: true).generate()
        XCTAssertFalse(world.streams.isEmpty)
        XCTAssertLessThanOrEqual(world.streams.count, WorldGenerator.streamCount(seats: 6))
        XCTAssertFalse(world.hearts.isEmpty, "The shores parted between them")
        for course in world.streams {
            XCTAssertTrue(course.allSatisfy { hex in world.map[hex].map { [Terrain.stream, .shoal].contains($0.terrain) } == true }, "Its course a stream, crossed at its shoals")
            XCTAssertTrue(course.contains { world.map[$0]?.terrain == .shoal }, "At least one shoal")
            XCTAssertTrue(zip(course, course.dropFirst()).allSatisfy { $0.distance(to: $1) == 1 }, "Step by step")
        }
        XCTAssertEqual([2, 6, 10, 30, 40].map(WorldGenerator.streamCount(seats:)), [2, 3, 5, 12, 12])
        XCTAssertEqual(WorldGenerator.mostHouses, 1_024)
    }

    func testEachLakeHasItsOwnShape() {
        func generator(_ lake: Lake) -> WorldGenerator { WorldGenerator(seed: 1, radius: 12, lake: lake) }
        XCTAssertEqual(generator(.round).lakeDistance(x: 0.3, y: 0.4, d: 0.5), 0.5)
        XCTAssertEqual(generator(.isles).lakeDistance(x: 0.3, y: 0.4, d: 0.5), 0.43, accuracy: 1e-12, "Wider")
        XCTAssertEqual(generator(.twin).lakeDistance(x: 0.36, y: 0, d: 0.36), 0, accuracy: 1e-12, "Two hearts")
        XCTAssertEqual(generator(.twin).lakeDistance(x: -0.36, y: 0, d: 0.36), 0, accuracy: 1e-12)
        XCTAssertEqual(generator(.crescent).lakeDistance(x: 0, y: 0.3, d: 0.3), 0.8, accuracy: 1e-12, "The land's bite")
        XCTAssertEqual(generator(.crescent).lakeDistance(x: 0, y: -0.3, d: 0.3), 0.3, accuracy: 1e-12, "Open water across from it")
        for mere in [(0.5, 0.0), (-0.5, 0.0), (0.0, 0.5), (0.0, -0.5)] {
            XCTAssertEqual(generator(.marches).lakeDistance(x: mere.0, y: mere.1, d: 0.5), 0, accuracy: 1e-12, "A mere's heart")
        }
        XCTAssertEqual(generator(.marches).lakeDistance(x: 0, y: 0, d: 0), 1.2, accuracy: 1e-12, "Dry land between the meres")
    }
}
