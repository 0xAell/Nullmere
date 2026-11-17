import NullmereLive
import NullmereLiveStage
import SwiftUI

/// The phone's one screen, by where the session stands: reaching the
/// realm, a code from the player's Mac wanted, or their realm.
struct CompanionView: View {
    let session: LiveSession
    /// Whether a code given at launch has been taken.
    @State private var tried = false

    var body: some View {
        NavigationStack {
            Group {
                switch session.phase {
                case .opening:
                    ProgressView("Reaching the realm")
                case .lost:
                    VStack(spacing: 12) {
                        Text("The realm can't be reached.")
                        Button("Try again") { Task { await session.open() } }
                    }
                case .naming:
                    CompanionLink(session: session)
                case .playing:
                    CompanionHome(session: session)
                }
            }
            .navigationTitle("Nullmere")
        }
        .task(id: session.phase) {
            #if DEBUG
            // A debug build launched with NULLMERE_LINK_CODE takes it as
            // typed while it plays as no one: how CI brings the phone in.
            if session.phase == .naming, !tried, let code = ProcessInfo.processInfo.environment["NULLMERE_LINK_CODE"], !code.isEmpty {
                tried = true
                await session.takeLink(code)
            }
            #endif
        }
    }
}

/// A phone that plays as no one yet: the ten letters the player's Mac
/// shows bring it in as them.
struct CompanionLink: View {
    let session: LiveSession
    @State private var code = ""

    var body: some View {
        Form {
            Section {
                Text("On your Mac, open House, then Today, and choose Link a phone. Type the ten letters it shows.")
                TextField("Code", text: $code)
                    .font(.system(.title2, design: .monospaced))
                    #if os(iOS)
                    .textInputAutocapitalization(.characters)
                    #endif
                    .autocorrectionDisabled()
                Button("Link this phone") { Task { await session.takeLink(code) } }
                    .disabled(code.filter { $0.isLetter || $0.isNumber }.count != 10 || session.asking > 0)
            }
            if let said = session.said {
                Section { Text(verbatim: said).foregroundStyle(.red) }
            }
        }
    }
}

/// The player's realm as the phone shows it: their city and its stores,
/// the task in hand, what stands idle, what threatens them, their armies
/// out and the day's chests; and the few things a phone does about them.
struct CompanionHome: View {
    let session: LiveSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let seconds = session.now
            let world = session.world
            List {
                if let city = world.city {
                    Section("Your city") {
                        Text(verbatim: "\(city.name), Keep \(city.keep), power \(LiveWords.grouped(city.power))")
                        if let stock = world.stock {
                            Text(verbatim: stock.goods(at: seconds).words)
                        }
                    }
                }
                let threats = world.threats(at: seconds)
                if !threats.isEmpty {
                    Section("Threats") {
                        ForEach(threats) { threat in
                            Text(verbatim: threat.words).foregroundStyle(.red)
                        }
                    }
                }
                if let task = world.task {
                    Section("The task in hand") {
                        Text(verbatim: task.words)
                        Text(verbatim: "Gives \(world.holdings(task.gives, task.items)).").foregroundStyle(.secondary)
                        Button("Claim") { Task { await session.claimTask() } }
                            .disabled(!world.isDone(task) || session.asking > 0)
                    }
                }
                // The city's buildings, each with its level and a way to raise
                // it, or how long the work on it has left; then those it
                // could build now. The builders at work said once.
                let buildings = world.buildingLines(at: seconds).filter { $0.building != nil || $0.block == nil }
                if !buildings.isEmpty {
                    Section("Buildings") {
                        if buildings.contains(where: { $0.block == .buildersBusy }) {
                            Text(verbatim: LiveBlock.buildersBusy.words).font(.footnote).foregroundStyle(.secondary)
                        }
                        ForEach(buildings) { line in
                            CompanionBuilding(session: session, line: line, seconds: seconds)
                        }
                    }
                }
                // Each training ground: its batch in training and how long it
                // has left, or the highest tier it can train now, as many as a
                // batch holds and the stores pay for.
                let training = world.trainLines(at: seconds)
                if !training.isEmpty {
                    Section("Training") {
                        ForEach(training) { line in
                            CompanionTraining(session: session, line: line, seconds: seconds)
                        }
                    }
                }
                // The Academy: the topic it studies and how long it has left, or
                // each it could take up now, with a way to.
                let studies = world.studyLines(at: seconds).filter { $0.job != nil || ($0.block == nil && $0.next != nil) }
                if !studies.isEmpty {
                    Section("Studies") {
                        ForEach(studies) { line in
                            CompanionStudy(session: session, line: line, seconds: seconds)
                        }
                    }
                }
                let idle = world.idle(at: seconds)
                if !idle.isEmpty {
                    Section("Standing idle") {
                        ForEach(idle) { item in Text(verbatim: item.words) }
                    }
                }
                let armies = world.marchLines()
                if !armies.isEmpty {
                    Section("Armies out") {
                        ForEach(armies) { line in
                            Text(verbatim: "\(line.doing), \(LiveWords.grouped(line.soldiers)) soldiers")
                        }
                    }
                }
                let chests = world.chestLines(at: seconds)
                if !chests.isEmpty {
                    Section("The day's chests") {
                        ForEach(chests) { chest in
                            HStack {
                                Text(verbatim: "At \(chest.marks) marks: \(chest.holds)")
                                Spacer()
                                if chest.opened {
                                    Text("Opened").foregroundStyle(.secondary)
                                } else {
                                    Button("Open") { Task { await session.openChest(chest.id) } }
                                        .disabled(!chest.ready || session.asking > 0)
                                }
                            }
                        }
                    }
                }
                if let said = session.said {
                    Section { Text(verbatim: said).foregroundStyle(.red) }
                }
            }
        }
    }
}

