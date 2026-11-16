import AppKit
import LauncherCore
import LauncherKit
import NullmereKit
import SwiftUI

@main
struct NullmereOnlineApp: App {
    @NSApplicationDelegateAdaptor(OnlineAppDelegate.self) private var appDelegate
    @State private var shell = OnlineShell()

    var body: some Scene {
        Window("Nullmere Online", id: "nullmere-online") {
            NullmereOnlineView(shell: shell)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1440, height: 900)
        .commands {
            LauncherCommands(model: shell.launcher, settings: { shell.showSettings() })
            RealmCommands(shell: shell)
        }
    }
}

@MainActor
final class OnlineAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // A copy already running: it comes forward, and this one goes.
        if SingleInstance.handOver() {
            NSApp.terminate(nil)
            return
        }
        // The run is marked, and its faults watched, so the next launch can
        // tell of one that stops on a fault. What the last run left was
        // read as the ledger was made, before this.
        _ = RunLedger.shared.atLaunch
        RunLedger.shared.begin(version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")
        NSSetUncaughtExceptionHandler { exception in
            FaultWatch.record(exception: "\(exception.name.rawValue): \(exception.reason ?? "no reason given")")
        }
        // `swift run` starts a bare executable rather than an app bundle;
        // make sure it still behaves like a regular, frontmost Mac app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    /// The run ends as it should: nothing is left for the next launch to tell.
    func applicationWillTerminate(_ notification: Notification) {
        RunLedger.shared.end()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// The sound fades out rather than stopping dead.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let sound = RealmSound.current else { return .terminateNow }
        let fade = sound.ambience.fadeForQuitting()
        guard fade > 0 else { return .terminateNow }
        DispatchQueue.main.asyncAfter(deadline: .now() + fade) { NSApp.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}
