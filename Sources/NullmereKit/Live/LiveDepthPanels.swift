import NullmereLand
import NullmereLive
import NullmereLiveStage
import SwiftUI

// The realm's depth on the Mac's screens: the day's work, its chests,
// the items held, favour and the realm's contest; a commander's talents,
// pairing and keeping the city; and an alliance's Moonspire, learning,
// rallies, help, wardstones and gates.

/// What the player may do today: the day's deeds and how far each is
/// along, the chests their marks open, the items they hold, and their
/// favour.
struct LiveDayPanel: View {
    let session: LiveSession
    let seconds: Double

    var body: some View {
        let world = session.world
        let marks = world.marksToday(at: seconds)
        Text(verbatim: "\(marks) marks today")
            .font(.nm(LiveType.title, weight: .medium))
            .foregroundStyle(LiveEmphasis.primary)
        if world.duties.isEmpty {
            LiveSmall(words: "The day's work has not been told of yet.")
        }
        ForEach(world.deedLines(at: seconds)) { deed in
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: deed.words)
                        .font(.nm(LiveType.body, weight: deed.isDone ? .medium : .regular))
                        .foregroundStyle(LiveEmphasis.primary)
                    Spacer(minLength: 0)
                    LiveSmall(words: deed.isDone ? "Done: \(deed.marks) marks" : "\(LiveWords.grouped(deed.done)) of \(LiveWords.grouped(deed.asks))", dim: !deed.isDone)
                }
                // A bar of shapes, not AppKit's: its own control stayed a
                // child the row did not own, combined, hidden or ignored
                // (CI runs 1026, 1032 and 1039's audit).
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.line(0.25))
                        Capsule().fill(Palette.glow).frame(width: proxy.size.width * min(max(deed.progress, 0), 1))
                    }
                }
                .frame(height: 4)
            }
            // One element, said whole, as words.
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isStaticText)
            .accessibilityLabel(deed.isDone ? "\(deed.words) Done: \(deed.marks) marks" : "\(deed.words) \(LiveWords.grouped(deed.done)) of \(LiveWords.grouped(deed.asks))")
            .accessibilityValue(deed.isDone ? "Done" : "\(Int((deed.progress * 100).rounded())) percent")
        }

        if !world.chests.isEmpty {
            Caps("The day's chests", size: LiveType.small)
                .foregroundStyle(LiveEmphasis.secondary)
        }
        ForEach(world.chestLines(at: seconds)) { chest in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "At \(chest.marks) marks")
                        .font(.nm(LiveType.body, weight: .medium))
                        .foregroundStyle(LiveEmphasis.primary)
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
        Caps("Your satchel", size: LiveType.small)
            .foregroundStyle(LiveEmphasis.secondary)
        if held.isEmpty {
            LiveSmall(words: "Nothing yet. The day's chests hold hastes, and the last a peace.", dim: true)
        }
        // A haste goes on the soonest work that can still be hastened.
        let work = world.works(at: seconds).first?.job
        ForEach(held) { ware in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: "\(ware.name) ×\(world.satchel[ware.item] ?? 0)")
                    .font(.nm(LiveType.body))
                    .foregroundStyle(LiveEmphasis.primary)
                Spacer(minLength: 0)
                if ware.isMaterial {
                    LiveSmall(words: "For the Forge", dim: true)
                } else if ware.isTome {
                    LiveSmall(words: "Read by a commander", dim: true)
                } else if ware.isPeace {
                    // A peace is kept on the city itself, with no work to hasten.
                    QuietButton(title: "Use", enabled: session.asking == 0, name: "Use \(ware.name)", why: nil) { Task { await session.usePeace(ware.item) } }
                } else {
                    QuietButton(title: "Use", enabled: work != nil && session.asking == 0, name: "Use \(ware.name)", why: work == nil ? "No work is under way in your city." : nil) { Task { await session.useItem(ware.item, on: work?.id ?? 0) } }
                }
            }
        }

        if let favour = world.favour {
            LiveSmall(words: "Favour: level \(favour.level), \(LiveWords.grouped(favour.points)) points.")
        }
    }
}

