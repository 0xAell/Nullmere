import NullmereLand
import NullmereLive
import NullmereLiveStage
import SwiftUI

/// The side of the window, given over to the city's buildings, its
/// troops, or the reports, for as long as the player wants it.
struct LiveSidePanel: View {
    /// How wide an open destination stands.
    static let width: CGFloat = 300

    let session: LiveSession
    let seconds: Double
    let panel: LiveGameView.Panel
    let close: () -> Void
    /// Turns to another part of the same destination.
    var choose: (LiveGameView.Panel) -> Void = { _ in }
    /// The tallest it stands, its parts scrolling within.
    var tallest: CGFloat = .infinity

    var body: some View {
        let parts = panel.destination.panels
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Caps(panel.destination.title, size: LiveType.small, weight: .medium)
                    .foregroundStyle(LiveEmphasis.primary)
                Spacer(minLength: 0)
                QuietButton(title: "Close", action: close)
            }
            // A destination of more than one part shows each, the open one
            // marked, in rows that wrap: five parts don't fit in one.
            if parts.count > 1 {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 2, alignment: .leading)], alignment: .leading, spacing: 2) {
                    ForEach(parts, id: \.self) { part in
                        QuietButton(title: part.title, prominent: part == panel, name: "\(part.title), in \(panel.destination.title)") { choose(part) }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("The parts of \(panel.destination.title)")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch panel {
                    case .city: LiveBuildings(session: session, seconds: seconds)
                    case .troops:
                        LiveCommanders(session: session, seconds: seconds)
                        LiveTroops(session: session, seconds: seconds)
                    case .studies: LiveStudies(session: session, seconds: seconds)
                    case .alliance:
                        LiveAlliancePanel(session: session)
                        LiveAllianceDepth(session: session, seconds: seconds)
                    case .chat: LiveChatPanel(session: session)
                    case .reports:
                        LiveLetters(session: session, seconds: seconds)
                        LiveReports(session: session, seconds: seconds)
                    case .day: LiveDayPanel(session: session, seconds: seconds)
                    case .realm: LiveRealmPanel(session: session, seconds: seconds)
                    case .forge: LiveForgePanel(session: session, seconds: seconds)
                    case .rankings: LiveRankingsPanel(session: session)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(width: LiveSidePanel.width)
        .frame(maxHeight: tallest, alignment: .top)
        .panelBackground()
    }
}

/// Small words under a line: what it costs, or why not.
struct LiveSmall: View {
    let words: String
    var dim = false

    var body: some View {
        Text(verbatim: words)
            .font(.nm(LiveType.small))
            .foregroundStyle(dim ? LiveEmphasis.tertiary : LiveEmphasis.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// How far along something is, and how long it has to go.
struct LiveProgress: View {
    let part: Double
    let left: Int

    var body: some View {
        HStack(spacing: 8) {
            ProgressView(value: min(max(part, 0), 1))
                .progressViewStyle(.linear)
                .tint(Palette.glow)
            Text(verbatim: LiveWords.clock(left))
                .font(.nm(LiveType.small, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Palette.glowWords)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(LiveWords.spoken(left)) left")
    }
}

/// Every building of the catalogue: those the city has, with what the
/// next level costs and a way to raise it, then those it could build.
struct LiveBuildings: View {
    let session: LiveSession
    let seconds: Double

    var body: some View {
        let lines = session.world.buildingLines(at: seconds)
        // The builders at work hold back every other building alike: said
        // once over them all, not under each.
        if lines.contains(where: { $0.block == .buildersBusy }) {
            LiveSmall(words: LiveBlock.buildersBusy.words, dim: true)
        }
        ForEach(lines) { line in
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: LiveIcons.building(line.kind))
                        .font(.nm(LiveType.body))
                        .foregroundStyle(line.building == nil ? LiveEmphasis.tertiary : LiveEmphasis.secondary)
                        .frame(width: 18)
                        .accessibilityHidden(true)
                    Text(verbatim: line.name)
                        .font(.nm(LiveType.body, weight: .medium))
                        .foregroundStyle(LiveEmphasis.primary)
                    Text(verbatim: line.building == nil ? "Not built" : "Level \(line.level)")
                        .font(.nm(LiveType.small))
                        .foregroundStyle(LiveEmphasis.tertiary)
                    Spacer(minLength: 0)
                    if line.job == nil, line.next != nil {
                        QuietButton(title: line.building == nil ? "Build" : "Upgrade", prominent: line.block == nil,
                                    enabled: line.block == nil && session.asking == 0,
                                    name: "\(line.building == nil ? "Build" : "Upgrade") \(line.name)", why: line.block?.words) {
                            Task { await session.raise(line) }
                        }
                    }
                }
                if let job = line.job {
                    LiveProgress(part: job.progress(at: seconds), left: Int(job.left(at: seconds).rounded(.up)))
                } else if let next = line.next {
                    LiveSmall(words: "\(next.cost.sentence), \(LiveWords.spoken(next.seconds))")
                    if let block = line.block, block != .buildersBusy {
                        LiveSmall(words: block.words, dim: true)
                    }
                } else if let block = line.block {
                    LiveSmall(words: block.words, dim: true)
                }
            }
            .accessibilityElement(children: .contain)
        }
    }
}

/// Those who lead the city's armies: each with their way of war, their
/// level and where they are, and a way to take on another.
struct LiveCommanders: View {
    let session: LiveSession
    let seconds: Double
    /// Counsel being taken of one of them, if any.
    @State private var counsel: LiveCounselSession?

    var body: some View {
        let world = session.world
        ForEach(world.commanders) { commander in
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: commander.name)
                        .font(.nm(LiveType.body, weight: .medium))
                        .foregroundStyle(LiveEmphasis.primary)
                    Text(verbatim: "\(commander.told(in: world.people).title), level \(commander.level)")
                        .font(.nm(LiveType.small))
                        .foregroundStyle(LiveEmphasis.tertiary)
                    Spacer(minLength: 0)
                    // Held by the realm's word for it, or by the row that says who holds
                    // them, whichever comes first.
                    LiveSmall(words: commander.isHeld || world.held(commander.id) != nil ? "Held prisoner" : (commander.isFree ? "In the city" : "Out with an army"), dim: true)
                    let open = counsel?.commander == commander.id
                    QuietButton(title: open ? "Close" : "Counsel", name: open ? "Close counsel with \(commander.name)" : "Take counsel of \(commander.name)") {
                        if open {
                            counsel = nil
                        } else if let grounded = session.counsel(of: commander.id) {
                            counsel = LiveCounselSession(counsel: grounded)
                        }
                    }
                }
                if let counsel, counsel.commander == commander.id {
                    LiveCounselView(counsel: counsel, session: session)
                }
                LiveSmall(words: commander.wayWords)
                // Their gift, for one of the realm's own, and the sigils
                // toward its next level, with a way to raise it.
                if let gift = commander.told(in: world.people).gift {
                    LiveSmall(words: gift)
                    if commander.gift < 5 {
                        let why = world.giftBlock(of: commander)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            LiveSmall(words: "Sigils: \(commander.sigils); its next level asks \(LiveWorld.giftNeeds(commander.gift)).", dim: why != nil)
                            Spacer(minLength: 0)
                            QuietButton(title: "Raise gift", enabled: why == nil && session.asking == 0, name: "Raise \(commander.name)'s gift", why: why) {
                                Task { await session.raiseGift(commander: commander.id) }
                            }
                        }
                    }
                }
                // What they wear from the Forge, if anything.
                let worn = world.wornGear(of: commander.id).compactMap { world.patterns[$0.piece]?.name }
                if !worn.isEmpty {
                    LiveSmall(words: "Wears \(worn.joined(separator: ", ")).")
                }
                LiveTalents(session: session, commander: commander)
            }
            .accessibilityElement(children: .contain)
        }
        let block = world.hireBlock(at: seconds)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            LiveSmall(words: block?.words ?? "Another commander: \(LiveWorld.hireCost(have: world.commanders.count).words).", dim: block != nil)
            Spacer(minLength: 0)
            QuietButton(title: "Take on", prominent: block == nil, enabled: block == nil && session.asking == 0, name: "Take on another commander",
                        why: block?.words) {
                Task { await session.hire() }
            }
        }
        // The Tavern's summons: free once a day, or with one kept.
        let drawBlock = world.drawBlock(at: seconds)
        let free = world.freeDraws(at: seconds)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            LiveSmall(words: drawBlock ?? (free > 0 ? "The Tavern's summons is free today." : "A summons of the \(world.summonses) you keep."), dim: drawBlock != nil)
            Spacer(minLength: 0)
            QuietButton(title: "Summon", enabled: drawBlock == nil && session.asking == 0, name: "Summon a commander at the Tavern", why: drawBlock) {
                Task { await session.draw() }
            }
        }
        Rectangle()
            .fill(Palette.line(0.12))
            .frame(height: 1)
    }
}

