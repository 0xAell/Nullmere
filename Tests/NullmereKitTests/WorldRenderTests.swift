import AppKit
import ImageIO
import Metal
@testable import NullmereKit
import NullmereLand
import NullmereLive
import NullmereLiveStage
import NullmereModels
import NullmereRealm
import NullmereTestSupport
import NullmereWorld
import SwiftUI
import XCTest

/// The world in three dimensions, drawn by its own shaders on this Mac's
/// GPU and looked at: the still black lake holding the stars and the
/// moon, the mist over what the keeper has never seen, the land lit by the
/// moon, and the hex chosen. CI keeps the frames, and prints them small.
final class WorldRenderTests: XCTestCase {
    static let width = 960
    static let height = 600
    static var size: CGSize { CGSize(width: width, height: height) }

    struct Drawn {
        let name: String
        let pixels: [UInt8]
        let camera: Camera

        func luminance(_ x: Int, _ y: Int) -> Double {
            let i = (y * WorldRenderTests.width + x) * 4
            return 0.0722 * Double(pixels[i]) + 0.7152 * Double(pixels[i + 1]) + 0.2126 * Double(pixels[i + 2])
        }
    }

    /// A realm's world, as its keeper first sees it, and whole.
    struct World {
        let state: TestWorld
        let opening: [UInt8]
        /// What the keeper knows as the age opens, by map index: the
        /// country five out about their seat.
        let openingKnown: [Bool]
        let whole: [UInt8]
        let terrain: TerrainMesh
        let relief: Relief

        init() {
            let state = TestWorld(seedText: "drawn in the round", houses: 12, radius: 24)
            let seat = state.holds[0].position
            opening = state.tiles(known: { $0.distance(to: seat) <= 5 }, watched: { state.watchedByTheFirst($0) })
            openingKnown = state.map.hexes.map { $0.distance(to: seat) <= 5 }
            // The whole lake known, as its keeper knows it some ages on:
            // only what their seat and companies see watched.
            whole = state.tiles(watched: { state.watchedByTheFirst($0) })
            self.state = state
            terrain = TerrainMesh.shared(for: state.map)
            relief = Relief(map: state.map)
        }
    }

    static let world = World()

    func renderer() throws -> WorldRenderer {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device available") }
        let library = try device.makeLibrary(source: WorldShaders.source, options: nil)
        let renderer = try WorldRenderer(device: device, library: library, pixelFormat: .bgra8Unorm)
        try renderer.setLand(WorldRenderTests.world.terrain, for: WorldRenderTests.world.state.map)
        return renderer
    }

    /// Drawn at night, as every picture here was made to be judged, unless
    /// told another hour of the world's day.
    func draw(_ renderer: WorldRenderer, _ name: String, camera: Camera, tiles: [UInt8], selected: Hex? = nil,
              scene: SceneFrame = SceneFrame(), time: Float = 20, daylight: Daylight = .night) throws -> Drawn {
        let world = WorldRenderTests.world
        try renderer.updateTiles(tiles, side: TileTexture.side(for: world.state.map))
        let target = try renderer.makeTarget(width: WorldRenderTests.width, height: WorldRenderTests.height)
        var frame = FrameUniforms.make(camera: camera, size: WorldRenderTests.size, pixelsPerPoint: 1, time: time, motion: 1,
                                       radius: world.state.map.radius, terrain: world.terrain, hovered: nil, selected: selected,
                                       daylight: daylight)
        frame.light(with: PointLight.strongest(scene.lights, near: camera.focus))
        let pixels = try XCTUnwrap(renderer.pixels(frame, scene: scene, into: target), "\(name) drawn")
        return Drawn(name: name, pixels: pixels, camera: camera)
    }

