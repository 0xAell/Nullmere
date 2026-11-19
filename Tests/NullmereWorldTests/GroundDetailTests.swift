import Foundation
@testable import NullmereWorld
import XCTest

/// The ground's detail close to: a small picture of grass clumps, grit and
/// mottle that tiles, each channel about a half so it changes no colour's
/// mean, and a salt pan's crust in its alpha; its levels for drawing far
/// off each the mean of the larger.
final class GroundDetailTests: XCTestCase {
    private func channel(_ c: Int, _ pixels: [UInt8] = GroundDetail.pixels) -> [Float] {
        stride(from: c, to: pixels.count, by: 4).map { Float(pixels[$0]) / 255 }
    }

    func testEachChannelSwingsAboutAHalf() {
        let side = GroundDetail.side
        XCTAssertEqual(GroundDetail.pixels.count, side * side * 4)
        for c in 0..<3 {
            let values = channel(c)
            let mean = values.reduce(Float(0), +) / Float(values.count)
            let spread = (values.reduce(Float(0)) { $0 + ($1 - mean) * ($1 - mean) } / Float(values.count)).squareRoot()
            XCTAssertEqual(mean, 0.5, accuracy: 0.02, "channel \(c) about a half")
            XCTAssertEqual(spread, GroundDetail.swing, accuracy: 0.03, "channel \(c) swings as it should")
        }
    }

    /// Its alpha, the salt's crust: thin bright rims about dark floors, a
    /// network of polygons, each rim full where two polygons meet.
    func testItsAlphaIsASaltPansCrust() {
        let crust = channel(3)
        let mean = crust.reduce(Float(0), +) / Float(crust.count)
        XCTAssertGreaterThan(mean, 0.06, "rims enough to be seen")
        XCTAssertLessThan(mean, 0.2, "the floors the most of it")
        let rims = crust.filter { $0 > 0.5 }.count, floors = crust.filter { $0 < 0.05 }.count
        XCTAssertGreaterThan(Float(rims) / Float(crust.count), 0.04)
        XCTAssertLessThan(Float(rims) / Float(crust.count), 0.2, "rims thin")
        XCTAssertGreaterThan(Float(floors) / Float(crust.count), 0.6, "floors wide")
        XCTAssertGreaterThan(crust.max() ?? 0, 0.95, "full on an edge")
        // On an edge, a full rim; half a cell in from every edge, none.
        XCTAssertEqual(GroundDetail.rim(0.5, 0.5, cells: GroundDetail.crust, seed: 71),
                       Float(exp(-pow(Double(GroundDetail.border(0.5, 0.5, cells: GroundDetail.crust, seed: 71) / GroundDetail.rimWidth), 2))),
                       accuracy: 1e-5)
        XCTAssertEqual(Float(exp(-pow(0.5 / Double(GroundDetail.rimWidth), 2))), 0, accuracy: 1e-6)
    }

    /// Every point lies in its own polygon, measured to the nearest of its
    /// edges, never as far as a cell from one.
    func testEveryPointLiesInItsPolygon() {
        let n = 32
        for y in 0..<n {
            for x in 0..<n {
                let border = GroundDetail.border((Float(x) + 0.5) / Float(n), (Float(y) + 0.5) / Float(n), cells: GroundDetail.crust, seed: 71)
                XCTAssertGreaterThanOrEqual(border, 0)
                XCTAssertLessThan(border, 1)
            }
        }
    }

    /// Its right edge runs on into its left and its foot into its head: the
    /// step across the seam no greater than across its own columns and rows.
    func testItTilesWithoutASeam() {
        let n = GroundDetail.side
        for c in 0..<4 {
            let values = channel(c)
            func at(_ x: Int, _ y: Int) -> Float { values[y * n + x] }
            var inner: Float = 0, seam: Float = 0, innerRows: Float = 0, seamRows: Float = 0
            for y in 0..<n {
                for x in 0..<(n - 1) { inner += abs(at(x + 1, y) - at(x, y)) }
                seam += abs(at(0, y) - at(n - 1, y))
            }
            for x in 0..<n {
                for y in 0..<(n - 1) { innerRows += abs(at(x, y + 1) - at(x, y)) }
                seamRows += abs(at(x, 0) - at(x, n - 1))
            }
            inner /= Float(n * (n - 1))
            innerRows /= Float(n * (n - 1))
            XCTAssertLessThanOrEqual(seam / Float(n), 2 * inner + 0.01, "channel \(c) across its sides")
            XCTAssertLessThanOrEqual(seamRows / Float(n), 2 * innerRows + 0.01, "channel \(c) across its head and foot")
        }
    }

    /// Each level half the side of the last, to a single pixel, every
    /// pixel the mean of the four it covers: far off, only the mean.
    func testItsLevelsAreItsMeansFarOff() {
        let levels = GroundDetail.levels
        XCTAssertEqual(levels.count, 8, "128 down to 1")
        for (index, level) in levels.enumerated() {
            let side = GroundDetail.side >> index
            XCTAssertEqual(level.count, side * side * 4)
        }
        let last = levels[levels.count - 1]
        for c in 0..<3 {
            XCTAssertEqual(Float(last[c]) / 255, 0.5, accuracy: 0.03, "channel \(c) far off")
        }
        let crust = channel(3)
        XCTAssertEqual(Float(last[3]) / 255, crust.reduce(Float(0), +) / Float(crust.count), accuracy: 0.02, "the crust far off its mean")
        // A pixel of the second level, the mean of the four under it.
        let first = levels[0], second = levels[1], n = GroundDetail.side
        let sum = Int(first[0]) + Int(first[4]) + Int(first[n * 4]) + Int(first[n * 4 + 4])
        XCTAssertEqual(Int(second[0]), (sum + 2) / 4)
    }

    /// The shaders lay it as often across a unit of the land as it says.
    func testTheShadersLayItAsItSays() {
        XCTAssertTrue(WorldShaders.source.contains("kDetailPerUnit = \(GroundDetail.perUnit);"))
        XCTAssertTrue(WorldShaders.source.contains("NM_DETAIL("), "read by the land's shading")
        XCTAssertTrue(WorldShaders.source.contains("max(laid.a, turned.a)"), "the two crusts laid one over the other")
        XCTAssertTrue(WorldShaders.source.contains("kSaltCrust * crust * rims"), "read by the salt alone")
    }

    func testTheSameEveryTime() {
        XCTAssertEqual(GroundDetail.make(), GroundDetail.pixels)
    }
}