/// Counsel with a commander: what was asked and answered, the looks they
/// took, each deed they put forward with a way to do it, and a place to
/// ask.
struct LiveCounselView: View {
    let counsel: LiveCounselSession
    let session: LiveSession
    @State private var asked = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(counsel.lines) { line in
                switch line.kind {
                case .lord:
                    LiveSmall(words: "You: \(line.text)", dim: true)
                case .commander:
                    Text(verbatim: "\(counsel.name): \(line.text)")
                        .font(.nm(LiveType.body))
                        .foregroundStyle(LiveEmphasis.primary)
                        .fixedSize(horizontal: false, vertical: true)
                case .look:
                    LiveSmall(words: line.text, dim: true)
                case .deed:
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        LiveSmall(words: "Put to you: \(line.text)")
                        Spacer(minLength: 0)
                        if let command = line.command {
                            QuietButton(title: "Do it", prominent: true, enabled: session.asking == 0, name: "Do it: \(line.text)") {
                                Task { await session.perform(command) }
                            }
                        }
                    }
                case .trouble:
                    LiveSmall(words: line.text)
                }
            }
            if counsel.answering {
                LiveSmall(words: "\(counsel.name) is thinking.", dim: true)
            }
            LiveField(prompt: "Ask \(counsel.name)", text: $asked) {
                // Asked of the realm as it stands now.
                if let grounded = session.counsel(of: counsel.commander) {
                    counsel.renew(grounded)
                }
                counsel.ask(asked)
                asked = ""
            }
        }
        .padding(8)
        .panelBackground()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Counsel with \(counsel.name)")
    }
}

