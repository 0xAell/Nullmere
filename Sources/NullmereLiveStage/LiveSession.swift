import Foundation
import NullmereLand
import NullmereLive
import NullmereModels
import NullmereWorld
import Observation

/// What a session asks of the realm and reads from it: the client's own
/// calls, named apart from the client so that a session can be tried
/// without a server.
public protocol LiveLine: AnyObject, Sendable {
    var world: LiveWorld { get }
    func watch(changed: @escaping @Sendable () -> Void) async -> Bool
    func close()
    func join(name: String) async throws
    func build(_ kind: Int) async throws
    func upgrade(building: UInt64) async throws
    func train(building: UInt64, tier: Int, count: UInt64) async throws
    func promote(building: UInt64, from: Int, to: Int, count: UInt64) async throws
    func gather(at hex: LiveHex, soldiers: [(kind: Int, tier: Int, count: UInt64)], leader: UInt64) async throws
    func hunt(at hex: LiveHex, soldiers: [(kind: Int, tier: Int, count: UInt64)], leader: UInt64) async throws
    func attack(at hex: LiveHex, soldiers: [(kind: Int, tier: Int, count: UInt64)], leader: UInt64) async throws
    func hire() async throws
    func heal(kind: Int, tier: Int, count: UInt64) async throws
    func read(report: UInt64) async throws
    func forget(report: UInt64) async throws
    func recall(march: UInt64) async throws
    func learn(topic: Int) async throws
    func claimTask() async throws
    func foundAlliance(name: String, tag: String) async throws
    func joinAlliance(_ alliance: UInt64) async throws
    func leaveAlliance() async throws
    func answer(applicant: UInt64, admit: Bool) async throws
    func expel(_ player: UInt64) async throws
    func setRank(of player: UInt64, to rank: Int) async throws
    func setAlliance(open: Bool, words: String) async throws
    func say(_ words: String, withinAlliance: Bool) async throws
    func reportLine(_ line: UInt64, withinAlliance: Bool) async throws
    func scout(at hex: LiveHex, soldiers: [(kind: Int, tier: Int, count: UInt64)]) async throws
    func explore(at hex: LiveHex, soldiers: [(kind: Int, tier: Int, count: UInt64)]) async throws
    func raid(at hex: LiveHex, soldiers: [(kind: Int, tier: Int, count: UInt64)], leader: UInt64) async throws
    func reinforce(at hex: LiveHex, soldiers: [(kind: Int, tier: Int, count: UInt64)], leader: UInt64) async throws
    func callRally(at hex: LiveHex, soldiers: [(kind: Int, tier: Int, count: UInt64)], leader: UInt64) async throws
    func joinRally(_ rally: UInt64, soldiers: [(kind: Int, tier: Int, count: UInt64)], leader: UInt64) async throws
    func askHelp(job: UInt64) async throws
    func help(job: UInt64) async throws
    func raiseWard(at hex: LiveHex) async throws
    func razeWard(_ ward: UInt64) async throws
    func giveToLearning(topic: Int, _ goods: LiveGoods) async throws
    func giveToSpire(_ goods: LiveGoods) async throws
    func learnTalent(commander: UInt64, talent: Int) async throws
    func forgetTalents(commander: UInt64) async throws
    func pair(commander: UInt64, with partner: UInt64) async throws
    func keepCity(commander: UInt64) async throws
    func speedUp(job: UInt64) async throws
    func useItem(_ item: Int, on job: UInt64) async throws
    func moveCity(to hex: LiveHex) async throws
    func forge(piece: Int) async throws
    func equip(gear: UInt64, on commander: UInt64) async throws
    func unequip(gear: UInt64) async throws
    func claimBoons() async throws
    func buy(item: Int, count: UInt64) async throws
    func readTome(commander: UInt64, item: Int, count: UInt64) async throws
    func usePeace(_ item: Int) async throws
    func openChest(_ chest: Int) async throws
    func claimPrize(contest: Int, place: Int) async throws
    func claimPlace(contest: Int) async throws
    func offerLink() async throws
    func takeLink(_ code: String) async throws
    func nameDevice(_ name: String) async throws
    func draw() async throws
    func raiseGift(commander: UInt64) async throws
    func letGo(device: UInt64) async throws
    func leaveRealm(name: String) async throws
    func sendEnvoy(to alliance: UInt64, terms: Int, days: Int) async throws
    func answerEnvoy(_ envoy: UInt64, accept: Bool) async throws
    func breakPact(_ pact: UInt64) async throws
    func ransom(commander: UInt64) async throws
    func releasePrisoner(commander: UInt64) async throws
    func petition(_ goods: LiveGoods) async throws
    func answerPetition(of asker: UInt64, _ goods: LiveGoods) async throws
    func withdrawPetition() async throws
    func bestowTitle(_ title: Int, on player: UInt64) async throws
    func takeTitle(_ title: Int) async throws
    func sendLetter(to player: UInt64, _ words: String) async throws
    func sendAllianceLetter(_ words: String) async throws
    func readLetter(_ letter: UInt64) async throws
    func forgetLetter(_ letter: UInt64) async throws
}

