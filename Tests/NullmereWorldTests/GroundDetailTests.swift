@testable import NullmereWorld
import XCTest

/// The ground's detail close to: a small picture of grass clumps, grit and
/// mottle that tiles, each channel about a half so it changes no colour's
/// mean, its levels for drawing far off each the mean of the larger.
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
        XCTAssertTrue(channel(3).allSatisfy { $0 == 1 }, "alpha full")
    }

    /// Its right edge runs on into its left and its foot into its head: the
    /// step across the seam no greater than across its own columns and rows.
    func testItTilesWithoutASeam() {
        let n = GroundDetail.side
        for c in 0..<3 {
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
        XCTAssertEqual(last[3], 255)
        // A pixel of the second level, the mean of the four under it.
        let first = levels[0], second = levels[1], n = GroundDetail.side
        let sum = Int(first[0]) + Int(first[4]) + Int(first[n * 4]) + Int(first[n * 4 + 4])
        XCTAssertEqual(Int(second[0]), (sum + 2) / 4)
    }

    /// The shaders lay it as often across a unit of the land as it says.
    func testTheShadersLayItAsItSays() {
        XCTAssertTrue(WorldShaders.source.contains("kDetailPerUnit = \(GroundDetail.perUnit);"))
        XCTAssertTrue(WorldShaders.source.contains("NM_DETAIL("), "read by the land's shading")
    }

    func testTheSameEveryTime() {
        XCTAssertEqual(GroundDetail.make(), GroundDetail.pixels)
    }
}
