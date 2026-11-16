import NullmereCore
import NullmereLive
import NullmereLiveStage
import SwiftUI

// The realm's depth on the Mac's screens: the day's work, its chests,
// the items held, favour and the realm's contest; a commander's talents,
// pairing and keeping the city; and an alliance's Moonspire, learning,
// rallies, help, wardstones and gates.

/// What the player may do today: the day's deeds and how far each is
/// along, the chests their marks open, the items they hold, their favour,
/// and the realm's contest.
struct LiveDayPanel: View {
    let session: LiveSession
    let seconds: Double

    var body: some View {
        let world = session.world
        let marks = world.marksToday(at: seconds)
        Text(verbatim: "\(marks) marks today")
            .font(.nm(14, weight: .medium))
            .foregroundStyle(Palette.ink)
        if world.duties.isEmpty {
            LiveSmall(words: "The day's work has not been told of yet.")
        }
        ForEach(world.deedLines(at: seconds)) { deed in
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: deed.words)
                        .font(.nm(12, weight: deed.isDone ? .medium : .regular))
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: 0)
                    LiveSmall(words: deed.isDone ? "Done: \(deed.marks) marks" : "\(LiveWords.grouped(deed.done)) of \(LiveWords.grouped(deed.asks))", dim: !deed.isDone)
                }
                ProgressView(value: deed.progress)
                    .progressViewStyle(.linear)
                    .tint(Palette.glow)
            }
            .accessibilityElement(children: .combine)
        }

        if !world.chests.isEmpty {
            Caps("The day's chests", size: 10)
                .foregroundStyle(Palette.text(0.7))
        }
        ForEach(world.chestLines(at: seconds)) { chest in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "At \(chest.marks) marks")
                        .font(.nm(12, weight: .medium))
                        .foregroundStyle(Palette.ink)
                    LiveSmall(words: chest.holds, dim: true)
                }
                Spacer(minLength: 0)
                if chest.opened {
                    LiveSmall(words: "Opened", dim: true)
                } else {
                    QuietButton(title: "Open", prominent: chest.ready, enabled: chest.ready && session.asking == 0, name: "Open the chest at \(chest.marks) marks", why: chest.ready ? nil : "It opens at \(chest.marks) marks.") { Task { await session.openChest(chest.id) } }
                }
            }
        }

        let held = world.heldItems.map { $0.ware }
        Caps("Your satchel", size: 10)
            .foregroundStyle(Palette.text(0.7))
        if held.isEmpty {
            LiveSmall(words: "Nothing yet. The day's chests hold hastes.", dim: true)
        }
        let work = world.jobs.first
        ForEach(held) { ware in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: "\(ware.name) ×\(world.satchel[ware.item] ?? 0)")
                    .font(.nm(12))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 0)
                QuietButton(title: "Use", enabled: work != nil && session.asking == 0, name: "Use \(ware.name)", why: work == nil ? "No work is under way in your city." : nil) { Task { await session.useItem(ware.item, on: work?.id ?? 0) } }
            }
        }

        if let favour = world.favour {
            LiveSmall(words: "Favour: level \(favour.level), \(LiveWords.grouped(favour.points)) points.")
        }

        ForEach(world.trials.values.sorted { $0.id < $1.id }) { trial in
            let tally = world.tallies.filter { $0.trial == trial.id }.max { $0.round < $1.round }
            VStack(alignment: .leading, spacing: 3) {
                Caps(trial.name, size: 10)
                    .foregroundStyle(Palette.text(0.7))
                LiveSmall(words: trial.words)
                LiveSmall(words: "Your points: \(LiveWords.grouped(tally?.points ?? 0)).", dim: true)
                ForEach(world.prizes.filter { $0.trial == trial.id }) { prize in
                    let reached = (tally?.points ?? 0) >= prize.points
                    let claimed = tally?.hasClaimed(prize.place) ?? false
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        LiveSmall(words: "At \(LiveWords.grouped(prize.points)): \(world.holdings(prize.goods, prize.hastes))")
                        Spacer(minLength: 0)
                        if claimed {
                            LiveSmall(words: "Claimed", dim: true)
                        } else {
                            QuietButton(title: "Claim", prominent: reached, enabled: reached && session.asking == 0, name: "Claim the prize at \(prize.points) points") { Task { await session.claimPrize(contest: trial.id, place: prize.place) } }
                        }
                    }
                }
            }
        }
    }
}

