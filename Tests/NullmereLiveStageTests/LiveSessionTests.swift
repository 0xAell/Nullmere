import Foundation
#if canImport(CoreGraphics)
// CGPoint's Equatable on a Mac is CoreGraphics', not Foundation's.
import CoreGraphics
#endif
import NullmereLand
@testable import NullmereLive
@testable import NullmereLiveStage
import NullmereModels
import NullmereRealm
import NullmereTestSupport
@testable import NullmereWorld
import XCTest

/// A player's session over a line: what it reads, the window it keeps
/// about where the player looks, what it stages, what is chosen, and what
/// it asks. The world is `LiveWindowTests`' own: Ada's city at 10, -4.
@MainActor
final class LiveSessionTests: XCTestCase {
    private func n(_ value: Int) -> JSONValue { .number(Double(value)) }
    private func n(_ value: UInt64) -> JSONValue { .number(Double(value)) }

    /// A session on the stand-in line at a moment of the realm's clock.
    private func session(_ line: StandInLine, at seconds: Double = 2_015) -> LiveSession {
        LiveSession(line: line) { seconds }
    }

    func testASessionOpensOnTheRealmAndAsksANameOfWhoHasNone() async throws {
        // A realm that can't be reached.
        let nowhere = session(StandInLine(reachable: false))
        XCTAssertEqual(nowhere.phase, .opening)
        await nowhere.open()
        XCTAssertEqual(nowhere.phase, .lost)
        XCTAssertNil(nowhere.window)

        // A door that won't open: the same, and asking says so; tried
        // again once it will, the session is in.
        let tries = Tries()
        let shut = LiveSession(opening: {
            guard tries.next() > 1 else { throw URLError(.cannotConnectToHost) }
            return StandInLine(rows: LiveWindowTests.rows())
        }, clock: { 2_015 })
        await shut.open()
        XCTAssertEqual(shut.phase, .lost)
        await shut.build(2)
        XCTAssertEqual(shut.said, LiveSession.unreached)
        shut.refresh()
        XCTAssertEqual(shut.phase, .lost)
        await shut.open()
        XCTAssertEqual(shut.phase, .playing)
        XCTAssertEqual(shut.world.me?.name, "Ada")

        // A realm whose rows have not come yet; then they come, and the
        // player has no city there: a name is wanted.
        var rows = LiveWindowTests.rows()
        let (me, city) = (rows.removeValue(forKey: "me"), rows.removeValue(forKey: "my_city"))
        rows["my_buildings"] = []
        let line = StandInLine()
        let session = session(line)
        await session.open()
        XCTAssertEqual(session.phase, .opening)
        XCTAssertNil(session.window, "nothing to draw of a realm not yet read")
        line.change { $0 = rows }
        session.refresh()
        XCTAssertEqual(session.phase, .naming)
        XCTAssertEqual(session.window?.centre, LiveHex(q: 0, r: 0), "the lake, until they have a city to look at")
        XCTAssertEqual(session.windowVersion, 1)

        // They join: the realm's rows bring their city, and the look goes to it.
        await session.join(name: "Ada")
        XCTAssertEqual(line.asked, ["join Ada"])
        line.change {
            $0["me"] = me
            $0["my_city"] = city
        }
        session.refresh()
        XCTAssertEqual(session.phase, .playing)
        XCTAssertEqual(session.look, LiveHex(q: 10, r: -4))
        XCTAssertEqual(session.window?.centre, LiveHex(q: 10, r: -4))
        XCTAssertEqual(session.window?.radius, LiveSession.reach)
        XCTAssertEqual(session.windowVersion, 2)
        XCTAssertEqual(session.world.me?.name, "Ada")
        XCTAssertNil(session.said)

        // What the line is told, the session is told: rows pushed reach it.
        line.change { $0["city"]?.append([self.n(9), self.n(3), self.n(LiveHex(q: 12, r: -6).packed), .string("Cato"), self.n(1), self.n(140), self.n(1_000), self.n(1)]) }
        for _ in 0..<50 where session.world.cities.count < 3 { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(session.world.cities.count, 3, "pushed, with no one asking")
        session.close()
        XCTAssertEqual(line.asked.last, "close")
    }

    func testTheWindowFollowsTheLookOnceItStrays() async throws {
        let line = StandInLine(rows: LiveWindowTests.rows())
        let session = session(line)
        await session.open()
        XCTAssertEqual(session.phase, .playing)
        XCTAssertEqual([session.windowVersion, session.standingVersion], [1, 1])
        let land = try XCTUnwrap(session.land())
        XCTAssertEqual(land.map.radius, LiveSession.reach)
        XCTAssertEqual(land.map[Hex(0, 0)]?.terrain, .greyfield)
        XCTAssertEqual(land.terrain.columns > 10, true)

        // A little way: the same window, the same land.
        session.look(at: LiveHex(q: 15, r: -4))
        XCTAssertEqual(session.look, LiveHex(q: 15, r: -4))
        XCTAssertEqual(session.window?.centre, LiveHex(q: 10, r: -4))
        XCTAssertEqual(session.windowVersion, 1)
        // Past eight hexes from its heart: another, about where they look.
        session.look(at: LiveHex(q: 19, r: -4))
        XCTAssertEqual(session.window?.centre, LiveHex(q: 19, r: -4))
        XCTAssertEqual([session.windowVersion, session.standingVersion], [2, 2])
        XCTAssertEqual(try XCTUnwrap(session.land()).map[Hex(0, 0)]?.terrain, .blackwood, "the wood east of the sixteenth column")
        session.look(at: LiveHex(q: 19, r: -4))
        XCTAssertEqual(session.windowVersion, 2, "looking where they look already changes nothing")

        // What stands in the window: a city founded in it is noted, one far off is not.
        line.change { $0["city"]?.append([self.n(9), self.n(3), self.n(LiveHex(q: 20, r: -6).packed), .string("Cato"), self.n(1), self.n(140), self.n(1_000), self.n(1)]) }
        session.refresh()
        XCTAssertEqual([session.windowVersion, session.standingVersion], [2, 3])
        line.change { $0["city"]?.append([self.n(10), self.n(4), self.n(LiveHex(q: -30, r: 0).packed), .string("Dara"), self.n(1), self.n(140), self.n(1_000), self.n(1)]) }
        session.refresh()
        XCTAssertEqual([session.windowVersion, session.standingVersion], [2, 3])
        // An army on the move changes nothing that stands.
        line.change { $0["march"]?.removeLast() }
        session.refresh()
        XCTAssertEqual([session.windowVersion, session.standingVersion], [2, 3])
    }

    func testARealmsAddressIsReadAndItsPlayerKept() async throws {
        let read = try XCTUnwrap(LiveDoor.address(" https://maincloud.spacetimedb.com/nullmere-online\n"))
        XCTAssertEqual(read.server.absoluteString, "https://maincloud.spacetimedb.com")
        XCTAssertEqual(read.database, "nullmere-online")
        let local = try XCTUnwrap(LiveDoor.address("http://127.0.0.1:3000/nullmere_check/"))
        XCTAssertEqual([local.server.absoluteString, local.database], ["http://127.0.0.1:3000", "nullmere_check"])
        for text in ["", "nullmere-online", "https://maincloud.spacetimedb.com", "https://maincloud.spacetimedb.com/", "ftp://example.com/realm",
                     "https://example.com/a/b", "https://example.com/a b", "https:///realm", "https://example.com/realm;drop"] {
            XCTAssertNil(LiveDoor.address(text), text)
        }

        // The player a store keeps is the player the door opens as.
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("nullmere-door-\(UUID().uuidString)").appendingPathComponent("key")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = FileIdentityStore(url: file)
        XCTAssertNil(LiveDoor.kept(in: store), "no one yet")
        let credentials = SpacetimeCredentials(identity: "c200ab", token: "a.token")
        try store.save(String(decoding: try JSONEncoder().encode(credentials), as: UTF8.self))
        XCTAssertEqual(LiveDoor.kept(in: store), credentials)
        let client = try await LiveDoor.open(server: local.server, database: local.database, keeping: store)
        XCTAssertEqual(client.credentials, credentials, "opened as the one kept, with no word to the server")
        try store.save("not a key")
        XCTAssertNil(LiveDoor.kept(in: store))
    }

    func testTheCameraKeepsItsPlaceAsTheWindowMoves() async throws {
        let line = StandInLine(rows: LiveWindowTests.rows())
        let session = session(line)
        await session.open()
        XCTAssertEqual([session.camera.centerX, session.camera.centerY], [0, 0], "opened on her city, at the window's heart")
        XCTAssertEqual(session.camera.scale, LiveSession.openingScale)

        // Panned four hexes east: the look follows, the window stays.
        var camera = session.camera
        camera.centerX = 4 * 3.0.squareRoot()
        session.moved(camera)
        XCTAssertEqual(session.look, LiveHex(q: 14, r: -4))
        XCTAssertEqual(session.windowVersion, 1)
        XCTAssertEqual(session.camera.centerX, 4 * 3.0.squareRoot(), accuracy: 1e-9)

        // Ten hexes east: the window is taken afresh about the look, and
        // the camera is at that window's heart: the same place in the world.
        camera.centerX = 10 * 3.0.squareRoot()
        session.moved(camera)
        XCTAssertEqual(session.look, LiveHex(q: 20, r: -4))
        XCTAssertEqual(session.window?.centre, LiveHex(q: 20, r: -4))
        XCTAssertEqual(session.windowVersion, 2)
        XCTAssertEqual(session.camera.centerX, 0, accuracy: 1e-9)
        XCTAssertEqual(session.camera.centerY, 0, accuracy: 1e-9)
        // A little south-east in the new window: no new window, the camera as it was put.
        camera = session.camera
        (camera.centerX, camera.centerY) = (3.0.squareRoot() / 2, 1.5)
        session.moved(camera)
        XCTAssertEqual(session.look, LiveHex(q: 20, r: -3))
        XCTAssertEqual(session.windowVersion, 2)
        XCTAssertEqual(session.camera.centerY, 1.5, accuracy: 1e-9)

        // Drawn back no further than keeps the window's rim out of sight.
        camera.scale = 5
        session.moved(camera)
        XCTAssertEqual(session.camera.scale, LiveSession.furthestScale)

        // Turned to a hex far off: a window about it, the camera on it.
        session.go(to: LiveHex(q: -20, r: 9))
        XCTAssertEqual(session.window?.centre, LiveHex(q: -20, r: 9))
        XCTAssertEqual([session.camera.centerX, session.camera.centerY], [0, 0])
        // And to one nearby: the same window, the camera moved over it.
        session.go(to: LiveHex(q: -18, r: 9))
        XCTAssertEqual(session.window?.centre, LiveHex(q: -20, r: 9))
        XCTAssertEqual(session.camera.centerX, 2 * 3.0.squareRoot(), accuracy: 1e-9)

        // A hex of the window chosen is a hex of the world.
        session.choose(local: Hex(3, -1))
        XCTAssertEqual(session.selected, LiveHex(q: -17, r: 8))
        XCTAssertEqual(session.selectedLocal, Hex(3, -1))
        session.go(to: LiveHex(q: 10, r: -4))
        XCTAssertNil(session.selectedLocal, "chosen still, but out of the window now")
        XCTAssertEqual(session.selected, LiveHex(q: -17, r: 8))
        session.choose(local: nil)
        XCTAssertNil(session.selected)
    }

    func testTheWindowIsStagedForTheRendererAtAMoment() async throws {
        let line = StandInLine(rows: LiveWindowTests.rows())
        let session = session(line)
        XCTAssertEqual(session.frame(time: 0).instanceCount, 0, "nothing before the realm is read")
        XCTAssertNil(session.tiles())
        await session.open()
        let frame = session.frame(time: 20)
        XCTAssertGreaterThan(frame.fixed.reduce(0) { $0 + $1.instances.count }, 100, "the land's own furniture")
        XCTAssertTrue(frame.batches.contains { if case .keep = $0.key { return true } else { return false } }, "a Keep")
        XCTAssertTrue(frame.batches.contains { $0.key == .figure(.rider, tier: 2) }, "Ada's riders on the road")
        XCTAssertTrue(frame.batches.contains { $0.key == .site(.timber) }, "the grove")
        XCTAssertTrue(frame.batches.contains { $0.key == .lair(.barrowkin) }, "the barrow")
        XCTAssertEqual(frame.fixedVersion, 100_001)
        // The next frame keeps the furniture as it is: the GPU is sent it once.
        let next = session.frame(time: 20.1)
        XCTAssertEqual(next.fixedVersion, frame.fixedVersion)
        XCTAssertEqual(next.fixed, frame.fixed)
        // A new window, new furniture.
        session.look(at: LiveHex(q: 19, r: -4))
        XCTAssertEqual(session.frame(time: 20.2).fixedVersion, 200_002)

        // The tiles: all of the window watched, a hold where each city stands.
        let tiles = try XCTUnwrap(session.tiles())
        let side = 2 * LiveSession.reach + 1
        XCTAssertEqual(tiles.count, side * side * 4)
        let cityAt = ((0 + LiveSession.reach) * side + (-9 + LiveSession.reach)) * 4
        XCTAssertEqual(tiles[cityAt + 1] & TileTexture.holdFlag, TileTexture.holdFlag, "Ada's city, nine hexes west of the window's heart")
        XCTAssertEqual(LiveSession.colours.count, 24)
        XCTAssertEqual(Set(LiveSession.colours.map { [$0.x, $0.y, $0.z] }).count, 24, "no two alike")
    }

    func testWhatLiesAtAHexIsChosen() async throws {
        let line = StandInLine(rows: LiveWindowTests.rows())
        let session = session(line)
        await session.open()
        XCTAssertNil(session.selection)

        guard case .home(let home) = session.selection(at: LiveHex(q: 10, r: -4)) else { return XCTFail("her own city") }
        XCTAssertEqual(home.id, 7)
        guard case .city(let other, let owner) = session.selection(at: LiveHex(q: 14, r: -4)) else { return XCTFail("another's city") }
        XCTAssertEqual([String(other.id), owner], ["8", "Bryn"])
        guard case .site(let site) = session.selection(at: LiveHex(q: 12, r: -2)) else { return XCTFail("the grove, though an army works it") }
        XCTAssertEqual(site.kind, 2)
        guard case .barrow(let barrow) = session.selection(at: LiveHex(q: 8, r: -2)) else { return XCTFail("the barrow, though an army fights there") }
        XCTAssertEqual(barrow.level, 2)
        // Ada's army, fifteen seconds along: between 11, -3 and 11, -2, nearer neither; a second on, past the middle.
        let later = self.session(line, at: 2_017)
        await later.open()
        guard case .army(let march, let own) = later.selection(at: LiveHex(q: 11, r: -2)) else { return XCTFail("her army on the road") }
        XCTAssertEqual(march.id, 3)
        XCTAssertTrue(own)
        guard case .land(let hex, let ground) = session.selection(at: LiveHex(q: 5, r: 5)) else { return XCTFail("bare land") }
        XCTAssertEqual([hex.q, hex.r], [5, 5])
        XCTAssertEqual(ground, 4)
        guard case .land(_, let unknown) = session.selection(at: LiveHex(q: 500, r: 0)) else { return XCTFail("land never told") }
        XCTAssertNil(unknown)

        session.selected = LiveHex(q: 12, r: -2)
        XCTAssertEqual(session.selection, .site(site))
        XCTAssertEqual(session.everyoneReady.count, 0, "no one stands ready in these rows")
    }

    /// A building of the player's own city is chosen where it stands on the
    /// map, by a click whose ray meets it: its card tells its level, what
    /// the next costs and why it can't be had yet, with a way to raise it
    /// and to open the city's buildings; pressed once it can be, the realm
    /// is asked. A click on the keep chooses the city, and choosing anything
    /// else puts the building away.
    func testABuildingOfTheCityIsChosenWhereItStands() async throws {
        var rows = LiveWindowTests.rows()
        func blueprint(_ kind: Int, _ level: Int, _ name: String) -> [JSONValue] {
            [n(kind << 32 | level), n(kind), n(level), .string(name), n(0), n(100 * level), n(0), n(0), n(10 * level), n(0), n(0), n(0), n(0),
             n(1), n(0), n(0), n(20 * level)]
        }
        rows["blueprint"] = [blueprint(2, 1, "Farm"), blueprint(2, 3, "Farm"), blueprint(7, 1, "Barracks")]
        let line = StandInLine(rows: rows)
        let session = session(line)
        await session.open()
        // Her Farm, of the second level, drawn as the first of the works' five heights.
        let frame = session.frame(time: 1)
        let farm = try XCTUnwrap(frame.batches.first { $0.key == .work(.granary, level: 1) }?.instances.first).model.c3
        let local = try XCTUnwrap(session.window?.local(LiveHex(q: 10, r: -4)))
        let down = Vec3(0, -1, 0)
        session.choose(local: local, ray: (Vec3(farm.x, farm.y + 10, farm.z), down))
        let city = try XCTUnwrap(session.world.city)
        XCTAssertEqual(session.selection, .work(2, in: city))
        XCTAssertEqual(session.selected, LiveHex(q: 10, r: -4), "her city's hex")
        let chosen = try XCTUnwrap(session.chosenWork)
        XCTAssertEqual(chosen.foot.x, farm.x, accuracy: 1e-4)
        XCTAssertEqual(chosen.foot.z, farm.z, accuracy: 1e-4)
        let card = session.card(for: try XCTUnwrap(session.selection))
        XCTAssertEqual(card.title, "Farm")
        XCTAssertEqual(card.lines, ["Level 2.", "Brings in grain.", "Level 3 takes 300 timber, 30 seconds."])
        XCTAssertEqual(card.buttons.map(\.title), ["Upgrade to level 3", "Buildings"])
        XCTAssertEqual(card.buttons.first?.why, "You need 300 timber more.")
        XCTAssertEqual(card.buttons.first?.icon, "arrow.up.circle")
        XCTAssertEqual(session.mapItems().first?.kind, .home, "the city is still read as hers")

        // With timber enough, pressed, the realm is asked to raise it.
        let stock: [[JSONValue]] = [[n(7), n(60_000), n(60_000), n(60_000), n(0), n(2_000), n(0), n(0), n(0), n(0), n(0), n(0), n(0), n(0), n(200_000)]]
        line.change { $0["my_stock"] = stock }
        session.refresh()
        let ready = session.card(for: try XCTUnwrap(session.selection))
        XCTAssertNil(ready.buttons[0].why)
        line.clear()
        await session.press(ready.buttons[0])
        XCTAssertTrue(line.asked.contains("upgrade 22"), "\(line.asked)")

        // A plot of her city: the Barracks she has not built, where it
        // would stand; the Farm, standing, has none. Chosen, its card asks
        // it built.
        let plots = session.plots()
        let barracks = try XCTUnwrap(plots.first { $0.kind == 7 }, "\(plots)")
        XCTAssertFalse(plots.contains { $0.kind == 2 }, "the Farm stands already")
        session.choose(barracks)
        XCTAssertEqual(session.selection, .work(7, in: city))
        let plot = session.card(for: try XCTUnwrap(session.selection))
        XCTAssertEqual(plot.title, "Barracks")
        XCTAssertEqual(plot.lines, ["Not built yet.", "Trains spearmen.", "Building it takes 100 timber, 10 seconds."])
        XCTAssertEqual((1...19).compactMap(LiveWorld.buildingWords).count, 19, "every building of the catalogue says what it does")
        XCTAssertNil(LiveWorld.buildingWords(20))
        XCTAssertEqual(plot.buttons.map(\.title), ["Build", "Buildings"])
        XCTAssertEqual(plot.buttons[0].icon, "hammer")
        line.clear()
        await session.press(plot.buttons[0])
        XCTAssertTrue(line.asked.contains("build 7"), "\(line.asked)")

        // The keep, at the city's heart, chooses the city itself.
        let heart = Relief.centre(of: local)
        session.choose(local: local, ray: (Vec3(heart.x, 10, heart.z), down))
        guard case .home = session.selection else { return XCTFail("the keep chooses her city") }
        XCTAssertNil(session.chosenWork)
        // Chosen again, then the grove: the Farm is put away.
        session.choose(local: local, ray: (Vec3(farm.x, farm.y + 10, farm.z), down))
        XCTAssertNotNil(session.chosenWork)
        session.selected = LiveHex(q: 12, r: -2)
        XCTAssertNil(session.chosenWork)
        guard case .site = session.selection else { return XCTFail("the grove") }

        // The city's list raises a building: upgrading what stands, building what does not.
        let lines = session.world.buildingLines(at: 2_015)
        line.clear()
        await session.raise(try XCTUnwrap(lines.first { $0.kind == 2 }))
        await session.raise(try XCTUnwrap(lines.first { $0.kind == 7 }))
        XCTAssertEqual(line.asked.filter { $0.hasPrefix("upgrade") || $0.hasPrefix("build") }, ["upgrade 22", "build 7"])
    }

    func testWhatIsChosenIsToldOnACardWithWhatCanBeDone() async throws {
        var rows = LiveWindowTests.rows()
        rows["my_troops"] = [[n(7 << 16 | 1 << 8 | 1), n(7), n(1), n(1), n(40), n(0)]]
        rows["my_hunt"] = [[n(1), n(1_000), n(2_000), n(1_000), n(8_000), n(1)]]
        rows["blueprint"] = [[n(2 << 32 | 1), n(2), n(1), .string("Farm"), n(0), n(100), n(0), n(0), n(10), n(0), n(0), n(0), n(0), n(1), n(0), n(0), n(20)]]
        rows["my_jobs"] = [[n(4), n(7), n(1), n(22), n(3), n(0), n(2_000), n(2_100), n(9)]]
        // A second barrow no one is at, of the fourth level; a second site no one works.
        rows["barrow"]?.append([n(10), n(LiveHex(q: 6, r: -1).packed), n(4), n(0)])
        rows["place"]?.append([n(LiveHex(q: 6, r: -1).packed), n(3), n(10)])
        rows["barrow"]?.append([n(11), n(LiveHex(q: 6, r: 0).packed), n(2), n(0)])
        rows["place"]?.append([n(LiveHex(q: 6, r: 0).packed), n(3), n(11)])
        rows["site"]?.append([n(6), n(LiveHex(q: 7, r: 1).packed), n(1), n(2), n(40_000), n(0)])
        rows["place"]?.append([n(LiveHex(q: 7, r: 1).packed), n(2), n(6)])
        let line = StandInLine(rows: rows)
        let session = session(line)
        await session.open()
        func card(_ q: Int, _ r: Int) -> LiveCard { session.card(for: session.selection(at: LiveHex(q: q, r: r))) }

        // Her city: what it is, what it is raising, and its two doors.
        let home = card(10, -4)
        XCTAssertEqual(home.title, "Ada")
        XCTAssertEqual(home.lines, ["Your city. Keep level 3, power 1,000.", "Farm to level 3: 1:25"])
        XCTAssertEqual(home.buttons.map(\.title), ["Buildings", "Troops", "Hasten the Farm to level 3"])
        XCTAssertEqual(home.buttons.map(\.act), [.city, .troops, .hasten(4)])
        XCTAssertEqual(home.buttons.map(\.icon), ["building.2", "person.3", "forward.fill"], "each drawn as a symbol in the ring about it")
        XCTAssertEqual(home.buttons[2].why, "Hastening takes 300 grain, 300 timber and 300 stone.", "no goods in her city to hasten with")
        let acts: [LiveCard.Act] = [.city, .troops, .send, .recall(1), .rally, .raiseWard, .razeWard(1), .scout, .reinforce, .explore, .hasten(1), .moveCity]
        XCTAssertEqual(Set(acts.map { LiveCard.Button(title: "", act: $0, why: nil).icon }).count, acts.count, "no two acts drawn alike")
        XCTAssertEqual(LiveCard.Button(title: "Gather with 40 soldiers", act: .send, why: nil).icon, "shippingbox")
        // Ada has one army out and a Keep of the third level: no second
        // army may go, wherever it is sent.
        let oneOut = "Your one army is out. Raise your Keep to send more."
        // Another's: whose, that they are here, and that it may be attacked or scouted.
        XCTAssertEqual(card(14, -4), LiveCard(title: "Bryn", lines: ["Bryn's city. Keep level 8, power 9,000. They are here now."],
                                              buttons: [.init(title: "Attack with 40 soldiers", act: .send, why: oneOut),
                                                        .init(title: "Scout", act: .scout, why: "Raise a Scout Camp first.")]))
        XCTAssertEqual(card(7, 1), LiveCard(title: "Grain, level 2", lines: ["40,000 left to gather."],
                                            buttons: [.init(title: "Gather with 40 soldiers", act: .send, why: oneOut)]))
        // The grove Bryn's army works; the barrow his other army fights at.
        let grove = card(12, -2)
        XCTAssertEqual(grove.title, "Timber, level 4")
        // Whose army gathers there, said once (its line and Gather's why
        // the same words); and that it may be fallen on.
        XCTAssertEqual(grove.lines, ["80,000 left to gather.", "Bryn's army is gathering here."])
        XCTAssertEqual(grove.buttons, [.init(title: "Gather with 40 soldiers", act: .send, why: "Bryn's army is gathering here."),
                                       .init(title: "Attack it with 40 soldiers", act: .raid, why: oneOut)])
        XCTAssertEqual(grove.buttons.last?.icon, "flame")
        let fought = card(8, -2)
        XCTAssertEqual(fought.title, "Barrow, level 2")
        XCTAssertEqual(fought.lines, ["The Unquiet hold it. An attack takes 50 energy."])
        XCTAssertEqual(fought.buttons.first?.why, "Another army is fighting there.")
        // A barrow two levels above the one she has cleared.
        XCTAssertEqual(card(6, -1).buttons.first?.why, "Clear a level 3 barrow first.")
        XCTAssertEqual(card(6, 0).buttons.first, .init(title: "Attack with 40 soldiers", act: .send, why: oneOut))

        // With her army home, both may be sent for; pressed, everyone ready goes.
        line.change { $0["march"]?.removeFirst() }
        session.refresh()
        XCTAssertNil(card(7, 1).buttons.first?.why)
        XCTAssertNil(card(6, 0).buttons.first?.why)
        session.selected = LiveHex(q: 6, r: 0)
        await session.press(card(6, 0).buttons[0])
        XCTAssertEqual(line.asked, ["hunt at 6, 0 with 40 of 1.1"])
        // And the army gathering at the grove may be fallen on.
        XCTAssertNil(card(12, -2).buttons.last?.why)
        session.selected = LiveHex(q: 12, r: -2)
        await session.press(card(12, -2).buttons[1])
        XCTAssertEqual(line.asked.last, "raid 12,-2 with 40 of 1.1 led by 0")
        session.selected = LiveHex(q: 6, r: 0)
        // With commanders, the highest of those in the city leads, and the
        // card says who; one named leads instead.
        line.change { $0["my_commanders"] = [[self.n(11), self.n(1), .string("Corwen"), self.n(1), self.n(2), self.n(100), self.n(0)],
                                             [self.n(12), self.n(1), .string("Halen"), self.n(3), self.n(4), self.n(0), self.n(0)],
                                             [self.n(13), self.n(1), .string("Ulric"), self.n(6), self.n(9), self.n(0), self.n(77)]] }
        session.refresh()
        XCTAssertEqual(card(6, 0).lines.last, "Halen, outrider of level 4, will lead it.")
        XCTAssertEqual(card(7, 1).lines.last, "Halen, outrider of level 4, will lead it.")
        await session.press(card(6, 0).buttons[0])
        XCTAssertEqual(line.asked.last, "hunt at 6, 0 with 40 of 1.1 under 12")
        await session.send([(kind: 1, tier: 1, count: 5)], to: LiveHex(q: 6, r: 0), leader: 11)
        XCTAssertEqual(line.asked.last, "hunt at 6, 0 with 5 of 1.1 under 11")
        await session.send([(kind: 1, tier: 1, count: 5)], to: LiveHex(q: 6, r: 0), leader: 0)
        XCTAssertEqual(line.asked.last, "hunt at 6, 0 with 5 of 1.1")
        await session.hire()
        XCTAssertEqual(line.asked.last, "hire")
        XCTAssertNil(card(6, -1).lines.first { $0.hasSuffix("will lead it.") }, "no one is named for an army that can't be sent")
        line.change { rows in
            rows["my_commanders"] = nil
            rows["march"] = rows["march"]
        }
        session.refresh()
        line.clear()
        session.selected = LiveHex(q: 7, r: 1)
        await session.press(card(7, 1).buttons[0])
        XCTAssertEqual(line.asked.last, "gather at 7, 1 with 40 of 1.1")
        // A button that can't be pressed says why, and asks nothing.
        await session.press(card(6, -1).buttons[0])
        XCTAssertEqual(session.said, "Clear a level 3 barrow first.")
        XCTAssertEqual(line.asked.count, 1)
        // Bryn's city may be attacked; pressed, everyone ready goes against it.
        XCTAssertNil(card(14, -4).buttons.first?.why)
        session.selected = LiveHex(q: 14, r: -4)
        await session.press(card(14, -4).buttons[0])
        XCTAssertEqual(line.asked.last, "attack at 14, -4 with 40 of 1.1")
        // Once he is of her alliance, his city is her ally's: named with its
        // tag, never attacked, and soldiers may be sent to stay in it.
        line.change { rows in
            rows["alliance"] = [[self.n(5), self.n(77), self.n(78), .string("Keepers"), .string("MERE"), self.n(1), self.n(1_500), self.n(2), .bool(true), .string("")]]
            rows["member"] = [[self.n(1), self.n(5), self.n(5), self.n(1_500)], [self.n(2), self.n(5), self.n(1), self.n(1_600)]]
        }
        session.refresh()
        XCTAssertEqual(card(14, -4), LiveCard(title: "Bryn", lines: ["[MERE] Bryn's city. Keep level 8, power 9,000. They are here now.", "Your ally."],
                                              buttons: [.init(title: "Reinforce with 40 soldiers", act: .reinforce, why: nil)]))
        await session.press(card(14, -4).buttons[0])
        XCTAssertEqual(line.asked.last, "reinforce 14,-4 with 40 of 1.1 led by 0")
        line.change { rows in
            rows["alliance"] = nil
            rows["member"] = nil
        }
        session.refresh()
        // While his city is at peace it can't be; while her own is, she is
        // told what attacking would cost her.
        line.change { rows in
            rows["city"] = rows["city"]?.map { row in row[0] == .number(8) ? row + [.number(2_015 + 4_000)] : row + [.number(2_015 + 86_400)] }
            rows["my_city"] = rows["my_city"]?.map { $0 + [.number(2_015 + 86_400)] }
        }
        session.refresh()
        let guarded = card(14, -4)
        XCTAssertEqual(guarded.lines.last, "Attacking ends your own city's peace.")
        XCTAssertEqual(guarded.buttons.first?.why, "That city is at peace for another 1 hour 6 minutes.")
        XCTAssertEqual(card(10, -4).lines[1], "At peace for another 1 day: no army may attack it.")
        line.change { rows in
            rows["city"] = rows["city"]?.map { Array($0.prefix(8)) }
            rows["my_city"] = rows["my_city"]?.map { Array($0.prefix(8)) }
        }
        session.refresh()
        // Too little energy; and no one ready.
        line.change { $0["my_hunt"] = [[self.n(1), self.n(30), self.n(2_015), self.n(1_000), self.n(8_000), self.n(1)]] }
        session.refresh()
        XCTAssertEqual(card(6, 0).buttons.first?.why, "An attack takes 50 energy. You have 30.")
        line.change { $0["my_troops"] = [] }
        session.refresh()
        XCTAssertEqual(card(7, 1).buttons.first, .init(title: "Gather", act: .send, why: "No soldiers stand ready in your city."))

        // Bare land by its ground, where her city may move if she has the goods; land never told.
        XCTAssertEqual(card(5, 5), LiveCard(title: "Plain", lines: [],
                                            buttons: [.init(title: "Move your city here", act: .moveCity, why: "Moving your city takes 3,000 grain, 3,000 timber and 3,000 stone.")]))
        XCTAssertEqual(card(20, -4).title, "Wood")
        XCTAssertEqual(card(-12, 0).title, "Deep water")
        XCTAssertEqual(card(500, 0).title, "Unknown land")
    }

    /// The whole realm small, for the map in the corner: its grounds three
    /// pixels to a hex across, and where any hex falls on it.
    func testTheWholeRealmIsSmallInTheCorner() async throws {
        let session = session(StandInLine(rows: LiveWindowTests.rows()))
        XCTAssertNil(session.minimap, "none before the land is told")
        await session.open()
        let map = try XCTUnwrap(session.minimap)
        XCTAssertEqual([map.width, map.height, map.radius], [243, 210, 40], "the realm forty hexes from heart to rim, three pixels to a hex")
        XCTAssertEqual(map.grounds.count, 243 * 210)
        func ground(_ at: (u: Double, v: Double)) -> UInt8 { map.grounds[Int(at.v * Double(map.height)) * map.width + Int(at.u * Double(map.width))] }
        let heart = map.place(of: LiveHex(q: 0, r: 0))
        XCTAssertEqual(heart.u, 0.5, accuracy: 0.001)
        XCTAssertEqual(heart.v, 0.5, accuracy: 0.001)
        XCTAssertEqual(ground(heart), 4, "plain at the heart")
        XCTAssertEqual(ground(map.place(of: LiveHex(q: -30, r: 0))), 0, "deep water to the west")
        XCTAssertEqual(ground(map.place(of: LiveHex(q: 30, r: 0))), 5, "wood to the east")
        XCTAssertEqual(map.grounds[map.width - 1], LiveMinimap.unknown, "beyond the land told, at the top right corner")
        // Nothing past the rim, though the land is told in chunks that reach past it.
        var past = 0
        for row in 0..<map.height {
            for column in 0..<map.width {
                let hex = map.hex(atU: (Double(column) + 0.5) / Double(map.width), v: (Double(row) + 0.5) / Double(map.height))
                guard hex.distance(to: LiveHex(q: 0, r: 0)) > map.radius else { continue }
                past += 1
                XCTAssertEqual(map.grounds[row * map.width + column], LiveMinimap.unknown, "\(hex) is past the rim")
            }
        }
        XCTAssertGreaterThan(past, 1_000, "the map's corners lie past the rim")
        // A place on it is the hex there, and back again.
        XCTAssertEqual(map.hex(atU: heart.u, v: heart.v), LiveHex(q: 0, r: 0))
        let home = map.place(of: LiveHex(q: 10, r: -4))
        XCTAssertEqual(map.hex(atU: home.u, v: home.v), LiveHex(q: 10, r: -4))
    }

    /// Over each city in view, whose it is and its Keep's level.
    func testEachCityInViewIsNamedOverIt() async throws {
        let session = session(StandInLine(rows: LiveWindowTests.rows()))
        await session.open()
        let size = CGSize(width: 1280, height: 800)
        let labels = session.cityLabels(in: size)
        XCTAssertEqual(labels.map(\.words), ["Ada · 3", "Bryn · 8"])
        XCTAssertEqual(labels.map(\.own), [true, false])
        let home = try XCTUnwrap(session.viewPoint(of: LiveHex(q: 10, r: -4), in: size))
        XCTAssertEqual(labels.first?.point, CGPoint(x: home.x, y: home.y - LiveSession.labelLift), "hung over the heart of her city")
        XCTAssertTrue(labels.allSatisfy { size.width > $0.point.x && $0.point.x > 0 && size.height > $0.point.y && $0.point.y > 0 })
        XCTAssertTrue(session.cityLabels(in: CGSize(width: 1, height: 1)).isEmpty, "none hangs outside the view")
    }

    /// Over each army in view, whose it is; over the player's own, how many
    /// soldiers it has.
    func testEachArmyInViewIsMarkedOverIt() async throws {
        let session = session(StandInLine(rows: LiveWindowTests.rows()))
        await session.open()
        let size = CGSize(width: 1280, height: 800)
        let labels = session.armyLabels(in: size)
        XCTAssertEqual(labels.map(\.id), [3, 4, 6], "hers on the road, and Bryn's two at the grove and the barrow")
        XCTAssertEqual(labels.map(\.words), ["Your army · 40", "Bryn", "Bryn"])
        XCTAssertEqual(labels.map(\.own), [true, false, false])
        XCTAssertFalse(labels.contains { $0.foe }, "none marches on her city")
        XCTAssertTrue(labels.allSatisfy { size.width > $0.point.x && $0.point.x > 0 && size.height > $0.point.y && $0.point.y > 0 })
        XCTAssertTrue(session.armyLabels(in: CGSize(width: 1, height: 1)).isEmpty, "none hangs outside the view")
    }

    /// What is heard about her city: its town and Bryn's, their works in
    /// shares, Bryn's army fighting at the barrow and the barrow itself;
    /// the lake's edge, twenty hexes west, out of hearing. Nothing in a
    /// view of no size.
    func testWhatIsHeardAboutWhereThePlayerLooks() async throws {
        let session = session(StandInLine(rows: LiveWindowTests.rows()))
        await session.open()
        XCTAssertEqual(session.soundscape(in: .zero), LiveSoundscape())
        let heard = session.soundscape(in: CGSize(width: 1280, height: 800))
        XCTAssertGreaterThan(heard.town.level, 0.5, "her city, about the middle of the view")
        XCTAssertGreaterThan(heard.share(.granary), 0, "her Farm among the works heard")
        XCTAssertEqual(heard.share(.walls), 0, "walls make no sound of work")
        XCTAssertEqual(heard.works.values.reduce(0, +), 1, accuracy: 1e-4)
        XCTAssertEqual(heard.shore, LiveSoundscape.Heard.none, "the lake far to the west")
        XCTAssertGreaterThan(heard.din.level, 0, "Bryn's army fighting at the barrow")
        XCTAssertGreaterThan(heard.host, 0)
        XCTAssertGreaterThan(heard.keening.level, 0, "the barrow of the Unquiet")
        for layer in [heard.town, heard.din, heard.keening] {
            XCTAssertTrue((0...1).contains(layer.level) && (-1...1).contains(layer.pan), "\(layer)")
        }
    }

    /// Every kind of building has a symbol of its own.
    func testEachBuildingHasASymbolOfItsOwn() {
        let symbols = (1...19).map { LiveIcons.building($0) }
        XCTAssertEqual(Set(symbols).count, 19, "nineteen kinds, nineteen symbols")
        XCTAssertEqual(LiveIcons.building(1), "building.columns.fill", "the Keep")
        XCTAssertEqual(LiveIcons.building(99), "building.2.fill", "a kind not known")
        XCTAssertEqual((1...4).map { LiveIcons.troop($0) }, [7, 8, 9, 10].map { LiveIcons.building($0) }, "each soldier by the building that trains them")
    }

    /// What happens is told as it comes: a work done, an army home.
    func testWhatHappensIsToldAsItComes() async throws {
        var rows = LiveWindowTests.rows()
        rows["blueprint"] = [[n(2 << 32 | 1), n(2), n(1), .string("Farm"), n(0), n(100), n(0), n(0), n(10), n(0), n(0), n(0), n(0), n(1), n(0), n(0), n(20)]]
        rows["my_jobs"] = [[n(4), n(7), n(1), n(22), n(3), n(0), n(2_000), n(2_014), n(9)]]
        let line = StandInLine(rows: rows)
        let session = session(line)
        await session.open()
        XCTAssertTrue(session.news.isEmpty, "nothing told of the realm as first found")
        line.change { $0["my_jobs"] = [] }
        session.refresh()
        XCTAssertEqual(session.news.map(\.words), ["The Farm stands at level 3."])
        XCTAssertEqual(session.news.map(\.kind), [.raised], "told as a building raised, for its sound")
        XCTAssertEqual(session.news.first?.at, 2_015)
        for index in 0..<50 {
            // In typed steps, as a Mac's compiler types them in time.
            let job: [JSONValue] = [n(5 + index), n(7), n(1), n(22), n(4), n(0), n(2_000), n(2_014), n(9)]
            let jobs: [[JSONValue]] = index % 2 == 0 ? [job] : []
            line.change { $0["my_jobs"] = jobs }
            session.refresh()
        }
        XCTAssertEqual(session.news.count, LiveSession.newsKept, "only the latest are kept")
        XCTAssertEqual(Set(session.news.map(\.id)).count, LiveSession.newsKept, "each numbered apart")
    }

    /// The map as VoiceOver reads it: everything in the window, the
    /// player's own city first and their army next, each saying what it is
    /// and where it stands in a view.
    func testTheMapIsReadThingByThingHerCityFirst() async throws {
        let session = session(StandInLine(rows: LiveWindowTests.rows()))
        XCTAssertTrue(session.mapItems().isEmpty, "nothing before the realm is open")
        await session.open()
        let items = session.mapItems()
        XCTAssertEqual(items.first?.kind, .home)
        XCTAssertEqual(items.first?.hex, LiveHex(q: 10, r: -4))
        XCTAssertEqual(items.first?.label.hasPrefix("Ada. Your city. Keep level 3"), true, items.first?.label ?? "")
        XCTAssertEqual(items.dropFirst().first?.kind, .ownArmy, "her army out next")
        XCTAssertTrue(items.contains { $0.kind == .city && $0.hex == LiveHex(q: 14, r: -4) }, "Bryn's city")
        XCTAssertTrue(items.contains { $0.kind == .barrow && $0.hex == LiveHex(q: 8, r: -2) })
        XCTAssertTrue(items.contains { $0.kind == .site && $0.hex == LiveHex(q: 12, r: -2) })
        XCTAssertEqual(Set(items.map(\.id)).count, items.count, "each once")
        let size = CGSize(width: 1280, height: 800)
        XCTAssertNotNil(session.viewPoint(of: LiveHex(q: 10, r: -4), in: size))
        XCTAssertNil(session.viewPoint(of: LiveHex(q: 500, r: 0), in: size), "beyond the window")
    }

    /// The palette: everything that can be done this moment, in words to
    /// search by, and each done when chosen.
    func testThePaletteFindsWhatCanBeDoneAndDoesIt() async throws {
        var rows = LiveWindowTests.rows()
        rows["my_hunt"] = [[n(1), n(1_000), n(2_000), n(1_000), n(8_000), n(1)]]
        rows["my_stock"] = [[n(7), n(60_000), n(60_000), n(60_000), n(0), n(2_000), n(0), n(0), n(0), n(0), n(0), n(0), n(0), n(0), n(200_000)]]
        rows["my_jobs"] = []
        func blueprint(_ kind: Int, _ level: Int, _ name: String, opensAt: Int) -> [JSONValue] {
            [n(kind << 32 | level), n(kind), n(level), .string(name), n(0), n(100 * level), n(0), n(0), n(10 * level), n(0), n(0), n(0), n(0),
             n(opensAt), n(0), n(0), n(20 * level)]
        }
        rows["blueprint"] = [blueprint(2, 1, "Farm", opensAt: 1), blueprint(2, 3, "Farm", opensAt: 1), blueprint(7, 1, "Barracks", opensAt: 2)]
        // A barrow of the second level no one fights at; a grain site no one works.
        rows["barrow"]?.append([n(11), n(LiveHex(q: 6, r: 0).packed), n(2), n(0)])
        rows["place"]?.append([n(LiveHex(q: 6, r: 0).packed), n(3), n(11)])
        rows["site"]?.append([n(6), n(LiveHex(q: 7, r: 1).packed), n(1), n(2), n(40_000), n(0)])
        rows["place"]?.append([n(LiveHex(q: 7, r: 1).packed), n(2), n(6)])
        // A Forge and a Tavern of the first level; iron and leather enough
        // for a sword; and a contest whose first prize she has reached.
        rows["my_buildings"]?.append(contentsOf: [[n(32), n(7), n(19), n(1)], [n(33), n(7), n(16), n(1)]])
        // A Range of the fifth level, and forty archers of the first tier ready to be raised to the second.
        rows["my_buildings"]?.append([n(34), n(7), n(8), n(5)])
        rows["blueprint"]?.append(blueprint(8, 1, "Range", opensAt: 2))
        rows["soldier"] = [[n(2 << 8 | 1), n(2), n(1), .string("Archers"), n(110), n(90), n(95), n(60), n(10), n(1), n(40), n(70), n(0), n(0), n(8_000), n(8), n(1)],
                           [n(2 << 8 | 2), n(2), n(2), .string("Archers"), n(148), n(121), n(128), n(60), n(12), n(2), n(80), n(140), n(0), n(0), n(16_000), n(8), n(5)]]
        rows["my_troops"] = [[n(7 << 16 | 2 << 8 | 1), n(7), n(2), n(1), n(40), n(0)]]
        // A gift from her alliance, waiting.
        rows["my_boons"] = [[n(51), n(1), n(2), n(4), n(800), n(800), n(800), n(90_000), n(3)]]
        // An ally asking help with a work.
        rows["my_pleas"] = [[n(77), n(5), n(2), .string("[MERE] Bryn"), n(1), n(1), n(5)]]
        rows["my_satchel"] = [[n(1 << 8 | 5), n(1), n(5), n(4)], [n(1 << 8 | 6), n(1), n(6), n(4)]]
        rows["pattern"] = [[n(1), .string("Iron sword"), n(1), n(1), .string("Everyone its wearer leads strikes 3% harder."), n(4), n(4), n(0), n(0), n(0), n(5_000), n(5_000),
                            n(0), n(1)],
                           [n(5), .string("Steel sword"), n(1), n(2), .string("Everyone its wearer leads strikes 6% harder."), n(8), n(8), n(0), n(0), n(0), n(20_000), n(20_000),
                            n(0), n(8)]]
        rows["trial"] = [[n(1), .string("The Long Hunt"), .string("Points for every barrow cleared."), n(7), n(3)]]
        rows["prize"] = [[n(257), n(1), n(1), n(100), n(9_000), n(0), n(0), n(0), n(1), n(0), n(0)], [n(258), n(1), n(2), n(400), n(0), n(0), n(0), n(100), n(0), n(2), n(0)]]
        rows["my_tallies"] = [[n(5), n(1), n(1), n(0), n(120), n(0)]]
        let line = StandInLine(rows: rows)
        let session = session(line)
        await session.open()

        let all = session.commands(at: 2_015)
        XCTAssertEqual(all.first, LiveCommand(title: "Go to your city", act: .go(LiveHex(q: 10, r: -4))))
        XCTAssertTrue(all.contains { $0.title.hasPrefix("Go to your army: ") }, "her army out")
        XCTAssertEqual(all.compactMap { command -> String? in
            if case .open(let part) = command.act, command.title.hasPrefix("Open ") { return part }
            return nil
        }, LiveSession.parts.map { $0.name }, "every part of every destination")
        XCTAssertTrue(all.contains(LiveCommand(title: "Your devices, and leaving the realm", act: .open("day"))), "and Today again, for the account")
        XCTAssertTrue(all.contains(LiveCommand(title: "Raise the Farm to level 3", act: .upgrade(22))))
        XCTAssertTrue(all.contains(LiveCommand(title: "Build a Barracks", act: .build(7))))
        XCTAssertTrue(all.contains(LiveCommand(title: "Go to the nearest barrow you may attack, of level 2", act: .go(LiveHex(q: 6, r: 0)))))
        XCTAssertTrue(all.contains(LiveCommand(title: "Go to the nearest grain site, of level 2", act: .go(LiveHex(q: 7, r: 1)))))
        XCTAssertFalse(all.contains { $0.title.contains("timber site") }, "the grove is being worked")
        XCTAssertFalse(all.contains { $0.act == .claimTask }, "no task done to claim")
        XCTAssertTrue(all.contains(LiveCommand(title: "Make a piece at the Forge: Iron sword", act: .forge(1))))
        XCTAssertFalse(all.contains { $0.act == .forge(5) }, "the steel sword wants a Forge of the eighth level")
        XCTAssertTrue(all.contains(LiveCommand(title: "Take on another commander", act: .hire)))
        XCTAssertTrue(all.contains(LiveCommand(title: "Claim your alliance's gifts: 800 grain, 800 timber and 800 stone", act: .claimBoons)))
        XCTAssertTrue(all.contains(LiveCommand(title: "Help your allies with 1 work", act: .helpAll)))
        XCTAssertTrue(all.contains(LiveCommand(title: "Raise 40 tier 1 Archers to tier 2", act: .promote(building: 34, from: 1, to: 2, count: 40))))
        XCTAssertTrue(all.contains(LiveCommand(title: "Claim the prize of The Long Hunt at 100 points", act: .claimPrize(contest: 1, place: 1))))
        XCTAssertFalse(all.contains { $0.act == .claimPrize(contest: 1, place: 2) }, "400 points not reached")

        // Searched by every word, whatever its case.
        XCTAssertEqual(session.commands(matching: "open REP", at: 2_015).map(\.title), ["Open Reports and letters"])
        XCTAssertEqual(session.commands(matching: "  ", at: 2_015).count, all.count, "nothing searched, everything found")
        XCTAssertTrue(session.commands(matching: "no such thing", at: 2_015).isEmpty)

        // Chosen: a part to open is handed back; a place gone to and chosen; the rest asked of the realm.
        let opened = await session.perform(LiveCommand(title: "Open Studies", act: .open("studies")))
        XCTAssertEqual(opened, "studies")
        await session.perform(LiveCommand(title: "Go to the nearest grain site, of level 2", act: .go(LiveHex(q: 7, r: 1))))
        XCTAssertEqual(session.selected, LiveHex(q: 7, r: 1))
        line.clear()
        await session.perform(LiveCommand(title: "Raise the Farm to level 3", act: .upgrade(22)))
        await session.perform(LiveCommand(title: "Build a Barracks", act: .build(7)))
        await session.perform(LiveCommand(title: "Study Tillage to level 1", act: .learn(1)))
        await session.perform(LiveCommand(title: "Claim the task", act: .claimTask))
        await session.perform(LiveCommand(title: "Open the day's chest at 20 marks", act: .openChest(1)))
        await session.perform(LiveCommand(title: "Make a piece at the Forge: Iron sword", act: .forge(1)))
        await session.perform(LiveCommand(title: "Take on another commander", act: .hire))
        await session.perform(LiveCommand(title: "Claim the prize of The Long Hunt at 100 points", act: .claimPrize(contest: 1, place: 1)))
        await session.perform(LiveCommand(title: "Raise 20 tier 1 Spearmen to tier 2", act: .promote(building: 24, from: 1, to: 2, count: 20)))
        await session.perform(LiveCommand(title: "Claim your alliance's gifts", act: .claimBoons))
        await session.perform(LiveCommand(title: "Help your allies with 1 work", act: .helpAll))
        XCTAssertEqual(line.asked, ["upgrade 22", "build 7", "learn 1", "claim task", "open chest 1", "forge 1", "hire", "claim prize 1 of 1", "promote 20 of tier 1 to 2 in 24",
                                    "claim boons", "help 0"])
    }

    /// The task set, not yet done, shows the way to where it is done: the
    /// part of a destination that does it, or the nearest place on the map;
    /// once done, or with nowhere to go, none.
    func testATaskNotYetDoneShowsTheWayToIt() async throws {
        var rows = LiveWindowTests.rows()
        // A barrow of the first level no one fights at, the nearest she may attack.
        rows["barrow"]?.append([n(11), n(LiveHex(q: 6, r: 0).packed), n(1), n(0)])
        rows["place"]?.append([n(LiveHex(q: 6, r: 0).packed), n(3), n(11)])
        func task(_ step: Int, _ goal: Int, _ amount: Int, _ words: String) -> [JSONValue] {
            [n(step), n(goal), n(amount), n(0), .string(words), n(1_000), n(1_000), n(0), n(0)]
        }
        rows["task"] = [task(1, LiveTask.keep, 2, "Raise your Keep to level 2."), task(2, LiveTask.keep, 4, "Raise your Keep to level 4."),
                        task(3, LiveTask.soldiers, 5_000, "Have 5,000 soldiers."), task(4, LiveTask.allied, 0, "Join an alliance."),
                        task(5, LiveTask.cleared, 1, "Clear a barrow."), task(6, LiveTask.found, 1, "Find a cairn."), task(7, LiveTask.power, 9_000, "Reach 9,000 power.")]
        rows["my_progress"] = [[n(1), n(1)]]
        let line = StandInLine(rows: rows)
        let session = session(line)
        await session.open()
        var ways: [LiveCommand?] = []
        for step in 1...7 {
            line.change { $0["my_progress"] = [[n(1), n(step)]] }
            session.refresh()
            XCTAssertEqual(session.world.task?.step, step)
            ways.append(session.taskWay)
        }
        XCTAssertEqual(ways, [nil, // her Keep stands at the third level: done, to be claimed
                              LiveCommand(title: "Go to your buildings", act: .open("city")),
                              LiveCommand(title: "Go to your troops", act: .open("troops")),
                              LiveCommand(title: "Go to the alliances", act: .open("alliance")),
                              LiveCommand(title: "Go to the nearest barrow you may attack", act: .go(LiveHex(q: 6, r: 0))),
                              nil, // no cairn known: nowhere to go
                              LiveCommand(title: "Go to your buildings", act: .open("city"))])
        XCTAssertEqual(session.nearestBarrowToAttack?.hex, LiveHex(q: 6, r: 0), "the barrow at 8, -2 being of the second level, and fought at")
        // Gone along: the barrow's hex looked at and chosen, and nothing asked of the realm.
        line.change { $0["my_progress"] = [[n(1), n(5)]] }
        session.refresh()
        line.clear()
        await session.perform(try XCTUnwrap(session.taskWay))
        XCTAssertEqual(session.selected, LiveHex(q: 6, r: 0))
        XCTAssertTrue(line.asked.isEmpty)
        // With a cairn about, the task to find one goes to it.
        line.change {
            $0["cairn"] = [[n(1), n(LiveHex(q: 13, r: -6).packed), n(2)]]
            $0["my_progress"] = [[n(1), n(6)]]
        }
        session.refresh()
        XCTAssertEqual(session.taskWay, LiveCommand(title: "Go to the nearest cairn your scouts have not found", act: .go(LiveHex(q: 13, r: -6))))
    }

    func testThePaletteOffersWhatAPlaceInAContestGave() async throws {
        // Ada first in the Long Hunt's first round, which runs the realm's
        // first three days (it opened at 1,000, a day to every 86,400).
        var rows = LiveWindowTests.rows()
        rows["trial"] = [[n(1), .string("The Long Hunt"), .string("Points for every barrow cleared."), n(7), n(3), n(0)]]
        rows["laurel"] = [[n(257), n(1), n(1), n(60_000), n(60_000), n(30_000), n(900), n(0), n(0), n(3), n(0)]]
        rows["standing"] = [[n(1 << 24 | 1), n(1), n(1), n(1), n(0), n(250), n(1_500), .bool(false)],
                            [n(2 << 24 | 1), n(1), n(2), n(1), n(0), n(90), n(1_200), .bool(false)]]
        let line = StandInLine(rows: rows)
        let session = session(line)
        await session.open()
        let claim = LiveCommand(title: "Claim what your place in The Long Hunt gave: 1st", act: .claimPlace(contest: 1))
        XCTAssertFalse(session.commands(at: 1_000 + 86_400).contains { $0.act == .claimPlace(contest: 1) }, "not while the round runs")
        XCTAssertTrue(session.commands(at: 1_000 + 4 * 86_400).contains(claim), "once it is over")
        XCTAssertFalse(session.commands(at: 1_000 + 11 * 86_400).contains { $0.act == .claimPlace(contest: 1) }, "nor once the next is")
        line.clear()
        await session.perform(claim)
        XCTAssertEqual(line.asked, ["claim place in 1"])

        // A phone linked from the palette: a code asked for while none is good.
        let link = LiveCommand(title: "Link a phone: ask for a code", act: .offerLink)
        XCTAssertTrue(session.commands(at: 2_015).contains(link))
        line.clear()
        await session.perform(link)
        XCTAssertEqual(line.asked, ["offer a link"])
        var linked = rows
        linked["my_link"] = [[n(77), n(1), .string("ABCDE23456"), n(2_600)]]
        let holding = self.session(StandInLine(rows: linked))
        await holding.open()
        XCTAssertFalse(holding.commands(at: 2_015).contains(link), "not while a code is good")
        XCTAssertTrue(holding.commands(at: 2_601).contains(link), "and again once it is not")

        // A commander's counsel knows it: where she stands while the round
        // runs, and what she may claim once it is over.
        rows["my_commanders"] = [[n(11), n(1), .string("Corwen"), n(3), n(4), n(200), n(0)]]
        let running = self.session(StandInLine(rows: rows), at: 1_000 + 86_400)
        await running.open()
        let told = try XCTUnwrap(running.counsel(of: 11)).realmLook
        XCTAssertTrue(told.contains("The Long Hunt runs: your lord stands 1st of 2, with 250 points."), told)
        let over = self.session(StandInLine(rows: rows), at: 1_000 + 4 * 86_400)
        await over.open()
        let later = try XCTUnwrap(over.counsel(of: 11)).realmLook
        XCTAssertFalse(later.contains("runs:"), later)
        XCTAssertTrue(later.contains("Your lord was 1st in The Long Hunt when its last round ended, and may claim 60,000 grain, 60,000 timber, 30,000 stone and 900 moonsalt"), later)
    }

    /// The player's account: this device named once, another let go, and
    /// the realm left, whoever comes back on this device joining anew and
    /// shown their new city first.
    func testThisDeviceIsNamedOnceAnotherLetGoAndTheRealmLeft() async throws {
        var rows = LiveWindowTests.rows()
        rows["my_devices"] = [[n(97), .string(""), .bool(true), .bool(true)], [n(41), .string("iPhone"), .bool(false), .bool(false)]]
        let line = StandInLine(rows: rows)
        let session = self.session(line)
        await session.open()
        line.clear()
        await session.nameDevice("Mac")
        XCTAssertEqual(line.asked, ["name this device Mac"])
        line.change { $0["my_devices"]?[0][1] = .string("Mac") }
        session.refresh()
        line.clear()
        await session.nameDevice("Mac")
        XCTAssertEqual(line.asked, [], "named once")
        let phone = try XCTUnwrap(session.world.devices.last)
        await session.letGo(phone)
        XCTAssertEqual(line.asked, ["let go device 41"])

        // From the palette: Today opened at the devices, and each other
        // device let go, two alike told apart.
        line.change {
            $0["my_devices"] = [[self.n(97), .string("Mac"), .bool(true), .bool(true)], [self.n(41), .string("iPhone"), .bool(false), .bool(false)],
                                [self.n(42), .string("iPhone"), .bool(false), .bool(false)], [self.n(43), .string(""), .bool(true), .bool(false)]]
        }
        session.refresh()
        let titles = session.commands(at: 2_015).map(\.title)
        for title in ["Your devices, and leaving the realm", "Let go iPhone, away", "Let go iPhone, away (2)", "Let go another device, here now"] {
            XCTAssertTrue(titles.contains(title), title)
        }
        XCTAssertFalse(titles.contains { $0.hasPrefix("Let go Mac") }, "not this one")
        let opened = await session.perform(LiveCommand(title: "Your devices, and leaving the realm", act: .open("day")))
        XCTAssertEqual(opened, "day")
        line.clear()
        await session.perform(LiveCommand(title: "Let go iPhone, away (2)", act: .letGo(42)))
        await session.perform(LiveCommand(title: "Let go a device no longer here", act: .letGo(5)))
        XCTAssertEqual(line.asked, ["let go device 42"], "one no longer among them asks nothing")

        // Leaving, the name refused as the realm refuses it; then left.
        let first = session.look
        line.refuse("Type your name as the realm knows it to leave.")
        await session.leaveRealm(name: "Bryn")
        XCTAssertEqual(session.said, "Type your name as the realm knows it to leave.")
        line.refuse(nil)
        await session.leaveRealm(name: "Ada")
        XCTAssertEqual(line.asked.last, "leave the realm as Ada")
        line.change { $0["me"] = []; $0["my_city"] = []; $0["my_devices"] = [] }
        session.refresh()
        XCTAssertEqual(session.phase, .naming, "this device joins anew")
        let me = try XCTUnwrap(rows["me"]?.first)
        let anew = LiveHex(q: 2, r: 3)
        line.change {
            $0["me"] = [me]
            $0["my_city"] = [[self.n(99), self.n(1), self.n(anew.packed), .string("Ada Again"), self.n(1), self.n(0), self.n(2_000), self.n(1), self.n(0)]]
        }
        session.refresh()
        XCTAssertNotEqual(first, anew)
        XCTAssertEqual(session.look, anew, "and is shown their new city first")
        // Nothing to name for one who is no one in the realm.
        let empty = StandInLine(rows: [:])
        let nobody = self.session(empty)
        await nobody.open()
        await nobody.nameDevice("Mac")
        XCTAssertFalse(empty.asked.contains { $0.hasPrefix("name this device") })
    }

    /// The Tavern from the palette: a summons taken while today's is free,
    /// and a gift raised once its sigils are held.
    func testTheTavernSummonsAndAGiftIsRaisedFromThePalette() async throws {
        var rows = LiveWindowTests.rows()
        let summon = LiveCommand(title: "Summon a commander at the Tavern, free today", act: .draw)
        let none = self.session(StandInLine(rows: rows))
        await none.open()
        XCTAssertFalse(none.commands(at: 2_015).contains(summon), "no Tavern, no summons")
        rows["my_buildings"]?.append([n(24), n(7), n(16), n(1)])
        rows["person"] = [[n(3), .string("Corran Ash"), n(1), n(1), n(2), .string("Mercy"), .string("")]]
        rows["my_commanders"] = [[n(11), n(1), .string("Corran Ash"), n(1), n(1), n(0), n(0), n(3), n(1), n(12)]]
        let line = StandInLine(rows: rows)
        let session = self.session(line)
        await session.open()
        let commands = session.commands(at: 2_015)
        XCTAssertTrue(commands.contains(summon))
        let raise = LiveCommand(title: "Raise Corran Ash's gift to level 2", act: .raiseGift(11))
        XCTAssertTrue(commands.contains(raise))
        line.clear()
        await session.perform(summon)
        await session.perform(raise)
        XCTAssertEqual(line.asked, ["summon at the Tavern", "raise the gift of 11"])
        // Today's taken, one kept: the summons is with it.
        line.change {
            $0["my_daily"] = [[self.n(1), self.n(0), self.n(0), self.n(0), self.n(0), self.n(0), self.n(0), self.n(0), self.n(1)]]
            $0["my_satchel"] = [[self.n(1 << 8 | 11), self.n(1), self.n(11), self.n(1)]]
        }
        session.refresh()
        XCTAssertTrue(session.commands(at: 2_015).contains(LiveCommand(title: "Summon a commander at the Tavern, with a summons, of 1", act: .draw)))
    }

    func testRalliesGatesAndWardstonesAreCalledFromTheirCards() async throws {
        var rows = LiveWindowTests.rows()
        rows["my_troops"] = [[n(7 << 16 | 1 << 8 | 1), n(7), n(1), n(1), n(40), n(0)]]
        rows["my_hunt"] = [[n(1), n(1_000), n(2_000), n(1_000), n(8_000), n(1)]]
        rows["my_stock"] = [[n(7), n(60_000), n(60_000), n(60_000), n(0), n(2_000), n(0), n(0), n(0), n(0), n(0), n(0), n(0), n(0), n(200_000)]]
        rows["alliance"] = [[n(5), n(77), n(78), .string("Keepers"), .string("MERE"), n(1), n(1_500), n(2), .bool(true), .string("")]]
        rows["member"] = [[n(1), n(5), n(5), n(1_500)]]
        rows["season"] = [[n(1), n(1_000), n(2_420_200), n(0), .string(""), n(0)]]
        // Ada's army is home; a barrow of the fourth level and one of the
        // ninth; a gate of the ridge; and a wardstone of her own alliance.
        rows["march"] = rows["march"]?.filter { $0[1] != .number(1) }
        rows["barrow"]?.append([n(10), n(LiveHex(q: 6, r: -1).packed), n(4), n(0)])
        rows["place"]?.append([n(LiveHex(q: 6, r: -1).packed), n(3), n(10)])
        rows["barrow"]?.append([n(12), n(LiveHex(q: 5, r: -1).packed), n(9), n(0)])
        rows["place"]?.append([n(LiveHex(q: 5, r: -1).packed), n(3), n(12)])
        rows["gate"] = [[n(1), n(LiveHex(q: 4, r: -6).packed), n(0), .string(""), n(0), n(0)]]
        rows["place"]?.append([n(LiveHex(q: 4, r: -6).packed), n(5), n(1)])
        rows["ward"] = [[n(3), n(5), n(LiveHex(q: 12, r: -8).packed), n(1), n(1_500)], [n(4), n(6), n(LiveHex(q: 2, r: -9).packed), n(2), n(1_500)]]
        rows["place"]?.append([n(LiveHex(q: 12, r: -8).packed), n(4), n(3)])
        rows["place"]?.append([n(LiveHex(q: 2, r: -9).packed), n(4), n(4)])
        rows["alliance"]?.append([n(6), n(79), n(80), .string("Wardens"), .string("WRD"), n(2), n(1_600), n(1), .bool(true), .string("")])
        let line = StandInLine(rows: rows)
        let session = session(line)
        await session.open()
        func card(_ q: Int, _ r: Int) -> LiveCard { session.card(for: session.selection(at: LiveHex(q: q, r: r))) }

        // A member may call a rally against a barrow up to three levels past what they may attack alone.
        let fourth = card(6, -1)
        XCTAssertEqual(fourth.buttons.map(\.title), ["Attack with 40 soldiers", "Call a rally"])
        XCTAssertEqual(fourth.buttons[0].why, "Clear a level 3 barrow first.")
        XCTAssertNil(fourth.buttons[1].why)
        XCTAssertEqual(card(5, -1).buttons[1].why, "A rally of yours may go against a barrow of level 5 at most.")
        // And against another's city, which may be scouted from a Scout Camp: one soldier goes.
        XCTAssertEqual(card(14, -4).buttons.map(\.act), [.send, .scout, .rally])
        XCTAssertEqual(card(14, -4).buttons[1].why, "Raise a Scout Camp first.")
        line.change { $0["my_buildings"]?.append([self.n(31), self.n(7), self.n(18), self.n(1)]) }
        session.refresh()
        XCTAssertNil(card(14, -4).buttons[1].why)
        session.selected = LiveHex(q: 14, r: -4)
        await session.press(card(14, -4).buttons[1])
        XCTAssertEqual(line.asked.last, "scout 14,-4 with 1 of 1.1")

        // A gate: held by the Unquiet, stormed only by a rally, and only a week into the season.
        guard case .gate(let gate) = session.selection(at: LiveHex(q: 4, r: -6)) else { return XCTFail("the gate is chosen") }
        XCTAssertEqual(gate.id, 1)
        XCTAssertEqual(card(4, -6), LiveCard(title: "Gate of the ridge",
                                             lines: ["A gate of the ridge, held by the Unquiet.", "Only an alliance's rally may storm it; whoever holds it passes it."],
                                             buttons: [.init(title: "Call a rally", act: .rally, why: "The gates of the ridge may be stormed in 6 days 23 hours.")]))

        // Her alliance's wardstone, which she may take down; its land, where she may raise another.
        XCTAssertEqual(card(12, -8), LiveCard(title: "Wardstone", lines: ["[MERE] Keepers's wardstone. Once it stands it claims the land within 3 hexes."],
                                              buttons: [.init(title: "Take it down", act: .razeWard(3), why: nil)]))
        XCTAssertEqual(card(12, -7), LiveCard(title: "Plain", lines: ["The land of [MERE] Keepers."],
                                              buttons: [.init(title: "Raise a wardstone", act: .raiseWard, why: nil), .init(title: "Move your city here", act: .moveCity, why: nil)]))
        XCTAssertEqual(card(-20, 0).buttons, [], "nothing is raised on deep water")
        // Another alliance's wardstone: a rally may take it down.
        XCTAssertEqual(card(2, -9), LiveCard(title: "Wardstone", lines: ["[WRD] Wardens's wardstone. Once it stands it claims the land within 3 hexes."],
                                             buttons: [.init(title: "Call a rally", act: .rally, why: nil)]))

        // Pressed, each goes to the realm.
        line.clear()
        session.selected = LiveHex(q: 6, r: -1)
        await session.press(card(6, -1).buttons[1])
        session.selected = LiveHex(q: 12, r: -7)
        await session.press(card(12, -7).buttons[0])
        await session.press(card(12, -8).buttons[0])
        XCTAssertEqual(line.asked.count, 3)
        XCTAssertTrue(line.asked[0].hasPrefix("rally at 6,-1 with 40 of 1.1 led by "), line.asked[0])
        XCTAssertEqual(Array(line.asked.dropFirst()), ["raise ward 12,-7", "raze ward 3"])
        session.selected = LiveHex(q: 12, r: -7)
        await session.press(card(12, -7).buttons[1])
        XCTAssertEqual(line.asked.last, "move city to 12,-7")

        // One in no alliance is offered no rally.
        line.change { rows in
            rows["member"] = nil
        }
        session.refresh()
        XCTAssertEqual(card(6, -1).buttons.map(\.act), [.send])
        XCTAssertEqual(card(4, -6).buttons, [])
        XCTAssertEqual(card(12, -7).buttons.map(\.act), [.moveCity], "nor a wardstone to raise; her city may still move there")
    }

    /// The old folk's cairns: each told on a card with what it holds, a
    /// scout sent from a Scout Camp to one not yet found, the nearest of
    /// those in the palette, and each read on the map.
    func testACairnIsToldOnItsCardAndAScoutIsSentToIt() async throws {
        var rows = LiveWindowTests.rows()
        rows["my_troops"] = [[n(7 << 16 | 1 << 8 | 1), n(7), n(1), n(1), n(40), n(0)]]
        rows["march"] = rows["march"]?.filter { $0[1] != .number(1) }
        // A third-level cairn beside Ada's city, whose hoard her scouts have
        // found; a first-level one three hexes off, not yet found.
        let (near, far) = (LiveHex(q: 9, r: -4), LiveHex(q: 12, r: -7))
        rows["cairn"] = [[n(1), n(near.packed), n(3)], [n(2), n(far.packed), n(1)]]
        rows["place"]?.append([n(near.packed), n(6), n(1)])
        rows["place"]?.append([n(far.packed), n(6), n(2)])
        rows["my_finds"] = [[n(UInt64(1) << 32 | 1), n(1), n(1), n(2_000)]]
        // Her task: to find what a cairn holds, which her scouts have.
        rows["task"] = [[n(13), n(LiveTask.found), n(1), n(0), .string("Send a scout to find what a cairn holds."), n(3_000), n(3_000), n(1_500), n(0)],
                        [n(14), n(LiveTask.found), n(2), n(0), .string("Have your scouts find what 2 cairns hold."), n(1), n(0), n(0), n(0)]]
        rows["my_progress"] = [[n(1), n(13)]]
        let line = StandInLine(rows: rows)
        let session = session(line)
        await session.open()
        func card(_ hex: LiveHex) -> LiveCard { session.card(for: session.selection(at: hex)) }

        XCTAssertEqual(session.world.task?.words, "Send a scout to find what a cairn holds.")
        XCTAssertTrue(session.world.task.map(session.world.isDone) ?? false, "one found: the task is done")
        XCTAssertFalse(session.world.tasks[14].map(session.world.isDone) ?? true, "two asked of the next")
        guard case .cairn(let found) = session.selection(at: near) else { return XCTFail("the cairn is chosen") }
        XCTAssertEqual(found.level, 3)
        XCTAssertTrue(session.world.hasFound(found))
        XCTAssertEqual(LiveCairn.hoard(level: 3).things, ["a five minutes' haste", "a tome of war"])
        XCTAssertEqual(found.hoardWords, "12,000 grain, 12,000 timber and 12,000 stone, and a five minutes' haste and a tome of war")
        XCTAssertEqual(LiveCairn.hoard(level: 5).goods, LiveGoods(grain: 30_000, timber: 30_000, stone: 30_000, moonsalt: 1_000), "as the module's hoard_of")
        XCTAssertEqual(card(near), LiveCard(title: "Cairn, level 3", lines: ["Your scouts have found what it held. It stands for others to find."],
                                            buttons: [.init(title: "Send a scout", act: .explore, why: "Your scouts have found what this cairn held already.")]))
        XCTAssertEqual(card(far), LiveCard(title: "Cairn, level 1", lines: ["The old folk laid 2,000 grain, 2,000 timber and 2,000 stone, and a tome of war in it."],
                                           buttons: [.init(title: "Send a scout", act: .explore, why: "Raise a Scout Camp first.")]))
        XCTAssertEqual(card(far).buttons[0].icon, "binoculars")

        // From a Scout Camp, one soldier goes.
        line.change { $0["my_buildings"]?.append([self.n(31), self.n(7), self.n(18), self.n(1)]) }
        session.refresh()
        XCTAssertEqual(card(far).lines.last, "A scout finds it the first time and comes home whole.")
        XCTAssertNil(card(far).buttons[0].why)
        session.selected = far
        await session.press(card(far).buttons[0])
        XCTAssertEqual(line.asked.last, "explore 12,-7 with 1 of 1.1")
        // On its way, the card and the army's line say so.
        let way = [LiveHex(q: 10, r: -4), LiveHex(q: 11, r: -5), LiveHex(q: 12, r: -6), far].flatMap { hex -> [UInt8] in
            let (q, r) = (UInt16(bitPattern: Int16(hex.q)), UInt16(bitPattern: Int16(hex.r)))
            return [UInt8(q & 0xFF), UInt8(q >> 8), UInt8(r & 0xFF), UInt8(r >> 8)]
        }.map { String(format: "%02x", $0) }.joined()
        line.change {
            $0["march"]?.append([self.n(12), self.n(1), self.n(7), self.n(7), self.n(1), self.n(LiveHex(q: 10, r: -4).packed), self.n(far.packed), self.n(2),
                                 self.n(2_015), self.n(2_033), self.n(1), .string(way), self.n(0)])
        }
        session.refresh()
        XCTAssertEqual(card(far).buttons[0].why, "Your scouts are on their way to it already.")
        XCTAssertEqual(card(far).lines.last, "Your scouts are on their way to it.")
        XCTAssertEqual(session.world.marchLines().first { $0.march.id == 12 }?.doing, "Scouting a level 1 cairn")

        // The palette goes to the nearest not yet found; the map reads both.
        XCTAssertTrue(session.commands(at: 2_015).contains(LiveCommand(title: "Go to the nearest cairn your scouts have not found, of level 1", act: .go(far))))
        let cairns = session.mapItems().filter { $0.kind == .cairn }
        XCTAssertEqual(cairns.map(\.hex), [near, far], "the nearest first")
        XCTAssertEqual(cairns.first?.label, "Cairn, level 3. Your scouts have found what it held. It stands for others to find.")
    }

    /// Tomes of war held are read by a commander: the palette offers each
    /// tome to each commander who may still rise, and none to one held
    /// prisoner or at the top.
    func testTomesAreReadByCommanders() async throws {
        var rows = LiveWindowTests.rows()
        rows["ware"] = [[n(9), .string("Tome of war"), .string("Read by one of your commanders."), n(0), n(4)],
                        [n(10), .string("Great tome of war"), .string("Read by one of your commanders."), n(0), n(4)]]
        rows["my_satchel"] = [[n(1 << 8 | 9), n(1), n(9), n(2)]]
        rows["my_commanders"] = [[n(11), n(1), .string("Corwen"), n(1), n(2), n(100), n(0)],
                                 [n(12), n(1), .string("Ysolde"), n(2), n(30), n(0), n(0)]]
        let line = StandInLine(rows: rows)
        let session = session(line)
        await session.open()
        XCTAssertEqual(session.world.heldTomes.map(\.ware.name), ["Tome of war"])
        XCTAssertEqual(session.world.heldTomes.map(\.count), [2])
        XCTAssertTrue(session.world.wares[9]?.isTome ?? false)
        let reads = session.commands(at: 2_015).filter { if case .readTome = $0.act { return true } else { return false } }
        XCTAssertEqual(reads, [LiveCommand(title: "Have Corwen read a tome of war", act: .readTome(commander: 11, item: 9))],
                       "Ysolde, at the thirtieth level, has seen all there is")
        await session.perform(reads[0])
        XCTAssertEqual(line.asked.last, "read 1 of 9 to 11")
    }

    /// Honour buys from the alliance's stores: what each costs, why what
    /// costs too much can't be bought, the palette's commands, and a buy.
    func testHonourBuysFromTheAlliancesStores() async throws {
        var rows = LiveWindowTests.rows()
        rows["ware"] = [[n(1), .string("Five minutes' haste"), .string("Takes five minutes off a work."), n(300), n(1)],
                        [n(2), .string("An hour's haste"), .string("Takes an hour off a work."), n(3_600), n(1)],
                        [n(4), .string("Eight hours' peace"), .string("Keeps your city at peace."), n(28_800), n(2)]]
        rows["price"] = [[n(4), n(5_000)], [n(1), n(100)], [n(2), n(1_000)]]
        rows["my_honour"] = [[n(1), n(1_200), n(0), n(40)]]
        let line = StandInLine(rows: rows)
        let session = session(line)
        await session.open()
        XCTAssertEqual(session.world.honourHeld, 1_200)
        XCTAssertEqual(session.world.storeLines(), [], "no stores for one in no alliance")

        line.change {
            $0["alliance"] = [[self.n(5), self.n(77), self.n(78), .string("Keepers"), .string("MERE"), self.n(1), self.n(1_500), self.n(2), .bool(true), .string("")]]
            $0["member"] = [[self.n(1), self.n(5), self.n(5), self.n(1_500)]]
        }
        session.refresh()
        let stores = session.world.storeLines()
        XCTAssertEqual(stores.map(\.ware.name), ["Five minutes' haste", "An hour's haste", "Eight hours' peace"], "the cheapest first")
        XCTAssertEqual(stores.map(\.honour), [100, 1_000, 5_000])
        XCTAssertEqual(stores.map(\.block), [nil, nil, "It costs 5,000 honour. You have 1,200."])
        XCTAssertEqual(session.world.honourFromHelpLeft(at: 2_015), 960, "forty earned helping today")
        XCTAssertEqual(session.world.honourFromHelpLeft(at: 2_015 + 86_400), 1_000, "a new day's")

        let commands = session.commands(at: 2_015)
        XCTAssertTrue(commands.contains(LiveCommand(title: "Buy five minutes' haste for 100 honour", act: .buy(1))))
        XCTAssertTrue(commands.contains(LiveCommand(title: "Buy an hour's haste for 1,000 honour", act: .buy(2))))
        XCTAssertFalse(commands.contains { $0.act == .buy(4) }, "nor what costs more than she has")
        await session.perform(LiveCommand(title: "Buy an hour's haste for 1,000 honour", act: .buy(2)))
        XCTAssertEqual(line.asked.last, "buy 1 of 2")
    }

    /// Counsel of a commander, grounded on the realm's rows: who they are,
    /// what they know as it begins, what they may look at, and deeds put
    /// forward only from what can be done now.
    func testACommandersCounselIsGroundedOnTheRealmsRows() async throws {
        var rows = LiveWindowTests.rows()
        rows["my_commanders"] = [[n(11), n(1), .string("Corwen"), n(3), n(4), n(200), n(0)]]
        rows["my_troops"] = [[n(7 << 16 | 1 << 8 | 1), n(7), n(1), n(1), n(40), n(0)]]
        rows["my_stock"] = [[n(7), n(60_000), n(60_000), n(60_000), n(0), n(2_000), n(0), n(0), n(0), n(0), n(0), n(0), n(0), n(0), n(200_000)]]
        // Her Farm may be raised to its third level, and a Sawmill built (a
        // building is named by its first level's blueprint).
        rows["blueprint"] = [[n(2 << 32 | 1), n(2), n(1), .string("Farm"), n(0), n(100), n(0), n(0), n(10), n(0), n(0), n(0), n(0), n(1), n(0), n(0), n(20)],
                             [n(2 << 32 | 3), n(2), n(3), .string("Farm"), n(0), n(300), n(0), n(0), n(30), n(0), n(0), n(0), n(0), n(1), n(0), n(0), n(20)],
                             [n(3 << 32 | 1), n(3), n(1), .string("Sawmill"), n(0), n(100), n(0), n(0), n(10), n(0), n(0), n(0), n(0), n(1), n(0), n(0), n(10)]]
        let session = session(StandInLine(rows: rows))
        await session.open()
        XCTAssertNil(session.counsel(of: 99), "no counsel of a commander she has not")
        let counsel = try XCTUnwrap(session.counsel(of: 11))
        XCTAssertTrue(counsel.instructions.hasPrefix("You are Corwen, an outrider of level 4, counselling Ada,"), counsel.instructions)
        XCTAssertTrue(counsel.instructions.contains("you counsel scouting, the cairns of the old folk, and hunting the barrows"))
        XCTAssertTrue(counsel.instructions.contains("never invent a number, a name, a place or an event"))
        let briefing = counsel.briefing.split(separator: "\n").map(String.init)
        XCTAssertEqual(briefing.first, "You are Corwen, outrider of level 4, 200 of 1,600 seen toward the next. You are in the city.")
        XCTAssertEqual(counsel.yourselfLook, briefing.first, "a look at themself tells them as the briefing did")
        // One of the realm's own knows their renown and their gift.
        var known = rows
        known["person"] = [[n(3), .string("Corwen"), n(3), n(1), n(2), .string("Mercy"),
                            .string("12 in a hundred of their army's dead are carried home wounded after all.\n16 in a hundred of their army's dead are carried home wounded after all.")]]
        known["my_commanders"] = known["my_commanders"]?.map { row in row[0] == n(11) ? row + [n(3), n(2), n(0)] : row }
        let theirs = self.session(StandInLine(rows: known))
        await theirs.open()
        let told = try XCTUnwrap(theirs.counsel(of: 11)).yourselfLook
        XCTAssertTrue(told.hasPrefix("You are Corwen, outrider of level 4, 200 of 1,600 seen toward the next. You are steady among the realm's commanders, "
                                     + "and your gift is Mercy, at level 2: 16 in a hundred of their army's dead are carried home wounded after all. You are in the city."), told)
        XCTAssertTrue(briefing.contains("Your lord's city: Keep level 3, power 1,000."))
        XCTAssertTrue(briefing.contains { $0.hasPrefix("Armies out: ") && $0.contains("40 soldiers") }, "her army at the grove")
        let deeds = try XCTUnwrap(briefing.last)
        XCTAssertTrue(deeds.hasPrefix("Deeds that can be done now, in the words you put them forward by: "), deeds)
        XCTAssertTrue(deeds.contains("Raise the Farm to level 3") && deeds.contains("Build a Sawmill"))
        XCTAssertFalse(counsel.deeds.contains { if case .open = $0.act { return true } else { return false } }, "opening a part is no deed")

        // What they may look at.
        XCTAssertTrue(counsel.cityLook.contains("May be built or raised now: Farm, Sawmill."), counsel.cityLook)
        XCTAssertTrue(counsel.cityLook.contains("40 soldiers stand ready"))
        XCTAssertNotEqual(counsel.armiesLook, "No army of your lord's is out.")
        XCTAssertEqual(counsel.allianceLook, "Your lord is in no alliance.")
        XCTAssertEqual(counsel.realmLook, "Your lord stands 2nd in power in the realm.")
        // Each look as the model asks it, held to five sights; words that are no sight's own fall to the nearest, or the city.
        XCTAssertEqual(LiveCounsel.Sight.allCases.map(\.rawValue), ["city", "armies", "alliance", "realm", "yourself"])
        XCTAssertEqual(LiveCounsel.Sight.allCases.map { counsel.look($0) },
                       [counsel.cityLook, counsel.armiesLook, counsel.allianceLook, counsel.realmLook, counsel.yourselfLook], "short enough to be whole")
        XCTAssertEqual(["Armies", "the armies out", "our alliance", "the realm.", "Yourself", "the granary", ""].map { LiveCounsel.Sight(asked: $0) },
                       [.armies, .armies, .alliance, .realm, .yourself, .city, .city])
        XCTAssertEqual(LiveCounsel.Sight.allCases.map(\.label), ["the city", "the armies out", "the alliance", "the realm", "themself"])
        // A look too long for the model's room: whole sentences while they fit, then a word that there is more.
        let long = (1...60).map { "Army \($0) gathers timber at the grove." }.joined(separator: " ")
        let held = LiveCounsel.capped(long, most: LiveCounsel.lookMost)
        XCTAssertLessThanOrEqual(held.count, LiveCounsel.lookMost)
        XCTAssertTrue(held.hasPrefix("Army 1 gathers timber at the grove. Army 2 gathers"), held)
        XCTAssertTrue(held.hasSuffix("at the grove. There is more than this."), held)
        XCTAssertEqual(LiveCounsel.capped("Short words.", most: 700), "Short words.")
        XCTAssertEqual(LiveCounsel.capped("One long sentence without an end in sight at all", most: 40), "One long. There is more than this.")
        XCTAssertLessThanOrEqual(LiveCounsel.capped(String(repeating: "word ", count: 400), most: 120).count, 120)

        // A deed put forward: in its own words, or in words it holds; only ever one that can be done now.
        let raise = counsel.propose("Raise the Farm to level 3.")
        XCTAssertEqual(raise.command?.act, .upgrade(22))
        XCTAssertEqual(raise.answer, "Put to your lord: Raise the Farm to level 3. Your lord decides.")
        XCTAssertEqual(counsel.propose("build sawmill").command?.act, .build(3))
        XCTAssertNil(counsel.propose("Burn the lake dry").command)
        XCTAssertEqual(counsel.propose("Burn the lake dry").answer, "That cannot be done now. Put forward only a deed you were told can be done.")
        XCTAssertNil(counsel.propose("").command)
        let either = counsel.propose("a")
        XCTAssertNil(either.command)
        XCTAssertTrue(either.answer.hasPrefix("Say which: "), either.answer)

        // Every number an answer gives must be one the commander was told.
        XCTAssertEqual(LiveCounsel.numbers(in: "1,600 seen, 40 soldiers; 3, 4 and 2,000,000."), ["1600", "40", "3", "4", "2000000"])
        XCTAssertEqual(counsel.strayNumbers(in: "Your Keep stands at level 3, my lord, with 40 soldiers ready."), [], "all told in the briefing or the look")
        XCTAssertEqual(counsel.strayNumbers(in: "Raise the Farm to level 3; it wants 300 timber."), ["300"], "the Farm's cost was never told")
        XCTAssertEqual(counsel.strayNumbers(in: "It wants 300 timber.", looks: ["The Farm to level 3 costs 300 timber."]), [], "unless a look told it")
    }

    /// Works under way are named, and hastened from the palette: by a
    /// quarter for goods, or by a haste held; never by a peace, and not
    /// once all but done.
    func testWorksUnderWayAreHastenedFromThePalette() async throws {
        var rows = LiveWindowTests.rows()
        rows["blueprint"] = [[n(2 << 32 | 1), n(2), n(1), .string("Farm"), n(0), n(100), n(0), n(0), n(10), n(0), n(0), n(0), n(0), n(1), n(0), n(0), n(20)]]
        rows["my_jobs"] = [[n(4), n(7), n(1), n(22), n(3), n(0), n(2_000), n(2_100), n(9)]]
        rows["my_stock"] = [[n(7), n(60_000), n(60_000), n(60_000), n(0), n(2_000), n(0), n(0), n(0), n(0), n(0), n(0), n(0), n(0), n(200_000)]]
        rows["ware"] = [[n(1), .string("Five minutes' haste"), .string("Takes five minutes off a work."), n(300), n(1)],
                        [n(4), .string("Eight hours' peace"), .string("Keeps your city at peace."), n(28_800), n(2)]]
        rows["my_satchel"] = [[n(1 << 8 | 1), n(1), n(1), n(2)], [n(1 << 8 | 4), n(1), n(4), n(1)]]
        let line = StandInLine(rows: rows)
        let session = session(line)
        await session.open()
        XCTAssertEqual(session.world.works(at: 2_015).map(\.words), ["the Farm to level 3"])
        XCTAssertTrue(session.world.works(at: 2_099.5).isEmpty, "all but done, nothing to hasten")

        let commands = session.commands(at: 2_015)
        XCTAssertTrue(commands.contains(LiveCommand(title: "Hasten the Farm to level 3 by a quarter, for 300 grain, 300 timber and 300 stone", act: .speedUp(4))))
        XCTAssertTrue(commands.contains(LiveCommand(title: "Use five minutes' haste on the Farm to level 3", act: .useHaste(item: 1, job: 4))))
        XCTAssertFalse(commands.contains { command in
            if case .useHaste(let item, _) = command.act { return item == 4 }
            return false
        }, "a peace hastens no work")
        await session.perform(LiveCommand(title: "Hasten", act: .speedUp(4)))
        XCTAssertEqual(line.asked.last, "speed up 4")
        await session.perform(LiveCommand(title: "Use", act: .useHaste(item: 1, job: 4)))
        XCTAssertEqual(line.asked.last, "use 1 on 4")
        // A commander's counsel knows the work, and how long it has to run.
        line.change { $0["my_commanders"] = [[self.n(11), self.n(1), .string("Corwen"), self.n(5), self.n(2), self.n(0), self.n(0)]] }
        session.refresh()
        let briefing = try XCTUnwrap(session.counsel(of: 11)).briefing
        XCTAssertTrue(briefing.contains("Works under way: the Farm to level 3, 1 minute 25 seconds left."), briefing)
    }

    func testAnArmyChosenIsToldAndCanBeCalledHome() async throws {
        let line = StandInLine(rows: LiveWindowTests.rows())
        // Seventeen seconds along its way of twenty-four: on 11, -2.
        let session = session(line, at: 2_017)
        await session.open()
        let hers = session.card(for: session.selection(at: LiveHex(q: 11, r: -2)))
        XCTAssertEqual(hers.title, "Your army")
        XCTAssertEqual(hers.lines, ["On its way to gather timber: 0:07", "40 soldiers."])
        XCTAssertEqual(hers.buttons, [.init(title: "Call home", act: .recall(3), why: nil)])
        await session.press(hers.buttons[0])
        XCTAssertEqual(line.asked, ["recall 3"])

        // Another's army is told by whose it is and how many march.
        guard let bryns = session.world.marches[4] else { return XCTFail("Bryn's army") }
        XCTAssertEqual(session.card(for: .army(bryns, own: false)), LiveCard(title: "Bryn's army", lines: ["90 soldiers"], buttons: []))
        // Her own in a fight can't be called away, and the card says why.
        guard let fighting = session.world.marches[6] else { return XCTFail("the army at the barrow") }
        line.change { rows in
            rows["march"] = rows["march"]?.map { row in
                var row = row
                if row[0] == .number(6) { row[1] = .number(1) }
                return row
            }
        }
        session.refresh()
        let own = session.card(for: .army(session.world.marches[6] ?? fighting, own: true))
        XCTAssertEqual(own.lines.first, "Fighting at a level 2 barrow: 0:08")
        XCTAssertEqual(own.buttons, [.init(title: "Call home", act: .recall(6), why: "That army is fighting. Wait for the fight to end.")])
    }

    func testWhatIsAskedGoesToTheRealmAndItsRefusalIsKept() async throws {
        var rows = LiveWindowTests.rows()
        rows["my_troops"] = [[n(7 << 16 | 1 << 8 | 1), n(7), n(1), n(1), n(40), n(0)], [n(7 << 16 | 3 << 8 | 2), n(7), n(3), n(2), n(12), n(5)],
                             [n(7 << 16 | 2 << 8 | 1), n(7), n(2), n(1), n(0), n(9)]]
        let line = StandInLine(rows: rows)
        let session = session(line)
        await session.open()
        XCTAssertEqual(session.everyoneReady.map { [$0.kind, $0.tier, Int($0.count)] }, [[1, 1, 40], [3, 2, 12]], "those ready, never the wounded")

        await session.build(2)
        await session.upgrade(building: 21)
        await session.train(building: 24, tier: 1, count: 50)
        await session.heal(kind: 3, tier: 2, count: 5)
        await session.recall(march: 3)
        await session.read(report: 31)
        await session.forget(report: 31)
        // An army is sent for what lies where it is sent: to gather at a
        // site, to fight at a barrow, and nowhere else.
        await session.send(session.everyoneReady, to: LiveHex(q: 12, r: -2))
        await session.send([(kind: 1, tier: 1, count: 30)], to: LiveHex(q: 8, r: -2))
        XCTAssertEqual(line.asked, ["build 2", "upgrade 21", "train 50 of tier 1 in 24", "heal 5 of 3.2", "recall 3", "read 31", "forget 31",
                                    "gather at 12, -2 with 40 of 1.1, 12 of 3.2", "hunt at 8, -2 with 30 of 1.1"])
        XCTAssertNil(session.said)
        XCTAssertEqual(session.asking, 0)
        await session.send([(kind: 1, tier: 1, count: 30)], to: LiveHex(q: 5, r: 5))
        XCTAssertEqual(session.said, "There is nothing to send an army for there.")
        XCTAssertEqual(line.asked.count, 9, "and the realm is not troubled with it")

        // Alliances and what is said go the same way.
        session.said = nil
        await session.foundAlliance(name: "Keepers", tag: "MERE")
        await session.joinAlliance(5)
        await session.answer(applicant: 9, admit: true)
        await session.answer(applicant: 8, admit: false)
        await session.setRank(of: 2, to: LiveMember.officer)
        await session.expel(3)
        await session.setAlliance(open: false, words: "We keep the east shore.")
        await session.say("Good morning, all.", withinAlliance: false)
        await session.say("East shore is quiet", withinAlliance: true)
        await session.leaveAlliance()
        await session.learn(topic: 5)
        XCTAssertEqual(line.asked.last, "learn 5")
        await session.claimTask()
        XCTAssertEqual(line.asked.last, "claim task")
        XCTAssertEqual(Array(line.asked.dropLast(2).suffix(10)), ["found Keepers [MERE]", "join alliance 5", "admit 9", "turn away 8", "rank 2 4", "expel 3",
                                                       "alliance closed: We keep the east shore.", "say to all: Good morning, all.",
                                                       "say within: East shore is quiet", "leave alliance"])
        XCTAssertNil(session.said)

        // A line reported to the realm's owner, and said so.
        XCTAssertFalse(session.hasReported(line: 12, withinAlliance: false))
        await session.report(line: 12, withinAlliance: false)
        XCTAssertEqual(line.asked.last, "report realm line 12")
        XCTAssertEqual(session.said, "Reported to the realm's owner, who reads every report.")
        XCTAssertTrue(session.hasReported(line: 12, withinAlliance: false))
        XCTAssertFalse(session.hasReported(line: 12, withinAlliance: true), "a line of the alliance's is another")
        session.said = nil

        // The realm's depth goes the same way: help, land, learning, the
        // Moonspire, talents, pairs, the keeper, hastes, items, chests and
        // prizes; and rallies, with everyone ready.
        line.clear()
        await session.askHelp(job: 4)
        await session.helpAll()
        await session.raiseWard(at: LiveHex(q: 3, r: -1))
        await session.razeWard(7)
        await session.giveToLearning(topic: 1, LiveGoods(grain: 10, timber: 20, stone: 30))
        await session.giveToSpire(LiveGoods(grain: 1, timber: 2, stone: 3, moonsalt: 4))
        await session.learnTalent(commander: 11, talent: 6)
        await session.forgetTalents(commander: 11)
        await session.pair(commander: 11, with: 12)
        await session.keepCity(commander: 12)
        await session.speedUp(job: 4)
        await session.useItem(2, on: 4)
        await session.usePeace(4)
        await session.forge(piece: 1)
        await session.equip(gear: 3, on: 11)
        await session.unequip(gear: 3)
        await session.openChest(1)
        await session.claimPrize(contest: 1, place: 2)
        await session.claimPlace(contest: 3)
        await session.offerLink()
        await session.takeLink("abcde 23456")
        XCTAssertEqual(line.asked, ["ask help 4", "help 0", "raise ward 3,-1", "raze ward 7", "give [10, 20, 30, 0] to learning 1",
                                    "give [1, 2, 3, 4] to the Moonspire", "talent 6 for 11", "forget talents of 11", "pair 11 with 12", "keep city 12",
                                    "speed up 4", "use 2 on 4", "keep the peace with 4", "forge 1", "equip 3 on 11", "unequip 3", "open chest 1", "claim prize 2 of 1",
                                    "claim place in 3", "offer a link", "take link abcde 23456"])
        line.clear()
        await session.sendEnvoy(to: 6, terms: LivePact.truce, days: 3)
        await session.answerEnvoy(5, accept: true)
        await session.answerEnvoy(7, accept: false)
        await session.breakPact(2)
        await session.ransom(commander: 11)
        await session.releasePrisoner(commander: 21)
        await session.petition(LiveGoods(grain: 50_000))
        await session.answerPetition(of: 2, LiveGoods(timber: 10_000))
        await session.withdrawPetition()
        await session.bestowTitle(1, on: 5)
        await session.takeTitle(3)
        await session.sendLetter(to: 5, "We come.")
        await session.sendAllianceLetter("Muster at dusk.")
        await session.readLetter(7)
        await session.forgetLetter(7)
        XCTAssertEqual(Array(line.asked.suffix(6)), ["title 1 on 5", "take title 3", "letter to 5: We come.", "letter to the alliance: Muster at dusk.", "read letter 7",
                                                     "forget letter 7"])
        XCTAssertEqual(Array(line.asked.prefix(9)), ["envoy to 6: 1 for 3 days", "accept envoy 5", "turn away envoy 7", "break pact 2", "ransom 11", "let 21 go",
                                    "petition for [50000, 0, 0, 0]", "answer 2's petition with [0, 10000, 0, 0]", "withdraw petition"])
        line.clear()
        await session.callRally(at: LiveHex(q: 8, r: -2))
        await session.joinRally(6)
        XCTAssertEqual(line.asked.count, 2)
        XCTAssertTrue(line.asked[0].hasPrefix("rally at 8,-2 with 40 of 1.1, 12 of 3.2 led by "), line.asked[0])
        XCTAssertTrue(line.asked[1].hasPrefix("join rally 6 with 40 of 1.1, 12 of 3.2 led by "), line.asked[1])
        XCTAssertNil(session.said)

        // The realm's refusal is kept in its own words until put away.
        session.said = nil
        line.refuse("Your builders are busy. Wait for them to finish.")
        await session.build(4)
        XCTAssertEqual(session.said, "Your builders are busy. Wait for them to finish.")
        session.said = nil
        line.refuse(nil)
        await session.build(4)
        XCTAssertNil(session.said)
        // A line that drops says so plainly.
        line.drop()
        await session.build(4)
        XCTAssertEqual(session.said, "The realm could not be reached. Try again in a moment.")
        XCTAssertEqual(session.asking, 0)
    }
}