/// What the Academy studies: each topic with what the city has of it,
/// what its next level costs, and a way to study it.
struct LiveStudies: View {
    let session: LiveSession
    let seconds: Double

    var body: some View {
        let lines = session.world.studyLines(at: seconds)
        if lines.isEmpty {
            LiveSmall(words: "Nothing to study has been told of yet.")
        }
        ForEach(lines) { line in
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: line.name)
                        .font(.nm(LiveType.body, weight: .medium))
                        .foregroundStyle(LiveEmphasis.primary)
                    Text(verbatim: line.soFar)
                        .font(.nm(LiveType.small))
                        .foregroundStyle(LiveEmphasis.tertiary)
                    Spacer(minLength: 0)
                    if line.job == nil, line.next != nil {
                        QuietButton(title: "Study", prominent: line.block == nil, enabled: line.block == nil && session.asking == 0,
                                    name: "Study \(line.name)", why: line.block?.words) {
                            Task { await session.learn(topic: line.topic) }
                        }
                    }
                }
                LiveSmall(words: line.words)
                if let job = line.job {
                    LiveProgress(part: job.progress(at: seconds), left: Int(job.left(at: seconds).rounded(.up)))
                } else if let next = line.next {
                    LiveSmall(words: "\(next.cost.sentence), \(LiveWords.spoken(next.seconds))", dim: true)
                    if let block = line.block, block != .studying {
                        LiveSmall(words: block.words, dim: true)
                    }
                } else if let block = line.block {
                    LiveSmall(words: block.words, dim: true)
                }
            }
            .accessibilityElement(children: .contain)
        }
    }
}

/// The city's soldiers, what each training building can train, and the
/// wounded to be healed.
struct LiveTroops: View {
    let session: LiveSession
    let seconds: Double

