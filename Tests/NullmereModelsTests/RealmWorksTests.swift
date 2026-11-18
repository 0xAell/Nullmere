import NullmereLand
@testable import NullmereModels
import XCTest

/// The works of the realm's own buildings that no hold had before it, the
/// Storehouse's fellows: each within the works' ceiling at every level and
/// its greatest a thousand triangles over its first, and each with its own
/// part moving through its idle, at the levels it has it.
final class RealmWorksTests: XCTestCase {
    static let kinds: [BuildingKind] = [.scoutCamp, .range, .tavern, .embassy, .market]

    func testEachStandsWithinTheCeilingAndGrows() {
        for kind in RealmWorksTests.kinds {
            let counts = (1...5).map { Library.model(.work(kind, level: $0)).mesh.triangleCount }
            XCTAssertTrue(counts.allSatisfy { $0 <= Estate.ceiling }, "\(kind): \(counts)")
            XCTAssertGreaterThan(counts[4], counts[0] + 1000, "\(kind): \(counts)")
        }
    }

    /// The bone that moves at each level, and the levels it is there.
    static let moving: [(BuildingKind, String, ClosedRange<Int>)] = [
        (.scoutCamp, "camp fire", 1...5), (.range, "hung target", 2...5), (.tavern, "garland", 1...2), (.tavern, "kiln cowl", 3...5),
        (.embassy, "vane", 1...5), (.embassy, "bell", 5...5), (.market, "weigh beam", 1...5),
    ]

    func testEachMovesThroughItsIdle() throws {
        for (kind, bone, levels) in RealmWorksTests.moving {
            for level in 1...5 {
                let model = Library.model(.work(kind, level: level))
                let index = model.rig.index(of: bone)
                XCTAssertEqual(index != nil, levels.contains(level), "\(kind)'s \(bone) at level \(level)")
                if let index {
                    XCTAssertNotEqual(model.pose(.idle, at: 0.1)[index], model.pose(.idle, at: 0.35)[index], "\(kind)'s \(bone) moves at level \(level)")
                }
            }
        }
    }

    func testTheirFiresAndTheHousesCloth() {
        let colours = { (kind: BuildingKind, level: Int) in Set(Library.model(.work(kind, level: level)).mesh.vertices.map(\.material)) }
        // The camp's fire and the kiln's are lit.
        XCTAssertTrue((1...5).allSatisfy { colours(.scoutCamp, $0).contains(.glow) })
        XCTAssertTrue((3...5).allSatisfy { colours(.tavern, $0).contains(.glow) })
        // The market's awnings and the tavern's are the House's cloth; the
        // embassy flies the House's banner at every level.
        XCTAssertTrue((1...5).allSatisfy { colours(.market, $0).contains(.house) })
        XCTAssertTrue((2...5).allSatisfy { colours(.tavern, $0).contains(.house) })
        XCTAssertTrue((1...5).allSatisfy { colours(.embassy, $0).contains(.cloth) })
        XCTAssertEqual(Library.model(.work(.scoutCamp, level: 1)).name, "scoutCamp 1")
    }
}