extension LiveClient: LiveLine {}

/// What lies at a hex the player has chosen.
public enum LiveSelection: Equatable, Sendable {
    /// The player's own city.
    case home(LiveCity)
    /// Another player's city, and their name.
    case city(LiveCity, of: String)
    case site(LiveSite)
    case barrow(LiveBarrow)
    /// A gate of the ridge, and an alliance's wardstone.
    case gate(LiveGate)
    case ward(LiveWard)
    /// A cairn of the old folk.
    case cairn(LiveCairn)
    /// An army there now, and whether it is the player's own.
    case army(LiveMarch, own: Bool)
    /// Bare land: its ground, as the module numbers it, where it is known.
    case land(LiveHex, ground: UInt8?)
    /// A building of the player's own city, chosen where it stands on the
    /// map, by its number in the module's catalogue.
    case work(Int, in: LiveCity)
}

/// A building of the player's own city chosen on the map: its number in
/// the module's catalogue, and where its foot stands as the city is drawn
/// in the window.
public struct LiveChosenWork: Equatable, Sendable {
    public let kind: Int
    public let foot: Vec3
}

/// Something that just happened in the player's realm, in a few words,
/// and when it was told.
public struct LiveNews: Equatable, Identifiable, Sendable {
    public let id: Int
    public let words: String
    public let at: Double
    /// What it is, for the sound that tells it.
    public let kind: LiveTold
}

/// A player in the realm: their line to it, the world as it stands, where
/// they are looking, what they have chosen, and what they ask.
///
/// Everything is the realm's to decide. The session keeps the latest rows,
/// stages the window of the world about where the player looks, and hands
/// what they ask to the line; what the realm refuses comes back in its
/// own words, kept in `said` until it is put away.
@MainActor
@Observable
public final class LiveSession {
    public enum Phase: Equatable, Sendable {
        /// Waiting on the realm's first rows.
        case opening
        /// In the realm, but not yet a player: a name is wanted.
        case naming
        case playing
        /// The realm can't be reached.
        case lost
    }

    /// How far the window reaches about its heart, and how far the look
    /// may stray from that heart before the window is taken afresh.
    public static let reach = 24
    public static let stray = 8
    /// How close the view opens on a city, and the furthest out it draws
    /// back: no further than keeps the window's rim out of sight. It opens
    /// on her city and its neighbours, some thirteen hexes across a
    /// laptop's window (at 46, nineteen, her city stood small in a broad
    /// green, CI run 1057's pictures); further out is a scroll away.
    public static let openingScale = 64.0
    public static let furthestScale = 22.0

    public private(set) var phase: Phase = .opening
    public private(set) var world = LiveWorld()
    /// What the realm last would not do, in its own words, or a thing
    /// done that wants saying, until put away.
    public var said: String?
    /// The lines of chat the player has reported while this session lasts.
    private var reported: Set<String> = []
    /// How many things asked are still on their way.
    public private(set) var asking = 0
    /// The hex of the world the player has chosen.
    public var selected: LiveHex? {
        didSet { if selected != oldValue { chosenWork = nil } }
    }
    /// The building of the player's own city chosen where it stands on the
    /// map, with the city's hex; nil where the city itself, or anything
    /// else, is chosen.
    public private(set) var chosenWork: LiveChosenWork?
    /// The hex of the world the player is looking at, and the camera over
    /// the window it is drawn in: in that window's own land, whose heart
    /// is the window's centre.
    public private(set) var look = LiveHex(q: 0, r: 0)
    public private(set) var camera = Camera(scale: LiveSession.openingScale)
    /// The window of the world being drawn, and a number that moves each
    /// time another is taken: the land to be drawn has changed.
    public private(set) var window: LiveWindow?
    /// The whole realm small, for the map in the corner: made afresh as
    /// more of the land is told.
    public private(set) var minimap: LiveMinimap?
    /// What just happened, the newest last, each with when it was told: the
    /// toasts the play view shows a while. The last `newsKept` are kept.
    public private(set) var news: [LiveNews] = []
    public static let newsKept = 20
    /// How many have been told, to number the next.
    private var told = 0
    public private(set) var windowVersion = 0
    /// A number that moves each time what stands still in the window has
    /// changed: its cities, sites and barrows.
    public private(set) var standingVersion = 0