    var body: some View {
        let world = session.world
        let troops = world.troopLines()
        if troops.isEmpty {
            LiveSmall(words: "Your city has no soldiers yet. Build a Barracks to train some.")
        }
        ForEach(troops) { troop in
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: LiveIcons.troop(troop.kind))
                        .font(.nm(LiveType.body))
                        .foregroundStyle(LiveEmphasis.secondary)
                        .frame(width: 18)
                        .accessibilityHidden(true)
                    Text(verbatim: "\(troop.name), tier \(troop.tier)")
                        .font(.nm(LiveType.body, weight: .medium))
                        .foregroundStyle(LiveEmphasis.primary)
                }
                LiveSmall(words: Self.counts(troop))
                if troop.wounded > 0 {
                    QuietButton(title: "Heal \(LiveWords.grouped(troop.wounded))", enabled: session.asking == 0,
                                name: "Heal \(LiveWords.grouped(troop.wounded)) \(troop.name)") {
                        Task { await session.heal(kind: troop.kind, tier: troop.tier, count: troop.wounded) }
                    }
                }
            }
        }
        if let healing = world.jobs.first(where: { $0.kind == LiveJob.heal }) {
            LiveSmall(words: "Healing \(LiveWords.grouped(healing.amount))")
            LiveProgress(part: healing.progress(at: seconds), left: Int(healing.left(at: seconds).rounded(.up)))
        }
        LiveSmall(words: "Room to tend \(LiveWords.grouped(world.roomForWounded)) more wounded.", dim: true)

        ForEach(world.trainLines(at: seconds)) { line in
            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: "\(line.name), level \(line.building.level)")
                    .font(.nm(LiveType.body, weight: .medium))
                    .foregroundStyle(LiveEmphasis.primary)
                if let job = line.job {
                    LiveSmall(words: "Training \(LiveWords.grouped(job.amount)) of tier \(job.level)")
                    LiveProgress(part: job.progress(at: seconds), left: Int(job.left(at: seconds).rounded(.up)))
                } else {
                    ForEach(line.tiers, id: \.tier) { tier in
                        let most = world.mostTrainable(line, tier: tier.tier, at: seconds)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                LiveSmall(words: "Tier \(tier.tier): \(tier.soldier.cost.words) each")
                                if let block = tier.block {
                                    LiveSmall(words: block.words, dim: true)
                                }
                            }
                            Spacer(minLength: 0)
                            QuietButton(title: most > 0 ? "Train \(LiveWords.grouped(most))" : "Train", prominent: tier.block == nil && most > 0,
                                        enabled: tier.block == nil && most > 0 && session.asking == 0,
                                        name: "Train \(LiveWords.grouped(most)) tier \(tier.tier) \(tier.soldier.name)", why: tier.block?.words) {
                                Task { await session.train(building: line.building.id, tier: tier.tier, count: most) }
                            }
                        }
                    }
                    if let raise = world.promotion(line, at: seconds) {
                        let name = line.tiers.first?.soldier.name ?? line.name
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                LiveSmall(words: "Raise tier \(raise.from) to tier \(raise.to): \(raise.each.words) each")
                                if let block = raise.block {
                                    LiveSmall(words: block.words, dim: true)
                                }
                            }
                            Spacer(minLength: 0)
                            QuietButton(title: raise.count > 0 ? "Raise \(LiveWords.grouped(raise.count))" : "Raise", enabled: raise.count > 0 && session.asking == 0,
                                        name: "Raise \(LiveWords.grouped(raise.count)) tier \(raise.from) \(name) to tier \(raise.to)", why: raise.block?.words) {
                                Task { await session.promote(building: line.building.id, from: raise.from, to: raise.to, count: raise.count) }
                            }
                        }
                    }
                }
            }
            .padding(.top, 6)
        }
    }

    /// A troop line's numbers in words: "40 ready, 6 wounded, 20 out".
    static func counts(_ troop: LiveTroopLine) -> String {
        var parts = ["\(LiveWords.grouped(troop.ready)) ready"]
        if troop.wounded > 0 { parts.append("\(LiveWords.grouped(troop.wounded)) wounded") }
        if troop.out > 0 { parts.append("\(LiveWords.grouped(troop.out)) out") }
        return parts.joined(separator: ", ")
    }
}

/// What the player's armies did, the latest first, in the realm's words.
struct LiveReports: View {
    let session: LiveSession
    let seconds: Double

