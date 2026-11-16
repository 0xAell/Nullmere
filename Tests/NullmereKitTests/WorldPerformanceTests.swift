import Metal
@testable import NullmereKit
import NullmereLand
import NullmereModels
import NullmereTestSupport
import NullmereWorld
import XCTest

/// How long the GPU takes to draw the world at a 14-inch MacBook Pro's
/// native resolution, over a game well under way. Prints the time for the
/// record; fails if a frame would not fit a 60 Hz display's budget.
final class WorldPerformanceTests: XCTestCase {
    static let width = 3024
    static let height = 1964

    func testTheWorldFitsAFrameAtSixtyHertz() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device available") }
        let library = try device.makeLibrary(source: WorldShaders.source, options: nil)
        let renderer = try WorldRenderer(device: device, library: library, pixelFormat: .bgra8Unorm)
        // A world known whole, as a keeper's is well under way, what
        // their seat and companies see watched.
        let state = TestWorld(seedText: "measured water")
        let seat = state.holds[0].position
        try renderer.setLand(TerrainMesh.shared(for: state.map), for: state.map)
        try renderer.updateTiles(state.tiles(watched: { state.watchedByTheFirst($0) }), side: TileTexture.side(for: state.map))
        let terrain = try XCTUnwrap(renderer.land).terrain