/// One building of the player's city on the phone: its name and level,
/// and a way to raise it, or how long the work on it has left; why it
/// can't be raised yet beneath.
struct CompanionBuilding: View {
    let session: LiveSession
    let line: LiveBuildingLine
    let seconds: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(verbatim: line.building == nil ? line.name : "\(line.name), level \(line.level)")
                Spacer()
                if let job = line.job {
                    Text(verbatim: LiveWords.clock(Int(job.left(at: seconds).rounded(.up))))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } else if line.next != nil {
                    Button(line.building == nil ? "Build" : "Upgrade") {
                        Task {
                            if let building = line.building {
                                await session.upgrade(building: building.id)
                            } else {
                                await session.build(line.kind)
                            }
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(line.block != nil || session.asking > 0)
                }
            }
            if line.job == nil, let next = line.next, line.block == nil {
                Text(verbatim: "\(next.cost.sentence), \(LiveWords.spoken(next.seconds))").font(.footnote).foregroundStyle(.secondary)
            } else if line.job == nil, let block = line.block, block != .buildersBusy {
                Text(verbatim: block.words).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

/// One training ground of the player's city on the phone: its batch in
/// training, or a way to train the highest tier it can now, as many as a
/// batch holds and the stores pay for; why not beneath.
struct CompanionTraining: View {
    let session: LiveSession
    let line: LiveTrainLine
    let seconds: Double

    var body: some View {
        let world = session.world
        let open = line.tiers.last { $0.block == nil && world.mostTrainable(line, tier: $0.tier, at: seconds) > 0 }
        let tier = open ?? line.tiers.first
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(verbatim: "\(line.name), level \(line.building.level)")
                Spacer()
                if let job = line.job {
                    Text(verbatim: LiveWords.clock(Int(job.left(at: seconds).rounded(.up))))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } else if let tier {
                    let most = world.mostTrainable(line, tier: tier.tier, at: seconds)
                    Button(most > 0 ? "Train \(LiveWords.grouped(most))" : "Train") {
                        Task { await session.train(building: line.building.id, tier: tier.tier, count: most) }
                    }
                    .buttonStyle(.borderless)
                    .disabled(tier.block != nil || most == 0 || session.asking > 0)
                }
            }
            if let job = line.job {
                Text(verbatim: "Training \(LiveWords.grouped(job.amount)) of tier \(job.level)").font(.footnote).foregroundStyle(.secondary)
            } else if let tier {
                Text(verbatim: "\(tier.soldier.name), tier \(tier.tier): \(tier.soldier.cost.words) each").font(.footnote).foregroundStyle(.secondary)
                if let block = tier.block {
                    Text(verbatim: block.words).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// A topic the player's Academy studies, or could take up now, on the
/// phone: its name and level so far, and the time left, or what the next
/// level costs with a way to study it.
struct CompanionStudy: View {
    let session: LiveSession
    let line: LiveStudyLine
    let seconds: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(verbatim: "\(line.name), \(line.soFar)")
                Spacer()
                if let job = line.job {
                    Text(verbatim: LiveWords.clock(Int(job.left(at: seconds).rounded(.up))))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } else {
                    Button("Study") { Task { await session.learn(topic: line.topic) } }
                        .buttonStyle(.borderless)
                        .disabled(line.block != nil || session.asking > 0)
                }
            }
            Text(verbatim: line.words).font(.footnote).foregroundStyle(.secondary)
            if line.job == nil, let next = line.next {
                Text(verbatim: "\(next.cost.sentence), \(LiveWords.spoken(next.seconds))").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