    var body: some View {
        let reports = session.world.reports
        if reports.isEmpty {
            LiveSmall(words: "No reports yet. Send an army against a barrow and what happens is told here.")
        }
        ForEach(reports) { report in
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: report.words)
                    .font(.nm(LiveType.body, weight: report.read ? .regular : .medium))
                    .foregroundStyle(report.read ? LiveEmphasis.secondary : LiveEmphasis.primary)
                    .fixedSize(horizontal: false, vertical: true)
                // How long ago beside what may be done about it where the
                // panel has room for both on one line; above it where not.
                let ago = LiveSmall(words: LiveWords.ago(Int(seconds) - report.at), dim: true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        ago.fixedSize()
                        Spacer(minLength: 0)
                        acts(report)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        ago
                        HStack(spacing: 8) {
                            Spacer(minLength: 0)
                            acts(report)
                        }
                    }
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    /// What may be done about a report: look where it happened, mark it read, throw it away.
    @ViewBuilder
    private func acts(_ report: LiveReport) -> some View {
        QuietButton(title: "Show", name: "Show where this happened") {
            session.go(to: report.hex)
            session.selected = report.hex
        }
        if !report.read {
            QuietButton(title: "Read", enabled: session.asking == 0, name: "Mark this report read") {
                Task { await session.read(report: report.id) }
            }
        }
        QuietButton(title: "Forget", enabled: session.asking == 0, name: "Throw this report away") {
            Task { await session.forget(report: report.id) }
        }
    }
}

/// A line of typing with a rule under it, as the interface takes words.
struct LiveField: View {
    let prompt: String
    @Binding var text: String
    var width: CGFloat?
    let submit: () -> Void

    var body: some View {
        TextField(prompt, text: $text)
            .textFieldStyle(.plain)
            .font(.nm(LiveType.body))
            .foregroundStyle(LiveEmphasis.primary)
            .frame(width: width)
            .padding(.vertical, 4)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Palette.line(0.35)).frame(height: 1)
            }
            .onSubmit(submit)
            .accessibilityLabel(prompt)
    }
}

/// The player's alliance, with its members and those asking to join; and
/// every alliance of the realm, to join one or found another.
struct LiveAlliancePanel: View {
    let session: LiveSession
    @State private var name = ""
    @State private var tag = ""

    var body: some View {
        let world = session.world
        if let mine = world.myAlliance {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: "[\(mine.tag)] \(mine.name)")
                    .font(.nm(LiveType.title, weight: .medium))
                    .foregroundStyle(LiveEmphasis.primary)
                LiveSmall(words: "\(mine.members) of \(LiveWorld.allianceMost) members. \(mine.open ? "Anyone may join." : "Joining is by asking.")")
                if !mine.words.isEmpty {
                    LiveSmall(words: mine.words)
                }
            }
            ForEach(world.roster(of: mine.id)) { member in
                let ranks = world.isLeader && member.player != world.me?.id
                let expels = world.isOfficer && member.rank < (world.myMembership?.rank ?? 0)
                // The member's name and rank, and beneath them what may be
                // done about them: a panel's width holds no more in a row.
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: world.players[member.player]?.name ?? "Someone")
                            .font(.nm(LiveType.body, weight: member.player == world.me?.id ? .medium : .regular))
                            .foregroundStyle(LiveEmphasis.primary)
                        LiveSmall(words: member.title, dim: true)
                        Spacer(minLength: 0)
                    }
                    if ranks || expels {
                        HStack(spacing: 8) {
                            if ranks {
                                QuietButton(title: member.rank == LiveMember.officer ? "Make member" : "Make officer", enabled: session.asking == 0,
                                            name: "Make \(world.players[member.player]?.name ?? "them") \(member.rank == LiveMember.officer ? "a member" : "an officer")") {
                                    Task { await session.setRank(of: member.player, to: member.rank == LiveMember.officer ? LiveMember.member : LiveMember.officer) }
                                }
                            }
                            if expels {
                                QuietButton(title: "Put out", enabled: session.asking == 0, name: "Put \(world.players[member.player]?.name ?? "them") out of the alliance") {
                                    Task { await session.expel(member.player) }
                                }
                            }
                        }
                    }
                }
            }
            if world.isOfficer, !world.applicants.isEmpty {
                Caps("Asking to join", size: LiveType.small)
                    .foregroundStyle(LiveEmphasis.secondary)
                ForEach(world.applicants) { asked in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: asked.name)
                            .font(.nm(LiveType.body))
                            .foregroundStyle(LiveEmphasis.primary)
                        Spacer(minLength: 0)
                        QuietButton(title: "Let in", prominent: true, enabled: session.asking == 0, name: "Let \(asked.name) in") {
                            Task { await session.answer(applicant: asked.player, admit: true) }
                        }
                        QuietButton(title: "Turn away", enabled: session.asking == 0, name: "Turn \(asked.name) away") {
                            Task { await session.answer(applicant: asked.player, admit: false) }
                        }
                    }
                }
            }
            QuietButton(title: "Leave the alliance", enabled: session.asking == 0) {
                Task { await session.leaveAlliance() }
            }
        } else {
            LiveSmall(words: "You are in no alliance. Join one below, or found your own.")
        }

        let others = world.allianceLines().filter { $0.standing != "Your alliance" }
        if !others.isEmpty {
            Caps("Alliances of the realm", size: LiveType.small)
                .foregroundStyle(LiveEmphasis.secondary)
        }
        ForEach(others) { line in
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: "[\(line.alliance.tag)] \(line.alliance.name)")
                        .font(.nm(LiveType.body, weight: .medium))
                        .foregroundStyle(LiveEmphasis.primary)
                    Spacer(minLength: 0)
                    if let offer = line.offer {
                        QuietButton(title: offer, prominent: line.why == nil, enabled: line.why == nil && session.asking == 0,
                                    name: "\(offer): \(line.alliance.name)", why: line.why) {
                            Task { await session.joinAlliance(line.alliance.id) }
                        }
                    }
                }
                LiveSmall(words: "\(line.alliance.members) members\(line.standing.map { ". \($0)." } ?? "")", dim: true)
                if !line.alliance.words.isEmpty {
                    LiveSmall(words: line.alliance.words)
                }
            }
        }

        if world.myAlliance == nil {
            Caps("Found an alliance", size: LiveType.small)
                .foregroundStyle(LiveEmphasis.secondary)
            if let block = world.foundingBlock {
                LiveSmall(words: block, dim: true)
            } else {
                HStack(spacing: 10) {
                    LiveField(prompt: "Its name", text: $name, width: nil, submit: found)
                    LiveField(prompt: "Tag", text: $tag, width: 56, submit: found)
                }
                QuietButton(title: "Found it", prominent: true,
                            enabled: LiveWorld.allianceNameFits(name) && LiveWorld.tagFits(tag) && session.asking == 0,
                            why: "A name of 3 to 20 letters, and a tag of 3 or 4.", action: found)
            }
        }
    }

    private func found() {
        guard LiveWorld.allianceNameFits(name), LiveWorld.tagFits(tag) else { return }
        Task { await session.foundAlliance(name: name, tag: tag) }
    }
}

