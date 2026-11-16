import Foundation
import NullmereLand
import XCTest

/// The hexes the land is laid on, and their layout on the flat map.
final class HexTests: XCTestCase {
    func testEachHexHasSixNeighboursAStepAway() {
        let hex = Hex(2, -3)
        XCTAssertEqual(hex.neighbors.count, 6)
        XCTAssertEqual(Set(hex.neighbors).count, 6, "Six, none twice")
        XCTAssertTrue(hex.neighbors.allSatisfy { $0.distance(to: hex) == 1 })
        XCTAssertEqual(Hex.directions.count, 6)
        XCTAssertEqual(Hex.origin, Hex(0, 0))
        XCTAssertEqual(Hex(3, -1).length, 3)
        XCTAssertEqual(Hex(-2, 5).distance(to: Hex(1, 1)), Hex(1, 1).distance(to: Hex(-2, 5)), "As far either way")
        XCTAssertEqual(Hex(-2, 5).distance(to: Hex(1, 1)), 4)
    }

    func testARingHoldsEveryHexAtItsDistanceAndASpiralEveryHexWithin() {
        let heart = Hex(1, 2)
        XCTAssertEqual(heart.ring(0), [heart])
        for radius in 1...4 {
            let ring = heart.ring(radius)
            XCTAssertEqual(ring.count, 6 * radius)
            XCTAssertEqual(Set(ring).count, ring.count)
            XCTAssertTrue(ring.allSatisfy { $0.distance(to: heart) == radius })
        }
        XCTAssertEqual(heart.spiral(0), [heart])
        let spiral = heart.spiral(3)
        XCTAssertEqual(spiral.count, 1 + 3 * 3 * 4)
        XCTAssertEqual(Set(spiral), Set((0...3).flatMap { heart.ring($0) }), "Every hex within, ring by ring")
        XCTAssertEqual(spiral.map { $0.distance(to: heart) }, spiral.map { $0.distance(to: heart) }.sorted(), "Nearest first")
    }

    func testALineRunsStepByStepFromOneHexToAnother() {
        let from = Hex(-3, 1), to = Hex(4, -2)
        let line = from.line(to: to)
        XCTAssertEqual(line.first, from)
        XCTAssertEqual(line.last, to)
        XCTAssertEqual(line.count, from.distance(to: to) + 1)
        XCTAssertTrue(zip(line, line.dropFirst()).allSatisfy { $0.distance(to: $1) == 1 }, "Each step to a neighbour")
        XCTAssertEqual(from.line(to: from), [from])
    }

    func testHexesAddSubtractScaleAndOrderRowByRow() {
        XCTAssertEqual(Hex(1, 2) + Hex(3, -1), Hex(4, 1))
        XCTAssertEqual(Hex(1, 2) - Hex(3, -1), Hex(-2, 3))
        XCTAssertEqual(Hex(1, -2) * 3, Hex(3, -6))
        XCTAssertLessThan(Hex(5, -1), Hex(0, 0), "An earlier row first")
        XCTAssertLessThan(Hex(-1, 0), Hex(1, 0), "Then by column")
        XCTAssertEqual([Hex(1, 1), Hex(0, -1), Hex(-1, 1)].sorted(), [Hex(0, -1), Hex(-1, 1), Hex(1, 1)])
        XCTAssertEqual(Hex(1, -2).description, "(1, -2)")
    }

    func testAHexKeepsItsCoordinatesThroughCoding() throws {
        let hexes = Hex(0, 0).spiral(2)
        let data = try JSONEncoder().encode(hexes)
        XCTAssertEqual(try JSONDecoder().decode([Hex].self, from: data), hexes)
    }

    func testTheLayoutFindsEachHexAtItsCentreAndNearIt() {
        for size in [1.0, 2.5] {
            let layout = HexLayout(size: size)
            for hex in Hex(0, 0).spiral(6) {
                let centre = layout.center(of: hex)
                XCTAssertEqual(layout.hex(atX: centre.x, y: centre.y), hex)
                // A point a little way from the centre still lies in the hex.
                XCTAssertEqual(layout.hex(atX: centre.x + 0.3 * size, y: centre.y - 0.3 * size), hex)
            }
        }
        let layout = HexLayout()
        XCTAssertEqual(layout.size, 1)
        XCTAssertEqual(layout.center(of: Hex(0, 0)).x, 0)
        XCTAssertEqual(layout.center(of: Hex(0, 2)).y, 3, accuracy: 1e-12, "Rows a hex and a half apart")
        XCTAssertEqual(layout.center(of: Hex(1, 0)).x, 3.0.squareRoot(), accuracy: 1e-12, "Columns the square root of three apart")
        XCTAssertEqual(layout, HexLayout(size: 1))
    }
}
