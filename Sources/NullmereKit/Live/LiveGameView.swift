import Foundation
import NullmereCore
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
            }
        }

        /// Which of the four destinations it belongs to.
        var destination: Destination { Destination.allCases.first { $0.panels.contains(self) } ?? .house }

        /// The part the palette names (`LiveSession.parts`).
        init?(part: String) {
            let all: [String: Panel] = ["city": .city, "troops": .troops, "studies": .studies, "forge": .forge, "day": .day, "alliance": .alliance,
                                        "realm": .realm, "chat": .chat, "reports": .reports]
            guard let panel = all[part] else { return nil }
            self = panel
        }
    }

    /// The four places beside the world: the player's House (their city,
    /// troops, studies and the day's work), their alliance, the realm
    /// (its season, contests and what is said in it), and their mail.
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
            case .house: return [.city, .troops, .studies, .forge, .day]
            case .alliance: return [.alliance]
            case .realm: return [.realm, .chat]
            case .mail: return [.reports]
            }
        }
    }

    private let session: LiveSession
    @State private var panel: Panel?
    @State private var palette = false
    @State private var cannotDraw = false

    public init(session: LiveSession) {
        self.session = session
    }

    /// The same, opened at one part of a destination.
    init(session: LiveSession, opening: Panel?) {
        self.session = session
        _panel = State(initialValue: opening)
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch session.phase {
            case .opening:
                LiveNotice(title: "Reaching the realm", words: "One moment.", button: nil) {}
            case .lost:
                LiveNotice(title: "The realm can't be reached", words: "Check your connection, then try again.", button: "Try again") {
                    Task { await session.open() }
                }
            case .naming, .playing:
                if cannotDraw {
                    LiveNotice(title: "The world can't be drawn", words: "This Mac's graphics could not draw it.", button: nil) {}
                } else {
                    LiveMapView(session: session, onFailure: { cannotDraw = true })
                        .ignoresSafeArea()
                        .accessibilityLabel("The realm's map")
                }
                if session.phase == .naming {
                    LiveNameCard(session: session)
                } else {
                    LiveHUD(session: session, panel: $panel, palette: $palette)
                }
            }
        }
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
    /// reports, or the nearest barrow or site chosen. It waits on the
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
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Caps(title, size: LiveType.body, weight: .medium, centred: true)
                .foregroundStyle(LiveEmphasis.primary)
            Text(verbatim: words)
                .font(.nm(LiveType.body))
                .foregroundStyle(LiveEmphasis.secondary)
            if let button {
                QuietButton(title: button, prominent: true, action: action)
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

    /// The share of the window's height an open destination stands to.
    static let panelShare: CGFloat = 0.42

    var body: some View {
        // Counted afresh each second: goods grow and timers run down
        // between the realm's own words.
        GeometryReader { proxy in
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let seconds = session.now
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 10) {
                        HStack(alignment: .top, spacing: 12) {
                            LiveTopBar(session: session, seconds: seconds)
                                .chrome("live-bar")
                            Spacer(minLength: 0)
                        }
                        HStack(alignment: .top, spacing: 12) {
                            LiveTaskChip(session: session)
                                .chrome("live-task")
                            Spacer(minLength: 0)
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
                    if let panel {
                        LiveSidePanel(session: session, seconds: seconds, panel: panel, close: { self.panel = nil }, choose: { self.panel = $0 },
                                      tallest: max(proxy.size.height * LiveHUD.panelShare, ChromeBudget.leastHeight))
                            .chrome("live-panel")
                    }
                }
                .padding(12)
                .overlay {
                    // What is chosen, shown about it on the map: its ring and its callout.
                    if let selection = session.selection, let place = LiveRing.place(of: session, in: proxy.size) {
                        LiveRing(session: session, card: session.card(for: selection), at: place, panel: $panel)
                    }
                }
                .overlay(alignment: .top) {
                    if palette {
                        LivePaletteView(session: session, seconds: seconds, open: { panel = $0 }) { palette = false }
                            .padding(.top, 90)
                    }
                }
            }
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
    let dismiss: () -> Void
    @State private var search = ""
    @FocusState private var focused: Bool

    /// The most it lists at once.
    static let most = 8

    var body: some View {
        let found = Array(session.commands(matching: search, at: seconds).prefix(Self.most))
        VStack(alignment: .leading, spacing: 6) {
            TextField("What would you do?", text: $search)
                .textFieldStyle(.plain)
                .font(.nm(LiveType.title))
                .foregroundStyle(LiveEmphasis.primary)
                .focused($focused)
                .onSubmit { if let first = found.first { choose(first) } }
                .accessibilityLabel("Search for something to do")
            ForEach(found) { command in
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
                Button {
                    session.go(to: city.hex)
                    session.selected = city.hex
                } label: {
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
                ForEach(Array(Self.stores.enumerated()), id: \.offset) { index, store in
                    HStack(spacing: 5) {
                        ResourceGlyph(resource: store, size: 11)
                        Text(verbatim: LiveWords.grouped(goods[index]))
                            .font(.nm(LiveType.body, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(goods[index] >= stock.holds ? Palette.bad : LiveEmphasis.primary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(LiveWords.grouped(goods[index])) \(LiveWords.goods[index])")
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
struct LiveTaskChip: View {
    let session: LiveSession

    var body: some View {
        if let task = session.world.task {
            let done = session.world.isDone(task)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: task.words)
                        .font(.nm(LiveType.body, weight: .medium))
                        .foregroundStyle(LiveEmphasis.primary)
                    Text(verbatim: "Gives \(task.gives.words).")
                        .font(.nm(LiveType.small))
                        .foregroundStyle(LiveEmphasis.secondary)
                }
                QuietButton(title: "Claim", prominent: done, enabled: done && session.asking == 0, name: "Claim what the task gives",
                            why: "Not done yet: \(task.words)") {
                    Task { await session.claimTask() }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .panelBackground()
            .accessibilityElement(children: .contain)
        }
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
                    Button {
                        let place = line.march.stands ? line.march.to : (line.march.route.last ?? line.march.to)
                        session.go(to: place)
                        session.selected = place
                    } label: {
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

    /// How far the ring's symbols stand from the heart of what is chosen,
    /// and how large each is.
    static let radius: CGFloat = 58
    static let side: CGFloat = 34

    /// Where what is chosen stands in a view of a size: the heart of its
    /// hex, at the height of the land there, kept clear of the view's
    /// edges; nil where it is not in the window drawn, or behind the eye.
    static func place(of session: LiveSession, in size: CGSize) -> CGPoint? {
        guard let local = session.selectedLocal, size.width > 0, size.height > 0 else { return nil }
        let height = session.land().map { Double($0.relief.height(of: local)) } ?? 0
        let point = session.camera.viewPoint(of: local, height: height, in: size)
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
                .frame(width: 280, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .position(x: at.x + LiveRing.radius + LiveRing.side / 2 + 152, y: at.y)
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
        Button(action: action) {
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
            if let why = card.buttons.compactMap(\.why).first {
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
    private func press(_ button: LiveCard.Button) {
        if button.act == .city {
            panel = .city
        } else if button.act == .troops {
            panel = .troops
        } else {
            Task { await session.press(button) }
        }
    }
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
                if let why = card.buttons.compactMap(\.why).first {
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
    private func press(_ button: LiveCard.Button) {
        let act = button.act
        if act == .city {
            panel = .city
        } else if act == .troops {
            panel = .troops
        } else {
            Task { await session.press(button) }
        }
    }
}
