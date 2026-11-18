import Foundation
import FoundationModels
import NullmereLive
import NullmereLiveStage
import Observation

/// What a commander's looks and deeds put forward are made of, shared by
/// the tools the model calls and the session that shows them: the counsel
/// as it stood when last renewed, and what was looked at and put forward
/// since the session last took them. An actor, for the model calls its
/// tools away from the main thread.
actor LiveCounselBench {
    private(set) var counsel: LiveCounsel
    private var looked: [String] = []
    private var deeds: [LiveCommand] = []
    /// The words of every look taken while the counsel lasts, which the
    /// commander holds as told.
    private var seen: [String] = []

    init(_ counsel: LiveCounsel) {
        self.counsel = counsel
    }

    /// The realm as it stands now, as the player acts on it.
    func renew(_ counsel: LiveCounsel) {
        self.counsel = counsel
    }

    /// One look: at the city, the armies out, the alliance, the realm or
    /// the commander themself.
    func look(at asked: String) -> String {
        let sight = LiveCounsel.Sight(asked: asked)
        let words = counsel.look(sight)
        looked.append(sight.label)
        seen.append(words)
        return words
    }

    /// The numbers in an answer that nothing the commander was told,
    /// looked at or heard holds.
    func strays(in answer: String, heard: [String]) -> [String] {
        counsel.strayNumbers(in: answer, looks: seen + heard)
    }

    /// A deed put forward in words: put to the player where it is one that
    /// can be done now; the commander told either way.
    func propose(_ words: String) -> String {
        let proposal = counsel.propose(words)
        if let command = proposal.command, !deeds.contains(command) {
            deeds.append(command)
        }
        return proposal.answer
    }

    /// What was looked at and put forward since last asked; forgotten here.
    func taken() -> (looks: [String], deeds: [LiveCommand]) {
        defer {
            looked.removeAll()
            deeds.removeAll()
        }
        return (looked, deeds)
    }
}

/// A look the commander may take.
struct LiveCounselLook: Tool {
    let bench: LiveCounselBench
    let name = "look"
    let description = "Tells what you see of one thing: your lord's city, the armies out, the alliance, the realm, or yourself."

    @Generable
    struct Arguments {
        // Held to the five sights: the model can ask for no other.
        @Guide(description: "What to look at: city, armies, alliance, realm or yourself", .anyOf(["city", "armies", "alliance", "realm", "yourself"]))
        var at: String
    }

    func call(arguments: Arguments) async throws -> String {
        await bench.look(at: arguments.at)
    }
}

/// The one way the commander puts a deed to the player.
struct LiveCounselProposal: Tool {
    let bench: LiveCounselBench
    let name = "proposeADeed"
    let description = "Puts a deed to your lord, who decides: one of the deeds you were told can be done now, in its words."

    @Generable
    struct Arguments {
        @Guide(description: "The deed, in the words you were told it can be done by")
        var deed: String
    }

    func call(arguments: Arguments) async throws -> String {
        await bench.propose(arguments.deed)
    }
}

/// Counsel with one of the player's commanders in the rebuilt realm,
/// spoken by Apple's on-device model on this Mac and nowhere else: a
/// conversation the model holds while it lasts, grounded on the realm's
/// rows (`LiveCounsel`), with looks it may take and deeds it may only put
/// forward, each shown for the player to do or leave. Where the model
/// can't be asked, that is said plainly, and nothing is answered for it.
@MainActor
@Observable
final class LiveCounselSession {
    /// A line of the counsel, as it is shown.
    struct Line: Identifiable, Equatable {
        enum Kind: Equatable {
            case lord, commander, look, deed, trouble
        }

        let id: Int
        let kind: Kind
        let text: String
        /// For a deed put forward, the command that does it.
        let command: LiveCommand?
    }

    let commander: UInt64
    let name: String
    private(set) var lines: [Line] = []
    private(set) var answering = false
    /// What the model's tools look at and put forward through; a stand-in
    /// for the model in a test takes them too.
    nonisolated let bench: LiveCounselBench
    private var made = 0
    private var model: LanguageModelSession?
    /// What the model was told as the counsel began, and every word the
    /// player has said in it: what a number in an answer may come from.
    private var told: [String] = []
    private var heard: [String] = []
    /// Whether the model can be asked, and for a test a stand-in for it.
    private let availability: () -> SystemLanguageModel.Availability
    private let speaker: ((String) async throws -> String)?