/// The realm beyond the player's own: its season, the Lord of the Mere
/// and the titles they bestow, and its contests with their prizes.
struct LiveRealmPanel: View {
    let session: LiveSession
    let seconds: Double

    var body: some View {
        let world = session.world
        LiveMere(session: session)
        if world.trials.isEmpty {
            LiveSmall(words: "The realm's contests have not been told of yet.", dim: true)
        }
        ForEach(world.trials.values.sorted { $0.id < $1.id }) { trial in
            let tally = world.tallies.filter { $0.trial == trial.id }.max { $0.round < $1.round }
            VStack(alignment: .leading, spacing: 3) {
                Caps(trial.name, size: LiveType.small)
                    .foregroundStyle(LiveEmphasis.secondary)
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
                LiveStandings(session: session, trial: trial, day: world.today(at: seconds))
            }
        }
    }
}

/// A contest's standings this round, its first three by name, and what
/// the player's place gave when its last round ended, to be claimed.
struct LiveStandings: View {
    let session: LiveSession
    let trial: LiveTrial
    let day: UInt64

    var body: some View {
        let world = session.world
        let first = world.contestRanking(of: trial.id, round: world.contestRound(of: trial, day: day), top: LiveLaurel.places)
        if !first.isEmpty {
            let named = first.enumerated().map { "\(LiveWords.ordinal($0.offset + 1)) \($0.element.name), \(LiveWords.grouped($0.element.amount))" }
            LiveSmall(words: "This round: " + named.joined(separator: "; ") + ".", dim: true)
        }
        if let laurel = world.laurelToClaim(of: trial, day: day) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                LiveSmall(words: "You were \(LiveWords.ordinal(laurel.place)) when its last round ended: \(world.holdings(laurel.goods, laurel.hastes))")
                Spacer(minLength: 0)
                QuietButton(title: "Claim", prominent: true, enabled: session.asking == 0, name: "Claim what your place in \(trial.name) gave") {
                    Task { await session.claimPlace(contest: trial.id) }
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
        // What to choose from, a menu each; then what is done at once: a
        // panel's width holds no more than three in a row.
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
                .font(.nm(LiveType.small))
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
                .font(.nm(LiveType.small))
            }
            // Tomes of war held: read by this commander, one at a time.
            let tomes = world.heldTomes
            if !tomes.isEmpty, commander.level < LiveCommander.topLevel {
                Menu("Read") {
                    ForEach(tomes, id: \.ware.item) { tome in
                        Button("\(tome.ware.name) (\(tome.count) held)") { Task { await session.readTome(commander: commander.id, item: tome.ware.item) } }
                    }
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .fixedSize()
                .font(.nm(LiveType.small))
            }
        }
        HStack(spacing: 6) {
            if !learnt.isEmpty {
                QuietButton(title: "Forget", enabled: session.asking == 0, name: "Have \(commander.name) forget every talent") { Task { await session.forgetTalents(commander: commander.id) } }
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
        // The alliance's gifts waiting, as allies cleared barrows: claimed all at once.
        if !world.boons.isEmpty {
            Caps("Gifts", size: LiveType.small)
                .foregroundStyle(LiveEmphasis.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                LiveSmall(words: "\(world.boons.count) \(world.boons.count == 1 ? "gift" : "gifts") from your alliance: \(world.boonGoods.words).")
                Spacer(minLength: 0)
                QuietButton(title: "Claim", prominent: true, enabled: session.asking == 0, name: "Claim your alliance's gifts") {
                    Task { await session.claimBoons() }
                }
            }
        }
        // Honour, earned helping allies and giving toward what the alliance
        // learns, and what the alliance's stores sell for it.
        let stores = world.storeLines()
        if !stores.isEmpty {
            Caps("The alliance's stores", size: LiveType.small)
                .foregroundStyle(LiveEmphasis.secondary)
            LiveSmall(words: "Your honour: \(LiveWords.grouped(world.honourHeld)). Each help to an ally earns \(LiveHonour.aHelp), up to \(LiveWords.grouped(LiveHonour.fromHelpADay)) a day; giving toward what the alliance learns, one for every thousand goods; a rally that clears a barrow, \(LiveHonour.aRallyLevel) for each of its levels.", dim: true)
            ForEach(stores) { line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    LiveSmall(words: "\(line.ware.name): \(LiveWords.grouped(line.honour)) honour")
                    Spacer(minLength: 0)
                    QuietButton(title: "Buy", enabled: session.asking == 0 && line.block == nil, name: "Buy \(line.ware.name.lowercased())", why: line.block) {
                        Task { await session.buy(item: line.ware.item) }
                    }
                }
            }
        }
        if let alliance = world.myMembership?.alliance {
            let spire = world.mySpire
            let stage = spire?.stage ?? 0
            Caps("The Moonspire", size: LiveType.small)
                .foregroundStyle(LiveEmphasis.secondary)
            if let season = world.season {
                let won = season.victor == 0 ? "" : " Won by \(season.victorName)."
                LiveSmall(words: "Season \(season.number): \(LiveWords.spoken(season.left(at: seconds))) left.\(won)", dim: true)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: "Stage \(stage) of \(LiveSpire.stages)")
                    .font(.nm(LiveType.body, weight: .medium))
                    .foregroundStyle(LiveEmphasis.primary)
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
                Caps("Learning together", size: LiveType.small)
                    .foregroundStyle(LiveEmphasis.secondary)
            }
            ForEach(learning) { line in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: "\(line.name), level \(line.level) of \(LiveLearning.topLevel)")
                            .font(.nm(LiveType.body))
                            .foregroundStyle(LiveEmphasis.primary)
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

            Caps("Rallies", size: LiveType.small)
                .foregroundStyle(LiveEmphasis.secondary)
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
            Caps("Help", size: LiveType.small)
                .foregroundStyle(LiveEmphasis.secondary)
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
            Caps("Land", size: LiveType.small)
                .foregroundStyle(LiveEmphasis.secondary)
            let raised = wards.count == 1 ? "1 wardstone raised." : "\(wards.count) wardstones raised."
            let held = gates.count == 1 ? "1 gate of the ridge held" : "\(gates.count) gates of the ridge held"
            LiveSmall(words: gates.isEmpty ? "\(raised) No gate of the ridge held." : "\(raised) \(held): the lake country is open to you.")
            LiveDiplomacy(session: session, seconds: seconds, alliance: alliance)
            LivePetitions(session: session, seconds: seconds)
        }
        let captives = world.captives
        if !captives.isEmpty {
            Caps("Your prisoners", size: LiveType.small)
                .foregroundStyle(LiveEmphasis.secondary)
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
        Caps("Pacts", size: LiveType.small)
            .foregroundStyle(LiveEmphasis.secondary)
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
        Caps("Petitions", size: LiveType.small)
            .foregroundStyle(LiveEmphasis.secondary)
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

/// The Mere's Lord and the titles they have bestowed; for the Lord, ways
/// to bestow each on a player of the realm and to take one back.
struct LiveMere: View {
    let session: LiveSession

    var body: some View {
        let world = session.world
        Caps("The Mere", size: LiveType.small)
            .foregroundStyle(LiveEmphasis.secondary)
        let lord = world.lord.flatMap { world.shownName(of: $0) }
        LiveSmall(words: lord.map { "The Lord of the Mere is \($0), whose alliance won the last season won." } ?? "No season has been won: the Mere has no Lord.", dim: lord == nil)
        let players = world.players.values.sorted { $0.id < $1.id }
        ForEach(LiveTitle.names.keys.sorted(), id: \.self) { title in
            let named = LiveTitle.names[title]
            let held = world.titles[title]
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: named?.name ?? "A title")
                        .font(.nm(LiveType.body))
                        .foregroundStyle(LiveEmphasis.primary)
                    LiveSmall(words: held.map { "Held by \(world.shownName(of: $0.holder) ?? $0.name)." } ?? (named?.lends ?? ""), dim: held == nil)
                }
                Spacer(minLength: 0)
                if world.isLord {
                    Menu("Bestow") {
                        ForEach(players) { player in
                            Button(player.name) { Task { await session.bestowTitle(title, on: player.id) } }
                        }
                    }
                    .menuStyle(.button)
                    .buttonStyle(.borderless)
                    .fixedSize()
                    .font(.nm(LiveType.small))
                    if held != nil {
                        QuietButton(title: "Take back", enabled: session.asking == 0, name: "Take back \(named?.name ?? "the title")") { Task { await session.takeTitle(title) } }
                    }
                }
            }
        }
    }
}