        var results: [String] = []
        // Zoomed out is the most work: the most land, mist and water in view.
        for scale in [12.0, 28.0, 60.0] {
            // At the resolution the view draws at for this zoom.
            let fraction = WorldMetalView.renderScale(forCameraScale: scale)
            let width = Int((Double(Self.width) * fraction).rounded())
            let height = Int((Double(Self.height) * fraction).rounded())
            let target = try renderer.makeTarget(width: width, height: height)
            var camera = Camera(scale: scale)
            camera.focus(on: seat)
            // The view as the window has it, in points: half the pixels each way.
            let size = CGSize(width: Double(Self.width) / 2, height: Double(Self.height) / 2)
            // Eighty frames once it has settled, as the pan is measured: over
            // fewer, the worst twentieth is a frame or two, and one hiccup of
            // a shared GPU reads as the world's own.
            var times: [Double] = []
            for frame in 0..<85 {
                let uniforms = FrameUniforms.make(camera: camera, size: size, pixelsPerPoint: 2 * fraction, time: Float(3 + Double(frame) / 60),
                                                  motion: 1, radius: state.map.radius, terrain: terrain, hovered: seat, selected: seat)
                if let ms = renderer.measureFrame(uniforms, into: target) { times.append(ms) }
            }
            let settled = Array(times.dropFirst(5)).sorted()
            let median = settled[settled.count / 2]
            let p95 = settled[min(settled.count - 1, Int(Double(settled.count) * 0.95))]
            print("PERFMETRIC world.gpu.scale\(Int(scale)).p50 \(String(format: "%.3f", median))")
            print("PERFMETRIC world.gpu.scale\(Int(scale)).p95 \(String(format: "%.3f", p95))")
            results.append("scale \(Int(scale)) at \(Int(fraction * 100))% median \(String(format: "%.2f", median)) ms")
            // A 60 Hz frame, with a sixth to spare for the interface.
            XCTAssertLessThan(median, 1000.0 / 60 * 0.85, "The world at scale \(scale) must fit a 60 Hz frame with room to spare")
        }
        print("PERF world \(Self.width)x\(Self.height) on \(device.name): " + results.joined(separator: ", "))
    }

    /// A realm of forty-eight seats, its lake twice as wide and its land's
    /// furniture four times the realm proper's, every hex known: near, the
    /// frame draws only the regions in view, and takes no longer than the
    /// whole land drawn, as it was before, which is measured beside it.
    /// One of ninety-six seats, its lake wider again and its land twice
    /// that, draws its frame near in about the time the forty-eight's does:
    /// what a frame costs is what is in view, not how wide the realm is.
    func testAWideRealmDrawsOnlyWhatItSees() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device available") }
        let library = try device.makeLibrary(source: WorldShaders.source, options: nil)
        let renderer = try WorldRenderer(device: device, library: library, pixelFormat: .bgra8Unorm)
        renderer.meshSource = { Library.model($0).mesh }
        let wide = try measureNear(seats: 48, seed: "a wide realm drawn", wholeToo: true, renderer: renderer)
        let culledMedian = wide.culled, wholeMedian = try XCTUnwrap(wide.whole)
        print("PERFMETRIC wide.gpu.scale28.p50 \(String(format: "%.3f", culledMedian))")
        print("PERFMETRIC wide.gpu.scale28.whole.p50 \(String(format: "%.3f", wholeMedian))")
        print("PERF a realm of 48 seats near on \(device.name): \(String(format: "%.2f", culledMedian)) ms drawing what is in view, "
              + "\(String(format: "%.2f", wholeMedian)) ms drawing the whole land")
        XCTAssertLessThanOrEqual(culledMedian, wholeMedian * 1.1 + 0.5, "Drawing what is in view costs no more than drawing it all")

        let wider = try measureNear(seats: 96, seed: "a wider realm drawn", wholeToo: false, renderer: renderer)
        print("PERFMETRIC wider.gpu.scale28.p50 \(String(format: "%.3f", wider.culled))")
        print("PERF a realm of 96 seats near on \(device.name): \(String(format: "%.2f", wider.culled)) ms drawing what is in view")
        XCTAssertLessThanOrEqual(wider.culled, culledMedian * 1.25 + 1, "A realm twice as wide costs a frame near what the narrower does")
        XCTAssertLessThan(wider.culled, 16.7, "and well inside one")

        // By day, its land and water drawn with the day's relief and waves,
        // which the night's frames above carry none of: told, to be held
        // once it is known.
        let widerByDay = try measureNear(seats: 96, seed: "a wider realm drawn", wholeToo: false, renderer: renderer, daylight: .day)
        print("PERFMETRIC wider.gpu.scale28.day.p50 \(String(format: "%.3f", widerByDay.culled))")
        print("PERF a realm of 96 seats near by day on \(device.name): \(String(format: "%.2f", widerByDay.culled)) ms drawing what is in view")
    }

    /// The land and the water are drawn with the day's relief and waves from
    /// dusk to dawn's end, and by night by functions that hold none of it.
    func testTheDaysReliefIsDrawnByDayAlone() {
        XCTAssertTrue(WorldRenderer.drawsByDay(FrameUniforms(daylight: .day)))
        XCTAssertTrue(WorldRenderer.drawsByDay(FrameUniforms(daylight: .dusk)))
        XCTAssertTrue(WorldRenderer.drawsByDay(FrameUniforms(daylight: .dawn)))
        XCTAssertFalse(WorldRenderer.drawsByDay(FrameUniforms(daylight: .night)))
        XCTAssertFalse(WorldRenderer.drawsByDay(FrameUniforms()), "A frame told no hour is the night's")
    }

    /// Close in on a seat, its holds' keeps and works standing and the land's
    /// furniture about them, the moon casts the shadows of all of it: the
    /// frame, its shadow map drawn first, fits a 60 Hz frame with room to
    /// spare, and is measured beside the same frame casting none.
    func testTheMoonsShadowsFitAFrameAtSixtyHertz() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device available") }
        let library = try device.makeLibrary(source: WorldShaders.source, options: nil)
        let renderer = try WorldRenderer(device: device, library: library, pixelFormat: .bgra8Unorm)
        renderer.meshSource = { Library.model($0).mesh }
        let state = TestWorld(seedText: "moonlit and measured")
        try renderer.setLand(TerrainMesh.shared(for: state.map), for: state.map)
        try renderer.updateTiles(state.tiles(watched: { state.watchedByTheFirst($0) }), side: TileTexture.side(for: state.map))
        let terrain = try XCTUnwrap(renderer.land).terrain
        let stage = WorldStage(map: state.map, relief: Relief(map: state.map))
        var scene = SceneFrame()
        let sights = state.holds.map { HoldSight(hold: $0, colour: WorldStage.colour(WorldRenderer.houseColours, sigil: $0.owner)) }
        let holds = stage.holds(sights, time: 20, into: &scene)
        scene.batches = holds.batches
        scene.fixed = stage.furnish(occupied: [], holds: Set(state.holds.map(\.position)))
        scene.fixedVersion = stage.furnitureVersion
        scene.fixedRegions = stage.furnitureRegions
        let seat = state.holds[0].position
        let scale = 60.0
        let fraction = WorldMetalView.renderScale(forCameraScale: scale)
        let target = try renderer.makeTarget(width: Int((Double(Self.width) * fraction).rounded()),
                                             height: Int((Double(Self.height) * fraction).rounded()))
        var camera = Camera(scale: scale)
        camera.focus(on: seat)
        let size = CGSize(width: Double(Self.width) / 2, height: Double(Self.height) / 2)
        var medians: [Bool: Double] = [:]
        for casting in [true, false] {
            var times: [Double] = []
            for frame in 0..<85 {
                var uniforms = FrameUniforms.make(camera: camera, size: size, pixelsPerPoint: 2 * fraction, time: Float(3 + Double(frame) / 60),
                                                  motion: 1, radius: state.map.radius, terrain: terrain, hovered: nil, selected: nil)
                XCTAssertTrue(uniforms.casts, "Close in, the moon casts shadows")
                if !casting { uniforms.cast(nil) }
                if let ms = renderer.measureFrame(uniforms, scene: scene, into: target) { times.append(ms) }
            }
            let settled = Array(times.dropFirst(5)).sorted()
            medians[casting] = settled[settled.count / 2]
        }
        let shadowed = try XCTUnwrap(medians[true]), plain = try XCTUnwrap(medians[false])
        print("PERFMETRIC near.gpu.scale60.p50 \(String(format: "%.3f", shadowed))")
        print("PERFMETRIC near.gpu.scale60.plain.p50 \(String(format: "%.3f", plain))")
        print("PERF a seat close in on \(device.name): \(String(format: "%.2f", shadowed)) ms with the moon's shadows, "
              + "\(String(format: "%.2f", plain)) ms without")
        XCTAssertLessThan(shadowed, 1000.0 / 60 * 0.85, "The frame with its shadows fits a 60 Hz frame with room to spare")
    }

    /// The GPU's median time for a frame near a realm's seat, every hex
    /// known, drawing only the regions in view; and, `wholeToo`, drawing
    /// the whole land, as was done before.
    private func measureNear(seats: Int, seed: String, wholeToo: Bool, renderer: WorldRenderer,
                             daylight: Daylight = .night) throws -> (culled: Double, whole: Double?) {
        // As wide as the old realm made a lake for so many seats.
        let radius: Int = seats > 12 ? Int((36.0 * (Double(seats) / 12.0).squareRoot()).rounded()) : 36
        let state = TestWorld(seedText: seed, houses: seats, radius: radius)
        try renderer.setLand(TerrainMesh.shared(for: state.map), for: state.map)
        try renderer.updateTiles(state.tiles(watched: { state.watchedByTheFirst($0) }), side: TileTexture.side(for: state.map))
        let terrain = try XCTUnwrap(renderer.land).terrain
        let stage = WorldStage(map: state.map, relief: Relief(map: state.map))
        var culled = SceneFrame()
        culled.fixed = stage.furnish(occupied: [], holds: Set(state.holds.map(\.position)))
        culled.fixedVersion = stage.furnitureVersion
        culled.fixedRegions = stage.furnitureRegions
        XCTAssertNotNil(culled.fixedRegions)
        var whole = culled
        whole.fixedRegions = nil
        let seat = state.holds[0].position
        let scale = 28.0
        let fraction = WorldMetalView.renderScale(forCameraScale: scale)
        let target = try renderer.makeTarget(width: Int((Double(Self.width) * fraction).rounded()),
                                             height: Int((Double(Self.height) * fraction).rounded()))
        var camera = Camera(scale: scale)
        camera.focus(on: seat)
        let size = CGSize(width: Double(Self.width) / 2, height: Double(Self.height) / 2)
        var medians: [String: Double] = [:]
        let scenes: [(String, SceneFrame)] = wholeToo ? [("culled", culled), ("whole", whole)] : [("culled", culled)]
        for (name, scene) in scenes {
            var times: [Double] = []
            for frame in 0..<85 {
                let uniforms = FrameUniforms.make(camera: camera, size: size, pixelsPerPoint: 2 * fraction, time: Float(3 + Double(frame) / 60),
                                                  motion: 1, radius: state.map.radius, terrain: terrain, hovered: nil, selected: nil,
                                                  daylight: daylight)
                if let ms = renderer.measureFrame(uniforms, scene: scene, into: target) { times.append(ms) }
            }
            let settled = Array(times.dropFirst(5)).sorted()
            medians[name] = settled[settled.count / 2]
        }
        return (try XCTUnwrap(medians["culled"]), medians["whole"])
    }
}