/// What is being said: in the realm, or within the player's alliance,
/// the latest first, with a line to say something more.
struct LiveChatPanel: View {
    let session: LiveSession
    @State private var within = false
    @State private var words = ""

    var body: some View {
        let world = session.world
        HStack(spacing: 4) {
            QuietButton(title: "Realm", prominent: !within) { within = false }
            QuietButton(title: "Alliance", prominent: within, enabled: world.myAlliance != nil, why: "You are in no alliance.") { within = true }
        }
        HStack(spacing: 8) {
            LiveField(prompt: within ? "Say to your alliance" : "Say to the realm", text: $words, width: nil, submit: say)
            QuietButton(title: "Say", prominent: true, enabled: LiveWorld.sayingFits(words) && session.asking == 0,
                        why: "Something to say, of 200 letters at most.", action: say)
        }
        let lines = world.chatLines(withinAlliance: within && world.myAlliance != nil)
        if lines.isEmpty {
            LiveSmall(words: "Nothing has been said here yet.", dim: true)
        }
        let alliance = within && world.myAlliance != nil
        ForEach(lines.reversed()) { line in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: line.name)
                        .font(.nm(LiveType.small, weight: .medium))
                        .foregroundStyle(line.own ? Palette.glowWords : LiveEmphasis.secondary)
                    Text(verbatim: line.words)
                        .font(.nm(LiveType.body))
                        .foregroundStyle(line.takenAway ? LiveEmphasis.tertiary : LiveEmphasis.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                // Another's words may be reported to the realm's owner, once.
                if line.reportable {
                    if session.hasReported(line: line.id, withinAlliance: alliance) {
                        LiveSmall(words: "Reported", dim: true)
                    } else {
                        QuietButton(title: "Report", enabled: session.asking == 0, name: "Report \(line.name)'s words to the realm's owner") {
                            Task { await session.report(line: line.id, withinAlliance: alliance) }
                        }
                    }
                }
            }
        }
    }

    private func say() {
        guard LiveWorld.sayingFits(words) else { return }
        let saying = words
        words = ""
        Task { await session.say(saying, withinAlliance: within && session.world.myAlliance != nil) }
    }
}
