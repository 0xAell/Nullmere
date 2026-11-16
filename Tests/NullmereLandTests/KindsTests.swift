import Foundation
import NullmereLand
import XCTest

/// The kinds of what stands on the land, the holds that stand on it, and
/// the seeded chance every world is made by.
final class KindsTests: XCTestCase {
    /// A plain kind is told apart, and hashed, by which case it is, the
    /// same as by its name; its case is its place among the kinds.
    private func holdsPlain<Kind: PlainCases & CaseIterable>(_ kind: Kind.Type, file: StaticString = #filePath, line: UInt = #line) {
        let all = Array(Kind.allCases)
        XCTAssertEqual(Set(all).count, all.count, "\(Kind.self): each its own", file: file, line: line)
        for (index, one) in all.enumerated() {
            XCTAssertEqual(Int(one.caseNumber), index, "\(Kind.self).\(one.rawValue)", file: file, line: line)
            XCTAssertEqual(Kind(rawValue: one.rawValue), one, file: file, line: line)
            for other in all {
                XCTAssertEqual(one == other, one.rawValue == other.rawValue, file: file, line: line)
            }
            XCTAssertEqual(one.hashValue, Kind(rawValue: one.rawValue)?.hashValue, file: file, line: line)
        }
    }

    func testEveryPlainKindIsToldApartByItsCase() {
        holdsPlain(Terrain.self)
        holdsPlain(Feature.self)
        holdsPlain(Resource.self)
        holdsPlain(BuildingKind.self)
        holdsPlain(UnitKind.self)
        holdsPlain(Heritage.self)
        holdsPlain(WildKind.self)
        holdsPlain(ShrineKind.self)
        holdsPlain(Lake.self)
        holdsPlain(FindKind.self)
    }

    func testWorksRiseToTheirHighestLevelInTheirOwnTime() {
        for kind in BuildingKind.allCases {
            XCTAssertEqual(kind.maxLevel, kind == .beacon ? 3 : 5, "\(kind)")
            for level in 1...kind.maxLevel {
                XCTAssertEqual(kind.buildWatches(toLevel: level), kind == .moonspire ? 3 + 3 * level : 1 + level, "\(kind) to \(level)")
            }
        }
    }

    func testEachPeopleHasACompanyOfWarOfItsOwn() {
        XCTAssertEqual(Set(UnitKind.allCases.filter(\.isMilitary)), [.spear, .bow, .rider, .mangonel])
        let signatures = Heritage.allCases.map(\.signature)
        XCTAssertTrue(signatures.allSatisfy(\.isMilitary))
        for kind in [UnitKind.spear, .bow, .rider] {
            XCTAssertEqual(signatures.filter { $0 == kind }.count, 2, "\(kind): two peoples' own")
        }
        XCTAssertEqual(Heritage.blackwood.signature, .rider)
    }

    func testAHoldBeginsBareWithTheWardItsWallsGive() {
        let seat = Hold(id: 7, name: "Ilsen", owner: 2, position: Hex(1, -1), isSeat: true, foundedWatch: 3)
        XCTAssertEqual(seat.id, 7)
        XCTAssertEqual(seat.name, "Ilsen")
        XCTAssertEqual(seat.owner, 2)
        XCTAssertEqual(seat.position, Hex(1, -1))
        XCTAssertEqual(seat.foundedWatch, 3)
        XCTAssertTrue(seat.levels.isEmpty)
        XCTAssertNil(seat.project)
        XCTAssertNil(seat.training)
        XCTAssertNil(seat.wounded)
        XCTAssertNil(seat.places)
        XCTAssertNil(seat.raisedAnew)
        XCTAssertFalse(seat.struck)
        XCTAssertEqual(seat.ward, 50, "A seat's palisade-less ward")
        XCTAssertEqual(seat.level(.granary), 0)
        var walled = seat
        walled.levels[.walls] = 3
        XCTAssertEqual(walled.level(.walls), 3)
        XCTAssertEqual(walled.maximumWard, 30 + 90 + 20)
        XCTAssertEqual(Hold.maximumWard(wallLevel: 2), 90, "A hold's, not a seat's")
        XCTAssertEqual(Hold(id: 8, name: "Fen", owner: 2, position: Hex(0, 0), isSeat: false, foundedWatch: 3).ward, 30)
        XCTAssertNotEqual(walled, seat)
        XCTAssertEqual(Hold.placeCount, 18)
    }

