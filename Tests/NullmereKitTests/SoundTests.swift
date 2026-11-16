import AVFoundation
import NullmereLand
import XCTest
@testable import NullmereKit
@testable import NullmereSound

/// The game's sound on the Mac: the audio engine's buffers hear just what
/// the synthesiser makes, and the ambience plays the score each place asks
/// for. The sound itself, its bed, cues, hall and score, is rendered and
/// measured in NullmereSoundTests, on Linux and on the Mac alike.
final class SoundTests: XCTestCase {
    /// Rendered into the audio engine's buffers, as its source node asks,
    /// the synthesiser sounds just as it does into plain memory; a list of
    /// one buffer is left as it was.
    func testTheEngineHearsWhatTheSynthesiserMakes() {
        func synth() -> Synth {
            let synth = Synth()
            synth.prepare(sampleRate: 48_000)
            synth.settle()
            synth.setMusic(on: true, mood: .war)
            synth.trigger(.clash)
            return synth
        }
        let heard = synth(), made = synth()
        let chunk = 512
        let list = AudioBufferList.allocate(maximumBuffers: 2)
        defer { free(list.unsafeMutablePointer) }
        let left = UnsafeMutablePointer<Float>.allocate(capacity: chunk), right = UnsafeMutablePointer<Float>.allocate(capacity: chunk)
        let plainLeft = UnsafeMutablePointer<Float>.allocate(capacity: chunk), plainRight = UnsafeMutablePointer<Float>.allocate(capacity: chunk)
        defer { [left, right, plainLeft, plainRight].forEach { $0.deallocate() } }
        list[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(chunk * 4), mData: left)
        list[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(chunk * 4), mData: right)
        var loudest: Float = 0
        for _ in 0..<40 {
            heard.render(frames: chunk, into: list)
            made.render(frames: chunk, left: plainLeft, right: plainRight)
            XCTAssertEqual(Array(UnsafeBufferPointer(start: left, count: chunk)), Array(UnsafeBufferPointer(start: plainLeft, count: chunk)))
            XCTAssertEqual(Array(UnsafeBufferPointer(start: right, count: chunk)), Array(UnsafeBufferPointer(start: plainRight, count: chunk)))
            loudest = max(loudest, UnsafeBufferPointer(start: left, count: chunk).map(abs).max() ?? 0)
        }
        XCTAssertGreaterThan(loudest, 0.01, "Heard")

        let one = AudioBufferList.allocate(maximumBuffers: 1)
        defer { free(one.unsafeMutablePointer) }
        one[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(chunk * 4), mData: left)
        left.update(repeating: 7, count: chunk)
        heard.render(frames: chunk, into: one)
        XCTAssertEqual(left[0], 7, "Nothing written to one ear alone")
    }

    /// The ambience plays the title theme while a lake is named for it, war
    /// or not, and the realm's own score once none is.
    @MainActor
    func testTheLauncherPlaysTheLastLakesTheme() {
        let ambience = Ambience(enabled: false)
        XCTAssertEqual(ambience.mood, .peace)
        ambience.isAtWar = true
        XCTAssertEqual(ambience.mood, .war)
        ambience.titleLake = .isles
        XCTAssertEqual(ambience.mood, .title(.isles), "The title theme over the launcher")
        ambience.titleLake = nil
        XCTAssertEqual(ambience.mood, .war)
        ambience.isEclipse = true
        XCTAssertEqual(ambience.mood, .eclipse, "The eaten moon's music over war's")
        ambience.titleLake = .round
        XCTAssertEqual(ambience.mood, .title(.round), "and the title theme over all")
        ambience.titleLake = nil
        ambience.isEclipse = false
        XCTAssertEqual(ambience.mood, .war)
    }

    /// Quitting fades the sound fast and says how long to wait for it: a
    /// hard stop clicks. Nothing to wait for while silent, or already fading.
    @MainActor
    func testQuittingFadesTheSoundFastAndSaysHowLongToWait() async throws {
        let ambience = Ambience(enabled: true)
        XCTAssertEqual(ambience.fadeForQuitting(), 0, "Silent: nothing to wait for")
        ambience.start()
        // Whether this Mac has an output to play on: CI's may not.
        let hasOutput = ambience.isPlaying
        XCTAssertEqual(ambience.fadeForQuitting(), hasOutput ? Ambience.quitFadeSeconds : 0)
        ambience.isEnabled = false
        XCTAssertEqual(ambience.fadeForQuitting(), 0, "Already fading out: nothing more to wait for")
        ambience.stop()
        try await Task.sleep(for: .seconds(Ambience.fadeOutSeconds + 0.6))
        XCTAssertFalse(ambience.isRunning, "Faded out, stopped")
    }
}
