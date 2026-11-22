import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import NullmereLive
import NullmereRealm
import NullmereTestSupport
import XCTest

/// What the client asks of the realm, as it goes over the wire: each of
/// its asks a reducer the realm's module has, with as many arguments, of
/// the kinds it takes; and what the realm says when it refuses.
final class LiveClientTests: XCTestCase {
    private static func client(of server: StubHTTP.Server) -> LiveClient {
        LiveClient(transport: SpacetimeHTTP(server: server.address, database: "nullmere", session: server.session),
                   credentials: SpacetimeCredentials(identity: "ada", token: "key"))
    }

    /// The realm's reducers, by name, each with the types of what it takes
    /// after the caller, as the module declares them.
    private static func reducers() throws -> [String: [String]] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let module = try String(contentsOf: root.appendingPathComponent("realm/src/module.rs"), encoding: .utf8)
        let pattern = try NSRegularExpression(pattern: #"#\[reducer\]\s*pub fn (\w+)\(\s*ctx: &ReducerContext([^)]*)\)"#)
        var found: [String: [String]] = [:]
        for match in pattern.matches(in: module, range: NSRange(module.startIndex..., in: module)) {
            guard let name = Range(match.range(at: 1), in: module), let taken = Range(match.range(at: 2), in: module) else { continue }
            let types = module[taken].split(separator: ",").compactMap { part -> String? in
                let pieces = part.split(separator: ":", maxSplits: 1)
                return pieces.count == 2 ? pieces[1].trimmingCharacters(in: .whitespacesAndNewlines) : nil
            }
            found[String(module[name])] = types
        }
        return found
    }

    func testEveryAskIsOneOfTheRealmsReducersWithWhatItTakes() async throws {
        let server = StubHTTP.serve { _ in .init() }
        let client = Self.client(of: server)
        let hex = LiveHex(q: 3, r: -2)
        let soldiers: [(kind: Int, tier: Int, count: UInt64)] = [(kind: 1, tier: 1, count: 20)]
        let goods = LiveGoods(grain: 100, timber: 50)

        // Joining, and the city.
        try await client.join(name: "Ada")
        try await client.build(7)
        try await client.upgrade(building: 24)
        try await client.train(building: 24, tier: 1, count: 20)
        try await client.promote(building: 24, from: 1, to: 2, count: 10)
        try await client.heal(kind: 1, tier: 1, count: 6)
        try await client.learn(topic: 1)
        try await client.speedUp(job: 4)
        try await client.useItem(1, on: 4)
        try await client.claimTask()
        try await client.moveCity(to: hex)
        // Armies out.
        try await client.gather(at: hex, soldiers: soldiers, leader: 11)
        try await client.hunt(at: hex, soldiers: soldiers)
        try await client.attack(at: hex, soldiers: soldiers)
        try await client.scout(at: hex, soldiers: soldiers)
        try await client.explore(at: hex, soldiers: soldiers)
        try await client.raid(at: hex, soldiers: soldiers)
        try await client.reinforce(at: hex, soldiers: soldiers)
        try await client.callRally(at: hex, soldiers: soldiers)
        try await client.joinRally(6, soldiers: soldiers)
        try await client.recall(march: 9)
        // Reports and letters.
        try await client.read(report: 3)
        try await client.forget(report: 3)
        try await client.sendLetter(to: 2, "The east road is clear.")
        try await client.sendAllianceLetter("Gather at dusk.")
        try await client.readLetter(41)
        try await client.forgetLetter(41)
        try await client.shutOut(2)
        try await client.letIn(2)
        try await client.setMark(at: LiveHex(q: 3, r: -2), "Gather here")
        try await client.clearMark(3)
        try await client.claimMilestone(2)
        try await client.claimWelcome()
        try await client.walkRoad(soldiers: soldiers, leader: 11)
        try await client.enterLists(soldiers: soldiers, leader: 11)
        try await client.challenge(2)
        try await client.claimPurse()
        try await client.claimMerit(1)
        try await client.buyDeal(4)
        // Commanders.
        try await client.hire()
        try await client.draw()
        try await client.raiseGift(commander: 11)
        try await client.learnTalent(commander: 12, talent: 1)
        try await client.forgetTalents(commander: 12)
        try await client.pair(commander: 12, with: 11)
        try await client.keepCity(commander: 11)
        try await client.readTome(commander: 11, item: 9, count: 1)
        try await client.forge(piece: 1)
        try await client.equip(gear: 1, on: 11)
        try await client.unequip(gear: 1)
        try await client.ransom(commander: 11)
        try await client.releasePrisoner(commander: 31)
        // The alliance.
        try await client.foundAlliance(name: "Keepers of the Mere", tag: "MERE")
        try await client.joinAlliance(5)
        try await client.answer(applicant: 2, admit: true)
        try await client.expel(2)
        try await client.setRank(of: 2, to: 2)
        try await client.setAlliance(open: true, words: "We keep the east shore.")
        try await client.say("Morning.", withinAlliance: false)
        try await client.reportLine(12, withinAlliance: true)
        try await client.askHelp(job: 4)
        try await client.help(job: 4)
        try await client.raiseWard(at: hex)
        try await client.razeWard(3)
        try await client.giveToLearning(topic: 1, goods)
        try await client.giveToSpire(goods)
        try await client.claimBoons()
        try await client.sendEnvoy(to: 6, terms: 1, days: 7)
        try await client.answerEnvoy(5, accept: true)
        try await client.breakPact(1)
        try await client.petition(goods)
        try await client.answerPetition(of: 2, goods)
        try await client.withdrawPetition()
        try await client.leaveAlliance()
        // The realm's titles, contests and stores; the day's chests.
        try await client.bestowTitle(1, on: 2)
        try await client.takeTitle(1)
        try await client.claimPrize(contest: 1, place: 1)
        try await client.claimPlace(contest: 1)
        try await client.buy(item: 1, count: 1)
        try await client.usePeace(4)
        try await client.drink(16)
        try await client.openCrates(12, count: 3)
        try await client.sendGoods(to: hex, LiveGoods(grain: 1_000))
        try await client.openChest(1)
        // Devices, and leaving.
        try await client.offerLink()
        try await client.takeLink("ABCDE23456")
        try await client.nameDevice("Mac")
        try await client.letGo(device: 2)
        try await client.leaveRealm(name: "Ada")

        let reducers = try Self.reducers()
        XCTAssertGreaterThan(reducers.count, 60, "the module's reducers are read")
        let requests = server.requests
        XCTAssertEqual(requests.count, 89)
        var asked: Set<String> = []
        for request in requests {
            let reducer = request.url.lastPathComponent
            asked.insert(reducer)
            XCTAssertEqual(request.method, "POST")
            XCTAssertEqual(request.url.path, "/v1/database/nullmere/call/\(reducer)")
            XCTAssertEqual(request.headers.first { $0.key.lowercased() == "authorization" }?.value, "Bearer key", reducer)
            guard let takes = reducers[reducer] else {
                XCTFail("\(reducer) is no reducer of the realm's module")
                continue
            }
            let arguments = try XCTUnwrap(JSONSerialization.jsonObject(with: request.body) as? [Any], reducer)
            XCTAssertEqual(arguments.count, takes.count, "\(reducer) takes \(takes)")
            for (argument, type) in zip(arguments, takes) {
                if type == "String" {
                    XCTAssertTrue(argument is String, "\(reducer): a \(type)")
                } else if type.hasPrefix("Vec<") {
                    XCTAssertTrue(argument is [Any], "\(reducer): a \(type)")
                } else {
                    XCTAssertFalse(argument is String || argument is [Any], "\(reducer): a \(type)")
                }
            }
        }
        // Older realms still use the original forms. Check that removing
        // the receipt arguments gives each legacy reducer's wire signature.
        let legacy = ["send", "send_goods", "speed_up", "train", "upgrade"]
        for reducer in legacy {
            let original = try XCTUnwrap(reducers[reducer])
            XCTAssertEqual(reducers[reducer + "_once"], original + ["i64", "String"])
        }
        let administrative = ["bar_player", "dismiss_report", "fire", "forget_player", "set_pace", "take_away"]
        XCTAssertEqual(Set(reducers.keys).subtracting(asked), Set(administrative + legacy))
    }