    @ObservationIgnored private var line: (any LiveLine)?
    @ObservationIgnored private let door: @Sendable () async throws -> any LiveLine
    @ObservationIgnored private let clock: @Sendable () -> Double
    @ObservationIgnored private var staged: (stage: WorldStage, relief: Relief, terrain: TerrainMesh)?
    @ObservationIgnored private var fixed: [ModelBatch] = []
    @ObservationIgnored private var standing: [LiveHex] = []
    @ObservationIgnored private var landCount = 0
    @ObservationIgnored private var placed = false

    /// The colours players' things are drawn in, by their number.
    public static let colours: [Vec4] = (0..<24).map { index in
        // Hues a golden step apart, so neighbours in the list are far
        // apart in colour; three depths of each, so twenty-four differ.
        let hue = (Double(index) * 0.618_033_988_75).truncatingRemainder(dividingBy: 1) * 2 * Double.pi
        let depth = [0.95, 0.72, 0.55][index % 3]
        func part(_ shift: Double) -> Float { Float(depth * (0.55 + 0.42 * cos(hue + shift))) }
        return Vec4(part(0), part(-2.094), part(2.094), 1)
    }

    /// The colours as the renderer's palette takes them, by sigil: the
    /// twenty-four over and over, so a player's land and an alliance's
    /// (`LiveWindow.allianceSigil`) each find the colour its things are
    /// drawn in.
    public static let palette: [Vec4] = (0..<1_024).map { colours[$0 % colours.count] }

    /// A session over a line already open.
    public convenience init(line: any LiveLine, clock: @escaping @Sendable () -> Double = { Date().timeIntervalSince1970 }) {
        self.init(opening: { line }, clock: clock)
    }

    /// A session over a line still to be opened: `open` opens it, and
    /// tries again each time it is asked while the realm can't be reached.
    public init(opening door: @escaping @Sendable () async throws -> any LiveLine,
                clock: @escaping @Sendable () -> Double = { Date().timeIntervalSince1970 }) {
        self.door = door
        self.clock = clock
    }

    /// The moment, by the session's clock: seconds as the realm counts them.
    public var now: Double { clock() }

    // MARK: Reading

