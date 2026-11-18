import Foundation
import NullmereRealm

/// The realm as one client knows it at a moment: what everyone may read
/// (the land, who plays, where cities, sites and the Unquiet's barrows
/// stand, the armies on the map, the game's numbers) and what is the
/// player's own (their city, its buildings, work under way, goods, troops
/// and armies, their energy, and the reports of what their armies did).
public struct LiveWorld: Equatable, Sendable {
    public var realm: LiveRealm?
    public var players: [UInt64: LivePlayer] = [:]
    public var cities: [UInt64: LiveCity] = [:]
    public var places: [LiveHex: LivePlace] = [:]
    public var sites: [UInt64: LiveSite] = [:]
    public var barrows: [UInt64: LiveBarrow] = [:]
    public var marches: [UInt64: LiveMarch] = [:]
    public var alliances: [UInt64: LiveAlliance] = [:]
    /// Each player's place in an alliance, by the player's number.
    public var members: [UInt64: LiveMember] = [:]
    /// What has been said in the realm, the oldest first.
    public var realmChat: [LiveSaying] = []
    /// The land's chunks, sixteen hexes by sixteen, a byte a hex.
    public var land: [UInt64: [UInt8]] = [:]
    /// The players' first tasks, by their place in the order.
    public var tasks: [Int: LiveTask] = [:]
    var studies: [UInt64: LiveStudy] = [:]
    var blueprints: [UInt64: LiveBlueprint] = [:]
    var soldiers: [UInt64: LiveSoldier] = [:]
    /// The day's deeds and its chests, the levels of favour, the items
    /// there are, and the realm's contests and their prizes.
    public var duties: [LiveDuty] = []
    public var chests: [LiveChest] = []
    public var graces: [LiveGrace] = []
    public var wares: [Int: LiveWare] = [:]
    /// The realm's commanders, by number: who each is, their renown and gift.
    public var people: [Int: LivePerson] = [:]
    public var trials: [Int: LiveTrial] = [:]
    public var prizes: [LivePrize] = []
    /// Where every player stands in the contests' rounds, and what the
    /// first three places of a round give.
    public var standings: [LiveStanding] = []
    public var laurels: [LiveLaurel] = []
    /// The code the player has asked for, to bring another device in.
    public var link: LiveLink?
    /// The player's devices, the one looking first.
    public var devices: [LiveDevice] = []
    /// Every alliance's Moonspire this season, by the alliance; the
    /// realm's seasons, by their number.
    public var spires: [UInt64: LiveSpire] = [:]
    public var seasons: [UInt64: LiveSeason] = [:]
    /// Every alliance's wardstones, and what every alliance has learnt.
    public var wards: [UInt64: LiveWard] = [:]
    public var learnings: [UInt64: LiveLearning] = [:]
    /// The gates of the ridge, by their number.
    public var gates: [UInt64: LiveGate] = [:]
    /// Every pact between alliances, by its number; the titles of the Mere
    /// held, by the title.
    public var pacts: [UInt64: LivePact] = [:]
    public var titles: [Int: LiveTitle] = [:]
    /// What each player has struck down in battles between cities, by player.
    public var fame: [UInt64: LiveFame] = [:]

