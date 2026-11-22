import Foundation
import LauncherCore
import LauncherKit
import NullmereLand
import NullmereLive
import NullmereLiveStage
import NullmereModels
import NullmereWorld
import SwiftUI

/// The rebuilt realm, played: the world filling the window, and over it
/// only what the moment needs. Along the top, the city's goods and the
/// task the player is on; at the foot, the player's armies out, the
/// doors to everything else, and a card for whatever is chosen; at the
/// side, when asked for, the city, its troops, its studies, the
/// alliance, what is being said, or the reports.
public struct LiveGameView: View {
    /// What the side of the window is given over to.
    enum Panel: Hashable {
        case city
        case troops
        case studies
        case alliance
        case chat
        case reports
        case day
        case realm
        case forge
        case rankings
        case feats

        var title: String {
            switch self {
            case .city: return "Buildings"
            case .troops: return "Troops"
            case .studies: return "Studies"
            case .alliance: return "Alliance"
            case .chat: return "Chat"
            case .reports: return "Reports"
            case .day: return "Today"
            case .realm: return "The Mere"
            case .forge: return "Forge"
            case .rankings: return "Rankings"
            case .feats: return "Feats"
            }
        }

        /// Which of the four destinations it belongs to.
        var destination: Destination { Destination.allCases.first { $0.panels.contains(self) } ?? .house }

        /// The part the palette names (`LiveSession.parts`).
        init?(part: String) {
            let all: [String: Panel] = ["city": .city, "troops": .troops, "studies": .studies, "forge": .forge, "day": .day, "feats": .feats, "alliance": .alliance,
                                        "realm": .realm, "rankings": .rankings, "chat": .chat, "reports": .reports]
            guard let panel = all[part] else { return nil }
            self = panel
        }
    }

    /// The four places beside the world: the player's House (their city,
    /// troops, studies, the day's work and their feats), their alliance, the realm
    /// (its season, contests, rankings and what is said in it), and their
    /// mail.
    enum Destination: CaseIterable, Hashable {
        case house
        case alliance
        case realm
        case mail

        var title: String {
            switch self {
            case .house: return "House"
            case .alliance: return "Alliance"
            case .realm: return "Realm"
            case .mail: return "Mail"
            }
        }

        /// What it holds, the first opened when it is.
        var panels: [Panel] {
            switch self {
            case .house: return [.city, .troops, .studies, .forge, .day, .feats]
            case .alliance: return [.alliance]
            case .realm: return [.realm, .rankings, .chat]
            case .mail: return [.reports]
            }
        }
    }

    private let session: LiveSession
    /// The launcher's display settings: how much the map moves, its frame
    /// rate and the share of the screen's pixels it is drawn at.
    private let display: LauncherSettings
    /// Back to the launcher, where there is one to go back to.
    private let leave: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var panel: Panel?
    @State private var palette = false
    @State private var cannotDraw = false
    @State private var lighterMap = false

    public init(session: LiveSession, display: LauncherSettings = LauncherSettings(defaults: .standard), leave: (() -> Void)? = nil) {
        self.session = session
        self.display = display
        self.leave = leave
    }

