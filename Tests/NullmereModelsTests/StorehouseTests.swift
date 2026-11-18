import NullmereLand
@testable import NullmereModels
import XCTest

/// The Storehouse, where a city of the realm keeps its goods: within the
/// works' budget at every level, its greatest a thousand triangles over its
/// first; its hoist swinging at every level; moonsalt kept from the fourth
/// and the House's banners at its doors at the fifth.
final class StorehouseTests: XCTestCase {
    func testEachLevelStandsWithinItsBudgetAndTheGreatestOverTheFirst() {
        let counts = (1...5).map { Library.model(.work(.storehouse, level: $0)).mesh.triangleCount }
        XCTAssertTrue(counts.allSatisfy { $0 <= Estate.ceiling }, "\(counts)")
        XCTAssertGreaterThan(counts[4], counts[0] + 1000, "\(counts)")
        XCTAssertEqual(Library.model(.work(.storehouse, level: 1)).name, "storehouse 1")
    }

    func testTheHoistSwingsAtEveryLevel() throws {
        for level in 1...5 {
            let model = Library.model(.work(.storehouse, level: level))
            let hoist = try XCTUnwrap(model.rig.index(of: "store hoist"), "level \(level)")
            XCTAssertNotEqual(model.pose(.idle, at: 0)[hoist], model.pose(.idle, at: 0.35)[hoist], "The hoist swings at level \(level)")
        }
    }

    func testMoonsaltIsKeptFromTheFourthLevelAndBannersFlyAtTheFifth() {
        for level in 1...5 {
            let materials = Set(Library.model(.work(.storehouse, level: level)).mesh.vertices.map(\.material))
            XCTAssertEqual(materials.contains(.crystal), level >= 4, "moonsalt at level \(level)")
            XCTAssertEqual(materials.contains(.cloth), level == 5, "banners at level \(level)")
        }
    }
}
