import CoreGraphics
import NullmereLand
@testable import NullmereKit
import NullmereLive
@testable import NullmereLiveStage
import NullmereSound
import XCTest

/// The rebuilt realm heard: each piece of news its own cue, only what is
/// told after the last heard sounded, and the world's beds set from what
/// is heard about where the player looks.
@MainActor
final class LiveSoundsTests: XCTestCase {
    func testEachPieceOfNewsIsToldByItsCue() {
        XCTAssertEqual(LiveSounds.cue(for: .raised), .complete)
        XCTAssertEqual(LiveSounds.cue(for: .trained), .muster)
        XCTAssertEqual(LiveSounds.cue(for: .learnt), .lore)
        XCTAssertEqual(LiveSounds.cue(for: .won), .triumph)
        XCTAssertEqual(LiveSounds.cue(for: .lost), .dread)
        XCTAssertEqual(LiveSounds.cue(for: .threat), .dread, "an army set out against the city")
        XCTAssertEqual(LiveSounds.cue(for: .rally), .horn)
        XCTAssertEqual(LiveSounds.cue(for: .gift), .coin)
        let all = LiveTold.allCases.map(LiveSounds.cue)
        XCTAssertEqual(all.count, LiveTold.allCases.count)
        XCTAssertGreaterThanOrEqual(Set(all).count, 11, "nearly every kind of news its own")
    }

    func testOnlyWhatIsToldAfterTheLastHeardIsSounded() {
        let news = [LiveNews(id: 1, words: "The Farm stands at level 3.", at: 10, kind: .raised),
                    LiveNews(id: 2, words: "30 Spearmen of tier 1 are ready.", at: 11, kind: .trained),
                    LiveNews(id: 3, words: "A letter from Bryn.", at: 12, kind: .letter)]
        XCTAssertEqual(LiveSounds.cues(for: news, after: 1), [.muster, .envoy])
        XCTAssertEqual(LiveSounds.cues(for: news, after: nil), [.complete, .muster, .envoy], "the first news of all")
        XCTAssertEqual(LiveSounds.cues(for: news, after: 3), [])
    }

    /// Set from what is heard, and to silence; and a cue played where the
    /// Mac can play one, once however quickly it is asked twice.
    func testTheWorldsBedsAreSetFromWhatIsHeard() {
        var heard = LiveSoundscape()
        heard.town = .init(level: 0.8, pan: -0.2)
        heard.shore = .init(level: 0.3, pan: 0.5)
        heard.din = .init(level: 0.1, pan: -0.6)
        heard.keening = .init(level: 0.5, pan: -0.6)
        heard.host = 0.01
        heard.works = [.granary: 0.5, .musterHall: 0.25, .walls: 0, .forge: 0.25]
        XCTAssertEqual(heard.share(.granary), 0.5)
        XCTAssertEqual(heard.share(.sawpit), 0)
        for enabled in [false, true] {
            let ambience = Ambience(enabled: enabled)
            ambience.start()
            LiveSounds.apply(heard, to: ambience)
            LiveSounds.apply(LiveSoundscape(), to: ambience)
            ambience.play(.select)
            ambience.play(.select)
            ambience.play(.complete)
            ambience.fadeForQuitting()
        }
    }
}