/// The letters written to the player, to mark read or forget; and a
/// letter to write, to a player of the realm or, for an officer, to the
/// whole alliance.
struct LiveLetters: View {
    let session: LiveSession
    let seconds: Double
    @State private var to: UInt64?
    @State private var words = ""

    var body: some View {
        let world = session.world
        Caps("Letters", size: LiveType.small)
            .foregroundStyle(LiveEmphasis.secondary)
        let received = world.lettersReceived
        if received.isEmpty {
            LiveSmall(words: "No letters yet.", dim: true)
        }
        ForEach(received.prefix(12)) { letter in
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: letter.name)
                        .font(.nm(LiveType.body, weight: letter.read ? .regular : .medium))
                        .foregroundStyle(LiveEmphasis.primary)
                    LiveSmall(words: "\(LiveWords.spoken(max(Int(seconds) - letter.at, 0))) ago", dim: true)
                    Spacer(minLength: 0)
                    if !letter.read {
                        QuietButton(title: "Read", enabled: session.asking == 0, name: "Mark the letter from \(letter.name) read") { Task { await session.readLetter(letter.id) } }
                    }
                    QuietButton(title: "Forget", enabled: session.asking == 0, name: "Forget the letter from \(letter.name)") { Task { await session.forgetLetter(letter.id) } }
                }
                LiveSmall(words: letter.words)
            }
        }
        let others = world.players.values.filter { $0.id != world.me?.id }.sorted { $0.id < $1.id }
        let addressee = to.flatMap { id in others.first { $0.id == id } }
        HStack(spacing: 8) {
            // Whom to write to, once anyone else has joined.
            if others.isEmpty {
                LiveSmall(words: "No one else has joined to write to.", dim: true)
            } else {
                Menu(addressee.map { "To \($0.name)" } ?? "Write to…") {
                    ForEach(others) { player in
                        Button(player.name) { to = player.id }
                    }
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .fixedSize()
                .font(.nm(LiveType.small))
                .accessibilityLabel(addressee.map { "Writing to \($0.name): choose another" } ?? "Choose whom to write to")
            }
            LiveField(prompt: "A letter", text: $words, width: nil, submit: send)
        }
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            if world.isOfficer {
                QuietButton(title: "To the alliance", enabled: !words.isEmpty && session.asking == 0, name: "Send the letter to the whole alliance") { sendToAlliance() }
            }
            QuietButton(title: "Send", prominent: addressee != nil && !words.isEmpty, enabled: addressee != nil && !words.isEmpty && session.asking == 0,
                        name: "Send the letter", why: addressee == nil ? "Choose whom it is to." : nil, action: send)
        }
    }

    private func send() {
        guard let to, !words.isEmpty else { return }
        let words = self.words
        self.words = ""
        Task { await session.sendLetter(to: to, words) }
    }

    private func sendToAlliance() {
        let words = self.words
        self.words = ""
        Task { await session.sendAllianceLetter(words) }
    }
}

