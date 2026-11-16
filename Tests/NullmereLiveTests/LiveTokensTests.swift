import Foundation
import XCTest

/// The rebuilt realm's Mac screens are written in three sizes of type and
/// three levels of emphasis (`Sources/NullmereKit/Live/LiveTokens.swift`):
/// their source is read here, where the Mac's interface is not built, and
/// no size or strength of words may be written there but by those names.
final class LiveTokensTests: XCTestCase {
    private var screens: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/NullmereKit/Live")
    }

    /// What the screens may not write: a type size by its number, a
    /// heading's small capitals sized by number, a strength of words by
    /// its number, or the ink itself.
    static let forbidden = [#"\.nm\(\s*\d"#, #"Caps\([^\n]*size:\s*\d"#, #"Palette\.text\("#, #"Palette\.ink\b"#]

    /// Where a screen's source breaks the rule, line by line.
    static func broken(_ source: String) -> [String] {
        source.split(separator: "\n", omittingEmptySubsequences: false).enumerated().compactMap { number, line in
            let text = String(line)
            return forbidden.contains { text.range(of: $0, options: .regularExpression) != nil } ? "line \(number + 1): \(text.trimmingCharacters(in: .whitespaces))" : nil
        }
    }

    func testTheRuleCatchesWhatItShould() {
        XCTAssertEqual(LiveTokensTests.broken(".font(.nm(12))\n.font(.nm(LiveType.body))"), ["line 1: .font(.nm(12))"])
        XCTAssertEqual(LiveTokensTests.broken(#"Caps("Troops", size: 10)"#).count, 1)
        XCTAssertEqual(LiveTokensTests.broken(".foregroundStyle(Palette.text(0.7))\n.foregroundStyle(Palette.ink)\n.foregroundStyle(Palette.bad)").count, 2)
        XCTAssertEqual(LiveTokensTests.broken(#"Caps("Troops", size: LiveType.small)"#), [])
    }

    func testTheScreensKeepToThreeSizesAndThreeStrengths() throws {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: screens.path)) ?? []
        let files = names.filter { $0.hasSuffix(".swift") && $0 != "LiveTokens.swift" }
        guard !files.isEmpty else { throw XCTSkip("The Mac's screens are not beside the tests here") }
        var found: [String] = []
        for name in files.sorted() {
            let source = try String(contentsOf: screens.appendingPathComponent(name), encoding: .utf8)
            found += LiveTokensTests.broken(source).map { "\(name) \($0)" }
        }
        XCTAssertEqual(found, [], "three sizes, three strengths")
        let tokens = try String(contentsOf: screens.appendingPathComponent("LiveTokens.swift"), encoding: .utf8)
        for name in ["small", "body", "title", "primary", "secondary", "tertiary"] {
            XCTAssertTrue(tokens.contains("static let \(name)") || tokens.contains("static var \(name)"), name)
        }
    }
}
