import AppKit
import Foundation
import LauncherCore
import LauncherKit
import NullmereLiveStage
import NullmereRealm
import Observation
import SwiftUI

/// Which of its two faces the window shows.
@MainActor
@Observable
public final class OnlineShell {
    public private(set) var inRealm = false

    public let launcher: LauncherModel
    /// The window's sound: the title theme over the launcher, the realm's
    /// score within it.
    public let sound: RealmSound
    /// The player's session in the realm, played in the window in place of
    /// the launcher: opened by Play, or at once where a debug run was told
    /// of a realm to open on.
    public private(set) var rebuilt: LiveSession?
    /// How a session is opened on a realm's address; the keychain's way, but
    /// for a test.
    var opening: @MainActor (String) -> LiveSession? = { OnlineShell.session(at: $0) }

    public convenience init() {
        self.init(launcher: LauncherModel(), sound: RealmSound())
        #if DEBUG
        rebuilt = OnlineShell.session(in: ProcessInfo.processInfo.environment)
        #endif
        // The last run, if it stopped on a fault: the launcher opens on its
        // page.
        launcher.open(on: RunLedger.shared.atLaunch)
    }

    public init(launcher: LauncherModel, sound: RealmSound) {
        self.launcher = launcher
        self.sound = sound
        launcher.enterRealm = { [weak self] in self?.enterRealm() }
        sound.display = launcher
        // The launcher's Music and the realm's are one choice.
        launcher.onMusicChanged = { [weak sound] on in sound?.isMusicOn = on }
    }

    /// A session in the realm an environment names with
    /// NULLMERE_REBUILT_REALM (a server and, as its path, the database's
    /// name), opened at once without the launcher. The player is kept in
    /// the keychain, one for each realm, or for a test in the file
    /// NULLMERE_IDENTITY_FILE names.
    static func session(in environment: [String: String]) -> LiveSession? {
        guard let text = environment["NULLMERE_REBUILT_REALM"] else { return nil }
        return session(at: text, identityFile: environment["NULLMERE_IDENTITY_FILE"] ?? "")
    }

    /// The address Play opens: where the app was built to go (its
    /// Info.plist's NullmereRealm), or maincloud's; a debug run may name
    /// another with NULLMERE_REALM.
    static func realmAddress(info: [String: Any]?, environment: [String: String]) -> String {
        #if DEBUG
        if let text = environment["NULLMERE_REALM"], LiveDoor.address(text) != nil {
            return text
        }
        #endif
        return realmURL(in: info).absoluteString
    }

    /// The realm proper: maincloud's.
    static let maincloudURL = URL(string: "https://maincloud.spacetimedb.com/nullmere")!

    /// Where the app was built to go (its Info.plist's NullmereRealm, set by
    /// scripts/build-app.sh), or the realm proper.
    static func realmURL(in info: [String: Any]?) -> URL {
        if let text = info?["NullmereRealm"] as? String, let url = URL(string: text),
           url.scheme == "https" || url.scheme == "http", url.host() != nil, url.path().count > 1 {
            return url
        }
        return maincloudURL
    }

    /// A session in the realm at an address, nil where the text is none.
    static func session(at text: String, identityFile: String = "") -> LiveSession? {
        var named = identityFile
        #if DEBUG
        if named.isEmpty { named = ProcessInfo.processInfo.environment["NULLMERE_IDENTITY_FILE"] ?? "" }
        #endif
        let file = named
        guard let address = LiveDoor.address(text) else { return nil }
        let (server, database) = (address.server, address.database)
        return LiveSession(opening: {
            if !file.isEmpty {
                return try await LiveDoor.open(server: server, database: database, keeping: FileIdentityStore(url: URL(fileURLWithPath: file)))
            }
            let realm = "rebuilt \(server.host() ?? server.absoluteString)/\(database)"
            return try await LiveDoor.open(server: server, database: database, keeping: KeychainIdentityStore(realm: realm))
        })
    }

    /// Over the launcher, the title theme of the lake the player's realm
    /// last lay on, with the night about it.
    func playTitle() {
        sound.playTitle()
    }

    /// Play: into the realm, in place of the launcher.
    func enterRealm() {
        inRealm = true
        RunLedger.shared.note(.door)
        // The realm's own score from here on.
        sound.playRealm()
        if rebuilt == nil {
            rebuilt = opening(OnlineShell.realmAddress(info: Bundle.main.infoDictionary, environment: ProcessInfo.processInfo.environment))
        }
    }

    /// Back to the launcher: the realm is no longer watched.
    public func leaveRealm() {
        rebuilt?.close()
        rebuilt = nil
        inRealm = false
        RunLedger.shared.note(.launcher)
        launcher.returnFromRealm()
        playTitle()
    }

    /// What Settings… opens: the launcher's panel, where the launcher shows.
    public func showSettings() {
        if !inRealm, rebuilt == nil {
            launcher.show(.settings)
        }
    }
}

/// The one window of Nullmere Online: the launcher on the moonlit lake, and
/// through Play, the realm.
public struct NullmereOnlineView: View {
    private let shell: OnlineShell

    public init(shell: OnlineShell) {
        self.shell = shell
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let rebuilt = shell.rebuilt {
                LiveGameView(session: rebuilt, display: shell.launcher.displaySettings) { shell.leaveRealm() }
                    .transition(.opacity)
            } else {
                LauncherRootView(model: shell.launcher)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.8), value: shell.rebuilt == nil)
        // The window stays dark in the realm too, where the launcher that
        // asks for it is gone.
        .preferredColorScheme(.dark)
        .background(WindowFitter())
        .onAppear { if !shell.inRealm, shell.rebuilt == nil { shell.playTitle() } }
    }
}

/// The menu's commands while the realm shows: leaving it for the launcher,
/// and its sound and music.
public struct RealmCommands: Commands {
    let shell: OnlineShell

    public init(shell: OnlineShell) {
        self.shell = shell
    }

    public var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Leave the Realm") { shell.leaveRealm() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(shell.rebuilt == nil)
        }
        CommandMenu("Realm") {
            Toggle("Sound", isOn: Binding(get: { shell.sound.isSoundOn }, set: { shell.sound.isSoundOn = $0 }))
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(!shell.inRealm)
            Toggle("Music", isOn: Binding(get: { shell.sound.isMusicOn }, set: { shell.sound.isMusicOn = $0 }))
                .keyboardShortcut("u", modifiers: [.command, .shift])
                .disabled(!shell.inRealm || !shell.sound.isSoundOn)
        }
    }
}

/// Fits the window inside its screen when it first appears, so a display
/// smaller than the default size never hides the edges of the interface,
/// and names its content for VoiceOver as the window is named.
struct WindowFitter: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowFitterView { WindowFitterView() }
    func updateNSView(_ view: WindowFitterView, context: Context) {}
}

final class WindowFitterView: NSView {
    private var fitted = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !fitted, let window else { return }
        fitted = true
        window.contentView?.setAccessibilityLabel(window.title)
        DispatchQueue.main.async {
            guard let screen = window.screen ?? NSScreen.main else { return }
            let visible = screen.visibleFrame
            var frame = window.frame
            guard frame.width > visible.width || frame.height > visible.height else { return }
            frame.size.width = min(frame.width, visible.width)
            frame.size.height = min(frame.height, visible.height)
            frame.origin.x = visible.midX - frame.width / 2
            frame.origin.y = visible.midY - frame.height / 2
            window.setFrame(frame, display: true)
        }
    }
}
