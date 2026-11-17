import AppKit
import LauncherCore
import LauncherKit
import SwiftUI
import XCTest
@testable import NullmereKit
@testable import NullmereLive
import NullmereLiveStage
import NullmereRealm
import NullmereTestSupport
import NullmereWorld

/// The rebuilt realm's screens over a session on a stand-in line: what
/// lies over the world drawn for each state, the map in a real window
/// answering the pointer, and the way in that a debug run is given.
@MainActor
final class LiveGameTests: XCTestCase {
    private func n(_ value: Int) -> JSONValue { .number(Double(value)) }

    private func spin(_ seconds: Double) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let found = view as? T { return found }
        for child in view.subviews {
            if let found = find(type, in: child) { return found }
        }
        return nil
    }

    /// Ada's realm with something of everything a screen lists: troops
    /// ready and wounded, a Barracks training, a building rising, energy,
    /// and two reports, one unread.
    private func rows() -> [String: [[JSONValue]]] {
        var rows = LiveSample.rows()
        func blueprint(_ kind: Int, _ level: Int, _ name: String, opensAt: Int = 1) -> [JSONValue] {
            [n(kind << 32 | level), n(kind), n(level), .string(name), n(0), n(100 * level), n(40 * level), n(0), n(30 * level), n(0), n(0), n(0), n(0),
             n(opensAt), n(0), n(0), n(20 * level)]
        }
        rows["blueprint"] = (1...12).flatMap { level in
            [blueprint(1, level, "Keep"), blueprint(2, level, "Farm"), blueprint(7, level, "Barracks", opensAt: 2), blueprint(12, level, "Wall", opensAt: 3),
             blueprint(11, level, "Hospital", opensAt: 3)]
        }
        rows["soldier"] = [[n(1 << 8 | 1), n(1), n(1), .string("Spearmen"), n(90), n(110), n(110), n(60), n(12), n(1), n(50), n(50), n(0), n(0), n(8_000), n(7), n(1)],
                           [n(1 << 8 | 2), n(1), n(2), .string("Spearmen"), n(120), n(150), n(150), n(60), n(12), n(2), n(100), n(100), n(0), n(0), n(16_000), n(7), n(5)]]
        rows["my_buildings"]?.append([n(24), n(7), n(7), n(1)])
        rows["my_jobs"] = [[n(4), n(7), n(1), n(22), n(3), n(0), n(2_000), n(2_100), n(9)], [n(5), n(7), n(3), n(7 << 16 | 1 << 8 | 1), n(1), n(4), n(2_010), n(2_030), n(10)]]
        rows["my_stock"] = [[n(7), n(6_000), n(8_000), n(30_000), n(12), n(2_000), n(1_300), n(1_300), n(300), n(0), n(0), n(0), n(0), n(0), n(30_000)]]
        rows["my_troops"] = [[n(7 << 16 | 1 << 8 | 1), n(7), n(1), n(1), n(40), n(6)]]
        rows["my_hunt"] = [[n(1), n(940), n(2_000), n(1_000), n(8_000), n(1)]]
        rows["study"] = (1...3).flatMap { level -> [[JSONValue]] in
            [[n(1 << 32 | level), n(1), n(level), .string("Tillage"), .string("Your Farm brings in 5% more grain."), n(5), n(500 * level), n(300 * level), n(0), n(0),
              n(120 * level * level), n(2 * level - 1)],
             [n(8 << 32 | level), n(8), n(level), .string("Spearcraft"), .string("Your Spearmen strike 3% harder."), n(3), n(0), n(500 * level), n(300 * level), n(0),
              n(120 * level * level), n(2 * level - 1)]]
        }
        rows["my_lore"] = [[n(7 << 8 | 1), n(7), n(1), n(2)]]
        rows["my_buildings"]?.append([n(30), n(7), n(14), n(3)])
        rows["my_commanders"] = [[n(11), n(1), .string("Corwen"), n(1), n(2), n(100), n(0)], [n(12), n(1), .string("Halen"), n(3), n(4), n(0), n(3)]]
        rows["task"] = [[n(1), n(1), n(2), n(0), .string("Raise your Keep to level 2."), n(1_000), n(1_000), n(0), n(0)],
                        [n(2), n(2), n(7), n(1), .string("Build a Barracks."), n(1_000), n(1_000), n(0), n(0)]]
        rows["my_progress"] = [[n(1), n(1)]]
        rows["alliance"] = [[n(5), n(77), n(78), .string("Keepers of the Mere"), .string("MERE"), n(1), n(1_500), n(2), .bool(false), .string("We keep the east shore.")],
                            [n(6), n(79), n(80), .string("Wardens"), .string("WRD"), n(4), n(1_600), n(60), .bool(true), .string("")]]
        rows["member"] = [[n(1), n(5), n(5), n(1_500)], [n(2), n(5), n(1), n(1_600)]]
        rows["realm_chat"] = [[n(11), n(2), .string("[MERE] Bryn"), n(2_000), .string("Good morning, all.")], [n(12), n(1), .string("[MERE] Ada"), n(2_010), .string("Morning.")]]
        rows["my_alliance_chat"] = [[n(31), n(5), n(2), .string("Bryn"), n(2_012), .string("East shore is quiet")]]
        rows["my_applicants"] = [[n(9), n(5), .string("Edda"), n(2_013)]]
        rows["my_reports"] = [
            [n(31), n(1), n(1_900), n(1), n(Int(LiveHex(q: 8, r: -2).packed)), .bool(true), n(1), n(3), n(200), n(6), n(0), n(25), n(25), n(800), n(800), n(0), n(0),
             .string("Your army cleared a level 1 barrow of the Unquiet. Of your 200 soldiers, 6 were wounded. It is bringing home 800 grain and 800 timber."), .bool(true)],
            [n(32), n(1), n(1_950), n(1), n(Int(LiveHex(q: 8, r: -2).packed)), .bool(false), n(2), n(5), n(40), n(30), n(10), n(60), n(31), n(0), n(0), n(0), n(0),
             .string("Your army was beaten at a level 2 barrow of the Unquiet. 29 of the Unquiet still stood. Of your 40 soldiers, 30 were wounded and 10 died."), .bool(false)],
        ]
        // The realm's depth: the day's work and chests, items, favour and
        // the contest; talents, a pair and a keeper; the alliance's
        // Moonspire, learning, a rally, help, a wardstone and a gate.
        rows["duty"] = [[n(1), n(50), n(20), .string("Train 50 soldiers.")], [n(2), n(5_000), n(20), .string("Gather 5,000 goods.")]]
        rows["chest"] = [[n(1), n(20), n(5_000), n(5_000), n(0), n(0), n(2), n(0), n(0)], [n(2), n(60), n(0), n(0), n(10_000), n(50), n(0), n(1), n(0)]]
        rows["ware"] = [[n(1), .string("Five minutes' haste"), .string("Five minutes sooner."), n(300)], [n(2), .string("An hour's haste"), .string("An hour sooner."), n(3_600)],
                        [n(4), .string("Eight hours' peace"), .string("Keeps your city at peace for 8 hours."), n(28_800), n(2)],
                        [n(5), .string("Iron"), .string("Worked at the Forge into gear."), n(0), n(3)],
                        [n(9), .string("A tome of war"), .string("Adds 500 to what a commander has seen."), n(0), n(4)]]
        // Two tomes held, to read to a commander; the alliance's stores, a
        // haste she has the honour for and a tome she has not.
        rows["price"] = [[n(1), n(100)], [n(9), n(250)]]
        rows["my_honour"] = [[n(1), n(180), n(0), n(0)]]
        rows["my_daily"] = [[n(1), n(0), n(60), n(1_200), n(0), n(1), n(0), n(0)]]
        rows["my_satchel"] = [[n(1 << 8 | 1), n(1), n(1), n(3)], [n(1 << 8 | 4), n(1), n(4), n(1)], [n(1 << 8 | 5), n(1), n(5), n(6)],
                              [n(1 << 8 | 9), n(1), n(9), n(2)]]
        // The Forge: two pieces it makes, a piece worn and one spare.
        rows["pattern"] = [[n(1), .string("Iron sword"), n(1), n(1), .string("Everyone its wearer leads strikes 3% harder."), n(4), n(4), n(0), n(0), n(0), n(5_000), n(5_000),
                            n(0), n(1)],
                           [n(10), .string("Leather boots"), n(4), n(1), .string("Its wearer's army marches 4% faster."), n(4), n(4), n(0), n(0), n(0), n(5_000), n(5_000),
                            n(0), n(1)]]
        rows["my_gear"] = [[n(1), n(1), n(1), n(11)], [n(2), n(1), n(10), n(0)]]
        rows["my_favour"] = [[n(1), n(140), n(1)]]
        rows["fame"] = [[n(1), n(120), n(80), n(30)], [n(2), n(340), n(200), n(12)]]
        rows["my_boons"] = [[n(51), n(1), n(2), n(4), n(800), n(800), n(800), n(90_000), n(3)]]
        rows["trial"] = [[n(1), .string("The Long Hunt"), .string("Points for every barrow cleared."), n(7), n(3)]]
        rows["prize"] = [[n(257), n(1), n(1), n(100), n(9_000), n(0), n(0), n(0), n(1), n(0), n(0)], [n(258), n(1), n(2), n(400), n(0), n(0), n(0), n(100), n(0), n(2), n(0)]]
        rows["my_tallies"] = [[n(5), n(1), n(1), n(0), n(120), n(0)]]
        // The hunt's first round: Ada first, Bryn second; and what the first
        // three places give once it is over.
        rows["standing"] = [[n(1 << 24 | 1), n(1), n(1), n(1), n(0), n(120), n(1_500), .bool(false)],
                            [n(2 << 24 | 1), n(1), n(2), n(1), n(0), n(90), n(1_800), .bool(false)]]
        rows["laurel"] = [[n(257), n(1), n(1), n(60_000), n(60_000), n(30_000), n(900), n(0), n(0), n(3), n(0)],
                          [n(258), n(1), n(2), n(40_000), n(40_000), n(20_000), n(600), n(0), n(0), n(2), n(0)]]
        // A code asked for to link her phone, good until 2,600.
        rows["my_link"] = [[n(77), n(1), .string("ABCDE23456"), n(2_600)]]
        rows["my_skills"] = [[n(12 << 8 | 6), n(12), n(1), n(6), n(2)]]
        rows["my_bonds"] = [[n(12), n(1), n(11)]]
        rows["my_keeper"] = [[n(1), n(11)]]
        rows["spire"] = [[n(5), .string("Keepers of the Mere"), n(1), n(1), n(0), n(0), n(40_000), n(30_000), n(20_000), n(0)]]
        rows["season"] = [[n(1), n(1_000), n(2_420_200), n(5), .string("Keepers of the Mere"), n(1_800)]]
        rows["learning"] = [[n(5 << 8 | 1), n(5), n(1), n(1), n(0), n(0), n(60_000), n(0), n(0)]]
        rows["my_rallies"] = [[n(6), n(5), n(2), .string("[MERE] Bryn"), n(9), n(0), n(Int(LiveHex(q: 8, r: -2).packed)), n(2), n(2_300), n(1), n(1), n(500)]]
        rows["my_pleas"] = [[n(77), n(5), n(2), .string("[MERE] Bryn"), n(1), n(1), n(5)]]
        rows["ward"] = [[n(3), n(5), n(Int(LiveHex(q: 12, r: -6).packed)), n(1), n(1_500)]]
        rows["gate"] = [[n(1), n(Int(LiveHex(q: 22, r: 0).packed)), n(5), .string("[MERE] Keepers of the Mere"), n(1_900), n(0)]]
        // A truce with the Wardens, their envoy waiting, a prisoner each way, and two petitions.
        rows["pact"] = [[n(1), n(5), n(6), n(1), n(1_500), n(600_000)]]
        rows["my_envoys"] = [[n(5), n(6), n(5), .string("[WRD] Wardens"), n(2), n(7), n(2_000)]]
        rows["my_prisoners"] = [[n(11), n(1), n(2), .string("Corwen"), n(10_000), n(10_000), n(10_000), n(200_000), n(0)],
                                [n(31), n(2), n(1), .string("Sela"), n(5_000), n(5_000), n(5_000), n(200_000), n(0)]]
        rows["my_petitions"] = [[n(2), n(5), .string("[MERE] Bryn"), n(100_000), n(0), n(0), n(0), n(20_000), n(0), n(0), n(0), n(2_000)],
                                [n(1), n(5), .string("[MERE] Ada"), n(0), n(50_000), n(0), n(0), n(0), n(0), n(0), n(0), n(2_000)]]
        // Ada's alliance won the season: she is the Lord, a title bestowed; and letters, one unread.
        rows["title"] = [[n(1), n(2), .string("Bryn"), n(1_900)]]
        rows["my_letters"] = [[n(41), n(2), n(1), .string("[MERE] Bryn"), .string("The east road is clear. Come at dawn."), n(1_950), .bool(false)],
                              [n(42), n(2), n(1), .string("[MERE] Bryn"), .string("Muster at dusk."), n(1_960), .bool(true)]]
        return rows
    }

    private func playing(_ rows: [String: [[JSONValue]]]? = nil) async -> (LiveSession, StandInLine) {
        let line = StandInLine(rows: rows ?? self.rows())
        let session = LiveSession(line: line) { 2_015 }
        await session.open()
        return (session, line)
    }

    /// How much of a view shows when it is drawn in a window, as AppKit
    /// draws it; kept under a name where CI asks for the tests' renders.
    private func drawn(_ view: some View, width: CGFloat, height: CGFloat, as name: String? = nil) throws -> Int {
        let size = CGSize(width: width, height: height)
        let framed = view.frame(width: width, height: height)
        if let name { try CardShot.keep(framed, as: name, size: size) }
        return litPixels(try CardShot.draw(framed, size: size))
    }

    /// The world's share of a laptop's window as the rebuilt realm's play
    /// view lays it out, with a destination open or none, and the pieces
    /// that took the rest.
    private func worldShare(_ session: LiveSession, opening panel: LiveGameView.Panel?) -> (share: Double, pieces: [String]) {
        let size = CGSize(width: 1512, height: 982)
        ChromeLedger.isListening = true
        defer { ChromeLedger.isListening = false }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: LiveGameView(session: session, opening: panel).frame(width: size.width, height: size.height))
        window.orderFrontRegardless()
        defer { window.close() }
        spin(1.0)
        return (1 - ChromeLedger.covered(of: size), ChromeLedger.frames.keys.sorted())
    }

    /// What a side panel holds, unscrolled, as `LiveSidePanel` lays it
    /// in its scrolling list.
    @ViewBuilder
    private func whole(_ panel: LiveGameView.Panel, of session: LiveSession, at seconds: Double = 2_015) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            switch panel {
            case .city: LiveBuildings(session: session, seconds: seconds)
            case .troops:
                LiveCommanders(session: session, seconds: seconds)
                LiveTroops(session: session, seconds: seconds)
            case .studies: LiveStudies(session: session, seconds: seconds)
            case .alliance:
                LiveAlliancePanel(session: session)
                LiveAllianceDepth(session: session, seconds: seconds)
            case .chat: LiveChatPanel(session: session)
            case .reports:
                LiveLetters(session: session, seconds: seconds)
                LiveReports(session: session, seconds: seconds)
            case .day: LiveDayPanel(session: session, seconds: seconds)
            case .realm: LiveRealmPanel(session: session, seconds: seconds)
            case .forge: LiveForgePanel(session: session, seconds: seconds)
            case .rankings: LiveRankingsPanel(session: session)
            }
        }
        .padding(14)
        .background(NullmereKit.Palette.panel)
    }

    /// A card's buttons, in its ring or at the foot: Buildings and Troops
    /// open the House at those parts; any other asks the realm.
    func testACardsButtonsOpenTheHouseOrAskTheRealm() async throws {
        let (session, line) = await playing()
        var panel: LiveGameView.Panel?
        let binding = Binding(get: { panel }, set: { panel = $0 })
        let home = session.card(for: session.selection(at: LiveHex(q: 10, r: -4)))
        let city = try XCTUnwrap(home.buttons.first { $0.act == .city })
        let troops = try XCTUnwrap(home.buttons.first { $0.act == .troops })
        LiveGameView.press(city, session: session, panel: binding)
        XCTAssertEqual(panel, .city)
        LiveGameView.press(troops, session: session, panel: binding)
        XCTAssertEqual(panel, .troops)
        let hasten = try XCTUnwrap(home.buttons.first { if case .hasten = $0.act { return true } else { return false } }, "\(home.buttons.map(\.title))")
        line.clear()
        LiveGameView.press(hasten, session: session, panel: binding)
        for _ in 0..<100 where line.asked.isEmpty { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(line.asked.contains { $0.hasPrefix("speed up") }, "\(line.asked)")
        XCTAssertEqual(panel, .troops, "asking the realm opens nothing")
    }

    /// The world is the screen in the rebuilt realm too: whatever is open,
    /// the interface keeps to the edges and leaves the world its share.
    func testTheWorldKeepsMostOfTheScreenWhateverIsOpen() async throws {
        let (session, _) = await playing()
        let plain = worldShare(session, opening: nil)
        XCTAssertTrue(plain.pieces.contains("live-bar") && plain.pieces.contains("live-dock"), "The interface notes where it lies: \(plain.pieces)")
        session.selected = session.world.city?.hex
        let chosen = worldShare(session, opening: nil)
        XCTAssertTrue(chosen.pieces.contains("live-card"))
        session.selected = nil
        var opened: [String] = []
        for place in LiveGameView.Destination.allCases {
            for part in place.panels {
                let open = worldShare(session, opening: part)
                XCTAssertTrue(open.pieces.contains("live-panel"), "\(part) is open")
                XCTAssertGreaterThan(open.share, ChromeBudget.worldShare, "With \(part.title) open, the world keeps its share")
                opened.append("\(part.title) \(Int((open.share * 100).rounded()))%")
            }
        }
        func share(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
        print("LAYOUT the rebuilt realm's world in a 1512x982 window: \(share(plain.share)) plain, \(share(chosen.share)) with her city chosen; "
              + "open: \(opened.joined(separator: ", ")) (pieces: \(chosen.pieces.joined(separator: ", ")))")
        XCTAssertGreaterThan(plain.share, ChromeBudget.worldShare, "Nothing chosen, the world is the screen")
        XCTAssertGreaterThan(chosen.share, ChromeBudget.worldShare, "A card for what is chosen keeps to the foot")
    }

    func testWhatLiesOverTheWorldIsDrawnForEachState() async throws {
        let (session, line) = await playing()
        XCTAssertEqual(session.phase, .playing)

        // Nothing chosen, no panel: the top bar and the army out, and the
        // world left clear between them.
        var panel: LiveGameView.Panel?
        let binding = Binding(get: { panel }, set: { panel = $0 })
        let bare = try drawn(LiveHUD(session: session, panel: binding, palette: .constant(false)), width: 1280, height: 800)
        XCTAssertGreaterThan(bare, 400, "The city's name, its goods, the army out")
        XCTAssertLessThan(bare, 1280 * 800 / 4, "and most of the window left to the world")

        // Something chosen: its card at the foot. And what the realm said.
        session.selected = LiveHex(q: 12, r: -2)
        session.said = "Another army is gathering there."
        let chosen = try drawn(LiveHUD(session: session, panel: binding, palette: .constant(false)), width: 1280, height: 800, as: "live-hud.png")
        XCTAssertGreaterThan(chosen, bare + 200, "The grove's card and the realm's words")
        // The palette open over it, as Command-K opens it.
        let finding = try drawn(LiveHUD(session: session, panel: binding, palette: .constant(true)), width: 1280, height: 800, as: "live-hud-palette.png")
        XCTAssertGreaterThan(finding, chosen, "The palette over the world")
        for hex in [LiveHex(q: 10, r: -4), LiveHex(q: 14, r: -4), LiveHex(q: 8, r: -2), LiveHex(q: 5, r: 5)] {
            let card = session.card(for: session.selection(at: hex))
            XCTAssertGreaterThan(try drawn(LiveCardView(session: session, card: card, panel: binding), width: 640, height: 120), 40, card.title)
        }
        // What is chosen, shown about it: a ring of its symbols and a callout beside it.
        let home = session.card(for: session.selection(at: LiveHex(q: 10, r: -4)))
        XCTAssertGreaterThan(try drawn(LiveRing(session: session, card: home, at: CGPoint(x: 160, y: 160), panel: binding), width: 640, height: 320,
                                       as: "live-ring.png"), 300)
        // Her city chosen: its plots, a hammer where each building her Keep
        // has opened but she has not built would stand; one chosen, its
        // card asks it built.
        session.selected = LiveHex(q: 10, r: -4)
        let plots = session.plots()
        XCTAssertTrue(plots.contains { $0.kind == 11 }, "the Hospital, opened by her Keep and not built: \(plots.map(\.kind))")
        XCTAssertGreaterThan(try drawn(LivePlots(session: session, size: CGSize(width: 1280, height: 800)), width: 1280, height: 800), 20, "a hammer drawn")
        XCTAssertGreaterThan(try drawn(LiveHUD(session: session, panel: binding, palette: .constant(false)), width: 1280, height: 800,
                                       as: "live-plots.png"), bare)
        session.choose(try XCTUnwrap(plots.first { $0.kind == 11 }))
        let plot = session.card(for: try XCTUnwrap(session.selection))
        XCTAssertEqual(plot.title, "Hospital")
        XCTAssertEqual(plot.buttons.first?.title, "Build")
        XCTAssertGreaterThan(try drawn(LiveRing(session: session, card: plot, at: CGPoint(x: 160, y: 160), panel: binding), width: 640, height: 320,
                                       as: "live-plot-ring.png"), 300)
        session.selected = LiveHex(q: 12, r: -2)
        // The callout keeps clear of an open destination: to the ring's left where, to its right, the destination would cover it.
        let window = CGSize(width: 1024, height: 700)
        XCTAssertFalse(LiveRing.leftward(at: CGPoint(x: 500, y: 200), in: window, beside: nil), "Nothing open: to the right")
        XCTAssertTrue(LiveRing.leftward(at: CGPoint(x: 500, y: 200), in: window, beside: 294))
        XCTAssertFalse(LiveRing.leftward(at: CGPoint(x: 500, y: 600), in: window, beside: 294), "Beneath the destination, room to the right")
        XCTAssertFalse(LiveRing.leftward(at: CGPoint(x: 100, y: 200), in: window, beside: 294), "Far enough left to clear it")
        XCTAssertGreaterThan(try drawn(LiveRing(session: session, card: home, at: CGPoint(x: 480, y: 160), panel: binding, leftward: true), width: 640, height: 320), 300)
        XCTAssertGreaterThan(try drawn(LiveSaid(words: "Clear a level 3 barrow first.") {}, width: 600, height: 60), 60)
        XCTAssertGreaterThan(try drawn(LiveArmies(session: session, seconds: 2_015), width: 400, height: 80), 60)

        XCTAssertGreaterThan(try drawn(LiveTaskChip(session: session), width: 420, height: 70), 60)
        // The whole realm small: its grounds a pixel to a hex, the cities on it, where the view looks.
        let small = try XCTUnwrap(session.minimap)
        let image = try XCTUnwrap(LiveMiniMap.image(of: small))
        XCTAssertEqual([image.width, image.height], [small.width, small.height])
        XCTAssertGreaterThan(try drawn(LiveMiniMap(session: session), width: 190, height: 170, as: "live-minimap.png"), 5_000)
        // What just happened, told a few seconds at the top: a report come.
        let (toldOf, toldLine) = await playing()
        let report: [JSONValue] = [n(999), n(1), n(2_014), n(LiveReport.hunt), n(Int(LiveHex(q: 8, r: -2).packed)), .bool(true), n(0), n(3),
                                   n(20), n(2), n(0), n(12), n(12), n(0), n(0), n(0), n(0), .string("Your army cleared a level 2 barrow."), .bool(false)]
        toldLine.change { $0["my_reports"] = ($0["my_reports"] ?? []) + [report] }
        toldOf.refresh()
        XCTAssertEqual(toldOf.news.last?.words, "A report: Your army cleared a level 2 barrow.")
        XCTAssertGreaterThan(try drawn(LiveToasts(session: toldOf, seconds: 2_015), width: 600, height: 120, as: "live-toasts.png"), 100)
        XCTAssertEqual(try drawn(LiveToasts(session: toldOf, seconds: 2_015 + LiveToasts.shown), width: 600, height: 120), 0, "and then gone")
        // What stands idle is reminded of, each kind by a symbol of its own.
        let kinds: [LiveIdle.Kind] = [.builders, .academy, .training, .chest]
        XCTAssertEqual(Set(kinds.map(LiveIdleChips.symbol)).count, kinds.count)
        // An army marching on her city: told in red, with a way to look at it.
        var threatened = LiveSample.rows()
        threatened["march"]?.append([n(21), n(2), n(8), n(LiveMarch.attack), n(LiveMarch.going), n(Int(LiveHex(q: 14, r: -4).packed)),
                                     n(Int(LiveHex(q: 10, r: -4).packed)), n(7), n(2_000), n(2_100), n(300), .string(""), n(4)])
        let (under, _) = await playing(threatened)
        XCTAssertEqual(under.world.threats(at: 2_015).map(\.words), ["Bryn's army of 300 reaches your city in 1:25."])
        XCTAssertGreaterThan(try drawn(LiveThreats(session: under, seconds: 2_015), width: 600, height: 80, as: "live-threats.png"), 100)
        XCTAssertGreaterThan(try drawn(LiveDock(session: session, panel: binding), width: 640, height: 50), 100)
        // Four destinations: the House of four parts, the alliance, the realm of two, the mail.
        XCTAssertEqual(LiveDock.destinations.map(\.title), ["House", "Alliance", "Realm", "Mail"])
        XCTAssertEqual(LiveGameView.Destination.house.panels, [.city, .troops, .studies, .forge, .day])
        XCTAssertEqual(LiveGameView.Destination.realm.panels, [.realm, .rankings, .chat])
        XCTAssertEqual([LiveGameView.Panel.day, LiveGameView.Panel.chat, LiveGameView.Panel.reports].map(\.destination), [.house, .realm, .mail])
        // Pressed, a destination opens at its first part, and closes again from any of its parts.
        XCTAssertEqual(LiveDock.pressed(.house, while: nil), .city)
        XCTAssertNil(LiveDock.pressed(.house, while: .studies))
        XCTAssertEqual(LiveDock.pressed(.realm, while: .studies), .realm)
        // The palette lists what can be done, and every part it names is a part of a destination.
        XCTAssertGreaterThan(try drawn(LivePaletteView(session: session, seconds: 2_015, open: { _ in }) {}, width: 420, height: 320, as: "live-palette.png"), 200)
        XCTAssertEqual(LiveSession.parts.compactMap { LiveGameView.Panel(part: $0.name) },
                       LiveGameView.Destination.allCases.flatMap(\.panels), "the palette's parts are the destinations', in order")
        XCTAssertNil(LiveGameView.Panel(part: "nowhere"))
        // Each side panel, with something of everything in it.
        for side in [LiveGameView.Panel.city, .troops, .studies, .forge, .alliance, .day, .realm, .rankings, .chat, .reports] {
            let lit = try drawn(LiveSidePanel(session: session, seconds: 2_015, panel: side) {}, width: 340, height: 700, as: "live-\(side).png")
            XCTAssertGreaterThan(lit, 800, "\(side)")
        }
        // And with nothing in them: no soldiers yet, no reports yet.
        let (empty, _) = await playing(LiveSample.rows())
        for side in [LiveGameView.Panel.troops, .studies, .forge, .alliance, .day, .realm, .rankings, .chat, .reports] {
            XCTAssertGreaterThan(try drawn(LiveSidePanel(session: empty, seconds: 2_015, panel: side) {}, width: 340, height: 700), 150, "\(side)")
        }
        // In an alliance with nothing yet in it, each panel's whole content:
        // no rallies called, no help asked, no pacts, no petition of her own.
        var bare = LiveSample.rows()
        bare["alliance"] = rows()["alliance"]
        bare["member"] = rows()["member"]
        let (allied, _) = await playing(bare)
        XCTAssertNotNil(allied.world.myMembership)
        for side in [LiveGameView.Panel.city, .troops, .studies, .forge, .alliance, .day, .realm, .rankings, .chat, .reports] {
            _ = try drawn(whole(side, of: allied).frame(width: LiveSidePanel.width - 28), width: LiveSidePanel.width, height: 3_600)
        }
        // And each panel's whole content, as long as it runs, with no
        // scrolling to leave what lies below a panel's fold unbuilt.
        for side in [LiveGameView.Panel.city, .troops, .studies, .forge, .alliance, .day, .realm, .rankings, .chat, .reports] {
            XCTAssertGreaterThan(try drawn(whole(side, of: session).frame(width: LiveSidePanel.width - 28), width: LiveSidePanel.width, height: 3_600), 800,
                                 "\(side), whole")
        }
        // The realm's contests once the hunt's first round is over: Ada's
        // first place, its laurel to claim.
        let over = 1_000 + 4 * 86_400.0
        XCTAssertNotNil(session.world.trials[1].flatMap { session.world.laurelToClaim(of: $0, day: session.world.today(at: over)) })
        XCTAssertGreaterThan(try drawn(whole(.realm, of: session, at: over).frame(width: LiveSidePanel.width - 28), width: LiveSidePanel.width, height: 3_600), 800,
                             "the realm, a laurel to claim")
        XCTAssertEqual(try drawn(LiveTaskChip(session: empty), width: 420, height: 70), 0, "No task set, nothing shown")
        XCTAssertEqual(LiveTroops.counts(LiveTroopLine(kind: 1, tier: 1, name: "Spearmen", ready: 1_040, wounded: 6, out: 20)), "1,040 ready, 6 wounded, 20 out")
        XCTAssertEqual(LiveTroops.counts(LiveTroopLine(kind: 1, tier: 1, name: "Spearmen", ready: 0, wounded: 0, out: 0)), "0 ready")

        // The whole screen while the realm is being reached, when it can't
        // be, and while a name is wanted.
        let unopened = LiveSession(line: StandInLine())
        XCTAssertGreaterThan(try drawn(LiveGameView(session: unopened), width: 900, height: 600), 80, "Reaching the realm")
        let lost = LiveSession(line: StandInLine(reachable: false))
        await lost.open()
        XCTAssertEqual(lost.phase, .lost)
        let tryAgain = try drawn(LiveGameView(session: lost), width: 900, height: 600)
        XCTAssertGreaterThan(tryAgain, 120, "The realm can't be reached, and a way to try again")
        var left = 0
        XCTAssertGreaterThan(try drawn(LiveGameView(session: lost) { left += 1 }, width: 900, height: 600, as: "live-lost.png"), tryAgain,
                             "and, entered from the launcher, a way back to it")
        XCTAssertEqual(left, 0, "Drawing leaves nothing")
        // The palette offers leaving for the launcher, last, where there is one to leave for.
        XCTAssertEqual(LivePaletteView.found("leave", in: session, at: 2_015, leaving: true).last, LivePaletteView.leaving)
        XCTAssertFalse(LivePaletteView.found("leave", in: session, at: 2_015, leaving: false).contains(LivePaletteView.leaving))
        XCTAssertFalse(LivePaletteView.found("barrow", in: session, at: 2_015, leaving: true).contains(LivePaletteView.leaving), "Only where its words are searched for")
        XCTAssertLessThanOrEqual(LivePaletteView.found("", in: session, at: 2_015, leaving: true).count, LivePaletteView.most)
        XCTAssertGreaterThan(try drawn(LiveNotice(title: "The world can't be drawn", words: "This Mac's graphics could not draw it.", button: nil) {}, width: 600, height: 200), 80)
        XCTAssertGreaterThan(try drawn(LiveNameCard(session: session), width: 400, height: 260, as: "live-name.png"), 80)
        XCTAssertTrue(LiveNameCard.fits("Ada"))
        XCTAssertTrue(LiveNameCard.fits("  Ada   of the Lake "), "tidied as the realm tidies it")
        XCTAssertFalse(LiveNameCard.fits("Al"))
        XCTAssertFalse(LiveNameCard.fits(String(repeating: "a", count: 17)))
        XCTAssertTrue(line.asked.isEmpty, "Drawing asks the realm nothing")
    }

    func testTheRealmsMapLivesInAWindowAndAnswersThePointer() async throws {
        guard WorldMetalView.systemDevice != nil else { throw XCTSkip("No Metal device available") }
        let (session, _) = await playing()
        let size = NSSize(width: 1000, height: 700)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: LiveGameView(session: session).frame(width: size.width, height: size.height))
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        spin(1.5)

        let map = try XCTUnwrap(find(WorldMetalView.self, in: host), "The Metal view is in the window")
        XCTAssertEqual(map.radius, LiveSession.reach)
        XCTAssertNotNil(map.relief)
        // The whole palette, every player's sigil and every alliance's, its colours round again.
        XCTAssertEqual(map.houseColours.count, LiveSession.palette.count)
        XCTAssertEqual(map.houseColours.prefix(LiveSession.colours.count).map { $0 }, LiveSession.colours)
        XCTAssertEqual(map.camera, session.camera)
        map.draw(map.bounds)

        // A click at the window's middle chooses what the camera is over:
        // her own city, at the window's heart.
        let centre = NSPoint(x: map.bounds.midX, y: map.bounds.midY)
        func event(_ type: NSEvent.EventType, at point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: map.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        map.mouseDown(with: event(.leftMouseDown, at: centre))
        map.mouseUp(with: event(.leftMouseUp, at: centre))
        XCTAssertEqual(session.selected, LiveHex(q: 10, r: -4))
        spin(0.3)
        XCTAssertEqual(map.selected, session.selectedLocal)

        // A drag pans: the session's camera follows the view's, and the look with it.
        let before = session.camera
        map.mouseDown(with: event(.leftMouseDown, at: centre))
        map.mouseDragged(with: event(.leftMouseDragged, at: NSPoint(x: centre.x + 120, y: centre.y + 40)))
        map.mouseUp(with: event(.leftMouseUp, at: NSPoint(x: centre.x + 120, y: centre.y + 40)))
        spin(0.3)
        XCTAssertNotEqual(session.camera, before, "The camera moved")
        XCTAssertEqual(map.camera, session.camera)

        // Turned to a place far off: another window's land is given to the view.
        session.go(to: LiveHex(q: 30, r: -4))
        spin(0.5)
        XCTAssertEqual(session.windowVersion, 2)
        XCTAssertEqual(map.camera, session.camera)
        map.draw(map.bounds)
    }

    /// Every button drawn in every part of every destination, and on the
    /// card of each kind of place chosen, pressed as a player presses it:
    /// each runs its own action, which reaches the session, and those that
    /// ask the realm something ask it.
    func testEveryButtonOfEveryPartIsPressed() async throws {
        let (session, line) = await playing()
        let askedBefore = line.asked.count
        defer { PressableButtons.isListening = false }
        var pressed: [String] = []
        func pressAll<V: View>(_ view: V, as what: String) async throws {
            PressableButtons.isListening = true
            _ = try drawn(view, width: 1512, height: 982)
            for title in PressableButtons.actions.keys.sorted() where PressableButtons.press(title) {
                pressed.append("\(what): \(title)")
            }
            PressableButtons.isListening = false
            // What each press set going, let run.
            for _ in 0..<20 { await Task.yield() }
            spin(0.05)
        }
        for place in LiveGameView.Destination.allCases {
            for part in place.panels {
                try await pressAll(LiveGameView(session: session, opening: part), as: part.title)
            }
        }
        // Her city, the grove, the barrow and Bryn's city, each chosen.
        for hex in [LiveHex(q: 10, r: -4), LiveHex(q: 12, r: -2), LiveHex(q: 8, r: -2), LiveHex(q: 14, r: -4)] {
            session.selected = hex
            try await pressAll(LiveGameView(session: session), as: "\(hex.q),\(hex.r)")
        }
        session.selected = nil
        for _ in 0..<20 { await Task.yield() }
        spin(0.2)
        print("PRESSED \(pressed.count) buttons; the realm asked \(line.asked.count - askedBefore) things: \(line.asked.dropFirst(askedBefore).joined(separator: "; "))")
        XCTAssertGreaterThan(pressed.count, 30, "\(pressed)")
        XCTAssertGreaterThan(line.asked.count - askedBefore, 5, "The presses reached the realm: \(pressed)")
    }

    /// The map moves, and is drawn, as the launcher's display settings say:
    /// its Motion, its frame rate and its resolution.
    func testTheRealmsMapKeepsTheLaunchersDisplaySettings() async throws {
        guard WorldMetalView.systemDevice != nil else { throw XCTSkip("No Metal device available") }
        let (session, _) = await playing()
        let suite = "live-display-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var display = LauncherSettings(defaults: defaults)
        display.motion = .still
        display.frameRate = .thirty
        display.quality = .efficient
        let size = NSSize(width: 800, height: 500)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: LiveGameView(session: session, display: display).frame(width: size.width, height: size.height))
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        spin(1)

        let map = try XCTUnwrap(find(WorldMetalView.self, in: host), "The Metal view is in the window")
        XCTAssertEqual(map.motion, .still, "Still, as the launcher's Motion says")
        XCTAssertEqual(map.frameRateCap, .thirty)
        XCTAssertEqual(map.quality, .efficient)
    }

    /// Counsel with a commander: a stand-in speaking for the model, the
    /// model missing on this Mac said plainly, and the bench's looks and
    /// deeds put forward only where they can be done.
    func testACommanderIsTakenCounselOf() async throws {
        var counselled = rows()
        counselled["my_commanders"] = [[n(11), n(1), .string("Corwen"), n(3), n(4), n(200), n(0)]]
        let (advised, _) = await playing(counselled)
        let grounded = try XCTUnwrap(advised.counsel(of: 11))
        let talk = LiveCounselSession(counsel: grounded, speaker: { asked in "Look to the barrows, my lord. You asked: \(asked)" })
        talk.ask("What now?")
        for _ in 0..<100 where talk.answering {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(talk.lines.map(\.kind), [.lord, .commander])
        XCTAssertEqual(talk.lines.last?.text, "Look to the barrows, my lord. You asked: What now?")
        XCTAssertGreaterThan(try drawn(LiveCounselView(counsel: talk, session: advised), width: 320, height: 200, as: "live-counsel.png"), 100)

        // A number nothing told them is asked after once, and the answer
        // taken again; one that still stands is shown as not told; one the
        // player said is theirs to hear again.
        let corrected = LiveCounselSession(counsel: grounded, speaker: { asked in
            asked.hasPrefix("You named 7319,") ? "Raise the Farm, my lord." : "Raise the Farm for 7,319 timber, my lord."
        })
        let stubborn = LiveCounselSession(counsel: grounded, speaker: { _ in "Raise the Farm for 7,319 timber, my lord." })
        let echoing = LiveCounselSession(counsel: grounded, speaker: { _ in "Then 7,319 timber it is, my lord." })
        corrected.ask("What now?")
        stubborn.ask("What now?")
        echoing.ask("I have 7319 timber.")
        for _ in 0..<100 where corrected.answering || stubborn.answering || echoing.answering {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(corrected.lines.map(\.kind), [.lord, .commander])
        XCTAssertEqual(corrected.lines.last?.text, "Raise the Farm, my lord.")
        XCTAssertEqual(stubborn.lines.map(\.kind), [.lord, .commander, .trouble])
        XCTAssertEqual(stubborn.lines.last?.text, "Corwen was not told 7319 and did not see it. Weigh it before acting on it.")
        XCTAssertEqual(echoing.lines.map(\.kind), [.lord, .commander])
        XCTAssertEqual(LiveCounselSession.recall(["7319", "40"]), "You named 7319, 40, which you were not told and did not see. Say it again, naming only numbers you were told or saw, or none.")

        let silent = LiveCounselSession(counsel: grounded, availability: { .unavailable(.deviceNotEligible) })
        silent.ask("Anything?")
        XCTAssertEqual(silent.lines.map(\.kind), [.trouble], "no model here: said so, and nothing asked")
        XCTAssertFalse(silent.answering)

        let bench = LiveCounselBench(grounded)
        let city = await bench.look(at: "the city")
        XCTAssertEqual(city, grounded.cityLook)
        let yourself = await bench.look(at: "yourself")
        XCTAssertEqual(yourself, grounded.yourselfLook)
        let none = await bench.propose("Burn the lake dry")
        XCTAssertEqual(none, "That cannot be done now. Put forward only a deed you were told can be done.")
        let taken = await bench.taken()
        XCTAssertEqual(taken.looks, ["the city", "themself"])
        XCTAssertTrue(taken.deeds.isEmpty)
    }

    func testADebugRunIsShownIntoTheRebuiltRealm() async throws {
        // Named by the environment, or not at all.
        XCTAssertNil(OnlineShell.session(in: [:]))
        XCTAssertNil(OnlineShell.session(in: ["NULLMERE_REBUILT_REALM": "nowhere at all"]))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("nullmere-rebuilt-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        // A realm no one answers at: the session is made, and says it can't be reached.
        let named = try XCTUnwrap(OnlineShell.session(in: ["NULLMERE_REBUILT_REALM": "http://127.0.0.1:9/nullmere-rebuilt", "NULLMERE_IDENTITY_FILE": file.path]))
        XCTAssertEqual(named.phase, .opening)
        await named.open()
        XCTAssertEqual(named.phase, .lost)
        XCTAssertNotNil(OnlineShell.session(in: ["NULLMERE_REBUILT_REALM": "http://127.0.0.1:9/nullmere-rebuilt"]), "Kept in the keychain where no file is named")

        // The smoke test's rehearsal: a name given where one is wanted,
        // then what it asks to be shown.
        var unnamed = LiveSample.rows()
        unnamed["me"] = nil
        unnamed["my_city"] = nil
        let line = StandInLine(rows: unnamed)
        let joining = LiveSession(line: line) { 2_015 }
        await joining.open()
        XCTAssertEqual(joining.phase, .naming)
        var shown: [LiveGameView.Panel] = []
        await LiveGameView.rehearse(joining, ["NULLMERE_REBUILT_NAME": "Ilsen", "NULLMERE_REBUILT_SHOW": "city"], patience: 1) { shown.append($0) }
        XCTAssertEqual(line.asked, ["join Ilsen"])
        XCTAssertTrue(shown.isEmpty, "Nothing to show of a city not yet founded")

        let (session, played) = await playing()
        await LiveGameView.rehearse(session, [:]) { shown.append($0) }
        XCTAssertNil(session.selected)
        for what in ["city", "troops", "reports", "rankings", "nothing at all"] {
            await LiveGameView.rehearse(session, ["NULLMERE_REBUILT_NAME": "Ilsen", "NULLMERE_REBUILT_SHOW": what]) { shown.append($0) }
        }
        XCTAssertEqual(shown, [.city, .troops, .reports, .rankings])
        XCTAssertEqual(session.selected, LiveHex(q: 10, r: -4))
        await LiveGameView.rehearse(session, ["NULLMERE_REBUILT_SHOW": "barrow"]) { shown.append($0) }
        XCTAssertEqual(session.selected, LiveHex(q: 8, r: -2), "The nearest barrow, chosen")
        await LiveGameView.rehearse(session, ["NULLMERE_REBUILT_SHOW": "site"]) { shown.append($0) }
        XCTAssertEqual(session.selected, LiveHex(q: 12, r: -2), "The nearest site")
        XCTAssertTrue(played.asked.isEmpty, "A player already in the realm is not asked to join")
    }
}
