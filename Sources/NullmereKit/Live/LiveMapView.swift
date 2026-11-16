import AppKit
import LauncherCore
import NullmereCore
import NullmereLiveStage
import NullmereModels
import NullmereWorld
import SwiftUI

/// The realm's world under the player's hand: the window of it their
/// session keeps, drawn by the world's own renderer in the world's own
/// day. The view only carries things across; the session decides what
/// the window is and where the camera stands in it.
struct LiveMapView: NSViewRepresentable {
    /// The hour the world is drawn at: its own day, by the clock, the same
    /// for every player (nil); or, in a debug build, the hour NULLMERE_HOUR
    /// names, for the pictures.
    static func hour(environment: [String: String] = ProcessInfo.processInfo.environment) -> Float? {
        #if DEBUG
        if let named = environment["NULLMERE_HOUR"].flatMap(Float.init), named.isFinite, (0...24).contains(named) {
            return named
        }
        #endif
        return nil
    }

    let session: LiveSession
    /// How much the world moves, as the launcher's Motion and the system's
    /// Reduce Motion say; the frame rate it is held under; the share of
    /// the screen's pixels it is drawn at: the launcher's display settings.
    var motion: ResolvedMotion = .full
    var frameRate: FrameRateCap = .sixty
    var quality: RenderQuality = .native
    let onFailure: () -> Void

    /// Which window's land the view was last given.
    final class Kept {
        var land = -1
    }

    func makeCoordinator() -> Kept { Kept() }

    func makeNSView(context: Context) -> WorldMetalView {
        let view = WorldMetalView()
        view.onFailure = onFailure
        view.onClick = { [weak session] hex in session?.choose(local: hex) }
        view.onCameraChange = { [weak session] camera in session?.moved(camera) }
        view.cursor = { _ in .pointingHand }
        // What stands and moves in the window, posed afresh for every frame.
        view.scene = { [weak session] time, size in session?.frame(time: time, size: size) ?? SceneFrame() }
        update(view, context.coordinator)
        return view
    }

    func updateNSView(_ view: WorldMetalView, context: Context) {
        update(view, context.coordinator)
    }

    private func update(_ view: WorldMetalView, _ kept: Kept) {
        // Read here, so the view is brought up to date when either moves.
        let window = session.windowVersion
        let standing = session.standingVersion
        view.motion = motion
        view.frameRateCap = frameRate
        view.quality = quality
        guard let land = session.land() else { return }
        view.radius = land.map.radius
        view.relief = land.relief
        view.houseColours = LiveSession.palette
        if kept.land != window {
            view.setLand(land.terrain, for: land.map)
            kept.land = window
        }
        view.camera = session.camera
        view.selected = session.selectedLocal
        view.hour = LiveMapView.hour()
        if let tiles = session.tiles() {
            view.setTiles(tiles, side: TileTexture.side(for: land.map), version: window * 100_000 + standing)
        }
    }
}