/// The Forge: the materials held, each piece it makes with what it takes
/// and a way to make it, and the player's gear, each piece with who wears
/// it and ways to give it to a commander or take it off.
struct LiveForgePanel: View {
    let session: LiveSession
    let seconds: Double

    var body: some View {
        let world = session.world
        LiveSmall(words: "Held: \(LiveWorld.materialWords(world.materials)). The barrows of the Unquiet yield more.")
        ForEach(world.forgeLines(at: seconds)) { line in
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: line.pattern.name)
                        .font(.nm(LiveType.body, weight: .medium))
                        .foregroundStyle(LiveEmphasis.primary)
                    Spacer(minLength: 0)
                    QuietButton(title: "Make", enabled: line.block == nil && session.asking == 0, name: "Make: \(line.pattern.name)", why: line.block?.words) { Task { await session.forge(piece: line.pattern.piece) } }
                }
                LiveSmall(words: line.pattern.words)
                LiveSmall(words: "Takes \(line.takes).", dim: true)
                if let why = line.block {
                    LiveSmall(words: why.words, dim: true)
                }
            }
        }
        Caps("Your gear", size: LiveType.small)
            .foregroundStyle(LiveEmphasis.secondary)
        if world.gear.isEmpty {
            LiveSmall(words: "None made yet.", dim: true)
        }
        ForEach(world.gear) { piece in
            let name = world.patterns[piece.piece]?.name ?? "Gear"
            let wearer = world.commanders.first { $0.id == piece.commander }
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: name)
                        .font(.nm(LiveType.body))
                        .foregroundStyle(LiveEmphasis.primary)
                    Spacer(minLength: 0)
                    if wearer != nil {
                        QuietButton(title: "Take off", enabled: session.asking == 0, name: "Take off the \(name)") { Task { await session.unequip(gear: piece.id) } }
                    }
                }
                LiveSmall(words: wearer.map { "Worn by \($0.name)." } ?? "Worn by no one.", dim: wearer == nil)
                if wearer == nil {
                    HStack(spacing: 2) {
                        ForEach(world.commanders) { commander in
                            QuietButton(title: commander.name, enabled: session.asking == 0, name: "Give the \(name) to \(commander.name)") { Task { await session.equip(gear: piece.id, on: commander.id) } }
                        }
                    }
                }
            }
        }
    }
}