    /// The same, opened at one part of a destination.
    init(session: LiveSession, opening: Panel?, display: LauncherSettings = LauncherSettings(defaults: .standard), leave: (() -> Void)? = nil) {
        self.session = session
        self.display = display
        self.leave = leave
        _panel = State(initialValue: opening)
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch session.phase {
            case .opening:
                LiveNotice(title: "Reaching the realm", words: "One moment.", button: nil, back: leave) {}
            case .lost:
                LiveNotice(title: "The realm can't be reached", words: "Check your connection, then try again.", button: "Try again", back: leave) {
                    Task { await session.open() }
                }
            case .naming, .playing:
                if cannotDraw {
                    LiveNotice(title: "The world can't be drawn",
                               words: "Try drawing the map with lighter settings.",
                               button: "Retry map", back: leave) {
                        lighterMap = true
                        cannotDraw = false
                    }
                } else {
                    let items = session.mapItems()
                    LiveMapView(session: session, motion: display.motion.resolved(systemReducesMotion: reduceMotion),
                                frameRate: lighterMap ? .thirty : display.frameRate,
                                quality: lighterMap ? .efficient : display.quality,
                                onFailure: { cannotDraw = true }, onFaltering: {
                                    if lighterMap {
                                        cannotDraw = true
                                    } else {
                                        lighterMap = true
                                    }
                                })
                        .ignoresSafeArea()
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("The realm's map")
                        // VoiceOver's rotor goes straight to the player's armies, the cities, the barrows or the cairns.
                        .accessibilityRotor("Your armies", entries: items.filter { $0.kind == .ownArmy }, entryID: \.id, entryLabel: \.label)
                        .accessibilityRotor("Cities", entries: items.filter { $0.kind == .home || $0.kind == .city }, entryID: \.id, entryLabel: \.label)
                        .accessibilityRotor("Barrows", entries: items.filter { $0.kind == .barrow }, entryID: \.id, entryLabel: \.label)
                        .accessibilityRotor("Cairns", entries: items.filter { $0.kind == .cairn }, entryID: \.id, entryLabel: \.label)
                        // VoiceOver reads the map as what stands and moves on it, each where it
                        // lies, so its cursor rings it on the map; choosing one chooses it there.
                        .accessibilityChildren {
                            GeometryReader { proxy in
                                // Only what stands within the view: what lies past its
                                // edges is reached by moving the map, as anyone does.
                                let shown = CGRect(origin: .zero, size: proxy.size).insetBy(dx: 22, dy: 22)
                                ForEach(items) { item in
                                    if let point = session.viewPoint(of: item.hex, in: proxy.size), shown.contains(point) {
                                        Button(item.label) { session.selected = item.hex }
                                            .frame(width: 44, height: 44)
                                            .position(point)
                                    }
                                }
                            }
                        }
                }
                if session.phase == .naming {
                    LiveNameCard(session: session)
                } else {
                    LiveHUD(session: session, panel: $panel, palette: $palette, leave: leave)
                }
            }
        }
        // Drawn dark on dark whatever the Mac's appearance: the system's own
        // menus and fields in it take their words' colour from this, and in
        // Light they were dark grey on the panels' black.
        .environment(\.colorScheme, .dark)
        .task {
            await session.open()
            #if DEBUG
            await LiveGameView.rehearse(session, ProcessInfo.processInfo.environment) { panel = $0 }
            #endif
        }
    }

    #if DEBUG
    /// For the smoke test, which can press nothing: joins under the name
    /// NULLMERE_REBUILT_NAME gives where a name is wanted, then shows what
    /// NULLMERE_REBUILT_SHOW names: the city's buildings, its troops, the
    /// reports, the rankings, or the nearest barrow or site chosen. It waits on the
    /// realm for as many tenths of a second as it has patience.
    static func rehearse(_ session: LiveSession, _ environment: [String: String], patience: Int = 150, show: (Panel) -> Void) async {
        func wait(until done: () -> Bool) async {
            for _ in 0..<patience where !done() {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        if let name = environment["NULLMERE_REBUILT_NAME"], !name.isEmpty {
            await wait { session.phase != .opening }
            if session.phase == .naming { await session.join(name: name) }
        }
        guard let what = environment["NULLMERE_REBUILT_SHOW"], !what.isEmpty else { return }
        await wait { session.phase == .playing }
        guard let home = session.world.city?.hex else { return }
        func nearest(_ hexes: [LiveHex]) -> LiveHex? { hexes.min { $0.distance(to: home) < $1.distance(to: home) } }
        switch what {
        case "city":
            session.selected = home
            show(.city)
        case "troops":
            session.selected = home
            show(.troops)
        case "reports":
            show(.reports)
        case "rankings":
            show(.rankings)
        case "barrow":
            if let hex = nearest(session.world.barrows.values.map(\.hex)) {
                session.go(to: hex)
                session.selected = hex
            }
        case "site":
            if let hex = nearest(session.world.sites.values.map(\.hex)) {
                session.go(to: hex)
                session.selected = hex
            }
        default: break
        }
    }
    #endif
}

/// A plain notice in the middle of the window, with one thing to do
/// about it where there is one.
struct LiveNotice: View {
    let title: String
    let words: String
    let button: String?
    /// Back to the launcher, where there is one.
    var back: (() -> Void)?
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Caps(title, size: LiveType.body, weight: .medium, centred: true)
                .foregroundStyle(LiveEmphasis.primary)
            Text(verbatim: words)
                .font(.nm(LiveType.body))
                .foregroundStyle(LiveEmphasis.secondary)
            HStack(spacing: 16) {
                if let back {
                    QuietButton(title: "Back", name: "Back to the launcher", action: back)
                }
                if let button {
                    QuietButton(title: button, prominent: true, action: action)
                }
            }
        }
        .padding(24)
        .panelBackground()
    }
}

/// Asks who the player will be in the realm.
struct LiveNameCard: View {
    let session: LiveSession
    @State private var name = ""
    @FocusState private var focused: Bool

    /// Whether the realm would take the name as it stands: three to
    /// sixteen letters once tidied. The realm has the last word.
    static func fits(_ name: String) -> Bool {
        let tidy = name.split(separator: " ").joined(separator: " ")
        return (3...16).contains(tidy.count)
    }

