import NullmereCore
import XCTest
@testable import NullmereKit

final class VoiceTests: XCTestCase {
    func testCleaningKeepsOnlyTheSpokenLine() {
        XCTAssertEqual(OnDeviceVoice.clean("  \"We come in peace, as the water is still.\"\nExtra"), "We come in peace, as the water is still.")
        XCTAssertEqual(OnDeviceVoice.clean("Envoy: The lake remembers!"), "The lake remembers.")
        XCTAssertEqual(OnDeviceVoice.clean("The Chronicler: So it was written."), "So it was written.")
        XCTAssertNil(OnDeviceVoice.clean("  ok "))
        let long = String(repeating: "The water lies black. ", count: 30)
        XCTAssertLessThanOrEqual(OnDeviceVoice.clean(long)!.count, 281)
    }

    func testPromptsCarryTheFactsAndTheTask() {
        let moment = VoiceMoment(kind: .envoy(proposal: .pact), facts: ["The envoy comes from House Venn."])
        XCTAssertTrue(moment.prompt.contains("- The envoy comes from House Venn."))
        XCTAssertTrue(moment.prompt.contains("pact"))
        let line = VoiceMoment(kind: .chronicle(.war), facts: ["War."])
        XCTAssertTrue(line.prompt.contains("chronicler"))
    }

    func testOnlyMomentsTouchingThePlayerAreVoiced() {
        XCTAssertTrue(VoiceFacts.isVoiced(.betrayal))
        XCTAssertFalse(VoiceFacts.isVoiced(.founding))
    }

    /// A ballad as the model gives it, made one the realm would keep: its
    /// title, numbering, quotes and exclamations dropped.
    func testAVerseIsMadeABalladTheRealmWouldKeep() {
        XCTAssertEqual(OnDeviceVoice.verse("The Ballad of the Grey Ford\n1. \"The moon lay on the water!\"\n2) And the walls of Vael fell.\n"),
                       "The moon lay on the water.\nAnd the walls of Vael fell.")
        XCTAssertEqual(OnDeviceVoice.verse("- Forty thousand met at the ford\n- 40 of them were kings"), "Forty thousand met at the ford\n40 of them were kings",
                       "A number that begins a line is kept")
        XCTAssertEqual(OnDeviceVoice.verse("Verse:\nOne\nTwo\nThree\nFour\nFive\nSix\nSeven")?.components(separatedBy: "\n").count,
                       GameState.balladLines.upperBound, "At most six lines kept")
        XCTAssertNil(OnDeviceVoice.verse("Only one line."))
        let moment = VoiceMoment(kind: .ballad, facts: ["A battle at the Grey Ford."])
        XCTAssertTrue(moment.prompt.contains("four lines"))
        XCTAssertTrue(moment.prompt.contains("- A battle at the Grey Ford."))
    }
}