    /// Begins watching the realm. Its rows come as they change from here on.
    public func open() async {
        if phase == .lost { phase = .opening }
        if line == nil {
            line = try? await door()
        }
        let live = await line?.watch { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        guard live == true else {
            phase = .lost
            return
        }
        refresh()
    }

    /// Stops watching.
    public func close() {
        line?.close()
    }

    /// Takes the realm's rows as they now stand, noting what happened since
    /// the last.
    public func refresh() {
        guard let latest = line?.world else { return }
        guard latest != world || phase == .opening else { return }
        for item in LiveWorld.told(from: world, to: latest, at: now) {
            told += 1
            news.append(LiveNews(id: told, words: item.words, at: now, kind: item.kind))
        }
        if news.count > LiveSession.newsKept { news.removeFirst(news.count - LiveSession.newsKept) }
        world = latest
        if world.realm == nil {
            phase = .opening
        } else if world.me == nil || world.city == nil {
            phase = .naming
        } else {
            phase = .playing
        }
        // The first sight of the realm is of the player's own city.
        if !placed, let city = world.city {
            placed = true
            look = city.hex
            window = nil
            (camera.centerX, camera.centerY) = (0, 0)
        }
        retake()
    }

    /// The player looks at another hex of the world: the window follows
    /// once the look has strayed far enough from its heart.
    public func look(at hex: LiveHex) {
        guard hex != look else { return }
        look = hex
        retake()
    }

    /// The view's camera has moved: the look follows what it is centred
    /// on, and where that takes the window afresh, the camera is carried
    /// over to the same place in the new one, so nothing on screen moves.
    public func moved(_ camera: Camera) {
        var camera = camera
        camera.scale = max(camera.scale, LiveSession.furthestScale)
        self.camera = camera
        guard let before = window?.centre else { return }
        let under = HexLayout(size: 1).hex(atX: camera.centerX, y: camera.centerY)
        look(at: LiveHex(q: under.q + before.q, r: under.r + before.r))
        if let after = window?.centre, after != before {
            self.camera.centerX -= after.centre.x - before.centre.x
            self.camera.centerY -= after.centre.y - before.centre.y
        }
    }

    /// Turns the view to a hex of the world, wherever it lies.
    public func go(to hex: LiveHex) {
        look(at: hex)
        guard let centre = window?.centre else { return }
        camera.centerX = hex.centre.x - centre.centre.x
        camera.centerY = hex.centre.y - centre.centre.y
    }

    /// The player chooses a hex of the window's own land, or with nil,
    /// nothing; given the ray from the eye they chose along, a building of
    /// their own city it meets first, where it stands on the map.
    public func choose(local hex: Hex?, ray: (origin: Vec3, direction: Vec3)? = nil) {
        guard let hex, let centre = window?.centre else {
            selected = nil
            return
        }
        if let ray, let work = work(hitBy: ray), let home = world.city?.hex {
            selected = home
            chosenWork = work
            return
        }
        selected = LiveHex(q: hex.q + centre.q, r: hex.r + centre.r)
        chosenWork = nil
    }

    /// The building of the player's own city a ray from the eye first
    /// meets, as the city is drawn in the window, in the window's own land;
    /// nil where it meets none, or none the city has.
    public func work(hitBy ray: (origin: Vec3, direction: Vec3)) -> LiveChosenWork? {
        guard let window, let city = world.city, land() != nil, let stage = staged?.stage,
              let sight = window.holds(in: world, colours: LiveSession.colours, at: now).first(where: { $0.hold.id == Int(city.id) }),
              let hit = stage.work(of: sight, hitBy: ray.origin, toward: ray.direction) else { return nil }
        let kind: BuildingKind
        switch hit.work {
        case .building(let building): kind = building
        case .study: kind = .archive
        }
        guard let number = LiveWindow.building(for: kind), world.building(number) != nil else { return nil }
        return LiveChosenWork(kind: number, foot: hit.foot)
    }

    /// Where each building the player's city has not yet built, but its
    /// Keep has opened, would stand, as the city is drawn in the window, in
    /// the window's own land: the plot kept for it among the city's works.
    /// Only buildings the map draws, and none where the city's ground keeps
    /// no plots.
    public func plots() -> [LiveChosenWork] {
        guard let window, let city = world.city, land() != nil, let stage = staged?.stage,
              let sight = window.holds(in: world, colours: LiveSession.colours, at: now).first(where: { $0.hold.id == Int(city.id) })
        else { return [] }
        var works: [HoldLayout.Work: Int] = [:]
        for line in world.buildingLines(at: now) where line.building == nil && (line.next?.opensAt ?? .max) <= city.keep {
            guard let kind = BuildingKind.allCases.first(where: { LiveWindow.building(for: $0) == line.kind }) else { continue }
            works[HoldLayout.Work(kind)] = line.kind
        }
        guard !works.isEmpty else { return [] }
        return stage.plots(of: sight, for: Set(works.keys)).compactMap { plot in
            works[plot.work].map { LiveChosenWork(kind: $0, foot: plot.foot) }
        }
    }

    /// Whether the player's own city, or a building or plot of it, is
    /// chosen: while it is, its plots are shown.
    public var choosesHome: Bool {
        switch selection {
        case .home, .work: return true
        default: return false
        }
    }

    /// The player chooses a plot of their city, or a building of it, where
    /// it stands: the building, whether it stands yet or not.
    public func choose(_ work: LiveChosenWork) {
        guard let home = world.city?.hex else { return }
        selected = home
        chosenWork = work
    }

    /// What the player has chosen, as a hex of the window's own land,
    /// where it lies in the window.
    public var selectedLocal: Hex? { selected.flatMap { window?.local($0) } }

    /// Takes the window afresh where it is wanted: none yet, the look
    /// strayed from its heart, or more of the land known than when it was
    /// made. And notes what stands in it, if that has changed.
    private func retake() {
        guard world.realm != nil else { return }
        let strayed = window.map { $0.centre.distance(to: look) > LiveSession.stray } ?? true
        if strayed || world.land.count != landCount {
            if world.land.count != landCount { minimap = LiveMinimap(world: world) }
            landCount = world.land.count
            let next = LiveWindow(world: world, centre: strayed ? look : (window?.centre ?? look), radius: LiveSession.reach)
            if next.map != window?.map || next.centre != window?.centre {
                window = next
                windowVersion += 1
                staged = nil
                standing = []
            }
        }
        guard let window else { return }
        let stands = (world.cities.values.map(\.hex) + world.sites.values.map(\.hex) + world.barrows.values.map(\.hex))
            .filter { window.local($0) != nil }.sorted { $0.packed < $1.packed }
        if stands != standing || staged == nil {
            standing = stands
            standingVersion += 1
            fixed = []
        }
    }

    /// The window's land as the renderer takes it, made once for a window.
    public func land() -> (map: WorldMap, relief: Relief, terrain: TerrainMesh)? {
        guard let window else { return nil }
        if staged == nil {
            let relief = Relief(map: window.map, origin: Hex(window.centre.q, window.centre.r))
            staged = (WorldStage(map: window.map, relief: relief), relief, TerrainMesh(relief: relief))
        }
        return staged.map { (window.map, $0.relief, $0.terrain) }
    }

    /// The window's tiles as the world's shader takes them.
    public func tiles() -> [UInt8]? {
        guard let window else { return nil }
        let seconds = now
        return window.tiles(holds: window.holds(in: world, colours: LiveSession.colours, at: seconds), in: world, at: seconds)
    }

    /// What stands and moves in the window at a moment, staged for the
    /// renderer: its cities and their works, the sites, the Unquiet's
    /// barrows and the old folk's cairns, the armies where they are, and
    /// the land's own furniture.
    /// How far from a city's heart, and from an army's, what is staged for
    /// it reaches: what lies further out of the view is left out of a frame.
    public static let holdReach: Float = HoldLayout.reach + 1.5
    public static let companyReach: Float = 2

    /// The frame to draw at a moment: given the view's size, only what the
    /// camera can see of it is staged, as a crowded window's cities, each
    /// with its town, are too many to stage whole every frame.
    public func frame(time: Double, size: CGSize? = nil) -> SceneFrame {
        var frame = SceneFrame()
        guard let window, let land = land(), let stage = staged?.stage else { return frame }
        let seconds = now
        let view = size.flatMap { $0.width > 0 && $0.height > 0 ? ViewFrustum(viewProjection: camera.viewProjection(in: $0)) : nil }
        func seen(_ hex: Hex, within reach: Float) -> Bool { view?.sees(hex, within: reach) ?? true }
        let sights = timed("cities read") { window.holds(in: world, colours: LiveSession.colours, at: seconds) }
        let (sites, barrows, cairns) = timed("places read") { (window.sites(in: world), window.barrows(in: world), window.cairns(in: world)) }
        if fixed.isEmpty {
            fixed = stage.furnish(occupied: Set(sites.map(\.hex) + barrows.map(\.hex) + cairns.map(\.hex)), holds: Set(sights.map(\.hold.position)))
        }
        frame.fixed = fixed
        frame.fixedVersion = windowVersion * 100_000 + standingVersion
        let (holds, _) = timed("cities staged") { stage.holds(sights.filter { seen($0.hold.position, within: Self.holdReach) }, time: Float(time), into: &frame, smoke: false) }
        let poses = timed("armies read") { window.companies(in: world, relief: land.relief, at: seconds).filter { seen($0.hex, within: Self.companyReach) } }
        let places = timed("places staged") {
            stage.sites(sites.filter { seen($0.hex, within: 1) }) + stage.lairs(barrows.filter { seen($0.hex, within: 1) }).batches
                + stage.finds(cairns.filter { seen($0.hex, within: 1) }).batches
        }
        let armies = timed("armies staged") { stage.companies(poses, houses: LiveSession.colours, into: &frame) }
        frame.batches = holds + places + armies
        // The ways the armies on the move still have to go, lit on the land.
        frame.motes += timed("ways") { stage.marchLines(window.marchWays(in: world, at: seconds), time: Float(time)) }
        return frame
    }

    /// Where frames' staging has gone, part by part, in milliseconds
    /// summed over the frames since it was set; nil, and nothing is timed.
    /// The staging test sets it to say which part costs what.
    @ObservationIgnored public var stagingParts: [String: Double]?

    /// Does a part of a frame's staging, timed into `stagingParts` where asked.
    private func timed<T>(_ part: String, _ work: () -> T) -> T {
        guard stagingParts != nil else { return work() }
        let started = DispatchTime.now().uptimeNanoseconds
        let done = work()
        stagingParts?[part, default: 0] += Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        return done
    }

    // MARK: Choosing

    /// What lies at a hex of the world now: an army standing or passing
    /// there before what stands there, and that before the bare land.
    public func selection(at hex: LiveHex) -> LiveSelection {
        let seconds = now
        let layout = HexLayout(size: 1)
        let there = world.marches.values.sorted { $0.id < $1.id }.first { march in
            let at = march.position(at: seconds)
            let on = layout.hex(atX: at.x, y: at.y)
            return on.q == hex.q && on.r == hex.r
        }
        if let place = world.places[hex] {
            switch place.kind {
            case LivePlace.city:
                if let city = world.cities[place.id] {
                    if city.id == world.city?.id { return .home(city) }
                    return .city(city, of: world.shownName(of: city.owner) ?? city.name)
                }
            case LivePlace.site:
                // An army at work on a site is chosen with the site, not for it.
                if let site = world.sites[place.id] { return .site(site) }
            case LivePlace.barrow:
                if let barrow = world.barrows[place.id] { return .barrow(barrow) }
            case LivePlace.gate:
                if let gate = world.gates[place.id] { return .gate(gate) }
            case LivePlace.ward:
                if let ward = world.wards[place.id] { return .ward(ward) }
            case LivePlace.cairn:
                if let cairn = world.cairns[place.id] { return .cairn(cairn) }
            default: break
            }
        }
        if let there { return .army(there, own: there.owner == world.me?.id) }
        return .land(hex, ground: world.ground(at: hex))
    }

    /// What the player has chosen, if anything: a building of their own
    /// city where one was chosen in it.
    public var selection: LiveSelection? {
        guard let selected else { return nil }
        let found = selection(at: selected)
        if let chosenWork, case .home(let city) = found { return .work(chosenWork.kind, in: city) }
        return found
    }

    /// The player's soldiers standing ready, kind by kind and tier by tier:
    /// all of them, for an army sent with everyone.
    public var everyoneReady: [(kind: Int, tier: Int, count: UInt64)] {
        world.troops.filter { $0.ready > 0 }.map { ($0.kind, $0.tier, $0.ready) }
    }

    // MARK: Asking

    /// What is said when the realm can't be asked at all.
    public static let unreached = "The realm could not be reached. Try again in a moment."

    /// Asks something of the realm, its refusal kept in `said`; whether
    /// it was done.
    @discardableResult
    private func ask(_ work: @Sendable (any LiveLine) async throws -> Void) async -> Bool {
        guard let line else {
            said = LiveSession.unreached
            return false
        }
        asking += 1
        defer { asking -= 1 }
        do {
            try await work(line)
            refresh()
            return true
        } catch let refusal as LiveRefusal {
            said = refusal.words
        } catch {
            said = LiveSession.unreached
        }
        return false
    }

    public func join(name: String) async { await ask { try await $0.join(name: name) } }
    public func build(_ kind: Int) async { await ask { try await $0.build(kind) } }
    /// Raises a building of the city's list a level: upgraded where the
    /// city has it, built where it has not.
    public func raise(_ line: LiveBuildingLine) async {
        if let building = line.building {
            await upgrade(building: building.id)
        } else {
            await build(line.kind)
        }
    }
    public func upgrade(building: UInt64) async { await ask { try await $0.upgrade(building: building) } }
    public func train(building: UInt64, tier: Int, count: UInt64) async { await ask { try await $0.train(building: building, tier: tier, count: count) } }
    public func promote(building: UInt64, from: Int, to: Int, count: UInt64) async {
        await ask { try await $0.promote(building: building, from: from, to: to, count: count) }
    }
    public func heal(kind: Int, tier: Int, count: UInt64) async { await ask { try await $0.heal(kind: kind, tier: tier, count: count) } }
    public func recall(march: UInt64) async { await ask { try await $0.recall(march: march) } }
    public func read(report: UInt64) async { await ask { try await $0.read(report: report) } }
    public func forget(report: UInt64) async { await ask { try await $0.forget(report: report) } }

    public func hire() async { await ask { try await $0.hire() } }
    public func learn(topic: Int) async { await ask { try await $0.learn(topic: topic) } }
    public func claimTask() async { await ask { try await $0.claimTask() } }
    public func foundAlliance(name: String, tag: String) async { await ask { try await $0.foundAlliance(name: name, tag: tag) } }
    public func joinAlliance(_ alliance: UInt64) async { await ask { try await $0.joinAlliance(alliance) } }
    public func leaveAlliance() async { await ask { try await $0.leaveAlliance() } }
    public func answer(applicant: UInt64, admit: Bool) async { await ask { try await $0.answer(applicant: applicant, admit: admit) } }
    public func expel(_ player: UInt64) async { await ask { try await $0.expel(player) } }
    public func setRank(of player: UInt64, to rank: Int) async { await ask { try await $0.setRank(of: player, to: rank) } }
    public func setAlliance(open: Bool, words: String) async { await ask { try await $0.setAlliance(open: open, words: words) } }
    public func say(_ words: String, withinAlliance: Bool) async { await ask { try await $0.say(words, withinAlliance: withinAlliance) } }

    /// Reports a line of chat to the realm's owner, and says so.
    public func report(line: UInt64, withinAlliance: Bool) async {
        if await ask({ try await $0.reportLine(line, withinAlliance: withinAlliance) }) {
            reported.insert(LiveSession.reportKey(line, withinAlliance))
            said = LiveSession.reportedWords
        }
    }

    /// Whether the player has reported a line while this session lasts.
    public func hasReported(line: UInt64, withinAlliance: Bool) -> Bool {
        reported.contains(LiveSession.reportKey(line, withinAlliance))
    }

    static func reportKey(_ line: UInt64, _ withinAlliance: Bool) -> String { (withinAlliance ? "alliance " : "realm ") + String(line) }

    /// What the player is told of a line they reported.
    public static let reportedWords = "Reported to the realm's owner, who reads every report."

    // The alliance's help, land, learning and Moonspire; commanders'
    // talents, pairs and the city's keeper; the day's work, items and
    // contests.
    public func askHelp(job: UInt64) async { await ask { try await $0.askHelp(job: job) } }
    /// Helps with every work allies have asked help with.
    public func helpAll() async { await ask { try await $0.help(job: 0) } }
    public func raiseWard(at hex: LiveHex) async { await ask { try await $0.raiseWard(at: hex) } }
    public func razeWard(_ ward: UInt64) async { await ask { try await $0.razeWard(ward) } }
    public func giveToLearning(topic: Int, _ goods: LiveGoods) async { await ask { try await $0.giveToLearning(topic: topic, goods) } }
    public func giveToSpire(_ goods: LiveGoods) async { await ask { try await $0.giveToSpire(goods) } }
    public func learnTalent(commander: UInt64, talent: Int) async { await ask { try await $0.learnTalent(commander: commander, talent: talent) } }
    public func forgetTalents(commander: UInt64) async { await ask { try await $0.forgetTalents(commander: commander) } }
    public func pair(commander: UInt64, with partner: UInt64) async { await ask { try await $0.pair(commander: commander, with: partner) } }
    public func keepCity(commander: UInt64) async { await ask { try await $0.keepCity(commander: commander) } }
    public func speedUp(job: UInt64) async { await ask { try await $0.speedUp(job: job) } }
    public func useItem(_ item: Int, on job: UInt64) async { await ask { try await $0.useItem(item, on: job) } }
    public func usePeace(_ item: Int) async { await ask { try await $0.usePeace(item) } }
    public func forge(piece: Int) async { await ask { try await $0.forge(piece: piece) } }
    public func equip(gear: UInt64, on commander: UInt64) async { await ask { try await $0.equip(gear: gear, on: commander) } }
    public func unequip(gear: UInt64) async { await ask { try await $0.unequip(gear: gear) } }
    public func claimBoons() async { await ask { try await $0.claimBoons() } }
    public func buy(item: Int, count: UInt64 = 1) async { await ask { try await $0.buy(item: item, count: count) } }
    public func readTome(commander: UInt64, item: Int, count: UInt64 = 1) async {
        await ask { try await $0.readTome(commander: commander, item: item, count: count) }
    }
    public func openChest(_ chest: Int) async { await ask { try await $0.openChest(chest) } }
    public func claimPrize(contest: Int, place: Int) async { await ask { try await $0.claimPrize(contest: contest, place: place) } }
    public func claimPlace(contest: Int) async { await ask { try await $0.claimPlace(contest: contest) } }
    /// Asks the realm for a code to bring another device of the player's in.
    public func offerLink() async { await ask { try await $0.offerLink() } }
    /// Takes a code another device of a player's shows, as typed: this
    /// device, playing as no one yet, plays as them from now on.
    public func takeLink(_ code: String) async { await ask { try await $0.takeLink(code) } }
    /// Takes a summons to the Tavern: one of the realm's commanders comes,
    /// or sigils for one of the player's own.
    public func draw() async { await ask { try await $0.draw() } }
    /// Raises a commander's gift a level with the sigils they hold.
    public func raiseGift(commander: UInt64) async { await ask { try await $0.raiseGift(commander: commander) } }
    /// Names this device among the player's, as its client calls it, once:
    /// when the realm has it called nothing.
    public func nameDevice(_ name: String) async {
        guard world.me != nil, world.devices.first(where: \.current)?.name.isEmpty == true else { return }
        await ask { try await $0.nameDevice(name) }
    }
    /// Lets go another of the player's devices: a phone lost, a Mac given away.
    public func letGo(_ device: LiveDevice) async { await ask { try await $0.letGo(device: device.number) } }
    /// Leaves the realm for good, the player's own name typed to be sure:
    /// whoever comes back on this device joins anew, and is shown their
    /// own new city first.
    public func leaveRealm(name: String) async {
        if await ask({ try await $0.leaveRealm(name: name) }) {
            placed = false
        }
    }
    public func sendEnvoy(to alliance: UInt64, terms: Int, days: Int) async { await ask { try await $0.sendEnvoy(to: alliance, terms: terms, days: days) } }
    public func answerEnvoy(_ envoy: UInt64, accept: Bool) async { await ask { try await $0.answerEnvoy(envoy, accept: accept) } }
    public func breakPact(_ pact: UInt64) async { await ask { try await $0.breakPact(pact) } }
    public func ransom(commander: UInt64) async { await ask { try await $0.ransom(commander: commander) } }
    public func releasePrisoner(commander: UInt64) async { await ask { try await $0.releasePrisoner(commander: commander) } }
    public func petition(_ goods: LiveGoods) async { await ask { try await $0.petition(goods) } }
    public func answerPetition(of asker: UInt64, _ goods: LiveGoods) async { await ask { try await $0.answerPetition(of: asker, goods) } }
    public func withdrawPetition() async { await ask { try await $0.withdrawPetition() } }
    public func bestowTitle(_ title: Int, on player: UInt64) async { await ask { try await $0.bestowTitle(title, on: player) } }
    public func takeTitle(_ title: Int) async { await ask { try await $0.takeTitle(title) } }
    public func sendLetter(to player: UInt64, _ words: String) async { await ask { try await $0.sendLetter(to: player, words) } }
    public func sendAllianceLetter(_ words: String) async { await ask { try await $0.sendAllianceLetter(words) } }
    public func readLetter(_ letter: UInt64) async { await ask { try await $0.readLetter(letter) } }
    public func forgetLetter(_ letter: UInt64) async { await ask { try await $0.forgetLetter(letter) } }

    /// One soldier of the first kind and tier standing ready: a scout.
    public var scoutParty: [(kind: Int, tier: Int, count: UInt64)] {
        everyoneReady.first.map { [(kind: $0.kind, tier: $0.tier, count: UInt64(1))] } ?? []
    }

    /// Sends a scout to see the city at a hex.
    public func scout(at hex: LiveHex) async {
        let party = scoutParty
        await ask { try await $0.scout(at: hex, soldiers: party) }
    }

    /// Sends a scout to find what the cairn at a hex holds.
    public func explore(at hex: LiveHex) async {
        let party = scoutParty
        await ask { try await $0.explore(at: hex, soldiers: party) }
    }

    /// Sends everyone ready against another player's army gathering at the
    /// site at a hex, led by the highest commander in the city.
    public func raid(at hex: LiveHex) async {
        let asked = everyoneReady
        let leader = world.freeLeader?.id ?? 0
        await ask { try await $0.raid(at: hex, soldiers: asked, leader: leader) }
    }

    /// Sends everyone ready to stay in an ally's city at a hex, led by the
    /// highest commander in the city.
    public func reinforce(at hex: LiveHex) async {
        let asked = everyoneReady
        let leader = world.freeLeader?.id ?? 0
        await ask { try await $0.reinforce(at: hex, soldiers: asked, leader: leader) }
    }

    /// Moves the player's city to clear ground at a hex.
    public func moveCity(to hex: LiveHex) async { await ask { try await $0.moveCity(to: hex) } }

    /// Joins a rally of the player's alliance with everyone ready, led by
    /// the highest commander in the city.
    public func joinRally(_ rally: UInt64) async {
        let asked = everyoneReady
        let leader = world.freeLeader?.id ?? 0
        await ask { try await $0.joinRally(rally, soldiers: asked, leader: leader) }
    }

    /// Calls a rally of the player's alliance against what stands at a hex
    /// (a barrow, another's city, or a gate of the ridge) with everyone
    /// ready, led by the highest commander in the city.
    public func callRally(at hex: LiveHex) async {
        let asked = everyoneReady
        let leader = world.freeLeader?.id ?? 0
        await ask { try await $0.callRally(at: hex, soldiers: asked, leader: leader) }
    }

    /// Sends soldiers to what the player has chosen: to gather at a site,
    /// to clear a barrow, or against another player's city. Elsewhere
    /// there is nothing to send them for. The army is led by the commander
    /// named, or where none is, by the highest of those in the city.
    public func send(_ soldiers: [(kind: Int, tier: Int, count: UInt64)], to hex: LiveHex, leader: UInt64? = nil) async {
        let asked = soldiers.map { (kind: $0.kind, tier: $0.tier, count: $0.count) }
        // Led by whoever is named, or by the highest of those in the city.
        let leader = leader ?? world.freeLeader?.id ?? 0
        switch selection(at: hex) {
        case .site(let site): await ask { try await $0.gather(at: site.hex, soldiers: asked, leader: leader) }
        case .barrow(let barrow): await ask { try await $0.hunt(at: barrow.hex, soldiers: asked, leader: leader) }
        case .city(let city, _): await ask { try await $0.attack(at: city.hex, soldiers: asked, leader: leader) }
        default: said = "There is nothing to send an army for there."
        }
    }
}