    /// How many pixels of a grid over the frame, every other one each
    /// way, differ between two frames by more than a just-seen step of
    /// brightness.
    static func changed(_ a: Drawn, _ b: Drawn) -> Int {
        var count = 0
        for y in stride(from: 0, to: height, by: 2) {
            for x in stride(from: 0, to: width, by: 2) where abs(a.luminance(x, y) - b.luminance(x, y)) > 8 {
                count += 1
            }
        }
        return count
    }
    /// Where the view's ray through a pixel meets the world, and what is there.
    func ground(at x: Int, _ y: Int, in drawn: Drawn) -> (hex: Hex, terrain: Terrain?)? {
        let world = WorldRenderTests.world
        let (origin, direction) = drawn.camera.ray(through: CGPoint(x: x, y: y), in: WorldRenderTests.size)
        guard let hit = world.relief.intersect(origin: origin, direction: direction) else { return nil }
        let hex = HexLayout(size: 1).hex(atX: Double(hit.x), y: Double(hit.z))
        return (hex, world.state.map[hex]?.terrain)
    }

    func testTheStillWaterHoldsTheMoonAndTheStars() throws {
        let renderer = try renderer()
        let world = WorldRenderTests.world
        // Looking down on the deepest water from where it holds the moon:
        // the eye set opposite the moon, as high as the moon is.
        let lake = try XCTUnwrap(world.state.map.deepestWater()).hex
        var camera = Camera(scale: 16, tilt: acos(Double(Sky.moon.y)), heading: atan2(-Double(Sky.moon.x), -Double(Sky.moon.z)))
        camera.focus(on: lake)
        let drawn = try draw(renderer, "lake", camera: camera, tiles: world.whole)
        // The moon's image lies at the middle of the view, round and bright.
        var middle = 0.0
        for dy in -4...4 {
            for dx in -4...4 { middle = max(middle, drawn.luminance(WorldRenderTests.width / 2 + dx, WorldRenderTests.height / 2 + dy)) }
        }
        XCTAssertGreaterThan(middle, 170, "the moon lies in the water where the eye sees it")
        try keep([drawn], as: "world-lake")

        // Over the open water, deep from any shore: black, but for the
        // moon and the stars it gives back.
        var water: [Double] = []
        var brightest = (value: 0.0, x: 0, y: 0)
        for y in stride(from: 0, to: WorldRenderTests.height, by: 3) {
            for x in stride(from: 0, to: WorldRenderTests.width, by: 3) {
                guard let found = ground(at: x, y, in: drawn), found.terrain == .still,
                      found.hex.neighbors.allSatisfy({ world.state.map[$0]?.terrain == .still }) else { continue }
                let value = drawn.luminance(x, y)
                water.append(value)
                if value > brightest.value { brightest = (value, x, y) }
            }
        }
        XCTAssertGreaterThan(water.count, 2000, "the view holds open water")
        let sorted = water.sorted()
        XCTAssertLessThan(sorted[sorted.count / 2], 26, "the still water is black")
        XCTAssertGreaterThan(brightest.value, 170, "the moon lies in it")
        // And the stars, small bright points in the black away from it.
        var stars = 0
        for y in stride(from: 2, to: WorldRenderTests.height - 2, by: 2) {
            for x in stride(from: 2, to: WorldRenderTests.width - 2, by: 2) {
                let dx = x - WorldRenderTests.width / 2, dy = y - WorldRenderTests.height / 2
                guard dx * dx + dy * dy > 120 * 120, drawn.luminance(x, y) > 40 else { continue }
                guard let found = ground(at: x, y, in: drawn), found.terrain == .still else { continue }
                // A point: brighter than what lies three pixels round it.
                if [(3, 0), (-3, 0), (0, 3), (0, -3)].allSatisfy({ drawn.luminance(x + $0.0, y + $0.1) < drawn.luminance(x, y) - 12 }) {
                    stars += 1
                }
            }
        }
        XCTAssertGreaterThan(stars, 6, "and the stars")
    }