/// A commander's talents, whom they go out beside, and whether they keep
/// the city; with ways to change each.
struct LiveTalents: View {
    let session: LiveSession
    let commander: LiveCommander

    var body: some View {
        let world = session.world
        if let held = world.held(commander.id) {
            let captor = world.shownName(of: held.captor) ?? "Someone"
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                LiveSmall(words: "Held by \(captor). Ransom: \(held.ransom.words).")
                Spacer(minLength: 0)
                QuietButton(title: "Ransom", prominent: true, enabled: session.asking == 0, name: "Ransom \(commander.name)") { Task { await session.ransom(commander: commander.id) } }
            }
        } else {
            LiveTalentControls(session: session, commander: commander)
        }
    }
}

/// What a free commander may be set to: talents to learn or forget, a
/// partner to go out beside, and the city to keep.
struct LiveTalentControls: View {
    let session: LiveSession
    let commander: LiveCommander

    var body: some View {
        let world = session.world
        let lines = world.talentLines(of: commander)
        let learnt = lines.filter { $0.points > 0 }.map { "\($0.name) \($0.points)" }
        let left = world.talentPointsLeft(of: commander)
        let others = world.commanders.filter { $0.id != commander.id }
        let partner: String? = world.bonds[commander.id].flatMap { id in others.first { $0.id == id }?.name }
        LiveSmall(words: (learnt.isEmpty ? "No talents learnt" : "Talents: " + learnt.joined(separator: ", ")) + ". \(left) point\(left == 1 ? "" : "s") to spend.", dim: true)
        HStack(spacing: 6) {
            if left > 0 {
                Menu("Learn") {
                    ForEach(lines.filter(\.canLearn)) { talent in
                        Button(talent.name) { Task { await session.learnTalent(commander: commander.id, talent: talent.id) } }
                    }
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .fixedSize()
                .font(.nm(10))
            }
            if !learnt.isEmpty {
                QuietButton(title: "Forget", enabled: session.asking == 0, name: "Have \(commander.name) forget every talent") { Task { await session.forgetTalents(commander: commander.id) } }
            }
            if !others.isEmpty {
                Menu(partner.map { "Beside: \($0)" } ?? "Pair") {
                    ForEach(others) { other in
                        Button(other.name) { Task { await session.pair(commander: commander.id, with: other.id) } }
                    }
                    Button("No one") { Task { await session.pair(commander: commander.id, with: 0) } }
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .fixedSize()
                .font(.nm(10))
            }
            if world.keeper == commander.id {
                LiveSmall(words: "Keeps the city", dim: false)
            } else {
                QuietButton(title: "Keep the city", enabled: session.asking == 0, name: "Have \(commander.name) keep the city") { Task { await session.keepCity(commander: commander.id) } }
            }
        }
    }
}

/// What the player's alliance does together: its Moonspire, its learning,
/// its rallies, the help asked of it, its wardstones and the gates it holds.
struct LiveAllianceDepth: View {
    let session: LiveSession
    let seconds: Double

    /// What one gift gives: ten thousand of each good asked.
    static let gift = LiveGoods(grain: 10_000, timber: 10_000, stone: 10_000)

    var body: some View {
        let world = session.world
        if let alliance = world.myMembership?.alliance {
            let spire = world.mySpire
            let stage = spire?.stage ?? 0
            Caps("The Moonspire", size: 10)
                .foregroundStyle(Palette.text(0.7))
            if let season = world.season {
                let won = season.victor == 0 ? "" : " Won by \(season.victorName)."
                LiveSmall(words: "Season \(season.number): \(LiveWords.spoken(season.left(at: seconds))) left.\(won)", dim: true)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: "Stage \(stage) of \(LiveSpire.stages)")
                    .font(.nm(12, weight: .medium))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 0)
                if stage < LiveSpire.stages, (spire?.risesAt ?? 0) == 0 {
                    QuietButton(title: "Give", enabled: session.asking == 0, name: "Give to the Moonspire", why: nil) { Task { await session.giveToSpire(LiveAllianceDepth.gift) } }
                }
            }
            if let spire, spire.risesAt > 0 {
                LiveSmall(words: "The next stage stands in \(LiveWords.spoken(max(spire.risesAt - Int(seconds), 0))).")
            } else if stage < LiveSpire.stages {
                LiveSmall(words: "Given toward the next: \((spire?.given ?? LiveGoods()).words), of \(LiveSpire.cost(stage: stage + 1).words).", dim: true)
            }

            let learning = world.learningLines()
            if !learning.isEmpty {
                Caps("Learning together", size: 10)
                    .foregroundStyle(Palette.text(0.7))
            }
            ForEach(learning) { line in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: "\(line.name), level \(line.level) of \(LiveLearning.topLevel)")
                            .font(.nm(12))
                            .foregroundStyle(Palette.ink)
                        Spacer(minLength: 0)
                        if line.cost != nil, line.risesAt == 0 {
                            QuietButton(title: "Give", enabled: session.asking == 0, name: "Give toward \(line.name)") { Task { await session.giveToLearning(topic: line.id, LiveAllianceDepth.gift) } }
                        }
                    }
                    if line.risesAt > 0 {
                        LiveSmall(words: "Learnt in \(LiveWords.spoken(max(line.risesAt - Int(seconds), 0))).", dim: true)
                    } else if let cost = line.cost {
                        LiveSmall(words: "Given \(line.given.words) of \(cost.words).", dim: true)
                    }
                }
            }

            Caps("Rallies", size: 10)
                .foregroundStyle(Palette.text(0.7))
            if world.rallies.isEmpty {
                LiveSmall(words: "None called. A rally is called from a barrow, a city or a gate on the map.", dim: true)
            }
            let mine = world.myRally?.id
            ForEach(world.rallies) { rally in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    LiveSmall(words: world.rallyWords(rally, at: seconds))
                    Spacer(minLength: 0)
                    if rally.state == LiveRally.mustering, mine == nil {
                        QuietButton(title: "Join", prominent: true, enabled: session.asking == 0, name: "Join \(rally.name)'s rally") { Task { await session.joinRally(rally.id) } }
                    } else if mine == rally.id {
                        LiveSmall(words: "Your army is in it", dim: true)
                    }
                }
            }

            let pleas = world.pleasToHelp
            Caps("Help", size: 10)
                .foregroundStyle(Palette.text(0.7))
            ForEach(pleas) { plea in
                LiveSmall(words: world.pleaWords(plea))
            }
            HStack(spacing: 8) {
                LiveSmall(words: pleas.isEmpty ? "No ally is waiting on your help." : "\(pleas.count) waiting on your help.", dim: pleas.isEmpty)
                Spacer(minLength: 0)
                QuietButton(title: "Help all", prominent: !pleas.isEmpty, enabled: !pleas.isEmpty && session.asking == 0) { Task { await session.helpAll() } }
            }
            let asked = Set(world.pleas.map(\.job))
            ForEach(world.jobs.filter { !asked.contains($0.id) }) { job in
                HStack(spacing: 8) {
                    LiveSmall(words: "Work under way in your city, ending in \(LiveWords.spoken(max(job.ends - Int(seconds), 0))).", dim: true)
                    Spacer(minLength: 0)
                    QuietButton(title: "Ask help", enabled: session.asking == 0) { Task { await session.askHelp(job: job.id) } }
                }
            }

            let wards = world.wardstones(of: alliance)
            let gates = world.gatesHeld(by: alliance)
            Caps("Land", size: 10)
                .foregroundStyle(Palette.text(0.7))
            let raised = wards.count == 1 ? "1 wardstone raised." : "\(wards.count) wardstones raised."
            let held = gates.count == 1 ? "1 gate of the ridge held" : "\(gates.count) gates of the ridge held"
            LiveSmall(words: gates.isEmpty ? "\(raised) No gate of the ridge held." : "\(raised) \(held): the lake country is open to you.")
            LiveDiplomacy(session: session, seconds: seconds, alliance: alliance)
            LivePetitions(session: session, seconds: seconds)
        }
        let captives = world.captives
        if !captives.isEmpty {
            Caps("Your prisoners", size: 10)
                .foregroundStyle(Palette.text(0.7))
        }
        ForEach(captives) { prisoner in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                LiveSmall(words: "\(prisoner.name), of \(world.shownName(of: prisoner.owner) ?? "another"); free in \(LiveWords.spoken(max(prisoner.freedAt - Int(seconds), 0))).")
                Spacer(minLength: 0)
                QuietButton(title: "Let go", enabled: session.asking == 0, name: "Let \(prisoner.name) go") { Task { await session.releasePrisoner(commander: prisoner.commander) } }
            }
        }
    }
}

