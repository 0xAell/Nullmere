import Foundation
import NullmereLive

/// What the screen says of what the player has chosen: a name, a few
/// lines, and what can be done about it, each with why not where it
/// can't be done now. Plain words, read from the realm's rows; the
/// screen only draws it.
public struct LiveCard: Equatable, Sendable {
    public enum Act: Equatable, Sendable {
        /// Open the city's buildings, or its troops.
        case city
        case troops
        /// Send everyone ready to what is chosen.
        case send
        /// Call an army home.
        case recall(UInt64)
        /// Call a rally of the player's alliance against what is chosen,
        /// with everyone ready.
        case rally
        /// Raise a wardstone of the player's alliance where is chosen, or
        /// take one down.
        case raiseWard
        case razeWard(UInt64)
    }

    public struct Button: Equatable, Sendable {
        public let title: String
        public let act: Act
        /// Why it can't be pressed now; nil where it can.
        public let why: String?
    }

    public let title: String
    public let lines: [String]
    public let buttons: [Button]
}

extension LiveSession {
    /// The grounds, as the module numbers them, in a player's words.
    static let grounds = ["Deep water", "Shallows", "Strand", "Salt flat", "Plain", "Wood", "Heath", "Mountains"]
    /// The goods a site holds, by its kind.
    static let goods = ["Grain", "Timber", "Stone", "Moonsalt"]

    private func soldiers(_ count: UInt64) -> String { "\(LiveWords.grouped(count)) \(count == 1 ? "soldier" : "soldiers")" }

    /// Who would lead an army sent now, in a line; nil where no commander
    /// is in the city.
    private var leaderLine: String? {
        world.freeLeader.map { "\($0.name), \($0.wayName.lowercased()) of level \($0.level), will lead it." }
    }

    /// Why no army can be sent now, whatever it is sent for: no one ready,
    /// or every army the city may send already out.
    private var cannotSend: String? {
        let ready = world.troops.reduce(0) { $0 + $1.ready }
        if ready == 0 { return "No soldiers stand ready in your city." }
        let most = LiveWorld.marches(keep: world.city?.keep ?? 1)
        if world.myMarches.count >= most {
            return most == 1 ? "Your one army is out. Raise your Keep to send more." : "All \(most) of your armies are out."
        }
        return nil
    }

    /// A button to call a rally against what is chosen, for a member of an
    /// alliance; none for anyone else.
    private func rallyButton(why: String?) -> [LiveCard.Button] {
        guard world.myMembership != nil else { return [] }
        if let mine = world.myRally {
            return [.init(title: "Call a rally", act: .rally, why: "Your army is in a rally already: \(world.rallyWords(mine, at: now))")]
        }
        return [.init(title: "Call a rally", act: .rally, why: why ?? cannotSend)]
    }

    /// When the gates of the ridge may be stormed this season: a week in,
    /// at the realm's pace.
    var gatesOpenAt: Int? {
        guard let season = world.season, let realm = world.realm else { return nil }
        return season.began + 7 * 86_400 / max(realm.pace, 1)
    }