    func testAWorkInHandIsAsFarOnAsItsWatchesAreSpent() throws {
        var project = Hold.Project(kind: .quarry, targetLevel: 3, watchesLeft: 2)
        XCTAssertEqual(project.progress, 0.5, accuracy: 1e-12, "Two of the quarry's four watches left")
        project.watches = 8
        XCTAssertEqual(project.progress, 0.75, accuracy: 1e-12, "Two of eight, its House's hastening counted")
        project.watchesLeft = 0
        XCTAssertEqual(project.progress, 1)
        XCTAssertEqual(Hold.Project(kind: .moonspire, targetLevel: 1, watchesLeft: 6).progress, 0, accuracy: 1e-12, "Just begun")
        let coded = try JSONDecoder().decode(Hold.Project.self, from: Data(#"{"kind":"forge","targetLevel":2,"watchesLeft":1,"helpers":[4]}"#.utf8))
        XCTAssertEqual(coded, Hold.Project(kind: .forge, targetLevel: 2, watchesLeft: 1, helpers: [4]))
        XCTAssertEqual(try JSONDecoder().decode(Hold.Project.self, from: JSONEncoder().encode(coded)), coded)

        XCTAssertNil(Hold.Training(kind: .spear, watchesLeft: 2).tier, "The first tier as none")
        XCTAssertNil(Hold.Training(kind: .spear, watchesLeft: 2, tier: 1).tier)
        XCTAssertEqual(Hold.Training(kind: .bow, watchesLeft: 2, tier: 4).tier, 4)
        XCTAssertNil(Hold.Training(kind: .bow, watchesLeft: 2, tier: 4).helpers)

        let wounded = Wounded(kind: .rider, tier: 2, experience: 30, since: 12)
        XCTAssertEqual(wounded.kind, .rider)
        XCTAssertEqual(wounded.tier, 2)
        XCTAssertEqual(wounded.experience, 30)
        XCTAssertEqual(wounded.since, 12)
        XCTAssertFalse(wounded.healing)
        XCTAssertTrue(Wounded(kind: .rider, tier: 2, experience: 30, since: 12, healing: true).healing)
    }

    func testEachStoreHasItsNameColourAndMark() {
        XCTAssertEqual(Resource.allCases.map(\.title), ["Grain", "Timber", "Stone", "Moonsalt"])
        XCTAssertEqual(FindKind.allCases.map(\.title), ["hamlet", "barrow"])
        var colours: [String] = []
        for resource in Resource.allCases {
            let colour = StoreMarks.colour(of: resource)
            colours.append("\(colour.red) \(colour.green) \(colour.blue)")
            let parts = StoreMarks.drawing(of: resource)
            XCTAssertGreaterThanOrEqual(parts.count, 3, "\(resource)")
            for part in parts {
                XCTAssertGreaterThanOrEqual(part.outline.count, 3, "\(resource): a shape, not a line")
                XCTAssertTrue(part.outline.allSatisfy { (-0.01...1.01).contains($0.x) && (-0.01...1.01).contains($0.y) }, "\(resource) within its square")
                XCTAssertTrue([part.colour.red, part.colour.green, part.colour.blue].allSatisfy { (0...1).contains($0) })
            }
        }
        XCTAssertEqual(Set(colours).count, 4, "Each store its own colour")
        XCTAssertEqual(StoreMarks.Point(0.5, 0.25), StoreMarks.Point(0.5, 0.25))
    }

    func testTheSameSeedGivesTheSameChanceOnEveryMachine() {
        var one = SeededRandom(seed: 42), again = SeededRandom(seed: 42), other = SeededRandom(seed: 43)
        let first = (0..<8).map { _ in one.next() }
        XCTAssertEqual(first, (0..<8).map { _ in again.next() })
        XCTAssertNotEqual(first, (0..<8).map { _ in other.next() })
        XCTAssertEqual(one, again, "As far along")
        var counts = [Int](repeating: 0, count: 6)
        for _ in 0..<6_000 {
            let value = one.int(below: 6)
            XCTAssertTrue((0..<6).contains(value))
            counts[value] += 1
        }
        XCTAssertTrue(counts.allSatisfy { (850...1_150).contains($0) }, "Even: \(counts)")
        XCTAssertEqual(one.int(below: 1), 0)
        XCTAssertFalse((0..<100).contains { _ in one.chance(0) })
        XCTAssertTrue((0..<100).allSatisfy { _ in one.chance(100) })
        let items = ["salt", "reed", "stone"]
        XCTAssertTrue((0..<30).allSatisfy { _ in items.contains(one.pick(items)) })
        var shuffled = Array(0..<20)
        one.shuffle(&shuffled)
        XCTAssertEqual(shuffled.sorted(), Array(0..<20), "The same items")
        XCTAssertNotEqual(shuffled, Array(0..<20), "In another order")
        var single = [7]
        one.shuffle(&single)
        XCTAssertEqual(single, [7])
        var coded = SeededRandom(seed: 9)
        _ = coded.next()
        XCTAssertNoThrow(try JSONEncoder().encode(coded))
    }

    func testSeedsAndNoiseAreTheSameEverywhere() {
        XCTAssertEqual(Seed.from("the lake"), Seed.from("the lake"))
        XCTAssertNotEqual(Seed.from("the lake"), Seed.from("the lakes"))
        XCTAssertNotEqual(Seed.mix(1, 2), Seed.mix(2, 1), "Order counts")
        XCTAssertEqual(Seed.mix(5, 6, 7), Seed.mix(5, 6, 7))
        for x in -3...3 {
            for y in -3...3 {
                XCTAssertTrue((0..<1).contains(Seed.lattice(x, y, 11)))
            }
        }
        let noise = ValueNoise(seed: 3)
        XCTAssertEqual(noise.seed, 3)
        XCTAssertEqual(noise.value(2, 5), Seed.lattice(2, 5, 3), accuracy: 1e-12, "At a lattice point, its value")
        var last = noise.value(0, 0.5)
        for step in 1...100 {
            let x = Double(step) * 0.01
            let value = noise.value(x, 0.5)
            XCTAssertTrue((0...1).contains(value))
            XCTAssertLessThan(abs(value - last), 0.05, "Smooth")
            last = value
            XCTAssertTrue((0...1).contains(noise.fractal(x * 3, -x, octaves: 5)))
        }
        XCTAssertEqual(noise.fractal(1.3, 2.7), ValueNoise(seed: 3).fractal(1.3, 2.7))
    }
}
