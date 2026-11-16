import LauncherCore
import Foundation
import LauncherKit
import NullmereRealm
import SwiftUI
import XCTest
import NullmereLand
@testable import NullmereKit
import NullmereTestSupport

/// The app as it starts, its sound off.
@MainActor
final class NearTheEndTests: XCTestCase {
    private var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// The app as it starts: the launcher's face shown, the realm's door
    /// not yet opened; with the sound off, as the keeper left it.
    func testTheAppStartsOnTheLauncher() {
        let defaults = UserDefaults.standard
        let kept = defaults.object(forKey: "sound.enabled")
        defaults.set(false, forKey: "sound.enabled")
        defer { kept == nil ? defaults.removeObject(forKey: "sound.enabled") : defaults.set(kept, forKey: "sound.enabled") }
        let shell = OnlineShell()
        XCTAssertFalse(shell.inRealm)
        XCTAssertFalse(shell.sound.isSoundOn)
        // On the menu, or on the page of a run that stopped on a fault
        // before, should this Mac have one.
        XCTAssertEqual(shell.launcher.screen, RunLedger.shared.atLaunch == nil ? .title : .mishap)
    }
}