    /// The card for what lies at a chosen hex.
    public func card(for selection: LiveSelection) -> LiveCard {
        let seconds = now
        let ready = world.troops.reduce(0) { $0 + $1.ready }
        switch selection {
        case .home(let city):
            var lines = ["Your city. Keep level \(city.keep), power \(LiveWords.grouped(city.power))."]
            if city.peace(at: seconds) > 0 {
                lines.append("At peace for another \(LiveWords.spoken(city.peace(at: seconds))): no army may attack it.")
            }
            if let job = world.jobs.first(where: { $0.kind == LiveJob.raise }),
               let name = world.buildings.first(where: { $0.id == job.subject }).flatMap({ world.blueprint($0.kind, level: 1)?.name }) {
                lines.append("\(name) to level \(job.level): \(LiveWords.clock(Int(job.left(at: seconds).rounded(.up))))")
            }
            return LiveCard(title: city.name, lines: lines, buttons: [.init(title: "Buildings", act: .city, why: nil), .init(title: "Troops", act: .troops, why: nil)])

        case .city(let city, let owner):
            let here = world.players[city.owner]?.online == true ? " They are here now." : ""
            var lines = ["\(owner)'s city. Keep level \(city.keep), power \(LiveWords.grouped(city.power)).\(here)"]
            var why = cannotSend
            if let mine = world.city, mine.peace(at: seconds) > 0 {
                lines.append("Attacking ends your own city's peace.")
            }
            if city.peace(at: seconds) > 0 {
                why = "That city is at peace for another \(LiveWords.spoken(city.peace(at: seconds)))."
            }
            // An ally's city is never attacked, and nothing else can be
            // sent to it yet.
            if world.isAlly(city.owner) {
                return LiveCard(title: city.name, lines: [lines[0], "Your ally."], buttons: [])
            }
            if why == nil, let leaderLine { lines.append(leaderLine) }
            let peace = city.peace(at: seconds) > 0 ? "That city is at peace for another \(LiveWords.spoken(city.peace(at: seconds)))." : nil
            return LiveCard(title: city.name, lines: lines,
                            buttons: [.init(title: ready > 0 ? "Attack with \(soldiers(ready))" : "Attack", act: .send, why: why)] + rallyButton(why: peace))

        case .site(let site):
            let good = LiveSession.goods.indices.contains(site.kind - 1) ? LiveSession.goods[site.kind - 1] : "Goods"
            var lines = ["\(LiveWords.grouped(site.left)) left to gather."]
            var why = cannotSend
            if site.gatherer != 0 {
                let mine = world.myMarches.contains { $0.id == site.gatherer }
                lines.append(mine ? "Your army is gathering here." : "Another army is gathering here.")
                why = "Another army is gathering there."
            }
            if why == nil, let leaderLine { lines.append(leaderLine) }
            return LiveCard(title: "\(good), level \(site.level)", lines: lines,
                            buttons: [.init(title: ready > 0 ? "Gather with \(soldiers(ready))" : "Gather", act: .send, why: why)])

        case .barrow(let barrow):
            var lines = ["The Unquiet hold it. An attack takes \(LiveWorld.energyAnAttack) energy."]
            var why = cannotSend
            let energy = world.hunt?.energy(at: seconds) ?? 0
            if energy < LiveWorld.energyAnAttack { why = "An attack takes \(LiveWorld.energyAnAttack) energy. You have \(energy)." }
            if barrow.level > (world.hunt?.mayAttack ?? 1) { why = "Clear a level \(barrow.level - 1) barrow first." }
            if barrow.fighter != 0 {
                let mine = world.myMarches.contains { $0.id == barrow.fighter }
                lines.append(mine ? "Your army is fighting here." : "Another army is fighting here.")
                why = "Another army is fighting there."
            }
            if why == nil, let leaderLine { lines.append(leaderLine) }
            // A rally reaches three levels past what one may attack alone.
            let reach = (world.hunt?.mayAttack ?? 1) + 3
            var rallyWhy: String? = barrow.fighter != 0 ? "Another army is fighting there." : nil
            if energy < LiveWorld.energyAnAttack { rallyWhy = "A rally takes \(LiveWorld.energyAnAttack) energy. You have \(energy)." }
            if barrow.level > reach { rallyWhy = "A rally of yours may go against a barrow of level \(reach) at most." }
            return LiveCard(title: "Barrow, level \(barrow.level)", lines: lines,
                            buttons: [.init(title: ready > 0 ? "Attack with \(soldiers(ready))" : "Attack", act: .send, why: why)] + rallyButton(why: rallyWhy))

        case .gate(let gate):
            let mine = world.myMembership?.alliance
            var lines = [gate.holder == 0 ? "A gate of the ridge, held by the Unquiet." : "A gate of the ridge, held by \(gate.holderName)."]
            if gate.holder != 0, gate.holder == mine {
                lines.append("Your alliance holds it: your armies pass it, and your city may move into the lake country.")
                return LiveCard(title: "Gate of the ridge", lines: lines, buttons: [])
            }
            lines.append("Only an alliance's rally may storm it; whoever holds it passes it.")
            var why: String?
            if let opens = gatesOpenAt, opens > Int(seconds) { why = "The gates of the ridge may be stormed in \(LiveWords.spoken(opens - Int(seconds)))." }
            if gate.fighter != 0 { why = "Another rally is at that gate." }
            return LiveCard(title: "Gate of the ridge", lines: lines, buttons: rallyButton(why: why))

        case .ward(let ward):
            let owner = world.alliances[ward.alliance].map { "[\($0.tag)] \($0.name)" } ?? "An alliance"
            var lines = ["\(owner)'s wardstone. Once it stands it claims the land within \(LiveWard.reach) hexes."]
            if !ward.stands(at: seconds) {
                lines.append("It stands in \(LiveWords.spoken(ward.standsAt - Int(seconds))).")
            }
            let ours = world.myMembership?.alliance == ward.alliance
            if !ours {
                // Another alliance's: a rally of one's own may take it down.
                return LiveCard(title: "Wardstone", lines: lines, buttons: rallyButton(why: nil))
            }
            let buttons: [LiveCard.Button] = world.isOfficer ? [.init(title: "Take it down", act: .razeWard(ward.id), why: nil)] : []
            return LiveCard(title: "Wardstone", lines: lines, buttons: buttons)

        case .army(let march, let own):
            guard own, let line = world.marchLines().first(where: { $0.id == march.id }) else {
                let owner = world.shownName(of: march.owner) ?? "Another player"
                return LiveCard(title: "\(owner)'s army", lines: [soldiers(march.soldiers)], buttons: [])
            }
            var lines = ["\(line.doing): \(LiveWords.clock(march.arrives - Int(seconds)))"]
            if let leader = world.commanders.first(where: { $0.id == march.leader }) {
                lines.append("Led by \(leader.name).")
            }
            lines.append(line.wounded > 0 ? "\(soldiers(line.soldiers)), and \(LiveWords.grouped(line.wounded)) wounded." : "\(soldiers(line.soldiers)).")
            let why = line.canRecall ? nil : (march.state == LiveMarch.fighting ? "That army is fighting. Wait for the fight to end." : "That army is already on its way home.")
            return LiveCard(title: "Your army", lines: lines, buttons: [.init(title: "Call home", act: .recall(march.id), why: why)])

        case .land(let hex, let ground):
            let name = ground.flatMap { LiveSession.grounds.indices.contains(Int($0)) ? LiveSession.grounds[Int($0)] : nil }
            var lines: [String] = []
            if let owner = world.landOf(hex, at: seconds), let alliance = world.alliances[owner] {
                lines.append("The land of [\(alliance.tag)] \(alliance.name).")
            }
            // An officer may raise a wardstone on clear ground of strand, plain or heath.
            guard world.isOfficer, let ground, [2, 4, 6].contains(ground) else {
                return LiveCard(title: name ?? "Unknown land", lines: lines, buttons: [])
            }
            return LiveCard(title: name ?? "Unknown land", lines: lines,
                            buttons: [.init(title: "Raise a wardstone", act: .raiseWard, why: world.stock.map { $0.goods(at: seconds).covers(LiveGoods(timber: 30_000, stone: 30_000)) } == true ? nil : "A wardstone takes 30,000 timber and 30,000 stone.")])
        }
    }

    /// Does what a card's button says.
    public func press(_ button: LiveCard.Button) async {
        guard button.why == nil else {
            said = button.why
            return
        }
        switch button.act {
        case .send:
            if let selected { await send(everyoneReady, to: selected) }
        case .recall(let march): await recall(march: march)
        case .rally:
            if let selected { await callRally(at: selected) }
        case .raiseWard:
            if let selected { await raiseWard(at: selected) }
        case .razeWard(let ward): await razeWard(ward)
        case .city, .troops: break
        }
    }
}
