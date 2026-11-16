import Foundation
import XCTest

/// Plain words throughout the rebuilt realm (the plan's decision 8): the
/// fiction keeps its proper names, House, Nullmere, Moonspire, moonsalt,
/// and the coined vocabulary of the turn-based game stays retired from
/// what a player reads. Every string the realm's rules say and the
/// client's lists, cards and screens show is read from their source, and
/// none may use a retired word.
final class PlainWordsTests: XCTestCase {
    /// The coined words of the turn-based game that a player no longer
    /// reads. Some of them are good English in other senses ("hold" is
    /// left out for that reason: a Storehouse holds goods); each of these
    /// stands only for what the old game coined it for.
    static let retired = ["watch", "watches", "seat", "seats", "steward", "stewards", "standard", "standards", "happening", "happenings",
                          "labour", "veil", "keeper", "keepers", "muster", "musters", "mustering", "pace"]

    /// Where what a player reads is written: the realm's rules and its
    /// catalogue, and the client's world, lists, cards and screens.
    static let places = ["realm/src/catalog.rs", "realm/src/rules", "Sources/NullmereLive", "Sources/NullmereLiveStage",
                         "Sources/NullmereKit/Live"]

    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// Every source file under a place, a file or a folder.
    private func files(_ place: String) -> [URL] {
        let url = root.appendingPathComponent(place)
        guard let walk = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else { return [url] }
        return walk.compactMap { $0 as? URL }.filter { ["rs", "swift"].contains($0.pathExtension) }
    }

    /// The text of a source's string literals that read as words: a space
    /// in them, with what is put into them (Swift's `\(…)`, Rust's `{…}`)
    /// taken out.
    static func phrases(in source: String) -> [String] {
        let literal = try! NSRegularExpression(pattern: #""((?:[^"\\\n]|\\.)*)""#)
        let range = NSRange(source.startIndex..., in: source)
        return literal.matches(in: source, range: range).compactMap { match -> String? in
            guard let inner = Range(match.range(at: 1), in: source) else { return nil }
            var text = String(source[inner])
            for pattern in [#"\\\([^)]*\)"#, #"\{[^}]*\}"#] {
                text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
            }
            return text.contains(" ") ? text : nil
        }
    }

    /// The retired words a phrase uses.
    static func retiredWords(in phrase: String) -> [String] {
        let words = phrase.lowercased().split { !$0.isLetter && $0 != "'" }.map { $0.hasSuffix("'s") ? String($0.dropLast(2)) : String($0) }
        return retired.filter { words.contains($0) }
    }

    func testTheRetiredWordsAreFound() {
        XCTAssertEqual(PlainWordsTests.retiredWords(in: "Your steward's watch is over."), ["watch", "steward"])
        XCTAssertEqual(PlainWordsTests.retiredWords(in: "The Storehouse holds goods; the Unquiet hold it."), [])
        XCTAssertEqual(PlainWordsTests.phrases(in: #"say("The \(name) watches", "{count} seats", "key")"#), ["The   watches", "  seats"])
    }

    func testNoPlayerReadsARetiredWord() throws {
        var read = 0
        var found: [String] = []
        for place in PlainWordsTests.places {
            for file in files(place) {
                guard let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
                read += 1
                for phrase in PlainWordsTests.phrases(in: source) {
                    let words = PlainWordsTests.retiredWords(in: phrase)
                    if !words.isEmpty { found.append("\(file.lastPathComponent): \(words.joined(separator: ", ")) in \"\(phrase)\"") }
                }
            }
        }
        guard read > 0 else { throw XCTSkip("The realm's and the client's sources are not beside the tests here") }
        XCTAssertGreaterThan(read, 30, "every place was read")
        XCTAssertEqual(found, [], "plain words throughout")
    }
}