    init(counsel: LiveCounsel, availability: (() -> SystemLanguageModel.Availability)? = nil, speaker: ((String) async throws -> String)? = nil) {
        commander = counsel.commander.id
        name = counsel.commander.name
        bench = LiveCounselBench(counsel)
        self.availability = availability ?? { SystemLanguageModel.default.availability }
        self.speaker = speaker
    }

    /// Why counsel can't be taken now, in words; nil where it can.
    var unavailable: String? {
        if speaker != nil { return nil }
        switch availability() {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "This Mac can't run Apple's on-device model, so your commanders can't take counsel here. Everything else plays as ever."
            case .appleIntelligenceNotEnabled:
                return "Apple Intelligence is turned off in System Settings, so your commanders can't take counsel until it is turned on."
            case .modelNotReady:
                return "Apple's on-device model is still downloading or preparing. Your commanders can take counsel once it is ready."
            @unknown default:
                return "Apple's on-device model can't be asked on this Mac now."
            }
        }
    }

    /// The realm as it stands now, for the next question.
    func renew(_ counsel: LiveCounsel) {
        Task { await bench.renew(counsel) }
    }

    private func add(_ kind: Line.Kind, _ text: String, command: LiveCommand? = nil) {
        made += 1
        lines.append(Line(id: made, kind: kind, text: text, command: command))
    }

    /// Asks the commander, in the player's own words.
    func ask(_ words: String) {
        let asked = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !asked.isEmpty, !answering else { return }
        if let unavailable {
            add(.trouble, unavailable)
            return
        }
        add(.lord, asked)
        answering = true
        Task { await answer(asked) }
    }

    private func answer(_ asked: String) async {
        defer { answering = false }
        do {
            heard.append(asked)
            var said = try await speak(asked)
            // A number nothing told them is asked after once; one that
            // still stands is shown as not told, never as true.
            var strays = await bench.strays(in: said, heard: told + heard)
            if !strays.isEmpty {
                said = try await speak(LiveCounselSession.recall(strays))
                strays = await bench.strays(in: said, heard: told + heard)
            }
            let taken = await bench.taken()
            for look in taken.looks {
                add(.look, "Looked at \(look)")
            }
            let spoken = said.trimmingCharacters(in: .whitespacesAndNewlines)
            add(.commander, spoken.isEmpty ? "\(name) says nothing." : spoken)
            if !strays.isEmpty {
                add(.trouble, LiveCounselSession.untold(strays, by: name))
            }
            for deed in taken.deeds {
                add(.deed, deed.title, command: deed)
            }
        } catch {
            add(.trouble, LiveCounselSession.trouble(error))
        }
    }

    /// What the model, or its stand-in, says to some words.
    private func speak(_ words: String) async throws -> String {
        if let speaker {
            return try await speaker(words)
        }
        let session = try await modelSession()
        let response = try await session.respond(to: words, options: GenerationOptions(temperature: 0.6, maximumResponseTokens: 220))
        return response.content
    }

    /// What the commander is asked when they named numbers they were not
    /// told.
    nonisolated static func recall(_ strays: [String]) -> String {
        "You named \(strays.joined(separator: ", ")), which you were not told and did not see. Say it again, naming only numbers you were told or saw, or none."
    }

    /// What the player is told of numbers an answer named that nothing
    /// told the commander.
    nonisolated static func untold(_ strays: [String], by name: String) -> String {
        "\(name) was not told \(strays.joined(separator: ", ")) and did not see it. Weigh it before acting on it."
    }

    private func modelSession() async throws -> LanguageModelSession {
        if let model { return model }
        let counsel = await bench.counsel
        told = [counsel.instructions, counsel.briefing]
        let made = LanguageModelSession(model: .default, tools: [LiveCounselLook(bench: bench), LiveCounselProposal(bench: bench)],
                                        instructions: counsel.instructions + "\n\n" + counsel.briefing)
        model = made
        return made
    }

    /// What the player is told of an error from the model or its tools.
    nonisolated static func trouble(_ error: Error) -> String {
        if let error = error as? LanguageModelSession.GenerationError {
            if case .exceededContextWindowSize = error { return "The counsel has run too long to hold. Start it afresh." }
            if case .guardrailViolation = error { return "The commander will not speak of that. Ask another way." }
            if case .refusal = error { return "The commander will not speak of that. Ask another way." }
            if case .rateLimited = error { return "The commander is answering another. Ask again in a moment." }
            if case .concurrentRequests = error { return "The commander is answering another. Ask again in a moment." }
            if case .unsupportedLanguageOrLocale = error { return "The commander can't make out that language here." }
        }
        return "The commander gave no counsel. Ask again in a while."
    }
}