    var body: some View {
        VStack(spacing: 14) {
            Caps("Your name in the realm", size: LiveType.body, weight: .medium, centred: true)
                .foregroundStyle(LiveEmphasis.primary)
            // Noted for a listening test, to type a name into it as a player would.
            let _ = PressableButtons.noteField("Your name in the realm") { [binding = $name] words in binding.wrappedValue = words }
            TextField("Three to sixteen letters", text: $name)
                .textFieldStyle(.plain)
                .font(.nm(LiveType.title))
                .multilineTextAlignment(.center)
                .foregroundStyle(LiveEmphasis.primary)
                .focused($focused)
                .frame(width: 260)
                .padding(.vertical, 6)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Palette.line(focused ? 0.7 : 0.35)).frame(height: 1)
                }
                .onSubmit(join)
                .accessibilityLabel("Your name in the realm")
            if let said = session.said {
                Text(verbatim: said)
                    .font(.nm(LiveType.body))
                    .foregroundStyle(Palette.bad)
                    .fixedSize(horizontal: false, vertical: true)
            }
            QuietButton(title: "Found your city", prominent: true, enabled: Self.fits(name) && session.asking == 0,
                        why: "A name needs at least 3 letters and at most 16.", action: join)
        }
        .padding(24)
        .frame(width: 340)
        .panelBackground()
        .onAppear { focused = true }
    }

    private func join() {
        guard Self.fits(name) else { return }
        session.said = nil
        Task { await session.join(name: name) }
    }
}

/// What lies over the world while it is played, keeping to its edges so
/// the world keeps the screen (`ChromeBudget`): the top bar and the task
/// at the top left, the armies out and the four destinations at the foot,
/// a card for what is chosen, and an open destination at the top right,
/// no taller than `LiveHUD.panelShare` of the window.
struct LiveHUD: View {
    let session: LiveSession
    @Binding var panel: LiveGameView.Panel?
    /// Whether the palette is open, to search for anything to do.
    @Binding var palette: Bool
    /// Back to the launcher, where there is one.
    var leave: (() -> Void)?

    /// The share of the window's height an open destination stands to.
    static let panelShare: CGFloat = 0.42

    /// The height an open destination stands to in a window of a size.
    private func tallest(in size: CGSize) -> CGFloat {
        max(size.height * LiveHUD.panelShare, ChromeBudget.leastHeight)
    }