/// The player's alliance's pacts and envoys: those that hold, those come
/// waiting on an answer, and for an officer a way to offer another
/// alliance a truce or passage.
struct LiveDiplomacy: View {
    let session: LiveSession
    let seconds: Double
    let alliance: UInt64

    /// How many days an offer from these screens is for.
    static let days = 7

    var body: some View {
        let world = session.world
        let officer = world.isOfficer
        Caps("Pacts", size: 10)
            .foregroundStyle(Palette.text(0.7))
        let pacts = world.pacts(of: alliance, at: seconds)
        if pacts.isEmpty {
            LiveSmall(words: "No pact holds with any alliance.", dim: true)
        }
        ForEach(pacts) { pact in
            let other = world.alliances[pact.other(than: alliance)].map { "[\($0.tag)] \($0.name)" } ?? "another alliance"
            let what = pact.terms == LivePact.truce ? "A truce with \(other)" : "Passage with \(other)"
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                LiveSmall(words: "\(what), for \(LiveWords.spoken(max(pact.ends - Int(seconds), 0))) more.")
                Spacer(minLength: 0)
                if officer {
                    QuietButton(title: "Break", enabled: session.asking == 0, name: "Break the pact with \(other)") { Task { await session.breakPact(pact.id) } }
                }
            }
        }
        ForEach(world.envoysWaiting(at: seconds)) { envoy in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                LiveSmall(words: "An envoy of \(envoy.name) offers \(envoy.words).")
                Spacer(minLength: 0)
                if officer {
                    QuietButton(title: "Accept", prominent: true, enabled: session.asking == 0, name: "Accept the envoy of \(envoy.name)") { Task { await session.answerEnvoy(envoy.id, accept: true) } }
                    QuietButton(title: "Turn away", enabled: session.asking == 0, name: "Turn away the envoy of \(envoy.name)") { Task { await session.answerEnvoy(envoy.id, accept: false) } }
                }
            }
        }
        if officer {
            let others = world.alliances.values.filter { $0.id != alliance }.sorted { $0.id < $1.id }
            ForEach(others) { other in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    LiveSmall(words: "[\(other.tag)] \(other.name)", dim: true)
                    Spacer(minLength: 0)
                    QuietButton(title: "Offer a truce", enabled: session.asking == 0, name: "Offer [\(other.tag)] a truce of a week") { Task { await session.sendEnvoy(to: other.id, terms: LivePact.truce, days: LiveDiplomacy.days) } }
                    QuietButton(title: "Offer passage", enabled: session.asking == 0, name: "Offer [\(other.tag)] passage for a week") { Task { await session.sendEnvoy(to: other.id, terms: LivePact.passage, days: LiveDiplomacy.days) } }
                }
            }
        }
    }
}

