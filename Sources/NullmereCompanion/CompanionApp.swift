import Foundation
import NullmereLive
import NullmereLiveStage
import NullmereRealm
import SwiftUI

/// Nullmere Companion: a player's realm on their iPhone, beside their Mac
/// (plan 3.5). It comes into the realm as them by the code their Mac shows
/// (`take_link`), never by their Mac's own key, and keeps a key of its own
/// in the phone's keychain, so it comes back as them each time it opens.
@main
struct CompanionApp: App {
    @State private var session = CompanionApp.session(at: CompanionApp.realmAddress(info: Bundle.main.infoDictionary,
                                                                                     environment: ProcessInfo.processInfo.environment))

    var body: some Scene {
        WindowGroup {
            CompanionView(session: session)
                .task { await session.open() }
        }
    }

    /// The realm proper: maincloud's.
    static let realmProper = "https://maincloud.spacetimedb.com/nullmere"

    /// Where the app was built to go (its Info.plist's NullmereRealm), another
    /// named by NULLMERE_REALM in a debug build, or the realm proper.
    static func realmAddress(info: [String: Any]?, environment: [String: String]) -> String {
        #if DEBUG
        if let text = environment["NULLMERE_REALM"], LiveDoor.address(text) != nil {
            return text
        }
        #endif
        if let text = info?["NullmereRealm"] as? String, LiveDoor.address(text) != nil {
            return text
        }
        return realmProper
    }

    /// A session in the realm at an address, its key kept in the phone's
    /// keychain, one for each realm.
    @MainActor
    static func session(at text: String) -> LiveSession {
        let address = LiveDoor.address(text) ?? LiveDoor.address(realmProper)!
        let server = address.server, database = address.database
        let realm = "\(server.host() ?? server.absoluteString)/\(database)"
        return LiveSession(opening: {
            try await LiveDoor.open(server: server, database: database, keeping: CompanionKeychain(realm: realm))
        })
    }
}