    var body: some View {
        // Counted afresh each second: goods grow and timers run down
        // between the realm's own words.
        GeometryReader { proxy in
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let seconds = session.now
                VStack(spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        LiveTopBar(session: session, seconds: seconds)
                            .chrome("live-bar")
                        Spacer(minLength: 0)
                        // The whole realm small, at the top right (an open destination stands over it).
                        LiveMiniMap(session: session)
                            .chrome("live-minimap")
                    }
                    HStack(alignment: .top, spacing: 12) {
                        LiveTaskChip(session: session, panel: $panel)
                            .chrome("live-task")
                        Spacer(minLength: 0)
                    }
                    // What stands idle that could be at work: each opens the part that answers it.
                    let idle = session.world.idle(at: seconds)
                    if !idle.isEmpty {
                        HStack(alignment: .top, spacing: 12) {
                            LiveIdleChips(idle: idle) { part in panel = LiveGameView.Panel(part: part) }
                                .chrome("live-idle")
                            Spacer(minLength: 0)
                        }
                    }
                    if !session.world.threats(at: seconds).isEmpty {
                        HStack(alignment: .top, spacing: 12) {
                            LiveThreats(session: session, seconds: seconds)
                                .chrome("live-threats")
                            Spacer(minLength: 0)
                        }
                    }
                    if let said = session.said {
                        LiveSaid(words: said) { session.said = nil }
                            .chrome("live-said")
                    }
                    Spacer(minLength: 0)
                    HStack(alignment: .bottom, spacing: 12) {
                        LiveArmies(session: session, seconds: seconds)
                            .chrome("live-armies")
                        Spacer(minLength: 0)
                        LiveDock(session: session, panel: $panel, find: { palette.toggle() })
                            .chrome("live-dock")
                    }
                    // What is chosen, where it can't be shown beside it on the map.
                    if let selection = session.selection, LiveRing.place(of: session, in: proxy.size) == nil {
                        LiveCardView(session: session, card: session.card(for: selection), panel: $panel)
                            .chrome("live-card")
                    }
                }
                // An open destination stands over the world at the top right,
                // so the dock and the armies keep their places at the foot.
                .overlay(alignment: .topTrailing) {
                    if let panel {
                        LiveSidePanel(session: session, seconds: seconds, panel: panel, close: { self.panel = nil }, choose: { self.panel = $0 },
                                      tallest: tallest(in: proxy.size))
                            .chrome("live-panel")
                    }
                }
                .padding(12)
                // Over each city in view, whose it is and its Keep's level: beneath the
                // interface, and never in the way of a click on the map.
                .background {
                    // What the ring about what is chosen would cover is left out while it is shown.
                    let ring = session.selection == nil ? nil : LiveRing.place(of: session, in: proxy.size)
                    ForEach(session.cityLabels(in: proxy.size).filter { !LiveRing.covers($0.point, ringAt: ring) }) { label in
                        Text(verbatim: label.words)
                            .font(.nm(LiveType.small, weight: label.own ? .semibold : .medium))
                            .foregroundStyle(label.own || label.ally ? LiveEmphasis.primary : LiveEmphasis.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Palette.panel.opacity(0.7), in: Capsule())
                            .overlay(Capsule().strokeBorder(label.ally ? Palette.good.opacity(0.6) : .clear, lineWidth: 1))
                            .fixedSize()
                            .position(label.point)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    // Over each army in view, whose it is; over the player's own, who
                    // leads it and how many; edged red where it marches on their city.
                    // Over each place the alliance marked, a flag and what it says.
                    ForEach(session.markLabels(in: proxy.size).filter { !LiveRing.covers($0.point, ringAt: ring) }) { label in
                        HStack(spacing: 4) {
                            Image(systemName: "flag.fill")
                                .foregroundStyle(Palette.good)
                            Text(verbatim: label.words)
                                .foregroundStyle(LiveEmphasis.primary)
                        }
                        .font(.nm(LiveType.small, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Palette.panel.opacity(0.8), in: Capsule())
                        .overlay(Capsule().strokeBorder(Palette.good.opacity(0.8), lineWidth: 1))
                        .fixedSize()
                        .position(label.point)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    ForEach(session.armyLabels(in: proxy.size).filter { !LiveRing.covers($0.point, ringAt: ring) }) { label in
                        Text(verbatim: label.words)
                            .font(.nm(LiveType.small, weight: label.own ? .semibold : .regular))
                            .foregroundStyle(label.own || label.ally ? LiveEmphasis.primary : LiveEmphasis.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Palette.panel.opacity(0.6), in: Capsule())
                            .overlay(Capsule().strokeBorder(label.foe ? Palette.bad.opacity(0.8) : label.ally ? Palette.good.opacity(0.6) : .clear, lineWidth: 1))
                            .fixedSize()
                            .position(label.point)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                // While the player's city is chosen, its plots: where each building
                // it has not built would stand, to be chosen and built.
                .overlay {
                    if session.choosesHome {
                        LivePlots(session: session, size: proxy.size)
                    }
                }
                .overlay {
                    // What is chosen, shown about it on the map: its ring and its callout,
                    // the callout to the ring's left where an open destination would cover it.
                    if let selection = session.selection, let place = LiveRing.place(of: session, in: proxy.size) {
                        LiveRing(session: session, card: session.card(for: selection), at: place, panel: $panel,
                                 leftward: LiveRing.leftward(at: place, in: proxy.size, beside: panel == nil ? nil : tallest(in: proxy.size)))
                    }
                }
                // What just happened, told a few seconds at the top.
                .overlay(alignment: .top) {
                    LiveToasts(session: session, seconds: seconds)
                        .padding(.top, 12)
                }
                .overlay(alignment: .top) {
                    if palette {
                        LivePaletteView(session: session, seconds: seconds, open: { panel = $0 }, leave: leave) { palette = false }
                            .padding(.top, 90)
                    }
                }
            }
            // The world about where the player looks heard each second.
            .task(id: proxy.size) { await LiveSounds.listen(to: session, in: proxy.size) }
        }
        // This device named among the player's, once the realm has it.
        .task(id: session.world.devices.count) { await session.nameDevice("Mac") }
        // Each piece of news told by its cue as it comes; what is chosen,
        // and what the realm refuses, each by its own.
        .onChange(of: session.news.last?.id) { last, _ in
            guard let ambience = RealmSound.current?.ambience else { return }
            for cue in LiveSounds.cues(for: session.news, after: last) { ambience.play(cue) }
        }
        .onChange(of: session.selected) { _, chosen in
            if chosen != nil { RealmSound.current?.ambience.play(.select) }
        }
        .onChange(of: session.said) { _, words in
            if words != nil { RealmSound.current?.ambience.play(.refusal) }
        }
    }
}

/// The palette: a line to type what the player would do in, and what
/// can be done this moment that answers to it; Return does the first,
/// a click any, Escape puts it away.
struct LivePaletteView: View {
    let session: LiveSession
    let seconds: Double
    let open: (LiveGameView.Panel) -> Void
    /// Back to the launcher, where there is one: the palette offers it last.
    var leave: (() -> Void)?
    let dismiss: () -> Void
    @State private var search = ""
    @FocusState private var focused: Bool

    /// The most it lists at once.
    static let most = 8
    /// The command that leaves the realm for the launcher.
    static let leaving = LiveCommand(title: "Leave the realm for the launcher", act: .open("launcher"))

    /// What answers to a search: the realm's commands, and leaving where
    /// there is somewhere to leave for; at most `most` of them.
    static func found(_ search: String, in session: LiveSession, at seconds: Double, leaving: Bool) -> [LiveCommand] {
        var all = session.commands(matching: search, at: seconds)
        let words = search.lowercased().split(separator: " ").map(String.init)
        if leaving, words.allSatisfy({ LivePaletteView.leaving.title.lowercased().contains($0) }) {
            all.append(LivePaletteView.leaving)
        }
        return Array(all.prefix(most))
    }

    var body: some View {
        let found = LivePaletteView.found(search, in: session, at: seconds, leaving: leave != nil)
        VStack(alignment: .leading, spacing: 6) {
            // Noted for a listening test, to type into it and choose as a player would.
            let _ = PressableButtons.noteField("What would you do?") { [binding = $search] words in binding.wrappedValue = words }
            let _ = PressableButtons.note("Send: What would you do?", enabled: true) { if let first = found.first { choose(first) } }
            TextField("What would you do?", text: $search)
                .textFieldStyle(.plain)
                .font(.nm(LiveType.title))
                .foregroundStyle(LiveEmphasis.primary)
                .focused($focused)
                .onSubmit { if let first = found.first { choose(first) } }
                .accessibilityLabel("Search for something to do")
            ForEach(found) { command in
                let _ = PressableButtons.note("Do: \(command.title)", enabled: true) { choose(command) }
                Button { choose(command) } label: {
                    Text(verbatim: command.title)
                        .font(.nm(LiveType.body))
                        .foregroundStyle(LiveEmphasis.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if found.isEmpty {
                LiveSmall(words: "Nothing answers to those words.", dim: true)
            }
        }
        .padding(14)
        .frame(width: 420)
        .panelBackground()
        .onAppear { focused = true }
        .onExitCommand(perform: dismiss)
    }

    /// Puts the palette away and does what was chosen, opening a part of a
    /// destination where that is what it does.
    private func choose(_ command: LiveCommand) {
        dismiss()
        if command == LivePaletteView.leaving {
            leave?()
            return
        }
        Task { if let part = await session.perform(command), let panel = LiveGameView.Panel(part: part) { open(panel) } }
    }
}

/// Along the top: whose city, its goods as they stand this second, and
/// the player's energy.
struct LiveTopBar: View {
    let session: LiveSession
    let seconds: Double

    private static let stores: [Resource] = [.grain, .timber, .stone, .moonsalt]

    var body: some View {
        HStack(spacing: 14) {
            if let city = session.world.city {
                let home = {
                    session.go(to: city.hex)
                    session.selected = city.hex
                }
                let _ = PressableButtons.note("Go to your city", enabled: true, home)
                Button(action: home) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: city.name)
                            .font(.nm(LiveType.body, weight: .medium))
                            .foregroundStyle(LiveEmphasis.primary)
                        Text(verbatim: "Keep \(city.keep) · Power \(LiveWords.grouped(city.power))")
                            .font(.nm(LiveType.small))
                            .foregroundStyle(LiveEmphasis.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(city.name), your city: go to it")
            }
            if let stock = session.world.stock {
                let goods = stock.goods(at: seconds).parts
                let incoming = session.world.incomingArmyGoods.parts
                ForEach(Array(Self.stores.enumerated()), id: \.offset) { index, store in
                    let stored = "\(LiveWords.grouped(goods[index])) \(LiveWords.goods[index])"
                    let onTheWay = "\(LiveWords.grouped(incoming[index])) incoming, carried by armies and not yet in stores"
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            ResourceGlyph(resource: store, size: 11)
                            Text(verbatim: LiveWords.grouped(goods[index]))
                                .font(.nm(LiveType.body, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(goods[index] >= stock.holds ? Palette.bad : LiveEmphasis.primary)
                        }
                        if incoming[index] > 0 {
                            Text(verbatim: "+\(LiveWords.grouped(incoming[index])) incoming")
                                .font(.nm(LiveType.small))
                                .foregroundStyle(LiveEmphasis.secondary)
                                .help(onTheWay)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(incoming[index] > 0 ? "\(stored), \(onTheWay)" : stored)
                    .accessibilityAddTraits(.isStaticText)
                }
            }
            if let hunt = session.world.hunt {
                Text(verbatim: "Energy \(LiveWords.grouped(UInt64(hunt.energy(at: seconds))))")
                    .font(.nm(LiveType.body))
                    .monospacedDigit()
                    .foregroundStyle(LiveEmphasis.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .panelBackground()
    }
}

/// The task the player is on: what it asks, what it gives, and a way to
/// claim it once it is done.
/// What stands idle that could be at work, as small reminders under the
/// task: a builder free, the Academy idle, a training ground training no
/// one, a chest waiting. Each opens the part that answers it.
struct LiveIdleChips: View {
    let idle: [LiveIdle]
    let open: (String) -> Void

    static func symbol(of kind: LiveIdle.Kind) -> String {
        switch kind {
        case .builders: return "hammer"
        case .academy: return "book.closed"
        case .training: return "shield.lefthalf.filled"
        case .chest: return "shippingbox"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(idle) { item in
                let _ = PressableButtons.note("Idle: \(item.words)", enabled: true) { open(item.part) }
                Button { open(item.part) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: LiveIdleChips.symbol(of: item.kind))
                            .font(.nm(LiveType.small))
                            .foregroundStyle(LiveEmphasis.secondary)
                        Text(verbatim: item.words)
                            .font(.nm(LiveType.small, weight: .medium))
                            .foregroundStyle(LiveEmphasis.primary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .panelBackground()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.words)
                .accessibilityHint("Opens what answers it.")
            }
        }
    }
}

struct LiveTaskChip: View {
    let session: LiveSession
    /// The part of a destination open, for Go to open where the task is done.
    var panel: Binding<LiveGameView.Panel?> = .constant(nil)

    var body: some View {
        if let task = session.world.task {
            let done = session.world.isDone(task)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: task.words)
                        .font(.nm(LiveType.body, weight: .medium))
                        .foregroundStyle(LiveEmphasis.primary)
                    Text(verbatim: "Gives \(session.world.holdings(task.gives, task.items)).")
                        .font(.nm(LiveType.small))
                        .foregroundStyle(LiveEmphasis.secondary)
                }
                if !done, let way = session.taskWay {
                    // Not done yet: the way to where it is done.
                    QuietButton(title: "Go", prominent: true, name: way.title) { go(way) }
                } else {
                    QuietButton(title: "Claim", prominent: done, enabled: done && session.asking == 0, name: "Claim what the task gives",
                                why: "Not done yet: \(task.words)") {
                        Task { await session.claimTask() }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .panelBackground()
            .accessibilityElement(children: .contain)
        }
    }

    /// Goes where the task is done: opens the part of a destination that
    /// does it, or looks at the place on the map and chooses it.
    private func go(_ way: LiveCommand) {
        Task {
            if let part = await session.perform(way), let opened = LiveGameView.Panel(part: part) { panel.wrappedValue = opened }
        }
    }
}

/// What just happened in the realm, each told for `shown` seconds at the
/// top of the window, the newest last, three at most.
struct LiveToasts: View {
    let session: LiveSession
    let seconds: Double

    static let shown: Double = 6

    var body: some View {
        let fresh = session.news.filter { seconds - $0.at < LiveToasts.shown }.suffix(3)
        VStack(spacing: 4) {
            ForEach(fresh) { news in
                Text(verbatim: news.words)
                    .font(.nm(LiveType.body, weight: .medium))
                    .foregroundStyle(LiveEmphasis.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .panelBackground()
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: 520)
        .animation(.easeInOut(duration: 0.3), value: fresh.map(\.id))
        .accessibilityElement(children: .contain)
        .chrome("live-toasts")
    }
}

/// Armies marching on the player's city, or storming it: each in words,
/// the soonest at the walls first, with a way to look at it on the map.
struct LiveThreats: View {
    let session: LiveSession
    let seconds: Double

    var body: some View {
        let threats = session.world.threats(at: seconds)
        VStack(alignment: .leading, spacing: 4) {
            ForEach(threats.prefix(3)) { threat in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.nm(LiveType.small))
                        .foregroundStyle(Palette.bad)
                        .accessibilityHidden(true)
                    Text(verbatim: threat.words)
                        .font(.nm(LiveType.body, weight: .medium))
                        .foregroundStyle(LiveEmphasis.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    QuietButton(title: "Look", name: "Look at it: \(threat.words)") {
                        let at = threat.march.position(at: seconds)
                        let hex = HexLayout(size: 1).hex(atX: at.x, y: at.y)
                        session.go(to: LiveHex(q: hex.q, r: hex.r))
                    }
                }
            }
            if threats.count > 3 {
                LiveSmall(words: "And \(threats.count - 3) more.", dim: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .panelBackground()
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Palette.bad.opacity(0.7), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your city is threatened")
    }
}

/// The four destinations beside the world: each opens a side of the
/// window at its first part, or closes it again; the mail says how much
/// is unread.
struct LiveDock: View {
    static let destinations = LiveGameView.Destination.allCases

    let session: LiveSession
    @Binding var panel: LiveGameView.Panel?
    /// Opens the palette, as Command-K does.
    var find: () -> Void = {}

    var body: some View {
        HStack(spacing: 2) {
            // Allies asking help with their works: helped all at once, as a handshake.
            let pleas = session.world.pleasToHelp.count
            if pleas > 0 {
                QuietButton(title: "Help \(pleas)", prominent: true, enabled: session.asking == 0, name: "Help your allies with \(pleas) \(pleas == 1 ? "work" : "works")") {
                    Task { await session.helpAll() }
                }
            }
            QuietButton(title: "Find", name: "Find something to do, Command-K", action: find)
                .keyboardShortcut("k", modifiers: .command)
            ForEach(Self.destinations, id: \.self) { place in
                let unread = place == .mail ? session.world.unread + session.world.unreadLetters : 0
                let open = panel?.destination == place
                QuietButton(title: unread > 0 ? "\(place.title) \(unread)" : place.title, prominent: open || unread > 0,
                            name: unread > 0 ? "\(place.title), \(unread) unread" : place.title) { panel = LiveDock.pressed(place, while: panel) }
            }
        }
        .padding(4)
        .panelBackground()
    }

    /// What is open once a destination is pressed: it closes if it was
    /// open, and opens at its first part if not.
    static func pressed(_ place: LiveGameView.Destination, while open: LiveGameView.Panel?) -> LiveGameView.Panel? {
        open?.destination == place ? nil : place.panels.first
    }
}

/// What the realm last would not do, in its own words, until put away.
struct LiveSaid: View {
    let words: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: words)
                .font(.nm(LiveType.body))
                .foregroundStyle(Palette.bad)
                .fixedSize(horizontal: false, vertical: true)
            QuietButton(title: "Close", action: dismiss)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .panelBackground()
        .accessibilityElement(children: .contain)
    }
}

/// The player's armies out of the city: what each is doing and how long
/// it has to go. Pressing one turns the view to it.
struct LiveArmies: View {
    let session: LiveSession
    let seconds: Double

    var body: some View {
        let lines = session.world.marchLines()
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(lines) { line in
                    let go = {
                        let place = line.march.stands ? line.march.to : (line.march.route.last ?? line.march.to)
                        session.go(to: place)
                        session.selected = place
                    }
                    let _ = PressableButtons.note("Go to: \(line.doing)", enabled: true, go)
                    Button(action: go) {
                        HStack(spacing: 8) {
                            Text(verbatim: line.doing)
                                .font(.nm(LiveType.body))
                                .foregroundStyle(LiveEmphasis.primary)
                            Text(verbatim: LiveWords.clock(line.march.arrives - Int(seconds)))
                                .font(.nm(LiveType.body, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(Palette.glowWords)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .panelBackground()
        }
    }
}

/// The plots of the player's city while it is chosen: each building it
/// has not built but its Keep has opened, a small hammer where it would
/// stand among the city's works, to be chosen, its card saying what
/// building it takes.
struct LivePlots: View {
    let session: LiveSession
    let size: CGSize

    var body: some View {
        ForEach(session.plots(), id: \.kind) { plot in
            let point = session.camera.viewPoint(worldX: Double(plot.foot.x), worldY: Double(plot.foot.z), height: Double(plot.foot.y), in: size)
            let name = session.world.blueprint(plot.kind, level: 1)?.name ?? "building"
            let _ = PressableButtons.note("Build a \(name) here", enabled: true) { session.choose(plot) }
            Button { session.choose(plot) } label: {
                Image(systemName: "hammer")
                    .font(.nm(LiveType.small, weight: .medium))
                    .foregroundStyle(session.chosenWork?.kind == plot.kind ? LiveEmphasis.primary : LiveEmphasis.secondary)
                    .frame(width: 24, height: 24)
                    .background(Palette.panel.opacity(0.75), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Build a \(name) here")
            .accessibilityLabel("Build a \(name) here")
            .position(point)
        }
    }
}

/// What is chosen, shown where it stands on the map: each thing that can
/// be done about it a symbol in a ring about it, the first of them at
/// the top and the rest round the clock, with a way to put it away last;
/// and beside the ring a small callout saying what it is, a few lines
/// about it, and why the first thing that can't be done can't be.
struct LiveRing: View {
    let session: LiveSession
    let card: LiveCard
    let at: CGPoint
    @Binding var panel: LiveGameView.Panel?
    /// Whether the callout stands to the ring's left rather than its right.
    var leftward = false

    /// How far the ring's symbols stand from the heart of what is chosen,
    /// and how large each is.
    static let radius: CGFloat = 58
    static let side: CGFloat = 34
    /// How wide the callout is, and how far its middle stands from the
    /// heart of what is chosen.
    static let calloutWidth: CGFloat = 280
    static let calloutReach: CGFloat = radius + side / 2 + calloutWidth / 2 + 12

    /// Whether a name over the map, centred at a point, would lie under a
    /// ring shown about a place: within its symbols' reach across, with
    /// room for a name's half width, and up and down. Such a name is left
    /// out while the ring is shown, so no symbol stands over its words.
    static func covers(_ point: CGPoint, ringAt place: CGPoint?) -> Bool {
        guard let place else { return false }
        return abs(point.x - place.x) < radius + side / 2 + 56 && abs(point.y - place.y) < radius + side / 2 + 10
    }

    /// Whether the callout goes to the ring's left: where, to its right, it
    /// would lie under a destination open at the top right of a view of a
    /// size, standing `panel` tall; never where none is open.
    static func leftward(at point: CGPoint, in size: CGSize, beside panel: CGFloat?) -> Bool {
        guard let panel else { return false }
        let right = point.x + calloutReach + calloutWidth / 2
        let beneath = point.y - 60 > panel + 24
        return !beneath && right > size.width - LiveSidePanel.width - 24
    }

    /// Where what is chosen stands in a view of a size: the heart of its
    /// hex, at the height of the land there, kept clear of the view's
    /// edges; nil where it is not in the window drawn, or behind the eye.
    static func place(of session: LiveSession, in size: CGSize) -> CGPoint? {
        guard let local = session.selectedLocal, size.width > 0, size.height > 0 else { return nil }
        let point: CGPoint
        if let work = session.chosenWork {
            // A building of the player's city: where it stands.
            point = session.camera.viewPoint(worldX: Double(work.foot.x), worldY: Double(work.foot.z), height: Double(work.foot.y), in: size)
        } else {
            let height = session.land().map { Double($0.relief.height(of: local)) } ?? 0
            point = session.camera.viewPoint(of: local, height: height, in: size)
        }
        guard point.x > -radius, point.x < size.width + radius, point.y > -radius, point.y < size.height + radius else { return nil }
        let margin = radius + side
        return CGPoint(x: min(max(point.x, margin), size.width - margin - 300), y: min(max(point.y, margin), size.height - margin - 60))
    }

    var body: some View {
        let count = card.buttons.count + 1
        ZStack(alignment: .topLeading) {
            ForEach(Array(card.buttons.enumerated()), id: \.offset) { index, button in
                symbol(button.icon, name: button.title, enabled: button.why == nil && session.asking == 0, why: button.why) { press(button) }
                    .position(spot(index, of: count))
            }
            symbol("xmark", name: "Put away \(card.title)", enabled: true, why: nil) { session.selected = nil }
                .position(spot(count - 1, of: count))
            callout
                .frame(width: LiveRing.calloutWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .position(x: at.x + (leftward ? -LiveRing.calloutReach : LiveRing.calloutReach), y: at.y)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The place of the ring's `index`th symbol of `count`: the first at
    /// the top, the rest clockwise.
    private func spot(_ index: Int, of count: Int) -> CGPoint {
        let angle = -Double.pi / 2 + Double(index) * 2 * .pi / Double(max(count, 1))
        return CGPoint(x: at.x + LiveRing.radius * CGFloat(cos(angle)), y: at.y + LiveRing.radius * CGFloat(sin(angle)))
    }

    private func symbol(_ icon: String, name: String, enabled: Bool, why: String?, action: @escaping () -> Void) -> some View {
        PressableButtons.note("Ring: \(name)", enabled: enabled, action)
        return Button(action: action) {
            Image(systemName: icon)
                .font(.nm(LiveType.title, weight: .medium))
                .foregroundStyle(enabled ? LiveEmphasis.primary : LiveEmphasis.tertiary)
                .frame(width: LiveRing.side, height: LiveRing.side)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .panelBackground()
        .clipShape(Circle())
        .help(why ?? name)
        .accessibilityLabel(why.map { "\(name): \($0)" } ?? name)
        .chrome("live-ring")
    }

    private var callout: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: card.title)
                .font(.nm(LiveType.title, weight: .medium))
                .foregroundStyle(LiveEmphasis.primary)
            ForEach(card.lines, id: \.self) { line in
                Text(verbatim: line)
                    .font(.nm(LiveType.small))
                    .foregroundStyle(LiveEmphasis.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let why = card.buttons.compactMap(\.why).first, !card.lines.contains(why) {
                Text(verbatim: why)
                    .font(.nm(LiveType.small))
                    .foregroundStyle(LiveEmphasis.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .panelBackground()
        .chrome("live-card")
    }

    /// Does what a symbol says: opens a part of the House, or asks the realm.
    private func press(_ button: LiveCard.Button) { LiveGameView.press(button, session: session, panel: $panel) }
}

/// The card for what is chosen: its name, a few lines, and what can be
/// done about it; at the foot of the window, where what is chosen can't
/// be shown beside it on the map.
struct LiveCardView: View {
    let session: LiveSession
    let card: LiveCard
    @Binding var panel: LiveGameView.Panel?

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: card.title)
                    .font(.nm(LiveType.title, weight: .medium))
                    .foregroundStyle(LiveEmphasis.primary)
                ForEach(card.lines, id: \.self) { line in
                    Text(verbatim: line)
                        .font(.nm(LiveType.body))
                        .foregroundStyle(LiveEmphasis.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Why the first thing that can't be done can't be.
                if let why = card.buttons.compactMap(\.why).first, !card.lines.contains(why) {
                    Text(verbatim: why)
                        .font(.nm(LiveType.small))
                        .foregroundStyle(LiveEmphasis.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            ForEach(card.buttons, id: \.title) { button in
                QuietButton(title: button.title, prominent: true, enabled: button.why == nil && session.asking == 0, why: button.why) {
                    press(button)
                }
            }
            QuietButton(title: "Close") { session.selected = nil }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 640)
        .panelBackground()
    }

    /// Does what a button says: opens a side of the window, or asks the
    /// realm.
    private func press(_ button: LiveCard.Button) { LiveGameView.press(button, session: session, panel: $panel) }
}

extension LiveGameView {
    /// Does what a card's button says, in its ring or at the foot: opens
    /// the House's buildings or its troops, or asks the realm.
    static func press(_ button: LiveCard.Button, session: LiveSession, panel: Binding<Panel?>) {
        switch button.act {
        case .city: panel.wrappedValue = .city
        case .troops: panel.wrappedValue = .troops
        default: Task { await session.press(button) }
        }
    }
}