    /// Where the lake meets the land the small waves wash up pale with the
    /// moon and draw back, so the water's edge shows in the dark: the
    /// shore nearest the keeper's seat drawn with its froth and without
    /// it (the same shaders, NM_NO_WASH), and again three seconds on.
    func testTheStrandWashesPaleWithTheMoon() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device available") }
        let world = WorldRenderTests.world
        let washed = try renderer()
        let options = MTLCompileOptions()
        options.preprocessorMacros = ["NM_NO_WASH": NSNumber(value: 1)]
        let bare = try WorldRenderer(device: device, library: device.makeLibrary(source: WorldShaders.source, options: options),
                                     pixelFormat: .bgra8Unorm)
        try bare.setLand(world.terrain, for: world.state.map)
        let map = world.state.map
        let isLand = { (hex: Hex) -> Bool in !(map[hex]?.terrain.isWater ?? true) }
        let seat = world.state.holds[0].position
        // The lake's own water, the still and the shallows that rim it, where
        // it meets the land.
        let lakeWater: Set<Terrain> = [.still, .shallows]
        let shore = try XCTUnwrap(map.hexes.filter { hex in
            map[hex].map { lakeWater.contains($0.terrain) } == true && hex.neighbors.contains(where: isLand)
        }.min { $0.distance(to: seat) < $1.distance(to: seat) }, "The lake has a shore")
        var camera = Camera(scale: 40)
        camera.focus(on: shore)
        let drawn = try draw(washed, "strand", camera: camera, tiles: world.whole)
        let unwashed = try draw(bare, "strand unwashed", camera: camera, tiles: world.whole)
        let later = try draw(washed, "strand later", camera: camera, tiles: world.whole, time: 23)
        try keep([drawn, later], as: "world-strand")
        var paler: [Double] = [], byTheEdge = 0, moved = 0, darker = 0
        for y in stride(from: 0, to: WorldRenderTests.height, by: 2) {
            for x in stride(from: 0, to: WorldRenderTests.width, by: 2) {
                let gain = drawn.luminance(x, y) - unwashed.luminance(x, y)
                if gain < -2 { darker += 1 }
                guard gain >= 2 else { continue }
                paler.append(gain)
                // Within two hexes of both land and water, never out on the
                // open Still nor up on dry ground.
                if let found = ground(at: x, y, in: drawn) {
                    let near = [found.hex] + found.hex.neighbors + found.hex.neighbors.flatMap(\.neighbors)
                    if near.contains(where: isLand), near.contains(where: { map[$0]?.terrain.isWater ?? false }) { byTheEdge += 1 }
                }
                if abs(later.luminance(x, y) - drawn.luminance(x, y)) >= 2 { moved += 1 }
            }
        }
        let mean = paler.isEmpty ? 0 : paler.reduce(0, +) / Double(paler.count)
        print("RENDER wash: \(paler.count) points paler at the strand by a mean of \(String(format: "%.1f", mean)) levels, "
            + "\(byTheEdge) of them by the water's edge, \(moved) changed three seconds on; \(darker) darker")
        XCTAssertGreaterThan(paler.count, 150, "the strand shows pale where the water meets the land")
        XCTAssertGreaterThan(Double(byTheEdge), 0.9 * Double(paler.count), "and only there")
        XCTAssertGreaterThan(mean, 4, "pale enough to be seen at night")
        XCTAssertEqual(darker, 0, "the froth never darkens what it lies on")
        XCTAssertGreaterThan(Double(moved), 0.3 * Double(paler.count), "the waves wash up and draw back")
    }

    /// A light by the water lies on it as the moon does: a lantern held a
    /// little above the open water, drawn with it and without it, brightens
    /// the water by it with its own warm light, from under it toward the
    /// eye, and darkens nothing.
    func testALanternLiesOnTheWater() throws {
        let renderer = try renderer()
        let world = WorldRenderTests.world
        let lake = try XCTUnwrap(world.state.map.deepestWater()).hex
        var camera = Camera(scale: 60)
        camera.focus(on: lake)
        // As high over the water as a fisher's at a boat's bow, and as bright.
        let centre = Relief.centre(of: lake)
        let lantern = PointLight(at: Vec3(centre.x, Relief.waterline + 0.3, centre.z), reach: 1.5, colour: Vec3(1.9, 1.15, 0.45))
        let lit = try draw(renderer, "lantern", camera: camera, tiles: world.whole, scene: SceneFrame(lights: [lantern]))
        let unlit = try draw(renderer, "no lantern", camera: camera, tiles: world.whole)
        try keep([lit], as: "world-lantern")
        let under = camera.viewPoint(of: lake, height: Double(Relief.waterline), in: WorldRenderTests.size)
        var brighter: [Double] = [], towardEye = 0, warm = 0, darker = 0
        for y in stride(from: 0, to: WorldRenderTests.height, by: 2) {
            for x in stride(from: 0, to: WorldRenderTests.width, by: 2) {
                let gain = lit.luminance(x, y) - unlit.luminance(x, y)
                if gain < -1 { darker += 1 }
                guard gain >= 3 else { continue }
                brighter.append(gain)
                if Double(y) > under.y { towardEye += 1 }
                // Its red against its blue, the pixels being BGRA.
                let i = (y * WorldRenderTests.width + x) * 4
                let red = Double(lit.pixels[i + 2]) - Double(unlit.pixels[i + 2])
                let blue = Double(lit.pixels[i]) - Double(unlit.pixels[i])
                if red > 1.5 * blue { warm += 1 }
            }
        }
        let mean = brighter.isEmpty ? 0 : brighter.reduce(0, +) / Double(brighter.count)
        print("RENDER lantern: \(brighter.count) points of the water brighter by a mean of \(String(format: "%.1f", mean)) levels, "
            + "\(warm) of them warm, \(towardEye) toward the eye; \(darker) darker")
        XCTAssertGreaterThan(brighter.count, 20, "The lantern's light lies on the water")
        XCTAssertGreaterThan(Double(warm), 0.8 * Double(brighter.count), "in its own warm colour")
        XCTAssertGreaterThan(Double(towardEye), 0.6 * Double(brighter.count), "from under it toward the eye")
        XCTAssertEqual(darker, 0, "darkening nothing")
    }

    /// Vigils' lights for the fallen carried round the lake on its
    /// current, as the session stages them, drawn low over the water: each
    /// a warm flame in its glow, the nearest laying their light on the water
    /// toward the eye, and nothing darker for them.
    func testVigilsBurnOnTheWater() throws {
        let renderer = try renderer()
        let world = WorldRenderTests.world
        let heart = try XCTUnwrap(world.state.map.deepestWater()).hex
        // Round the lake, a hex at a time.
        let way = world.state.roundTheLake(from: heart, count: 7)
        let sights = (0..<min(6, max(way.count - 1, 0))).map { index in
            VigilSight(at: way[index], next: way[index + 1], id: 40 + index, burned: 0)
        }
        XCTAssertEqual(sights.count, 6)
        var camera = Camera(scale: 130, tilt: 1.2, heading: 0.4)
        camera.focus(on: sights[3].at)
        let lit = WorldStage.vigils(sights, progress: 0.5, scale: camera.scale, time: 20)
        let burning = try draw(renderer, "vigils", camera: camera, tiles: world.whole, scene: SceneFrame(motes: lit.motes, lights: lit.lights))
        let dark = try draw(renderer, "no vigils", camera: camera, tiles: world.whole)
        try keep([burning], as: "world-vigils")
        // Where each flame stands on the screen, and how far its glow
        // reaches about it: the light within that is its own, the rest of
        // what brightens lies on the water.
        let flames = stride(from: 0, to: lit.motes.count, by: 2).map { index -> (at: CGPoint, reach: Double) in
            let place = lit.motes[index].place, glow = lit.motes[index + 1].place.w
            let at = camera.viewPoint(worldX: Double(place.x), worldY: Double(place.z), height: Double(place.y), in: WorldRenderTests.size)
            let edge = camera.viewPoint(worldX: Double(place.x + glow), worldY: Double(place.z), height: Double(place.y), in: WorldRenderTests.size)
            return (at, hypot(Double(edge.x - at.x), Double(edge.y - at.y)) + 3)
        }
        var atFlames = 0, onWater = 0, towardEye = 0, warm = 0, darker = 0
        for y in stride(from: 0, to: WorldRenderTests.height, by: 2) {
            for x in stride(from: 0, to: WorldRenderTests.width, by: 2) {
                let gain = burning.luminance(x, y) - dark.luminance(x, y)
                if gain < -1 { darker += 1 }
                guard gain >= 3 else { continue }
                let i = (y * WorldRenderTests.width + x) * 4
                if Double(burning.pixels[i + 2]) - Double(dark.pixels[i + 2]) > 1.5 * (Double(burning.pixels[i]) - Double(dark.pixels[i])) { warm += 1 }
                func away(_ point: CGPoint) -> Double { hypot(Double(point.x) - Double(x), Double(point.y) - Double(y)) }
                let nearest = flames.min { away($0.at) < away($1.at) }!
                if away(nearest.at) <= nearest.reach {
                    atFlames += 1
                } else {
                    onWater += 1
                    // On the water under one of them, toward the eye.
                    if flames.contains(where: { Double(y) > Double($0.at.y) && abs(Double(x) - Double($0.at.x)) <= 40 }) { towardEye += 1 }
                }
            }
        }
        print("RENDER vigils: \(flames.count) flames, \(atFlames) points lit about them and \(onWater) on the water, "
            + "\(towardEye) of those toward the eye; \(warm) warm in all, \(darker) darker")
        XCTAssertGreaterThan(atFlames, 6 * 4, "Each flame burns in its glow")
        XCTAssertGreaterThan(onWater, 20, "The nearest lay their light on the water")
        XCTAssertGreaterThan(Double(towardEye), 0.8 * Double(onWater), "from under them toward the eye")
        XCTAssertGreaterThan(Double(warm), 0.8 * Double(atFlames + onWater), "in a candle's warm colour")
        XCTAssertEqual(darker, 0, "darkening nothing")
    }

    /// Points brighter in one picture than another by more than `by`
    /// luminance levels, sampled every other pixel, within `radius` of a
    /// point and beyond it; and how many of those within are warm, their
    /// red risen over their blue.
    static func brighter(_ lit: Drawn, than bare: Drawn, about point: CGPoint, within radius: Double, by: Double = 4)
        -> (near: Int, warm: Int, beyond: Int) {
        var near = 0, warm = 0, beyond = 0
        for y in stride(from: 0, to: height, by: 2) {
            for x in stride(from: 0, to: width, by: 2) where abs(lit.luminance(x, y) - bare.luminance(x, y)) > by {
                guard hypot(Double(x) - Double(point.x), Double(y) - Double(point.y)) < radius else {
                    beyond += 1
                    continue
                }
                near += 1
                // The pixels being BGRA: red against blue.
                let i = (y * width + x) * 4
                if Double(lit.pixels[i + 2]) - Double(bare.pixels[i + 2]) > 1.3 * (Double(lit.pixels[i]) - Double(bare.pixels[i])) { warm += 1 }
            }
        }
        return (near, warm, beyond)
    }
    func testTheUnknownLiesUnderMistAndTheKnownIsLit() throws {
        let renderer = try renderer()
        let world = WorldRenderTests.world
        let seat = world.state.holds[0].position
        var camera = Camera(scale: 30)
        camera.focus(on: seat)
        let opening = try draw(renderer, "opening", camera: camera, tiles: world.opening, selected: seat)
        try keep([opening], as: "world-opening")
        let explored = world.openingKnown
        // As the keeper first sees it: their own land lit, the rest unknown.
        var mistPoints: [(x: Int, y: Int)] = [], land: [Double] = []
        for y in stride(from: 0, to: WorldRenderTests.height, by: 4) {
            for x in stride(from: 0, to: WorldRenderTests.width, by: 4) {
                let point = CGPoint(x: x, y: y)
                let flat = camera.hex(at: point, in: WorldRenderTests.size)
                guard let index = world.state.map.index(of: flat) else { continue }
                let around = flat.neighbors.compactMap { world.state.map.index(of: $0) }
                if !explored[index], around.allSatisfy({ !explored[$0] }) {
                    mistPoints.append((x, y))
                } else if explored[index], around.allSatisfy({ explored[$0] }), !(world.state.map[flat]?.terrain.isWater ?? true) {
                    land.append(opening.luminance(x, y))
                }
            }
        }
        let mist = mistPoints.map { opening.luminance($0.x, $0.y) }
        XCTAssertGreaterThan(mist.count, 200)
        XCTAssertGreaterThan(land.count, 50)
        let mistMean = mist.reduce(0, +) / Double(mist.count), landMean = land.reduce(0, +) / Double(land.count)
        let spread = (mist.map { ($0 - mistMean) * ($0 - mistMean) }.reduce(0, +) / Double(mist.count)).squareRoot()
        // And the mist drifts: the same view half a minute on.
        let later = try draw(renderer, "later", camera: camera, tiles: world.opening, selected: seat, time: 50)
        let drifted = mistPoints.filter { abs(later.luminance($0.x, $0.y) - opening.luminance($0.x, $0.y)) >= 1 }.count
        print("RENDER mist: mean \(String(format: "%.1f", mistMean)) beside the known land's \(String(format: "%.1f", landMean)), "
            + "spread \(String(format: "%.2f", spread)); \(drifted) of \(mist.count) points changed half a minute on")
        XCTAssertLessThan(mistMean, 40, "the mist is night-dark")
        XCTAssertGreaterThan(landMean, mistMean + 6, "the known land is lit well above the mist")
        XCTAssertGreaterThan(spread, 1, "the mist lies in banks, never one flat grey")
        XCTAssertGreaterThan(Double(drifted) / Double(mist.count), 0.2, "the mist drifts")

        // The hex chosen is ringed.
        let plain = try draw(renderer, "unchosen", camera: camera, tiles: world.opening)
        let centre = camera.viewPoint(of: seat, height: Double(world.relief.height(of: seat)), in: WorldRenderTests.size)
        var brighter = 0
        for dy in -40...40 {
            for dx in -60...60 {
                let x = Int(centre.x) + dx, y = Int(centre.y) + dy
                guard x >= 0, y >= 0, x < WorldRenderTests.width, y < WorldRenderTests.height else { continue }
                if opening.luminance(x, y) > plain.luminance(x, y) + 8 { brighter += 1 }
            }
        }
        XCTAssertGreaterThan(brighter, 40, "a light rings the chosen hex")
    }

    func testTheWholeWorldFromAfarAndTurned() throws {
        let renderer = try renderer()
        let world = WorldRenderTests.world
        let far = try draw(renderer, "whole", camera: Camera(scale: 9, tilt: 0.6), tiles: world.whole)
        var turned = Camera(scale: 24, heading: 0.9)
        turned.focus(on: world.state.holds[0].position)
        let side = try draw(renderer, "turned", camera: turned, tiles: world.whole)
        try keep([far, side], as: "world-afar")
        for drawn in [far, side] {
            var values: [Double] = []
            for y in stride(from: 0, to: WorldRenderTests.height, by: 5) {
                for x in stride(from: 0, to: WorldRenderTests.width, by: 5) { values.append(drawn.luminance(x, y)) }
            }
            let lit = Double(values.filter { $0 > 14 }.count) / Double(values.count)
            let mean = values.reduce(0, +) / Double(values.count)
            let spread = (values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)).squareRoot()
            XCTAssertGreaterThan(lit, 0.15, "\(drawn.name): the world is drawn")
            XCTAssertGreaterThan(spread, 6, "\(drawn.name): land, water and mist told apart, never one flat field")
            XCTAssertLessThan(mean, 140, "\(drawn.name): a night scene")
        }
    }

    /// A ridge by day: the land's highest hex at noon, with the land's own
    /// shadow over its lee, kept as world-ridge for an eye to judge how
    /// deep a lee darkens on a Mac (plan 1.3), which the seat's view, on
    /// low ground, never showed.
    func testARidgeIsDrawnByDay() throws {
        let renderer = try renderer()
        let world = WorldRenderTests.world
        let land = world.state.map.hexes.filter { !(world.state.map[$0]?.terrain.isWater ?? true) }
        let peak = try XCTUnwrap(land.max { world.relief.height(of: $0) < world.relief.height(of: $1) })
        var camera = Camera(scale: 34)
        camera.focus(on: peak)
        let day = try draw(renderer, "ridge", camera: camera, tiles: world.whole, daylight: .day)
        try keep([day], as: "world-ridge")
        print("RENDER ridge: the highest hex, \(peak), at \(world.relief.height(of: peak))")
    }

    /// A load of carts on the road from Ada's city to the grove, staged
    /// from the realm's rows as the play view stages them and drawn by
    /// day at the view's opening zoom, then closer: a carter with a
    /// handcart, where the same march as an army is drawn as spearmen.
    /// Kept as live-carts (plan 2.13), carts being drawn on Metal nowhere
    /// else: no picture of the app's has carts on the road.
    @MainActor
    func testALoadOfCartsIsDrawnOnTheRoadByDay() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device available") }
        // In an async test Metal's own async compile is the one called.
        let library = try await device.makeLibrary(source: WorldShaders.source, options: nil)
        let renderer = try WorldRenderer(device: device, library: library, pixelFormat: .bgra8Unorm)
        // The models' meshes from the library, as the play view's renderer
        // takes them: without, nothing staged is drawn but the ways.
        renderer.meshSource = { Library.model($0).mesh }
        renderer.setHouses(LiveSession.palette)
        let target = try renderer.makeTarget(width: WorldRenderTests.width, height: WorldRenderTests.height)
        func drawn(_ name: String, kind: Int, scale: Double) async throws -> Drawn {
            var rows = LiveSample.rows()
            // Ada's army on its way to the grove, made what is asked.
            rows["march"] = rows["march"]?.map { row in row[0] == .number(3) ? Array(row[0..<3]) + [.number(Double(kind))] + Array(row[4...]) : row }
            let session = LiveSession(line: StandInLine(rows: rows)) { 2_015 }
            await session.open()
            // Five-eighths of its way gone, between the way's third hex and its fourth.
            session.go(to: LiveHex(q: 11, r: -3))
            var camera = session.camera
            camera.scale = scale
            session.moved(camera)
            let land = try XCTUnwrap(session.land(), "\(name): the window's land")
            try renderer.setLand(land.terrain, for: land.map)
            try renderer.updateTiles(try XCTUnwrap(session.tiles()), side: TileTexture.side(for: land.map))
            let scene = session.frame(time: 20, size: WorldRenderTests.size)
            var frame = FrameUniforms.make(camera: session.camera, size: WorldRenderTests.size, pixelsPerPoint: 1, time: 20, motion: 1,
                                           radius: land.map.radius, terrain: land.terrain, hovered: nil, selected: nil, daylight: .day)
            frame.light(with: PointLight.strongest(scene.lights, near: session.camera.focus))
            let pixels = try XCTUnwrap(renderer.pixels(frame, scene: scene, into: target), "\(name) drawn")
            return Drawn(name: name, pixels: pixels, camera: session.camera)
        }
        let carts = try await drawn("carts", kind: LiveMarch.carts, scale: LiveSession.openingScale)
        let army = try await drawn("army", kind: LiveMarch.gather, scale: LiveSession.openingScale)
        let close = try await drawn("carts close", kind: LiveMarch.carts, scale: 2 * LiveSession.openingScale)
        try keep([carts, army, close], as: "live-carts")
        let differ = WorldRenderTests.changed(carts, army)
        print("RENDER carts: \(differ) of the grid's points differ from the same march drawn as an army")
        XCTAssertGreaterThan(differ, 10, "The carts are not drawn as the army is")
        XCTAssertLessThan(differ, WorldRenderTests.width * WorldRenderTests.height / 40, "but in the same land: only the marchers differ")
    }

    /// The world's day: the same land about the keeper's seat at noon, at
    /// dusk and at midnight. By day it is read in full light; the dusk is
    /// dimmer and the night dimmer again, but a night of bright moonlight,
    /// never dark. CI keeps the three as world-hours.
    func testTheLandIsReadByDayAndByMoonlight() throws {
        let renderer = try renderer()
        let world = WorldRenderTests.world
        var camera = Camera(scale: 34)
        camera.focus(on: world.state.holds[0].position)
        func mean(_ drawn: Drawn) -> Double {
            var total = 0.0, count = 0.0
            for y in stride(from: 0, to: WorldRenderTests.height, by: 4) {
                for x in stride(from: 0, to: WorldRenderTests.width, by: 4) {
                    total += drawn.luminance(x, y)
                    count += 1
                }
            }
            return total / count
        }
        let day = try draw(renderer, "day", camera: camera, tiles: world.whole, daylight: .day)
        let dusk = try draw(renderer, "dusk", camera: camera, tiles: world.whole, daylight: .dusk)
        let night = try draw(renderer, "night", camera: camera, tiles: world.whole)
        try keep([day, dusk, night], as: "world-hours")
        let (noon, evening, midnight) = (mean(day), mean(dusk), mean(night))
        print("RENDER hours: day \(Int(noon)), dusk \(Int(evening)), night \(Int(midnight)) of 255")
        XCTAssertGreaterThan(noon, 90, "By day the land is read in full light")
        XCTAssertGreaterThan(noon, 1.8 * midnight, "well above the night's")
        XCTAssertGreaterThan(evening, midnight + 8, "the dusk between them")
        XCTAssertLessThan(evening, noon - 8)
        XCTAssertGreaterThan(midnight, 15, "The night is bright moonlight, the land read under it")
        XCTAssertLessThan(midnight, 90, "and still a night")
        // The day's picture holds its range: neither burnt out nor flat.
        var burnt = 0, sampled = 0
        for y in stride(from: 0, to: WorldRenderTests.height, by: 4) {
            for x in stride(from: 0, to: WorldRenderTests.width, by: 4) {
                sampled += 1
                if day.luminance(x, y) > 250 { burnt += 1 }
            }
        }
        XCTAssertLessThan(Double(burnt) / Double(sampled), 0.05, "The day's whites are rolled off, not burnt out")
    }

    /// A frame as an image, its pixels as the renderer gives them.
    static func image(_ drawn: Drawn) throws -> CGImage {
        let provider = try XCTUnwrap(CGDataProvider(data: Data(drawn.pixels) as CFData))
        return try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                     space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                                     provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    /// Keeps the frames as one sheet when NULLMERE_KEEP_RENDERS names a
    /// folder, and prints it small for CI's log.
    func keep(_ frames: [Drawn], as name: String) throws {
        let width = WorldRenderTests.width, height = WorldRenderTests.height
        let images: [CGImage] = try frames.map(WorldRenderTests.image)
        let sheet = NSImage(size: NSSize(width: width * images.count, height: height))
        sheet.lockFocus()
        for (index, image) in images.enumerated() {
            NSImage(cgImage: image, size: NSSize(width: width, height: height)).draw(in: NSRect(x: index * width, y: 0, width: width, height: height))
        }
        sheet.unlockFocus()
        let tiff = try XCTUnwrap(sheet.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        if let path = ProcessInfo.processInfo.environment["NULLMERE_KEEP_RENDERS"] {
            let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            try FileManager.default.createDirectory(at: URL(fileURLWithPath: path), withIntermediateDirectories: true)
            try png.write(to: URL(fileURLWithPath: path).appendingPathComponent("\(name).png"))
        }
        // Small enough to print at the foot of CI's log: a thumbnail of
        // each frame, as a JPEG, kept beside the full sheet.
        guard let path = ProcessInfo.processInfo.environment["NULLMERE_KEEP_RENDERS"] else { return }
        let thumbWidth = 288 * images.count, thumbHeight = 180
        let small = NSImage(size: NSSize(width: thumbWidth, height: thumbHeight))
        small.lockFocus()
        sheet.draw(in: NSRect(x: 0, y: 0, width: thumbWidth, height: thumbHeight))
        small.unlockFocus()
        if let smallTIFF = small.tiffRepresentation, let smallRep = NSBitmapImageRep(data: smallTIFF),
           let jpeg = smallRep.representation(using: .jpeg, properties: [.compressionFactor: 0.55]) {
            try jpeg.base64EncodedString().write(to: URL(fileURLWithPath: path).appendingPathComponent("\(name).thumb.b64"),
                                                 atomically: true, encoding: .utf8)
        }
    }
}
