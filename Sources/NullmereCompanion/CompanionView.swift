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
