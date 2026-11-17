import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import NullmereRealm

/// What the realm said when it would not do what was asked: its own
/// words, to show the player as they are.
public struct LiveRefusal: Error, Equatable, CustomStringConvertible, Sendable {
    public let words: String
    public var description: String { words }

    public init(words: String) {
        self.words = words
    }
}

/// A player's line to the realm: who they are there, what they ask of it,
/// and the realm's rows as it pushes them.
///
/// Everything the game decides is decided in the realm. The client asks
/// (each method here is one reducer) and reads; where the realm refuses,
/// it says why in words of its own, and they are thrown as `LiveRefusal`.
public final class LiveClient: @unchecked Sendable {
    public let credentials: SpacetimeCredentials
    private let transport: SpacetimeHTTP
    private let lock = NSLock()
    private var watching: (any RealmWatch)?

    public init(transport: SpacetimeHTTP, credentials: SpacetimeCredentials) {
        self.transport = transport
        self.credentials = credentials
    }

    /// A line to a realm's database on a server, as the identity given, or
    /// as a new one the server makes: keep its credentials to come back
    /// as the same player.
    public static func open(server: URL, database: String, credentials: SpacetimeCredentials? = nil) async throws -> LiveClient {
        let transport = SpacetimeHTTP(server: server, database: database)
        let known: SpacetimeCredentials
        if let credentials { known = credentials } else { known = try await transport.createIdentity() }
        return LiveClient(transport: transport, credentials: known)
    }

    // MARK: Reading

    /// Begins watching the realm: its rows as they stand, then every
    /// change as it happens; `changed` is told each time. False where no
    /// subscription can be opened (the client can still read with `read`).
    @discardableResult
    public func watch(changed: @escaping @Sendable () -> Void = {}) async -> Bool {
        let watch = await transport.watch(LiveSchema.queries, token: credentials.token, tables: LiveSchema.tables, changed: changed)
        keep(watch)
        return watch != nil
    }

    /// Keeps a subscription in place of the one kept, which is stopped.
    private func keep(_ watch: (any RealmWatch)?) {
        lock.lock()
        defer { lock.unlock() }
        watching?.stop()
        watching = watch
    }

