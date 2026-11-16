import AppKit
import Metal
import SwiftUI
import LauncherCore
import LauncherKit
import NullmereLand
import NullmereRealm
import XCTest
@testable import NullmereKit
import NullmereModels
import NullmereSound
import NullmereWorld

/// The first twelve colours, the elder Houses' as the old game named
/// them, the ones set plainly apart.
enum HouseColourTests {
    static let elder = 12
}

final class WorldShaderTests: XCTestCase {
    /// Every House that may sit around the lake has its colour, the same
    /// in the interface and on the map: the map's are the interface's,
    /// made linear for the shaders.
    func testEachHouseHasOneColourEverywhere() throws {
        XCTAssertEqual(Palette.houses.count, WorldGenerator.mostHouses, "A colour for every seat the widest lake has")
        XCTAssertEqual(WorldRenderer.houseColours.count, Palette.houseRGB.count)
        for (shader, interface) in zip(WorldRenderer.houseColours, Palette.houseRGB) {
            XCTAssertEqual(Double(shader.x), pow(interface.red, 2.2), accuracy: 1e-5)
            XCTAssertEqual(Double(shader.y), pow(interface.green, 2.2), accuracy: 1e-5)
            XCTAssertEqual(Double(shader.z), pow(interface.blue, 2.2), accuracy: 1e-5)
        }
        // Each a colour of its own: the elder Houses' plainly apart, every
        // younger House's of a lake of up to ninety-six seats still apart
        // from any beside it, and each of the widest lakes' still its own,
        // as far from every other as a thousand colours can be.
        let components = Palette.houses.compactMap { NSColor($0).usingColorSpace(.sRGB) }
        XCTAssertEqual(components.count, Palette.houses.count)
        let hand = Palette.houses.count - HousePalette.widestLakes.count
        XCTAssertEqual(hand, 96, "Ninety-six named by hand")
        var nearest = (elder: Double.infinity, hand: Double.infinity, widest: Double.infinity)
        for (index, a) in components.enumerated() {
            for (other, b) in components.enumerated() where other > index {
                let distance = Double(abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent)
                    + abs(a.blueComponent - b.blueComponent))
                if other < HouseColourTests.elder { nearest.elder = min(nearest.elder, distance) }
                else if other < hand { nearest.hand = min(nearest.hand, distance) }
                else { nearest.widest = min(nearest.widest, distance) }
            }
        }
        XCTAssertGreaterThan(nearest.elder, 0.3, "The elder Houses' plainly apart")
        XCTAssertGreaterThan(nearest.hand, 0.18, "A lake of up to ninety-six seats, each House's apart from any other")
        XCTAssertGreaterThan(nearest.widest, 0.03, "The widest lakes', each its own")
    }

    /// Compiles the world's shaders and builds their pipelines on this Mac's GPU.
    func testShadersCompileAndBuildTheirPipelines() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available")
        }
        let library = try device.makeLibrary(source: WorldShaders.source, options: nil)
        for name in WorldShaders.functions {
            XCTAssertNotNil(library.makeFunction(name: name), name)
        }
        XCTAssertNoThrow(try WorldRenderer(device: device, library: library, pixelFormat: .bgra8Unorm))
    }
}

@MainActor
final class TextSizeTests: XCTestCase {
    override func tearDown() {
        TextSize.shared.isLarger = false
        super.tearDown()
    }

    private func size(of view: some View) throws -> CGSize {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        return CGSize(width: image.width, height: image.height)
    }

    func testTheChoiceIsRemembered() {
        TextSize.shared.isLarger = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "text.larger"))
        XCTAssertEqual(TextSize.shared.scale, TextSize.largerScale)
        TextSize.shared.isLarger = false
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "text.larger"))
        XCTAssertEqual(TextSize.shared.scale, 1)
    }

    func testLargerTextEnlargesTheType() throws {
        TextSize.shared.isLarger = false
        let standard = try size(of: Caps("The Moonspire rises", size: 10).fixedSize())
        TextSize.shared.isLarger = true
        let larger = try size(of: Caps("The Moonspire rises", size: 10).fixedSize())
        XCTAssertGreaterThan(larger.width, standard.width * 1.15)
        XCTAssertGreaterThan(larger.height, standard.height)
    }

    /// Thin type only at display sizes: small text is never thinner than
    /// regular, and the smallest never lighter than medium, so its strokes
    /// hold their contrast.
    func testSmallTypeIsNeverThin() {
        XCTAssertEqual(Font.readable(.light, at: 12.5), .regular)
        XCTAssertEqual(Font.readable(.thin, at: 9), .medium)
        XCTAssertEqual(Font.readable(.light, at: 11.5), .medium)
        XCTAssertEqual(Font.readable(.semibold, at: 9), .semibold, "Heavier than medium, as asked")
        XCTAssertEqual(Font.readable(.thin, at: 26), .thin, "Display sizes keep their thin type")
    }
}