/// The realm's rankings: its most powerful players, the players with the
/// most kill points from battles between cities, and its most powerful
/// alliances; and where the player stands.
struct LiveRankingsPanel: View {
    let session: LiveSession

    var body: some View {
        let world = session.world
        if let place = world.powerPlace {
            LiveSmall(words: "You stand \(LiveWords.ordinal(place)) in power in the realm.")
        }
        board("Power", world.powerRanking(), mine: world.me?.id, none: "No one holds a city yet.")
        board("Kill points", world.killRanking(), mine: world.me?.id, none: "No city has been fought for yet.")
        board("Alliances", world.allianceRanking(), mine: world.myMembership?.alliance, none: "No alliance has been founded yet.")
    }

    private func board(_ title: String, _ ranks: [LiveRank], mine: UInt64?, none: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Caps(title, size: LiveType.small)
                .foregroundStyle(LiveEmphasis.secondary)
            if ranks.isEmpty {
                LiveSmall(words: none, dim: true)
            }
            ForEach(Array(ranks.enumerated()), id: \.element.id) { index, rank in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: "\(index + 1)")
                        .font(.nm(LiveType.small))
                        .foregroundStyle(LiveEmphasis.tertiary)
                        .frame(width: 18, alignment: .trailing)
                    Text(verbatim: rank.name)
                        .font(.nm(LiveType.small, weight: rank.id == mine ? .medium : .regular))
                        .foregroundStyle(rank.id == mine ? LiveEmphasis.primary : LiveEmphasis.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(verbatim: LiveWords.grouped(rank.amount))
                        .font(.nm(LiveType.small))
                        .foregroundStyle(LiveEmphasis.secondary)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