/// The petitions of the player's alliance: those standing, with a way to
/// send what each still asks, and the player's own, to make or withdraw.
struct LivePetitions: View {
    let session: LiveSession
    let seconds: Double

    /// What a petition from these screens asks: fifty thousand of each of
    /// grain, timber and stone.
    static let asked = LiveGoods(grain: 50_000, timber: 50_000, stone: 50_000)

    var body: some View {
        let world = session.world
        let standing = world.petitionsStanding(at: seconds)
        let mine = standing.first { $0.asker == world.me?.id }
        Caps("Petitions", size: 10)
            .foregroundStyle(Palette.text(0.7))
        ForEach(standing.filter { $0.asker != world.me?.id }) { petition in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                LiveSmall(words: "\(petition.name) asks for \(petition.still.words).")
                Spacer(minLength: 0)
                QuietButton(title: "Send", enabled: session.asking == 0, name: "Send \(petition.name) what they ask", why: nil) { Task { await session.answerPetition(of: petition.asker, petition.still) } }
            }
        }
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let mine {
                LiveSmall(words: "Yours asks for \(mine.still.words) more; a tenth of what allies send is lost on the road.", dim: true)
                Spacer(minLength: 0)
                QuietButton(title: "Withdraw", enabled: session.asking == 0, name: "Withdraw your petition") { Task { await session.withdrawPetition() } }
            } else {
                LiveSmall(words: "Ask your alliance for \(LivePetitions.asked.words).", dim: true)
                Spacer(minLength: 0)
                QuietButton(title: "Petition", enabled: session.asking == 0, name: "Petition your alliance") { Task { await session.petition(LivePetitions.asked) } }
            }
        }
    }
}