    public var me: LivePlayer?
    public var city: LiveCity?
    public var buildings: [LiveBuilding] = []
    public var jobs: [LiveJob] = []
    public var stock: LiveStock?
    public var troops: [LiveTroop] = []
    public var squads: [LiveSquad] = []
    public var hauls: [LiveHaul] = []
    public var hunt: LiveHunt?
    /// The player's reports, the latest first.
    public var reports: [LiveReport] = []
    /// The player's commanders, in the order they came.
    public var commanders: [LiveCommander] = []
    /// What the player's city has learnt: each topic's level, by the topic.
    public var lore: [Int: Int] = [:]
    /// The task the player is on, by its place in the order; one past the
    /// last when they have done them all.
    public var step: Int?
    /// What has been said within the player's alliance, the oldest first.
    public var allianceChat: [LiveSaying] = []
    /// Who has asked to join the player's alliance, for its officers; or
    /// the player's own asking, while they are in none.
    public var applicants: [LiveApplicant] = []
    /// What the player has done of the day's work, their favour, the
    /// items they hold (count by item), and what they have scored in the
    /// realm's contests.
    public var daily: LiveDaily?
    public var favour: LiveFavour?
    public var satchel: [Int: UInt64] = [:]
    public var tallies: [LiveTally] = []
    /// The talents of the player's commanders (points by talent, by
    /// commander), who goes out beside whom (partner by leader), and the
    /// commander keeping their city.
    public var skills: [UInt64: [Int: Int]] = [:]
    public var bonds: [UInt64: UInt64] = [:]
    public var keeper: UInt64?
    /// The rallies of the player's alliance and the armies in them (by
    /// march), its members' askings for help, the works the player has
    /// helped with, and what the player has given toward its Moonspire.
    public var rallies: [LiveRally] = []
    public var musters: [UInt64: LiveMuster] = [:]
    public var pleas: [LivePlea] = []
    public var helped: Set<UInt64> = []
    public var gift: LiveGift?
    /// The envoys from or to the player's alliance, the prisoners they
    /// hold and their own commanders held (by the commander), and their
    /// alliance's petitions (by who made them).
    public var envoys: [LiveEnvoy] = []
    public var prisoners: [UInt64: LivePrisoner] = [:]
    public var petitions: [UInt64: LivePetition] = [:]
    /// The letters the player has written and been written, the latest first.
    public var letters: [LiveLetter] = []
    /// The players the player has shut out: their letters are not taken,
    /// and what they say, in either chat or a letter, is left unshown.
    public var shunned: Set<UInt64> = []
    /// The marks of the player's alliance on the map, the first set first.
    public var marks: [LiveMark] = []
    /// The realm's milestones, by number, and those whose gifts the player
    /// has claimed.
    public var milestones: [LiveMilestone] = []
    public var claimed: Set<UInt64> = []
    /// The day of the realm the player last claimed the day's welcome on,
    /// and how many days in a row they had then.
    public var welcomed: LiveWelcome?
    /// The Barrow Road's stages, the first first, and how far along it the
    /// player has come.
    public var stages: [LiveStage] = []
    public var road: LiveRoad?
    /// The Lists: those in it, by place; their bands; what its purse
    /// gives; and the player's day in it.
    public var entrants: [LiveEntrant] = []
    public var guards: [LiveGuard] = []
    public var purses: [LivePurse] = []
    public var tilt: LiveTilt?
    /// What the Forge makes, by piece; and the player's gear.
    public var patterns: [Int: LivePattern] = [:]
    public var gear: [LiveGear] = []
    /// The gifts waiting on the player from their alliance's deeds.
    public var boons: [LiveBoon] = []
    /// The cairns of the old folk on the land, by number; and those whose
    /// hoards the player's scouts have found.
    public var cairns: [UInt64: LiveCairn] = [:]
    public var finds: Set<UInt64> = []
    /// The player's honour, and what the alliance's stores sell for it,
    /// item by item.
    public var honour: LiveHonour?
    public var prices: [Int: UInt64] = [:]

    public init() {}

