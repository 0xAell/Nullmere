import LauncherCore
@testable import LauncherKit
import NullmereLiveStage
import NullmereRealm
import NullmereWorld
import SwiftUI
import XCTest
@testable import NullmereCore
@testable import NullmereKit
import NullmereTestSupport

/// The whole window: the launcher, and through Play, the realm; and the
/// hour the realm's world is drawn at.
@MainActor
final class RootRenderTests: XCTestCase {
    private var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    @discardableResult
    private func draw(_ view: some View, width: CGFloat = 1200, height: CGFloat = 780) throws -> CGImage {
        let renderer = ImageRenderer(content: view.frame(width: width, height: height).background(Color.black))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        XCTAssertEqual(CGFloat(image.width), width)
        XCTAssertGreaterThanOrEqual(litPixels(image), 20, "Drawn, not blank")
        return image
    }
    func testTheOneWindowShowsTheLauncherThenTheRealm() throws {
        let suite = "root-render-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let environment = LauncherEnvironment(
            modelReadiness: { .ready },
            systemSavesEnergy: { false },
            downloadNews: { throw URLError(.notConnectedToInternet) },
            open: { _ in true },
            terminate: {}
        )
        let launcher = LauncherModel(defaults: defaults, environment: environment)
        let shell = OnlineShell(launcher: launcher, sound: RealmSound(sound: false))
        // Past its opening, which rises from black.
        launcher.refreshReadiness()
        launcher.completeIntro()
        try draw(NullmereOnlineView(shell: shell))
        shell.playTitle()
        XCTAssertEqual(shell.sound.ambience.titleLake, RealmSound.lastLake, "Over the launcher, the last lake's title theme")
        shell.showSettings()
        // Play opens the realm at its address, in place of the launcher.
        var asked: [String] = []
        shell.opening = { address in
            asked.append(address)
            return LiveSession(line: StandInLine(rows: LiveSample.rows())) { 2_015 }
        }
        shell.enterRealm()
        XCTAssertTrue(shell.inRealm)
        XCTAssertEqual(asked, [OnlineShell.realmURL(in: Bundle.main.infoDictionary).absoluteString], "The realm the app was built to go to")
        XCTAssertNotNil(shell.rebuilt)
        XCTAssertNil(shell.sound.ambience.titleLake, "Within the realm, its own score")
        try draw(NullmereOnlineView(shell: shell))
        // Settings… waits for the launcher: nothing opens over the realm.
        shell.showSettings()
        shell.leaveRealm()
        XCTAssertEqual(shell.launcher.screen, .title, "Back at the launcher's menu")
        XCTAssertFalse(shell.inRealm)
        XCTAssertNil(shell.rebuilt, "Left, the realm is no longer watched")
        XCTAssertEqual(shell.sound.ambience.titleLake, RealmSound.lastLake, "The title theme again")
        // A debug run may name another realm; nothing that is no address.
        XCTAssertEqual(OnlineShell.realmAddress(info: nil, environment: ["NULLMERE_REALM": "http://127.0.0.1:3000/nullmere-ui"]), "http://127.0.0.1:3000/nullmere-ui")
        XCTAssertEqual(OnlineShell.realmAddress(info: nil, environment: ["NULLMERE_REALM": "local"]), OnlineShell.maincloudURL.absoluteString)
        // Where the app was built to go, and only an address with a database's name in it.
        XCTAssertEqual(OnlineShell.realmURL(in: ["NullmereRealm": "https://realm.test/nullmere"]), URL(string: "https://realm.test/nullmere"))
        XCTAssertEqual(OnlineShell.realmURL(in: ["NullmereRealm": "https://realm.test"]), OnlineShell.maincloudURL)
        XCTAssertEqual(OnlineShell.realmURL(in: ["NullmereRealm": "realm"]), OnlineShell.maincloudURL)
        XCTAssertEqual(OnlineShell.realmURL(in: nil), OnlineShell.maincloudURL)
        XCTAssertNil(OnlineShell.session(at: "nowhere at all"))

        // The launcher's Music and the realm's are one choice, either way.
        let music = UserDefaults.standard.object(forKey: "music.enabled")
        defer { music == nil ? UserDefaults.standard.removeObject(forKey: "music.enabled") : UserDefaults.standard.set(music, forKey: "music.enabled") }
        shell.sound.isMusicOn = true
        launcher.setDisplay(.music, to: 0)
        XCTAssertFalse(shell.sound.isMusicOn, "Turned off in the launcher, off in the realm")
        shell.sound.isMusicOn = true
        XCTAssertTrue(launcher.displaySettings.music, "Turned on in the realm, on in the launcher")
    }

    /// The hour of the world's day the map is drawn at: the world's own day
    /// by the clock, the same for every player, but for the pictures the
    /// hour NULLMERE_HOUR names; and midnight where nothing is said.
    func testTheWorldKeepsItsDay() {
        XCTAssertEqual(WorldMetalView().hour, 0)
        XCTAssertNil(LiveMapView.hour(environment: [:]))
        XCTAssertEqual(LiveMapView.hour(environment: ["NULLMERE_HOUR": "12"]), 12)
        XCTAssertEqual(LiveMapView.hour(environment: ["NULLMERE_HOUR": "18.3"]), 18.3)
        XCTAssertNil(LiveMapView.hour(environment: ["NULLMERE_HOUR": "noon"]), "Only an hour it names")
        XCTAssertNil(LiveMapView.hour(environment: ["NULLMERE_HOUR": "31"]))
    }
}
