import LauncherKit
import SwiftUI
import XCTest
@testable import NullmereKit

/// Every text held to one rule of contrast, and no type too small or too
/// thin to hold it.
@MainActor
final class AccessiblePlayTests: XCTestCase {
    override func tearDown() async throws {
        Contrast.shared.isIncreased = false
        Contrast.shared.differentiates = false
    }

    /// One rule for every text, the launcher's and the realm's: never under
    /// nine tenths of the ink, so a full stop or a middle dot still stands
    /// clear of the dark at a 1x display's size; what is asked fainter a
    /// little fainter still; solid, mixed from the dark to the ink rather
    /// than laid over what lies beneath; with Increase Contrast, the full
    /// ink. Lines and meters by a rule of their own, so an empty one is
    /// never taken for a full one.
    func testOneRuleOfContrastForEveryText() {
        func resolved(_ colour: Color) -> Color.Resolved { colour.resolve(in: EnvironmentValues()) }
        func drawn(_ colour: Color) -> Double { Double(resolved(colour).opacity) }
        let asked = stride(from: 0.0, through: 1.0, by: 0.05).map { $0 }
        for opacity in asked {
            XCTAssertEqual(LauncherKit.Palette.textStrength(opacity), 0.9 + 0.1 * opacity, accuracy: 0.0001, "At \(opacity)")
            XCTAssertEqual(drawn(NullmereKit.Palette.text(opacity)), 1, accuracy: 0.0001, "Solid at \(opacity)")
            XCTAssertEqual(resolved(NullmereKit.Palette.text(opacity)), resolved(LauncherKit.Palette.text(opacity)),
                           "The launcher's rule and the realm's are one")
        }
        let greens = asked.map { Double(resolved(NullmereKit.Palette.text($0)).green) }
        XCTAssertEqual(greens, greens.sorted(), "What is asked fainter is fainter")
        XCTAssertGreaterThanOrEqual(LauncherKit.Palette.textStrength(-1), 0.9, "But never under the floor")
        let full = resolved(NullmereKit.Palette.text(1)), ink = resolved(NullmereKit.Palette.ink)
        XCTAssertEqual(full.red, ink.red, accuracy: 0.002, "At full strength, the ink")
        XCTAssertEqual(full.blue, ink.blue, accuracy: 0.002)
        XCTAssertEqual(drawn(NullmereKit.Palette.line(0.1)), 0.1, accuracy: 0.001, "A line as faint as it is drawn")

        Contrast.shared.isIncreased = true
        defer { Contrast.shared.isIncreased = false }
        XCTAssertTrue(asked.allSatisfy { LauncherKit.Palette.textStrength($0) == 1 }, "With Increase Contrast, every text the full ink")
        XCTAssertEqual(drawn(NullmereKit.Palette.line(0.1)), 0.2, accuracy: 0.001, "A track twice as plain")
        XCTAssertEqual(drawn(NullmereKit.Palette.line(0.3)), 0.4, accuracy: 0.001, "But no brighter than 0.4")
        XCTAssertEqual(drawn(NullmereKit.Palette.line(0.7)), 0.7, accuracy: 0.001, "A bright line as it was")
    }

    /// No type too small or too thin to hold its contrast on a 1x display:
    /// words never under eleven points and capitals never under nine and a
    /// half, nothing below fourteen points thinner than regular, nothing
    /// below twelve lighter than medium; Larger type larger still.
    func testNoTypeIsTooSmallOrTooThin() {
        TextSize.shared.isLarger = false
        defer { TextSize.shared.isLarger = false }
        XCTAssertEqual(TextSize.shared.size(7.5), 9.5, "Capitals")
        XCTAssertEqual(TextSize.shared.size(9, words: true), 11, "Words")
        XCTAssertEqual(TextSize.shared.size(13, words: true), 13)
        XCTAssertEqual(CGFloat.launcherType(9.5, unit: 0.72), 11, "The launcher's, in a small window, the realm's least for words")
        XCTAssertEqual(TextSize.readable(.regular, at: 11), .medium)
        XCTAssertEqual(TextSize.readable(.light, at: 12.5), .regular)
        XCTAssertEqual(TextSize.readable(.semibold, at: 9.5), .semibold, "Heavier, as asked")
        XCTAssertEqual(TextSize.readable(.thin, at: 26), .thin, "Display sizes keep their thin type")
        TextSize.shared.isLarger = true
        XCTAssertEqual(TextSize.shared.size(7.5), 12.5)
        XCTAssertEqual(TextSize.shared.size(9, words: true), 12.5)
    }
}

/// One copy of the game at a time.
final class SingleInstanceTests: XCTestCase {
    func testASecondCopyHandsOverToTheFirst() {
        var brought: [pid_t] = []
        XCTAssertFalse(SingleInstance.handOver(to: [(42, { brought.append(42) })], current: 42), "Alone: it stays")
        XCTAssertTrue(SingleInstance.handOver(to: [(42, { brought.append(42) }), (7, { brought.append(7) })], current: 42))
        XCTAssertEqual(brought, [7], "The first copy comes forward")
        XCTAssertNil(SingleInstance.other(among: [42], current: 42), "Alone: it stays")
        XCTAssertEqual(SingleInstance.other(among: [42, 7], current: 42), 7, "Another running: that one comes forward")
        XCTAssertNil(SingleInstance.other(among: [], current: 42))
    }

    /// The copy under test is the only one running: it carries on, with no
    /// other to hand over to.
    func testTheOnlyCopyRunningCarriesOn() {
        XCTAssertFalse(SingleInstance.handOver())
    }
}