    /// Without a subscription the realm is read table by table, every
    /// table the client knows, by SQL; and the client is not live.
    func testTheRealmIsReadTableByTableWithoutASubscription() async throws {
        let server = StubHTTP.serve { request in
            // Ada as the realm tells who is asking; every other table empty.
            request.text == "SELECT * FROM me"
                ? .init(text: #"[{"schema":{},"rows":[[1,9,"Ada",1000,true,1000]]}]"#)
                : .init(text: #"[{"schema":{},"rows":[]}]"#)
        }
        let client = Self.client(of: server)
        XCTAssertFalse(client.isLive, "nothing watched yet")
        XCTAssertNil(client.world.me, "and nothing mirrored")
        let world = try await client.read()
        XCTAssertEqual(world.me?.name, "Ada")
        let asked = server.requests
        XCTAssertEqual(asked.count, LiveSchema.tables.count)
        XCTAssertTrue(asked.allSatisfy { $0.method == "POST" && $0.url.path == "/v1/database/nullmere/sql" })
        XCTAssertEqual(asked.map(\.text), LiveSchema.tables.keys.sorted().map { "SELECT * FROM \($0)" })
        client.close()
        XCTAssertFalse(client.isLive)
    }

    func testARefusalIsThrownInTheRealmsOwnWords() async throws {
        let refusing = StubHTTP.serve { _ in .init(status: 530, text: "Your builders are all at work.") }
        do {
            try await Self.client(of: refusing).build(7)
            XCTFail("a refusal is thrown")
        } catch let refusal as LiveRefusal {
            XCTAssertEqual(refusal.words, "Your builders are all at work.")
            XCTAssertEqual(refusal.description, "Your builders are all at work.")
        }
        // A request the module doesn't know is not the realm refusing: it says the two don't match.
        let older = StubHTTP.serve { _ in .init(status: 404, text: "No such reducer: hire") }
        do {
            try await Self.client(of: older).hire()
            XCTFail("an unknown request is thrown")
        } catch let error as SpacetimeError {
            XCTAssertEqual(error.description, SpacetimeError.unknownRequest)
        }
    }
}