    /// Whether the realm's rows are coming as they change.
    public var isLive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return watching?.mirror?.isLive ?? false
    }

    /// The realm as the subscription has it now; empty until it takes.
    public var world: LiveWorld {
        lock.lock()
        let mirror = watching?.mirror
        lock.unlock()
        return LiveWorld(snapshot: mirror?.snapshot() ?? [:])
    }

    /// The realm read afresh, table by table, without a subscription.
    public func read() async throws -> LiveWorld {
        var snapshot: [String: [[JSONValue]]] = [:]
        for table in LiveSchema.tables.keys.sorted() {
            snapshot[table] = try await transport.query("SELECT * FROM \(table)", token: credentials.token)
        }
        return LiveWorld(snapshot: snapshot)
    }

    /// Stops watching.
    public func close() {
        keep(nil)
    }

    // MARK: Asking

    /// Calls a reducer; the realm's refusal is thrown in its own words.
    private func ask(_ reducer: String, _ arguments: [ReducerArgument]) async throws {
        do {
            try await transport.call(reducer, arguments, token: credentials.token)
        } catch let error as SpacetimeError where error.status == 530 || error.status == 400 {
            throw LiveRefusal(words: error.description)
        }
    }

    /// Joins the realm under a name: a city is founded for the player.
    public func join(name: String) async throws { try await ask("join", [.string(name)]) }

    /// Builds a building the player's city has not got, by its kind.
    public func build(_ kind: Int) async throws { try await ask("build", [.integer(UInt64(kind))]) }

    /// Raises one of the player's buildings a level.
    public func upgrade(building: UInt64) async throws { try await ask("upgrade", [.integer(building)]) }

    /// Trains a batch of soldiers of a tier in a training building.
    public func train(building: UInt64, tier: Int, count: UInt64) async throws {
        try await ask("train", [.integer(building), .integer(UInt64(tier)), .integer(count)])
    }

    /// Raises soldiers of a kind ready in the player's city from one tier to
    /// a higher, in the building that trains them.
    public func promote(building: UInt64, from: Int, to: Int, count: UInt64) async throws {
        try await ask("promote", [.integer(building), .integer(UInt64(from)), .integer(UInt64(to)), .integer(count)])
    }

    /// Sends soldiers from the player's city to gather at a hex, under one
    /// of the player's commanders (by their number) or under none.
    public func gather(at hex: LiveHex, soldiers: [(kind: Int, tier: Int, count: UInt64)], leader: UInt64 = 0) async throws {
        let records = soldiers.map { ["kind": UInt64($0.kind), "tier": UInt64($0.tier), "count": $0.count] }
        try await ask("send", [.signed(Int64(hex.q)), .signed(Int64(hex.r)), .integer(1), .records(records), .integer(leader)])
    }

    /// Sends soldiers from the player's city to clear the barrow of the
    /// Unquiet at a hex.
    public func hunt(at hex: LiveHex, soldiers: [(kind: Int, tier: Int, count: UInt64)], leader: UInt64 = 0) async throws {
        let records = soldiers.map { ["kind": UInt64($0.kind), "tier": UInt64($0.tier), "count": $0.count] }
        try await ask("send", [.signed(Int64(hex.q)), .signed(Int64(hex.r)), .integer(2), .records(records), .integer(leader)])
    }

    /// Sends soldiers from the player's city against another player's
    /// city at a hex.
    public func attack(at hex: LiveHex, soldiers: [(kind: Int, tier: Int, count: UInt64)], leader: UInt64 = 0) async throws {
        let records = soldiers.map { ["kind": UInt64($0.kind), "tier": UInt64($0.tier), "count": $0.count] }
        try await ask("send", [.signed(Int64(hex.q)), .signed(Int64(hex.r)), .integer(3), .records(records), .integer(leader)])
    }

    /// Has some of the player's wounded of a kind and tier healed.
    public func heal(kind: Int, tier: Int, count: UInt64) async throws {
        try await ask("heal", [.integer(UInt64(kind)), .integer(UInt64(tier)), .integer(count)])
    }

    /// Marks one of the player's reports read.
    public func read(report: UInt64) async throws { try await ask("read_report", [.integer(report)]) }

    /// Throws one of the player's reports away.
    public func forget(report: UInt64) async throws { try await ask("forget_report", [.integer(report)]) }

    /// Takes on another commander.
    public func hire() async throws { try await ask("hire", []) }

    /// Has the player's Academy study the next level of a topic.
    public func learn(topic: Int) async throws { try await ask("learn", [.integer(UInt64(topic))]) }

    /// Claims what the task the player is on gives, if it is done.
    public func claimTask() async throws { try await ask("claim_task", []) }

    // MARK: Alliances and chat

    /// Founds an alliance under a name and a tag, with the player its leader.
    public func foundAlliance(name: String, tag: String) async throws { try await ask("found_alliance", [.string(name), .string(tag)]) }

    /// Joins an alliance, or asks to be let into one that is not open.
    public func joinAlliance(_ alliance: UInt64) async throws { try await ask("join_alliance", [.integer(alliance)]) }

    /// Leaves the player's alliance.
    public func leaveAlliance() async throws { try await ask("leave_alliance", []) }

    /// Lets in, or turns away, a player who asked to join.
    public func answer(applicant: UInt64, admit: Bool) async throws { try await ask("answer_applicant", [.integer(applicant), .bool(admit)]) }

    /// Puts a member of lower rank out of the alliance.
    public func expel(_ player: UInt64) async throws { try await ask("expel", [.integer(player)]) }

    /// Gives a member a rank: `LiveMember.member`, `.officer` or `.leader`.
    public func setRank(of player: UInt64, to rank: Int) async throws { try await ask("set_rank", [.integer(player), .integer(UInt64(rank))]) }

    /// Says whether anyone may join without being let in, and what the
    /// alliance says of itself.
    public func setAlliance(open: Bool, words: String) async throws { try await ask("set_alliance", [.bool(open), .string(words)]) }

    /// Says something: to the whole realm, or within the player's alliance.
    public func say(_ words: String, withinAlliance: Bool) async throws { try await ask("say", [.bool(withinAlliance), .string(words)]) }
    /// Reports a line said in the realm's chat, or within the player's
    /// alliance, to the realm's owner.
    public func reportLine(_ line: UInt64, withinAlliance: Bool) async throws { try await ask("report_line", [.integer(line), .bool(withinAlliance)]) }

    /// Calls one of the player's armies home.
    public func recall(march: UInt64) async throws { try await ask("recall", [.integer(march)]) }

    // MARK: Scouts, allies' cities and rallies

    private func records(_ soldiers: [(kind: Int, tier: Int, count: UInt64)]) -> ReducerArgument {
        .records(soldiers.map { ["kind": UInt64($0.kind), "tier": UInt64($0.tier), "count": $0.count] })
    }

    /// Sends scouts from the player's city to see another player's city.
    public func scout(at hex: LiveHex, soldiers: [(kind: Int, tier: Int, count: UInt64)]) async throws {
        try await ask("send", [.signed(Int64(hex.q)), .signed(Int64(hex.r)), .integer(4), records(soldiers), .integer(0)])
    }

    /// Sends scouts from the player's city to find what the cairn at a hex holds.
    public func explore(at hex: LiveHex, soldiers: [(kind: Int, tier: Int, count: UInt64)]) async throws {
        try await ask("send", [.signed(Int64(hex.q)), .signed(Int64(hex.r)), .integer(7), records(soldiers), .integer(0)])
    }

    /// Sends soldiers from the player's city against another player's army
    /// gathering at the site at a hex.
    public func raid(at hex: LiveHex, soldiers: [(kind: Int, tier: Int, count: UInt64)], leader: UInt64 = 0) async throws {
        try await ask("send", [.signed(Int64(hex.q)), .signed(Int64(hex.r)), .integer(8), records(soldiers), .integer(leader)])
    }

    /// Sends soldiers from the player's city to stay in an ally's.
    public func reinforce(at hex: LiveHex, soldiers: [(kind: Int, tier: Int, count: UInt64)], leader: UInt64 = 0) async throws {
        try await ask("send", [.signed(Int64(hex.q)), .signed(Int64(hex.r)), .integer(5), records(soldiers), .integer(leader)])
    }

    /// Calls a rally of the player's alliance against the barrow or the
    /// city at a hex, with an army of the player's own.
    public func callRally(at hex: LiveHex, soldiers: [(kind: Int, tier: Int, count: UInt64)], leader: UInt64 = 0) async throws {
        try await ask("call_rally", [.signed(Int64(hex.q)), .signed(Int64(hex.r)), records(soldiers), .integer(leader)])
    }

    /// Joins a rally of the player's alliance that is still mustering.
    public func joinRally(_ rally: UInt64, soldiers: [(kind: Int, tier: Int, count: UInt64)], leader: UInt64 = 0) async throws {
        try await ask("join_rally", [.integer(rally), records(soldiers), .integer(leader)])
    }

    // MARK: An alliance's help, land, learning and Moonspire

    /// Asks the player's alliance's help with a work under way in their city.
    public func askHelp(job: UInt64) async throws { try await ask("ask_help", [.integer(job)]) }

    /// Helps an ally with a work they asked help with; with 0, every one.
    public func help(job: UInt64) async throws { try await ask("help", [.integer(job)]) }

    /// Raises a wardstone of the player's alliance at a hex, as an officer.
    public func raiseWard(at hex: LiveHex) async throws { try await ask("raise_ward", [.signed(Int64(hex.q)), .signed(Int64(hex.r))]) }

    /// Moves the player's city to clear ground, with its buildings and troops.
    public func moveCity(to hex: LiveHex) async throws { try await ask("move_city", [.signed(Int64(hex.q)), .signed(Int64(hex.r))]) }

    /// Takes down one of the player's alliance's wardstones, as an officer.
    public func razeWard(_ ward: UInt64) async throws { try await ask("raze_ward", [.integer(ward)]) }

    /// Gives grain, timber and stone toward the next level of a topic the
    /// player's alliance learns.
    public func giveToLearning(topic: Int, _ goods: LiveGoods) async throws {
        try await ask("give_to_learning", [.integer(UInt64(topic)), .integer(goods.grain), .integer(goods.timber), .integer(goods.stone)])
    }

    /// Gives goods toward the player's alliance's Moonspire.
    public func giveToSpire(_ goods: LiveGoods) async throws {
        try await ask("give_to_spire", [.integer(goods.grain), .integer(goods.timber), .integer(goods.stone), .integer(goods.moonsalt)])
    }

    // MARK: Commanders' talents, pairs and the city's keeper

    /// Puts one of a commander's points into a talent.
    public func learnTalent(commander: UInt64, talent: Int) async throws {
        try await ask("learn_talent", [.integer(commander), .integer(UInt64(talent))])
    }

    /// Has a commander forget every talent, for goods.
    public func forgetTalents(commander: UInt64) async throws { try await ask("forget_talents", [.integer(commander)]) }

    /// Has a commander go out beside another whenever that one leads; with
    /// 0, no one.
    public func pair(commander: UInt64, with partner: UInt64) async throws { try await ask("pair", [.integer(commander), .integer(partner)]) }

    /// Has a commander keep the player's city; with 0, none.
    public func keepCity(commander: UInt64) async throws { try await ask("keep_city", [.integer(commander)]) }

    // MARK: The day's work, items and contests

    /// Hastens a work under way in the player's city, for goods.
    public func speedUp(job: UInt64) async throws { try await ask("speed_up", [.integer(job)]) }

    /// Uses one of the player's items on a work under way.
    public func useItem(_ item: Int, on job: UInt64) async throws { try await ask("use_item", [.integer(UInt64(item)), .integer(job)]) }
    /// Has a piece of gear made at the player's Forge.
    public func forge(piece: Int) async throws { try await ask("forge", [.integer(UInt64(piece))]) }

    /// Has one of the player's commanders wear a piece of their gear.
    public func equip(gear: UInt64, on commander: UInt64) async throws { try await ask("equip", [.integer(gear), .integer(commander)]) }

    /// Takes a piece of the player's gear off whoever wears it.
    public func unequip(gear: UInt64) async throws { try await ask("unequip", [.integer(gear)]) }

    /// Claims every gift waiting on the player, for goods in their city.
    public func claimBoons() async throws { try await ask("claim_boons", []) }
    /// Has one of the player's commanders read so many tomes of war.
    public func readTome(commander: UInt64, item: Int, count: UInt64) async throws {
        try await ask("read_tome", [.integer(commander), .integer(UInt64(item)), .integer(count)])
    }
    /// Buys so many of a thing from the alliance's stores with the player's honour.
    public func buy(item: Int, count: UInt64) async throws { try await ask("buy", [.integer(UInt64(item)), .integer(count)]) }

    /// Uses one of the player's items of peace on their city.
    public func usePeace(_ item: Int) async throws { try await ask("use_peace", [.integer(UInt64(item))]) }

    /// Opens a chest of the day's work, by its number.
    public func openChest(_ chest: Int) async throws { try await ask("open_chest", [.integer(UInt64(chest))]) }

    // MARK: Envoys, pacts, prisoners and petitions

    /// Sends another alliance an envoy with the terms of a pact
    /// (`LivePact.truce` or `.passage`) for so many days.
    public func sendEnvoy(to alliance: UInt64, terms: Int, days: Int) async throws {
        try await ask("send_envoy", [.integer(alliance), .integer(UInt64(terms)), .integer(UInt64(days))])
    }

    /// Accepts, or turns away, an envoy come to the player's alliance.
    public func answerEnvoy(_ envoy: UInt64, accept: Bool) async throws { try await ask("answer_envoy", [.integer(envoy), .bool(accept)]) }

    /// Breaks a pact of the player's alliance: it holds a day more.
    public func breakPact(_ pact: UInt64) async throws { try await ask("break_pact", [.integer(pact)]) }

    /// Ransoms one of the player's commanders held prisoner.
    public func ransom(commander: UInt64) async throws { try await ask("ransom", [.integer(commander)]) }

    /// Lets a commander the player holds prisoner go, for nothing.
    public func releasePrisoner(commander: UInt64) async throws { try await ask("release_prisoner", [.integer(commander)]) }

    /// Petitions the player's alliance for goods.
    public func petition(_ goods: LiveGoods) async throws {
        try await ask("petition_alliance", [.integer(goods.grain), .integer(goods.timber), .integer(goods.stone), .integer(goods.moonsalt)])
    }

    /// Answers an ally's petition with goods from the player's city.
    public func answerPetition(of asker: UInt64, _ goods: LiveGoods) async throws {
        try await ask("answer_petition", [.integer(asker), .integer(goods.grain), .integer(goods.timber), .integer(goods.stone), .integer(goods.moonsalt)])
    }

    /// Withdraws the player's petition.
    public func withdrawPetition() async throws { try await ask("withdraw_petition", []) }

    // MARK: Titles and letters

    /// Bestows a title of the Mere on a player, as the Lord of the Mere.
    public func bestowTitle(_ title: Int, on player: UInt64) async throws { try await ask("bestow_title", [.integer(UInt64(title)), .integer(player)]) }

    /// Takes a title of the Mere back, as the Lord of the Mere.
    public func takeTitle(_ title: Int) async throws { try await ask("take_title", [.integer(UInt64(title))]) }

    /// Writes a letter to another player.
    public func sendLetter(to player: UInt64, _ words: String) async throws { try await ask("send_letter", [.integer(player), .string(words)]) }

    /// Writes one letter to every other member of the player's alliance, as an officer.
    public func sendAllianceLetter(_ words: String) async throws { try await ask("send_alliance_letter", [.string(words)]) }

    /// Marks a letter to the player read.
    public func readLetter(_ letter: UInt64) async throws { try await ask("read_letter", [.integer(letter)]) }

    /// Forgets a letter to the player.
    public func forgetLetter(_ letter: UInt64) async throws { try await ask("forget_letter", [.integer(letter)]) }

    /// Claims a prize of one of the realm's contests, by its place.
    public func claimPrize(contest: Int, place: Int) async throws {
        try await ask("claim_prize", [.integer(UInt64(contest)), .integer(UInt64(place))])
    }

    /// Claims what the player's place among the first three of a contest's
    /// last round over gives.
    public func claimPlace(contest: Int) async throws {
        try await ask("claim_place", [.integer(UInt64(contest))])
    }

    /// Asks for a code to bring another device of the player's into the
    /// realm as them: shown in the world's `link` once the realm has it.
    public func offerLink() async throws { try await ask("offer_link", []) }

    /// Takes a code another device of a player's shows, as typed: this
    /// client, which plays as no one yet, plays as them from now on.
    public func takeLink(_ code: String) async throws { try await ask("take_link", [.string(code)]) }

    /// Names the device this client runs on, as the player's devices show
    /// it ("Mac", "iPhone").
    public func nameDevice(_ name: String) async throws { try await ask("name_device", [.string(name)]) }

    /// Lets go another of the player's devices, by its number: it plays as
    /// them no more.
    public func letGo(device: UInt64) async throws { try await ask("let_go", [.integer(device)]) }

    /// Leaves the realm for good, the player's own name typed to be sure.
    public func leaveRealm(name: String) async throws { try await ask("leave_realm", [.string(name)]) }
}