    /// The world as a subscription's rows tell it, table by table.
    public init(snapshot: [String: [[JSONValue]]]) {
        func rows<Row>(_ table: String, _ make: ([JSONValue]) -> Row?) -> [Row] { (snapshot[table] ?? []).compactMap(make) }
        realm = rows("realm", LiveRealm.init).first
        // Those the player shut out first: what they said is left unshown.
        let shut = Set((snapshot["my_shunned"] ?? []).compactMap { Cells(row: $0).unsigned(2) })
        shunned = shut
        players = Dictionary(rows("player", LivePlayer.init).map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        cities = Dictionary(rows("city", LiveCity.init).map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        places = Dictionary(rows("place", LivePlace.init).map { ($0.hex, $0) }, uniquingKeysWith: { _, new in new })
        sites = Dictionary(rows("site", LiveSite.init).map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        barrows = Dictionary(rows("barrow", LiveBarrow.init).map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        marches = Dictionary(rows("march", LiveMarch.init).map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        alliances = Dictionary(rows("alliance", LiveAlliance.init).map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        members = Dictionary(rows("member", LiveMember.init).map { ($0.player, $0) }, uniquingKeysWith: { _, new in new })
        realmChat = rows("realm_chat", LiveSaying.init(realm:)).filter { !shut.contains($0.player) }.sorted { $0.id < $1.id }
        tasks = Dictionary(rows("task", LiveTask.init).map { ($0.step, $0) }, uniquingKeysWith: { _, new in new })
        studies = Dictionary(rows("study", LiveStudy.init).map { (LiveWorld.key($0.topic, $0.level), $0) }, uniquingKeysWith: { _, new in new })
        for row in snapshot["land"] ?? [] {
            let cells = Cells(row: row)
            if let chunk = cells.unsigned(0), let ground = cells.bytes(1) { land[chunk] = ground }
        }
        blueprints = Dictionary(rows("blueprint", LiveBlueprint.init).map { (LiveWorld.key($0.building, $0.level), $0) },
                                uniquingKeysWith: { _, new in new })
        soldiers = Dictionary(rows("soldier", LiveSoldier.init).map { (LiveWorld.key($0.kind, $0.tier), $0) },
                              uniquingKeysWith: { _, new in new })
        me = rows("me", LivePlayer.init).first
        city = rows("my_city", LiveCity.init).first
        buildings = rows("my_buildings", LiveBuilding.init).sorted { $0.kind < $1.kind }
        jobs = rows("my_jobs", LiveJob.init).sorted { $0.ends < $1.ends }
        stock = rows("my_stock", LiveStock.init).first
        troops = rows("my_troops", LiveTroop.init).sorted { ($0.kind, $0.tier) < ($1.kind, $1.tier) }
        squads = rows("my_squads", LiveSquad.init).sorted { $0.id < $1.id }
        hauls = rows("my_hauls", LiveHaul.init).sorted { $0.march < $1.march }
        hunt = rows("my_hunt", LiveHunt.init).first
        reports = rows("my_reports", LiveReport.init).sorted { $0.id > $1.id }
        allianceChat = rows("my_alliance_chat", LiveSaying.init(alliance:)).filter { !shut.contains($0.player) }.sorted { $0.id < $1.id }
        applicants = rows("my_applicants", LiveApplicant.init).sorted { $0.at < $1.at }
        step = (snapshot["my_progress"] ?? []).compactMap { Cells(row: $0).whole(1) }.first
        commanders = rows("my_commanders", LiveCommander.init).sorted { $0.id < $1.id }
        for row in snapshot["my_lore"] ?? [] {
            let cells = Cells(row: row)
            if let topic = cells.whole(2), let level = cells.whole(3) { lore[topic] = level }
        }

        duties = rows("duty", LiveDuty.init).sorted { $0.deed < $1.deed }
        chests = rows("chest", LiveChest.init).sorted { $0.id < $1.id }
        graces = rows("grace", LiveGrace.init).sorted { $0.level < $1.level }
        wares = Dictionary(rows("ware", LiveWare.init).map { ($0.item, $0) }, uniquingKeysWith: { _, new in new })
        people = Dictionary(rows("person", LivePerson.init).map { ($0.number, $0) }, uniquingKeysWith: { _, new in new })
        trials = Dictionary(rows("trial", LiveTrial.init).map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        prizes = rows("prize", LivePrize.init).sorted { ($0.trial, $0.place) < ($1.trial, $1.place) }
        standings = rows("standing", LiveStanding.init)
        link = rows("my_link", LiveLink.init).first
        devices = rows("my_devices", LiveDevice.init).sorted { ($0.current ? 0 : 1, $0.number) < ($1.current ? 0 : 1, $1.number) }
        laurels = rows("laurel", LiveLaurel.init).sorted { ($0.trial, $0.place) < ($1.trial, $1.place) }
        spires = Dictionary(rows("spire", LiveSpire.init).map { ($0.alliance, $0) }, uniquingKeysWith: { _, new in new })
        seasons = Dictionary(rows("season", LiveSeason.init).map { ($0.number, $0) }, uniquingKeysWith: { _, new in new })
        wards = Dictionary(rows("ward", LiveWard.init).map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        learnings = Dictionary(rows("learning", LiveLearning.init).map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        gates = Dictionary(rows("gate", LiveGate.init).map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        pacts = Dictionary(rows("pact", LivePact.init).map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        titles = Dictionary(rows("title", LiveTitle.init).map { ($0.title, $0) }, uniquingKeysWith: { _, new in new })
        fame = Dictionary(rows("fame", LiveFame.init).map { ($0.player, $0) }, uniquingKeysWith: { _, new in new })
        daily = rows("my_daily", LiveDaily.init).first
        favour = rows("my_favour", LiveFavour.init).first
        for row in snapshot["my_satchel"] ?? [] {
            let cells = Cells(row: row)
            if let item = cells.whole(2), let count = cells.unsigned(3) { satchel[item] = count }
        }
        tallies = rows("my_tallies", LiveTally.init).sorted { $0.id < $1.id }
        for row in snapshot["my_skills"] ?? [] {
            let cells = Cells(row: row)
            if let commander = cells.unsigned(1), let talent = cells.whole(3), let points = cells.whole(4) { skills[commander, default: [:]][talent] = points }
        }
        for row in snapshot["my_bonds"] ?? [] {
            let cells = Cells(row: row)
            if let commander = cells.unsigned(0), let partner = cells.unsigned(2) { bonds[commander] = partner }
        }
        keeper = (snapshot["my_keeper"] ?? []).compactMap { Cells(row: $0).unsigned(1) }.first
        rallies = rows("my_rallies", LiveRally.init).sorted { $0.id < $1.id }
        musters = Dictionary(rows("my_musters", LiveMuster.init).map { ($0.march, $0) }, uniquingKeysWith: { _, new in new })
        pleas = rows("my_pleas", LivePlea.init).sorted { $0.job < $1.job }
        helped = Set((snapshot["my_helps"] ?? []).compactMap { Cells(row: $0).unsigned(1) })
        gift = rows("my_gift", LiveGift.init).first
        envoys = rows("my_envoys", LiveEnvoy.init).sorted { $0.id < $1.id }
        prisoners = Dictionary(rows("my_prisoners", LivePrisoner.init).map { ($0.commander, $0) }, uniquingKeysWith: { _, new in new })
        petitions = Dictionary(rows("my_petitions", LivePetition.init).map { ($0.asker, $0) }, uniquingKeysWith: { _, new in new })
        letters = rows("my_letters", LiveLetter.init).filter { !shut.contains($0.sender) }.sorted { $0.id > $1.id }
        marks = rows("my_marks", LiveMark.init).sorted { $0.id < $1.id }
        milestones = rows("milestone", LiveMilestone.init).sorted { $0.id < $1.id }
        claimed = Set((snapshot["my_claims"] ?? []).compactMap { Cells(row: $0).unsigned(2) })
        welcomed = rows("my_welcome", LiveWelcome.init).first
        stages = rows("stage", LiveStage.init).sorted { $0.id < $1.id }
        road = rows("my_road", LiveRoad.init).first
        entrants = rows("entrant", LiveEntrant.init).sorted { $0.place < $1.place }
        guards = rows("guard", LiveGuard.init).sorted { first, second in
            if first.player != second.player { return first.player < second.player }
            return first.tier != second.tier ? first.tier > second.tier : first.kind < second.kind
        }
        purses = rows("purse", LivePurse.init).sorted { $0.first < $1.first }
        tilt = rows("my_tilt", LiveTilt.init).first
        patterns = Dictionary(rows("pattern", LivePattern.init).map { ($0.piece, $0) }, uniquingKeysWith: { _, new in new })
        gear = rows("my_gear", LiveGear.init).sorted { $0.id < $1.id }
        boons = rows("my_boons", LiveBoon.init).sorted { $0.id < $1.id }
        cairns = Dictionary(rows("cairn", LiveCairn.init).map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        finds = Set(rows("my_finds", LiveCairn.found))
        honour = rows("my_honour", LiveHonour.init).first
        prices = Dictionary(rows("price", LiveHonour.price).map { ($0.item, $0.honour) }, uniquingKeysWith: { _, new in new })
    }

    private static func key(_ kind: Int, _ level: Int) -> UInt64 { UInt64(kind) << 32 | UInt64(level) }

    /// What a building costs and gives at a level.
    public func blueprint(_ building: Int, level: Int) -> LiveBlueprint? { blueprints[LiveWorld.key(building, level)] }

    /// What learning a level of a topic costs and gives.
    public func study(_ topic: Int, level: Int) -> LiveStudy? { studies[LiveWorld.key(topic, level)] }

    /// What a soldier of a kind and tier is and costs.
    public func soldier(_ kind: Int, tier: Int) -> LiveSoldier? { soldiers[LiveWorld.key(kind, tier)] }

    /// The player's building of a kind, if their city has one.
    public func building(_ kind: Int) -> LiveBuilding? { buildings.first { $0.kind == kind } }

    /// The barrow at a hex, if one stands there.
    public func barrow(at hex: LiveHex) -> LiveBarrow? {
        guard let place = places[hex], place.kind == LivePlace.barrow else { return nil }
        return barrows[place.id]
    }

    /// The alliance a player is in, if any.
    public func alliance(of player: UInt64) -> LiveAlliance? {
        members[player].flatMap { alliances[$0.alliance] }
    }

    /// The player's own alliance and their place in it.
    public var myAlliance: LiveAlliance? { me.flatMap { alliance(of: $0.id) } }
    public var myMembership: LiveMember? { me.flatMap { members[$0.id] } }

    /// Whether another player is of the player's own alliance.
    public func isAlly(_ player: UInt64) -> Bool {
        guard let mine = myMembership, let theirs = members[player] else { return false }
        return mine.alliance == theirs.alliance && player != mine.player
    }

    /// A player's name as others read it: their alliance's tag before it,
    /// where they are in one.
    public func shownName(of player: UInt64) -> String? {
        guard let name = players[player]?.name else { return nil }
        return alliance(of: player).map { "[\($0.tag)] \(name)" } ?? name
    }

    /// An alliance's members, its leader first, then by rank and by when
    /// they joined.
    public func roster(of alliance: UInt64) -> [LiveMember] {
        members.values.filter { $0.alliance == alliance }.sorted { ($1.rank, $0.joined, $0.player) < ($0.rank, $1.joined, $1.player) }
    }

    /// The task the player is on, if any are left.
    public var task: LiveTask? { step.flatMap { tasks[$0] } }

    /// Whether the player's city has done what a task asks, as far as the
    /// rows tell: the realm has the last word when it is claimed.
    public func isDone(_ task: LiveTask) -> Bool {
        guard let city else { return false }
        switch task.goal {
        case LiveTask.keep: return city.keep >= Int(task.amount)
        case LiveTask.raised: return (building(Int(task.amount))?.level ?? 0) >= task.level
        case LiveTask.soldiers:
            let home = troops.reduce(0) { $0 + $1.ready + $1.wounded }
            return home + squads.reduce(0) { $0 + $1.count + $1.wounded } >= task.amount
        case LiveTask.cleared: return (hunt?.cleared ?? 0) >= Int(task.amount)
        case LiveTask.allied: return myMembership != nil
        case LiveTask.power: return city.power >= task.amount
        case LiveTask.found: return UInt64(finds.count) >= task.amount
        default: return false
        }
    }

    /// The commander to lead the next army, where the player has not
    /// said: the highest of those in the city.
    public var freeLeader: LiveCommander? {
        commanders.filter(\.isFree).max { ($0.level, $1.id) < ($1.level, $0.id) }
    }

    /// How many commanders the city keeps, by its Tavern's level, and what
    /// taking on the next costs, as the module's catalogue has them.
    public static func commandersKept(tavern: Int) -> Int { tavern == 0 ? 1 : min(2 + tavern / 5, 6) }
    public static func hireCost(have: Int) -> LiveGoods {
        let n = UInt64(max(have, 1))
        return LiveGoods(grain: 2_000 * n * n, timber: 2_000 * n * n, stone: 1_000 * n * n, moonsalt: n >= 2 ? 50 * n : 0)
    }

    /// Why the player can't take on another commander now; nil where they can.
    public func hireBlock(at seconds: Double) -> LiveBlock? {
        let tavern = building(16)?.level ?? 0
        if tavern == 0 { return .needsOther("Tavern", 1) }
        if commanders.count >= 6 { return .commandersFull }
        if commanders.count >= LiveWorld.commandersKept(tavern: tavern) { return .needsOther("Tavern", (commanders.count - 1) * 5) }
        let have = stock?.goods(at: seconds) ?? LiveGoods()
        let cost = LiveWorld.hireCost(have: commanders.count)
        return have.covers(cost) ? nil : .short(have.short(of: cost))
    }

    /// The season under way: the latest the realm has begun.
    public var season: LiveSeason? { seasons.values.max { $0.number < $1.number } }

    /// The player's alliance's Moonspire this season, if they are in one.
    public var mySpire: LiveSpire? { myMembership.flatMap { spires[$0.alliance] } }

    /// The alliance whose land a hex is at a moment, if any's: the one
    /// whose standing wardstone within reach of it was raised first.
    public func landOf(_ hex: LiveHex, at seconds: Double) -> UInt64? {
        wards.values.filter { $0.stands(at: seconds) && $0.hex.distance(to: hex) <= LiveWard.reach }.min { $0.id < $1.id }?.alliance
    }

    /// The Lord of the Mere: the leader of the alliance that won the latest
    /// season won, if it stands.
    public var lord: UInt64? {
        seasons.values.filter { $0.victor != 0 }.max { $0.number < $1.number }.flatMap { alliances[$0.victor]?.leader }
    }

    /// Whether the player is the Lord of the Mere.
    public var isLord: Bool { me.map { $0.id == lord } ?? false }

    /// How many days the day's welcome grows over, in a row.
    public static let welcomeDays: UInt64 = 7

    /// Whether the day's welcome waits on the player to claim it today.
    public func welcomeWaits(at seconds: Double) -> Bool {
        me != nil && welcomed?.day != today(at: seconds)
    }

    /// The day in a row the welcome claimed now would count as: the day
    /// after the last, to the seventh, or the first again.
    public func welcomeStreak(at seconds: Double) -> UInt64 {
        let today = today(at: seconds)
        guard let welcomed else { return 1 }
        if welcomed.day == today { return welcomed.streak }
        return welcomed.day + 1 == today && welcomed.streak < LiveWorld.welcomeDays ? welcomed.streak + 1 : 1
    }

    /// What the day's welcome gives on a day of so many in a row: more
    /// goods each day, and on the seventh an hour's haste.
    public func welcomeGifts(_ streak: UInt64) -> String {
        let day = min(max(streak, 1), LiveWorld.welcomeDays)
        let goods = LiveGoods(grain: 1_000 * day, timber: 1_000 * day, stone: 500 * day)
        guard day == LiveWorld.welcomeDays else { return goods.words }
        return "\(goods.words), \(LiveWorld.inLine(wares[2]?.name ?? "an hour's haste"))"
    }

    /// The milestones the realm has reached whose gifts the player has not claimed.
    public var milestonesToClaim: [LiveMilestone] { milestones.filter { $0.isReached && !claimed.contains($0.id) } }

    /// What a milestone gives each player, in words.
    public func gifts(of milestone: LiveMilestone) -> String {
        var parts = milestone.gives.isNone ? [] : [milestone.gives.words]
        if milestone.items > 0, let ware = wares[milestone.item] {
            let name = LiveWorld.inLine(ware.name)
            parts.append(milestone.items == 1 ? name : "\(name) ×\(milestone.items)")
        }
        return parts.isEmpty ? "nothing" : parts.joined(separator: ", ")
    }

    /// How long the player's soldiers rest after walking the Barrow Road,
    /// as the module's catalogue has it.
    public static let roadRest = 60

    /// The stage of the Barrow Road the player walks next: none once they
    /// have cleared them all.
    public var nextStage: LiveStage? { stages.first { $0.id == (road?.cleared ?? 0) + 1 } }

    /// How many seconds the player's soldiers rest yet before they may walk
    /// the road again.
    public func roadRests(at seconds: Double) -> Int {
        guard let road else { return 0 }
        let rest = max(LiveWorld.roadRest / max(realm?.pace ?? 1, 1), 1)
        return max(road.walked + rest - Int(seconds), 0)
    }

    /// The soldiers to walk a stage with: of those ready, the kind that
    /// bests its host first and the best tiers first, then the rest, as
    /// many as may go.
    public func roadArmy(for stage: LiveStage) -> [(kind: Int, tier: Int, count: UInt64)] {
        func order(_ troop: LiveTroop) -> [Int] { [troop.kind == stage.bestedBy ? 0 : 1, -troop.tier, troop.kind] }
        let ready = troops.filter { $0.ready > 0 }.sorted { order($0).lexicographicallyPrecedes(order($1)) }
        var room = stage.most
        var army: [(kind: Int, tier: Int, count: UInt64)] = []
        for troop in ready where room > 0 {
            let count = min(troop.ready, room)
            army.append((troop.kind, troop.tier, count))
            room -= count
        }
        return army
    }

    /// A stage's host in words: "21 riders and 15 spearmen of tier 1".
    public func host(of stage: LiveStage) -> String {
        let named = stage.host.map { "\(LiveWords.grouped($0.count)) \((LiveWorld.kindNames[$0.kind] ?? "soldiers").lowercased())" }
        return "\(named.joined(separator: " and ")) of tier \(stage.tier)"
    }

    /// The names of the kinds of soldier, by number.
    public static let kindNames: [Int: String] = [1: "Spearmen", 2: "Archers", 3: "Riders", 4: "Mangonels"]

    /// What clearing a stage the first time gives, in words.
    public func gifts(of stage: LiveStage) -> String {
        var parts = [stage.gives.words]
        if stage.items > 0, let ware = wares[stage.item] {
            parts.append("\(LiveWorld.inLine(ware.name)) ×\(stage.items)")
        }
        return parts.joined(separator: ", ")
    }

    /// How many challenges a player makes in the Lists a day, and how far
    /// above their own place, as the module's catalogue has them.
    public static let listsTries: UInt64 = 5
    public static let listsReach: UInt64 = 10

    /// The most soldiers a band in the Lists holds, by the Keep's level.
    public static func listsMost(keep: Int) -> UInt64 { 200 * UInt64(max(keep, 1)) }

    /// The player's own entry in the Lists, if they have entered.
    public var myEntry: LiveEntrant? { entrants.first { $0.player == me?.id } }

    /// Those the player may challenge: in the Lists above them, and no more
    /// than so many places up, the nearest first.
    public var challengeable: [LiveEntrant] {
        guard let mine = myEntry else { return [] }
        return entrants.filter { $0.place < mine.place && mine.place - $0.place <= LiveWorld.listsReach }.reversed()
    }

    /// How many challenges the player has left today.
    public func challengesLeft(at seconds: Double) -> UInt64 {
        guard let tilt, tilt.day == today(at: seconds) else { return LiveWorld.listsTries }
        return LiveWorld.listsTries - min(tilt.tries, LiveWorld.listsTries)
    }

    /// Whether the purse of the player's place waits on them today.
    public func purseWaits(at seconds: Double) -> Bool {
        myEntry != nil && tilt?.claimed != today(at: seconds) + 1
    }

    /// The purse of a place in the Lists, in words.
    public func purseWords(of place: UInt64) -> String? {
        guard let purse = purses.first(where: { $0.first <= place && place <= $0.last }) else { return nil }
        return "\(purse.gives.words), with \(LiveWords.grouped(purse.honour)) honour"
    }

    /// A player's band in the Lists in words: "300 spearmen of tier 1 and
    /// 50 riders of tier 3".
    public func bandWords(of player: UInt64) -> String {
        let named = guards.filter { $0.player == player }.map {
            "\(LiveWords.grouped($0.count)) \((LiveWorld.kindNames[$0.kind] ?? "soldiers").lowercased()) of tier \($0.tier)"
        }
        return named.isEmpty ? "no one" : named.joined(separator: " and ")
    }

    /// The band to set: the best of those ready, the best tiers first, as
    /// many as the Keep allows.
    public var listsBand: [(kind: Int, tier: Int, count: UInt64)] {
        func order(_ troop: LiveTroop) -> [Int] { [-troop.tier, troop.kind] }
        let ready = troops.filter { $0.ready > 0 }.sorted { order($0).lexicographicallyPrecedes(order($1)) }
        var room = LiveWorld.listsMost(keep: city?.keep ?? 1)
        var band: [(kind: Int, tier: Int, count: UInt64)] = []
        for troop in ready where room > 0 {
            let count = min(troop.ready, room)
            band.append((troop.kind, troop.tier, count))
            room -= count
        }
        return band
    }

    /// The mark of the player's alliance at a hex, if it has one there.
    public func mark(at hex: LiveHex) -> LiveMark? { marks.first { $0.hex == hex } }

    /// The letters written to the player, the latest first, and how many
    /// are unread.
    public var lettersReceived: [LiveLetter] { letters.filter { $0.receiver == me?.id } }
    public var unreadLetters: Int { lettersReceived.filter { !$0.read }.count }

    /// The pacts of an alliance that hold at a moment.
    public func pacts(of alliance: UInt64, at seconds: Double) -> [LivePact] {
        pacts.values.filter { ($0.first == alliance || $0.second == alliance) && $0.holds(at: seconds) }.sorted { $0.id < $1.id }
    }

    /// Whether the player's alliance is at truce with another at a moment.
    public func atTruce(with alliance: UInt64, at seconds: Double) -> Bool {
        guard let mine = myMembership?.alliance, mine != alliance else { return false }
        return pacts(of: mine, at: seconds).contains { $0.terms == LivePact.truce && $0.other(than: mine) == alliance }
    }

    /// The envoys come to the player's alliance and still waiting on an answer.
    public func envoysWaiting(at seconds: Double) -> [LiveEnvoy] {
        guard let mine = myMembership?.alliance else { return [] }
        return envoys.filter { $0.receiver == mine && Double($0.sentAt + LiveEnvoy.waits) > seconds }
    }

    /// The petitions of the player's alliance that still stand at a moment, the oldest first.
    public func petitionsStanding(at seconds: Double) -> [LivePetition] {
        petitions.values.filter { Double($0.madeAt + LivePetition.stands) > seconds }.sorted { ($0.madeAt, $0.asker) < ($1.madeAt, $1.asker) }
    }

    /// The prisoner a commander of the player's is, if they are held.
    public func held(_ commander: UInt64) -> LivePrisoner? {
        guard let prisoner = prisoners[commander], prisoner.owner == me?.id else { return nil }
        return prisoner
    }

    /// The prisoners the player holds.
    public var captives: [LivePrisoner] {
        guard let me else { return [] }
        return prisoners.values.filter { $0.captor == me.id }.sorted { $0.commander < $1.commander }
    }

    /// The gates an alliance holds, by their number.
    public func gatesHeld(by alliance: UInt64) -> [LiveGate] {
        gates.values.filter { $0.holder == alliance && alliance != 0 }.sorted { $0.id < $1.id }
    }

    /// An alliance's wardstones, the oldest first.
    public func wardstones(of alliance: UInt64) -> [LiveWard] {
        wards.values.filter { $0.alliance == alliance }.sorted { $0.id < $1.id }
    }

    /// The levels of a topic an alliance has learnt.
    public func learnt(_ topic: Int, by alliance: UInt64) -> Int { learnings[LiveLearning.key(alliance, topic)]?.level ?? 0 }

    /// The points a commander has left to spend on talents.
    public func talentPointsLeft(of commander: LiveCommander) -> Int {
        LiveTalent.points(level: commander.level) - (skills[commander.id] ?? [:]).values.reduce(0, +)
    }

    /// The commander keeping the player's city, if one is.
    public var keeperCommander: LiveCommander? { keeper.flatMap { id in commanders.first { $0.id == id } } }

    /// The rally the player has an army in, if they have.
    public var myRally: LiveRally? {
        guard let me else { return nil }
        let mine = Set(musters.values.filter { $0.player == me.id }.map(\.rally))
        return rallies.first { mine.contains($0.id) }
    }

    /// The most crates the realm opens at once.
    public static let mostOpened: UInt64 = 100

    /// The tomes of war the player holds, each with what it is.
    public var heldTomes: [(ware: LiveWare, count: UInt64)] { heldItems.filter { $0.ware.isTome } }

    /// The items the player holds, each with what it is.
    public var heldItems: [(ware: LiveWare, count: UInt64)] {
        var held: [(ware: LiveWare, count: UInt64)] = []
        for item in satchel.keys.sorted() {
            if let ware = wares[item], let count = satchel[item], count > 0 { held.append((ware: ware, count: count)) }
        }
        return held
    }

    /// How many of the player's reports are unread.
    public var unread: Int { reports.filter { !$0.read }.count }

    /// The player's own marches.
    public var myMarches: [LiveMarch] {
        guard let me else { return [] }
        return marches.values.filter { $0.owner == me.id }.sorted { $0.id < $1.id }
    }

    /// The player's armies out, their carts not among them: what keeps
    /// another from being sent, or the city from moving.
    public var myArmies: [LiveMarch] { myMarches.filter { $0.kind != LiveMarch.carts } }

    /// The player's loads of carts on the road.
    public var myCarts: [LiveMarch] { myMarches.filter { $0.kind == LiveMarch.carts } }

    /// The most goods, all four together, one load of carts takes, by the
    /// Storehouse's level, as the module reckons it.
    public static func cartload(storehouse: Int) -> UInt64 { 20_000 + 20_000 * UInt64(min(max(storehouse, 0), topLevel)) }

    /// The Storehouse's number among the buildings.
    public static let storehouse = 6

    /// A load of carts for an ally at a moment: a third of what a load
    /// takes of each of grain, timber and stone, or what the city has of
    /// it where that is less.
    public func cartLoad(at seconds: Double) -> LiveGoods {
        let third = LiveWorld.cartload(storehouse: building(LiveWorld.storehouse)?.level ?? 0) / 3
        let have = stock?.goods(at: seconds) ?? LiveGoods()
        return LiveGoods(grain: min(have.grain, third), timber: min(have.timber, third), stone: min(have.stone, third))
    }

    /// The ground at a hex, as the land's chunks have it (the module's
    /// `land::Ground` codes); nil where its chunk is not known.
    public func ground(at hex: LiveHex) -> UInt8? {
        func floored(_ value: Int) -> (Int, Int) {
            let chunk = value >= 0 ? value / 16 : -((-value + 15) / 16)
            return (chunk, value - chunk * 16)
        }
        let (cq, iq) = floored(hex.q), (cr, ir) = floored(hex.r)
        guard let bytes = land[LiveHex(q: cq, r: cr).packed], bytes.count == 256 else { return nil }
        return bytes[ir * 16 + iq]
    }
}
