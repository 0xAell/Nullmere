// swift-tools-version: 5.9
import PackageDescription

// The land, the realm's client, the world as the renderer takes it and the
// launcher's own logic build anywhere Swift does, Linux included. The app
// needs the Mac.
var products: [Product] = [
    .library(name: "NullmereLand", targets: ["NullmereLand"]),
]
var targets: [Target] = [
    // The land the world is drawn on: hexes and their layout, the map, its
    // terrain and its maker, cities and their works and stores, and the
    // kinds of what stands on it. Pure Swift, deterministic, and the same
    // on every machine.
    .target(
        name: "NullmereLand",
        linkerSettings: [.linkedLibrary("m", .when(platforms: [.linux]))]
    ),
    .testTarget(name: "NullmereLandTests", dependencies: ["NullmereLand"]),
    // The line to a realm on a SpacetimeDB server: its HTTP API, its
    // subscriptions pushed over a WebSocket, a player's identity, and
    // trouble said in plain words. Foundation only.
    .target(name: "NullmereRealm"),
    // A client of the realm being rebuilt (realm/): the rows of one
    // persistent world, pushed as they change, and the reducers a player
    // calls. Foundation only, so tested on Linux against a real server.
    .target(name: "NullmereLive", dependencies: ["NullmereRealm"]),
    .testTarget(name: "NullmereLiveTests", dependencies: ["NullmereLive", "NullmereRealm"]),
    // The rebuilt realm as the renderer takes it: a window of its land as
    // a map, its cities as holds and its armies as companies, each where
    // it is at a moment. Pure Swift, so tested on Linux.
    .target(name: "NullmereLiveStage", dependencies: ["NullmereLive", "NullmereRealm", "NullmereWorld", "NullmereModels", "NullmereLand"]),
    .testTarget(name: "NullmereLiveStageTests", dependencies: ["NullmereLiveStage", "NullmereLive", "NullmereWorld", "NullmereModels", "NullmereLand", "NullmereRealm",
                                                           "NullmereTestSupport"]),
    // The world's shapes: the land's relief and mesh, and every model in
    // it, built from solids in code, with the rigs that move them. Pure
    // Swift, so every shape is built and tested on Linux too.
    .target(name: "NullmereModels", dependencies: ["NullmereLand"]),
    .testTarget(name: "NullmereModelsTests", dependencies: ["NullmereModels", "NullmereLand", "NullmereTestSupport"]),
    // The world as the GPU draws it, apart from the GPU: the camera, the
    // shaders' source, the data they read and how a frame's models are
    // gathered. Pure Swift, so tested on Linux too.
    .target(name: "NullmereWorld", dependencies: ["NullmereLand", "NullmereModels"]),
    .testTarget(name: "NullmereWorldTests", dependencies: ["NullmereWorld", "NullmereModels", "NullmereLand", "NullmereTestSupport"]),
    // The game's sound, apart from the Mac's audio engine: the synthesiser,
    // its instruments, its hall and the score written as it plays. Pure
    // Swift, so every sound is rendered and measured on Linux too.
    .target(name: "NullmereSound", dependencies: ["NullmereLand"]),
    .testTarget(name: "NullmereSoundTests", dependencies: ["NullmereSound", "NullmereLand"]),
    // The trailer, apart from the GPU: its world, its shots and what moves
    // in them, and its score. Pure Swift, so every shot is staged and the
    // score rendered on Linux too; the Mac draws and encodes it.
    .target(name: "NullmereTrailer", dependencies: ["NullmereLand", "NullmereModels", "NullmereWorld", "NullmereSound", "NullmereLive", "NullmereLiveStage", "NullmereRealm"],
            resources: [.copy("TrailerRows.json")]),
    .testTarget(name: "NullmereTrailerTests", dependencies: ["NullmereTrailer", "NullmereLand", "NullmereModels", "NullmereWorld", "NullmereSound"]),
    // SpacetimeDB in memory, and credentials kept in memory, for tests of
    // the realm across the network: the realm's and the app's.
    .target(name: "NullmereTestSupport", dependencies: ["NullmereRealm", "NullmereLive", "NullmereLiveStage", "NullmereLand", "NullmereWorld"], path: "Tests/NullmereTestSupport"),
    .testTarget(name: "NullmereRealmTests", dependencies: ["NullmereRealm", "NullmereTestSupport"]),
    // Platform-independent launcher logic: settings, navigation, scene
    // constants, the news feed and the moon's veil. Pure Swift, so it is
    // tested on Linux too.
    .target(name: "LauncherCore"),
    .testTarget(name: "LauncherCoreTests", dependencies: ["LauncherCore"]),
]

#if os(macOS)
products.append(.executable(name: "NullmereLauncher", targets: ["NullmereLauncher"]))
targets += [
    // The SwiftUI/AppKit/Metal launcher interface.
    .target(name: "LauncherKit", dependencies: ["LauncherCore"]),
    // The window's realm: its screens, the Metal world, its sound.
    .target(name: "NullmereKit", dependencies: ["NullmereLand", "NullmereModels", "NullmereWorld", "NullmereRealm", "NullmereSound",
                                                "NullmereLive", "NullmereLiveStage", "LauncherCore", "LauncherKit"]),
    // The "Nullmere Online" app: the launcher, and through Play, the realm.
    .executableTarget(name: "NullmereLauncher", dependencies: ["LauncherCore", "LauncherKit", "NullmereKit"]),
    // Nullmere Companion, a player's iPhone app on the realm's client,
    // brought in as them by the code their Mac shows. Built for iOS by
    // scripts/build-companion.sh, which bundles it; on the Mac it builds
    // too, to be checked as the rest is.
    .executableTarget(name: "NullmereCompanion", dependencies: ["NullmereLand", "NullmereLive", "NullmereLiveStage", "NullmereRealm"]),
    .testTarget(name: "LauncherKitTests", dependencies: ["LauncherKit", "LauncherCore", "NullmereTestSupport"]),
    .testTarget(name: "NullmereKitTests", dependencies: ["NullmereKit", "NullmereLive", "NullmereLiveStage", "NullmereLand", "NullmereModels", "NullmereWorld", "NullmereRealm", "NullmereSound", "LauncherCore", "LauncherKit", "NullmereTestSupport"]),
]
// The trailer drawn by the game's own renderers and written to a film,
// built only when scripts/render-trailer.sh asks for it: then the trailer's
// are the only tests built, over an optimised build of the game, and its
// drawing is left unoptimised, as Swift 6.3.3's optimiser crashes on it.
if Context.environment["NULLMERE_TRAILER"] != nil {
    targets.removeAll { $0.type == .test && $0.name != "NullmereTrailerTests" }
    targets.append(.testTarget(name: "TrailerRenderTests",
                               dependencies: ["NullmereTrailer", "NullmereKit", "NullmereLand", "NullmereModels", "NullmereWorld", "NullmereSound",
                                              "LauncherCore", "LauncherKit"],
                               swiftSettings: [.unsafeFlags(["-Onone"])]))
}
#endif

let package = Package(
    name: "Nullmere",
    // Nullmere Online needs Apple's on-device language model through the
    // Foundation Models framework, which arrived in macOS 26. The app is
    // built for Apple silicon only.
    platforms: [
        .macOS("26.0"),
        // The companion on a player's iPhone.
        .iOS("26.0"),
    ],
    products: products,
    targets: targets
)
