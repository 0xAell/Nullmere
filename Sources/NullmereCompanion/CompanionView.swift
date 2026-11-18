import CoreGraphics
import NullmereLand
import NullmereLive
import NullmereLiveStage
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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
            // This phone named among the player's devices, once it plays.
            if session.phase == .playing {
                await session.nameDevice(CompanionView.deviceName)
            }
        }
    }

    /// What this device is called among the player's: the kind of device
    /// it is, never its owner's own name for it.
    @MainActor
    static var deviceName: String {
        #if os(iOS)
        return UIDevice.current.model
        #else
        return "Mac"
        #endif
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
                // The whole realm small: its grounds, every city on it, the
                // player's armies, and any marching on their city.
                if let map = session.minimap {
                    Section("The realm") {
                        CompanionChart(session: session, map: map, seconds: seconds)
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
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: line.withSoldiers)
                                    Text(verbatim: LiveWords.clock(line.march.arrives - Int(seconds)))
                                        .font(.footnote).monospacedDigit().foregroundStyle(.secondary)
                                }
                                Spacer()
                                if line.canRecall {
                                    Button("Call home") { Task { await session.recall(march: line.march.id) } }
                                        .buttonStyle(.borderless)
                                        .disabled(session.asking > 0)
                                }
                            }
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
                // Each device that plays as the player, and a way to let
                // another go: a Mac given away, an old phone.
                if world.devices.count > 1 {
                    Section("Your devices") {
                        ForEach(world.devices) { device in
                            HStack {
                                Text(verbatim: device.shown)
                                Text(verbatim: device.current ? "This one" : device.here ? "Here now" : "Away")
                                    .font(.footnote).foregroundStyle(.secondary)
                                Spacer()
                                if !device.current {
                                    Button("Let go") { Task { await session.letGo(device) } }
                                        .buttonStyle(.borderless)
                                        .disabled(session.asking > 0)
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
                        Task { await session.raise(line) }
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

/// The whole realm small on the phone, a pixel to each hex: its grounds
/// as the realm tells them, every city on it (the player's own brightest
/// and largest, an ally's green), the player's armies where they are, and
/// in red any army marching on the player's city.
struct CompanionChart: View {
    let session: LiveSession
    let map: LiveMinimap
    let seconds: Double

    /// Each ground's colour, as the module numbers grounds: deep water,
    /// shallows, strand, salt, plain, wood, heath and mountain (the Mac's
    /// small map's own).
    static let colours: [[UInt8]] = [[13, 31, 51], [31, 77, 97], [178, 166, 128], [217, 214, 204], [92, 133, 71], [46, 82, 46], [115, 107, 77], [128, 128, 133]]

    static func image(of map: LiveMinimap) -> CGImage? {
        var bytes = [UInt8](repeating: 0, count: map.width * map.height * 4)
        for (index, ground) in map.grounds.enumerated() where Int(ground) < colours.count {
            let colour = colours[Int(ground)]
            (bytes[index * 4], bytes[index * 4 + 1], bytes[index * 4 + 2], bytes[index * 4 + 3]) = (colour[0], colour[1], colour[2], 255)
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: map.width, height: map.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: map.width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    var body: some View {
        let world = session.world
        if let image = CompanionChart.image(of: map) {
            ZStack {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.none)
                Canvas { context, size in
                    func spot(_ at: (u: Double, v: Double), _ r: CGFloat) -> Path {
                        Path(ellipseIn: CGRect(x: at.u * size.width - r, y: at.v * size.height - r, width: 2 * r, height: 2 * r))
                    }
                    for city in world.cities.values where city.owner != world.me?.id {
                        let ally = world.isAlly(city.owner)
                        context.fill(spot(map.place(of: city.hex), ally ? 2.5 : 1.5), with: .color(ally ? Color.green : Color(white: 0.8)))
                    }
                    for march in world.marches.values {
                        let at = march.position(at: seconds)
                        let on = HexLayout(size: 1).hex(atX: at.x, y: at.y)
                        let foe = march.owner != world.me?.id && march.to == world.city?.hex
                        if march.owner == world.me?.id || foe {
                            context.fill(spot(map.place(of: LiveHex(q: on.q, r: on.r)), 2.5), with: .color(foe ? Color.red : Color.yellow))
                        }
                    }
                    if let home = world.city {
                        context.fill(spot(map.place(of: home.hex), 4), with: .color(Color.white))
                    }
                }
            }
            .aspectRatio(CGFloat(map.width) / CGFloat(max(map.height, 1)), contentMode: .fit)
            .accessibilityElement()
            .accessibilityLabel("The whole realm, small, with your city on it")
            .accessibilityAddTraits(.isImage)
        }
    }
}
