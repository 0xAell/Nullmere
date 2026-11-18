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
        /// Send a scout to the city chosen, or everyone ready to stay in
        /// an ally's.
        case scout
        case reinforce
        /// Send a load of carts with goods to the ally's city chosen.
        case sendGoods
        /// Shut out the player whose city is chosen, or let them back in.
        case shutOut(UInt64)
        case letIn(UInt64)
        /// Send a scout to find what the cairn chosen holds.
        case explore
        /// Send everyone ready against the army gathering at the site chosen.
        case raid
        /// Hasten a work under way in the city by a quarter, for goods.
        case hasten(UInt64)
        /// Move the player's city to the ground chosen.
        case moveCity
        /// Raise a building of the city a level, or build one it has not,
        /// by its number in the module's catalogue.
        case upgrade(UInt64)
        case build(Int)
    }

    /// Said on the city card of a player shut out.
    public static let shutOutLine = "You have shut them out: their letters are not taken, and what they say is left unshown."

    public struct Button: Equatable, Sendable {
        public let title: String
        public let act: Act
        /// Why it can't be pressed now; nil where it can.
        public let why: String?

        /// The symbol it is drawn as in a ring about what is chosen, a
        /// system symbol's name.
        public var icon: String {
            switch act {
            case .city: return "building.2"
            case .troops: return "person.3"
            case .send: return title.hasPrefix("Gather") ? "shippingbox" : "flame"
            case .recall: return "arrow.uturn.backward"
            case .rally: return "flag"
            case .raiseWard: return "shield.lefthalf.filled"
            case .razeWard: return "hammer"
            case .scout: return "eye"
            case .reinforce: return "shield"
            case .sendGoods: return "cart"
            case .shutOut: return "speaker.slash"
            case .letIn: return "speaker.wave.2"
            case .explore: return "binoculars"
            case .raid: return "flame"
            case .hasten: return "forward.fill"
            case .moveCity: return "arrow.up.and.down.and.arrow.left.and.right"
            case .upgrade: return "arrow.up.circle"
            case .build: return "hammer"
            }
        }
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
    /// The Scout Camp, as the module's catalogue numbers buildings.
    static let scoutCamp = 18
    /// What moving a city costs, as the module's catalogue has it.
    static let moving = LiveGoods(grain: 3_000, timber: 3_000, stone: 3_000)

    private func soldiers(_ count: UInt64) -> String { "\(LiveWords.grouped(count)) \(count == 1 ? "soldier" : "soldiers")" }

    /// Who would lead an army sent now, in a line; nil where no commander
    /// is in the city.
    private var leaderLine: String? {
        world.freeLeader.map { "\($0.name), \($0.wayName.lowercased()) of level \($0.level), will lead it." }
    }

    /// The button to send a load of carts to an ally's city: what it
    /// carries, or why none can go now.
    private var cartsButton: LiveCard.Button {
        let load = world.cartLoad(at: now)
        let most = LiveWorld.marches(keep: world.city?.keep ?? 1)
        let why: String?
        if load.isNone {
            why = "Your city has no grain, timber or stone to send."
        } else if world.myCarts.count >= most {
            why = most == 1 ? "You have a load of carts on the road already, as many as your Keep allows."
                : "You have \(most) loads of carts on the road already, as many as your Keep allows."
        } else {
            why = nil
        }
        return .init(title: load.isNone ? "Send goods" : "Send \(load.words)", act: .sendGoods, why: why)
    }

    /// Why no army can be sent now, whatever it is sent for: no one ready,
    /// or every army the city may send already out.
    private var cannotSend: String? {
        let ready = world.troops.reduce(0) { $0 + $1.ready }
        if ready == 0 { return "No soldiers stand ready in your city." }
        let most = LiveWorld.marches(keep: world.city?.keep ?? 1)
        if world.myArmies.count >= most {
            return most == 1 ? "Your one army is out. Raise your Keep to send more." : "All \(most) of your armies are out."
        }
        return nil
    }

    /// A button to call a rally against what is chosen, for a member of an
    /// alliance; none for anyone else.
    /// Shutting out the player whose city is chosen, or letting them back in.
    private func shunButton(_ player: UInt64) -> LiveCard.Button {
        let name = world.players[player]?.name ?? "them"
        return world.shunned.contains(player) ? .init(title: "Let \(name) back in", act: .letIn(player), why: nil)
            : .init(title: "Shut out \(name)", act: .shutOut(player), why: nil)
    }

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

    /// Where what is chosen stands, for a mark of the player's alliance
    /// there; nil for an army, which moves, and a building of their city.
    static func hex(of selection: LiveSelection) -> LiveHex? {
        switch selection {
        case .home(let city), .city(let city, _): return city.hex
        case .site(let site): return site.hex
        case .barrow(let barrow): return barrow.hex
        case .gate(let gate): return gate.hex
        case .ward(let ward): return ward.hex
        case .cairn(let cairn): return cairn.hex
        case .land(let hex, _): return hex
        case .army, .work: return nil
        }
    }

    /// The card for what lies at a chosen hex: what it is, and what the
    /// player's alliance marked there, if it did.
    public func card(for selection: LiveSelection) -> LiveCard {
        let card = bareCard(for: selection)
        guard let mark = LiveSession.hex(of: selection).flatMap({ world.mark(at: $0) }) else { return card }
        return LiveCard(title: card.title, lines: card.lines + ["Your alliance's mark: \(mark.words)"], buttons: card.buttons)
    }

    func bareCard(for selection: LiveSelection) -> LiveCard {
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
            var buttons: [LiveCard.Button] = [.init(title: "Buildings", act: .city, why: nil), .init(title: "Troops", act: .troops, why: nil)]
            // The soonest work under way, hastened by a quarter for goods.
            if let work = world.works(at: seconds).first {
                let goods = world.stock?.goods(at: seconds) ?? LiveGoods()
                let why = goods.covers(LiveWorld.hastening) ? nil : "Hastening takes \(LiveWorld.hastening.words)."
                buttons.append(.init(title: "Hasten \(work.words)", act: .hasten(work.job.id), why: why))
            }
            return LiveCard(title: city.name, lines: lines, buttons: buttons)

        case .work(let kind, let city):
            guard let line = world.buildingLines(at: seconds).first(where: { $0.kind == kind }) else { return card(for: .home(city)) }
            guard let building = line.building else {
                // Its plot: what building it costs, or why it can't be yet.
                var lines = ["Not built yet."]
                if let does = LiveWorld.buildingWords(kind) { lines.append(does) }
                if let first = line.next { lines.append("Building it takes \(first.cost.words), \(LiveWords.spoken(first.seconds)).") }
                return LiveCard(title: line.name, lines: lines,
                                buttons: [.init(title: "Build", act: .build(kind), why: line.block?.words), .init(title: "Buildings", act: .city, why: nil)])
            }
            var lines = [line.level > 0 ? "Level \(line.level)." : "Being built."]
            if let does = LiveWorld.buildingWords(kind) { lines.append(does) }
            var buttons: [LiveCard.Button] = []
            if let job = line.job {
                lines.append("To level \(job.level): \(LiveWords.clock(Int(job.left(at: seconds).rounded(.up))))")
                let goods = world.stock?.goods(at: seconds) ?? LiveGoods()
                let why = goods.covers(LiveWorld.hastening) ? nil : "Hastening takes \(LiveWorld.hastening.words)."
                buttons.append(.init(title: "Hasten", act: .hasten(job.id), why: why))
            } else if let next = line.next {
                lines.append("Level \(line.level + 1) takes \(next.cost.words), \(LiveWords.spoken(next.seconds)).")
                buttons.append(.init(title: "Upgrade to level \(line.level + 1)", act: .upgrade(building.id), why: line.block?.words))
            } else {
                lines.append(line.block?.words ?? "It is at its highest level.")
            }
            buttons.append(.init(title: "Buildings", act: .city, why: nil))
            return LiveCard(title: line.name, lines: lines, buttons: buttons)

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
            // An ally's city is never attacked: soldiers are sent to stay in it.
            let shut = world.shunned.contains(city.owner) ? [LiveCard.shutOutLine] : []
            if world.isAlly(city.owner) {
                var allied = [lines[0], "Your ally."] + shut
                if cannotSend == nil, let leaderLine { allied.append(leaderLine) }
                return LiveCard(title: city.name, lines: allied,
                                buttons: [.init(title: ready > 0 ? "Reinforce with \(soldiers(ready))" : "Reinforce", act: .reinforce, why: cannotSend), cartsButton,
                                          shunButton(city.owner)])
            }
            lines += shut
            if why == nil, let leaderLine { lines.append(leaderLine) }
            let peace = city.peace(at: seconds) > 0 ? "That city is at peace for another \(LiveWords.spoken(city.peace(at: seconds)))." : nil
            // A scout, one soldier, sees its garrison and comes home whole.
            let scout = world.building(LiveSession.scoutCamp) == nil ? "Raise a Scout Camp first." : cannotSend
            return LiveCard(title: city.name, lines: lines,
                            buttons: [.init(title: ready > 0 ? "Attack with \(soldiers(ready))" : "Attack", act: .send, why: why),
                                      .init(title: "Scout", act: .scout, why: scout)] + rallyButton(why: peace) + [shunButton(city.owner)])

        case .site(let site):
            let good = LiveSession.goods.indices.contains(site.kind - 1) ? LiveSession.goods[site.kind - 1] : "Goods"
            var lines = ["\(LiveWords.grouped(site.left)) left to gather."]
            var why = cannotSend
            // Whose army gathers here, said once: as a line, and in the same
            // words as why no other may gather (the callout tells a why that
            // is one of its lines once). Another player's army, not an
            // ally's, may be fallen on.
            var raid: [LiveCard.Button] = []
            if site.gatherer != 0 {
                let mine = world.myMarches.contains { $0.id == site.gatherer }
                let owner = mine ? nil : world.marches[site.gatherer]?.owner
                let whose = mine ? "Your army is gathering here."
                    : owner.flatMap { world.shownName(of: $0) }.map { "\($0)'s army is gathering here." } ?? "Another army is gathering here."
                lines.append(whose)
                why = whose
                if let owner {
                    raid = [.init(title: ready > 0 ? "Attack it with \(soldiers(ready))" : "Attack it", act: .raid,
                                  why: world.isAlly(owner) ? "That army is your ally's." : cannotSend)]
                }
            }
            if why == nil, let leaderLine { lines.append(leaderLine) }
            return LiveCard(title: "\(good), level \(site.level)", lines: lines,
                            buttons: [.init(title: ready > 0 ? "Gather with \(soldiers(ready))" : "Gather", act: .send, why: why)] + raid)

        case .barrow(let barrow):
            var lines = ["The Unquiet hold it. An attack takes \(LiveWorld.energyAnAttack) energy."]
            var why = cannotSend
            let energy = world.hunt?.energy(at: seconds) ?? 0
            if energy < LiveWorld.energyAnAttack { why = "An attack takes \(LiveWorld.energyAnAttack) energy. You have \(energy)." }
            if barrow.level > (world.hunt?.mayAttack ?? 1) { why = "Clear a level \(barrow.level - 1) barrow first." }
            if barrow.fighter != 0 {
                let mine = world.myMarches.contains { $0.id == barrow.fighter }
                if mine { lines.append("Your army is fighting here.") }
                why = mine ? "Your army is fighting here." : "Another army is fighting there."
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

        case .cairn(let cairn):
            // A scout, one soldier, finds what it holds the first time and comes home whole.
            var lines = ["The old folk laid \(cairn.hoardWords) in it."]
            var why: String?
            if world.hasFound(cairn) {
                lines = ["Your scouts have found what it held. It stands for others to find."]
                why = "Your scouts have found what this cairn held already."
            } else if world.scouting(cairn) {
                lines.append("Your scouts are on their way to it.")
                why = "Your scouts are on their way to it already."
            } else if world.building(LiveSession.scoutCamp) == nil {
                why = "Raise a Scout Camp first."
            } else {
                lines.append("A scout finds it the first time and comes home whole.")
                why = cannotSend
            }
            return LiveCard(title: "Cairn, level \(cairn.level)", lines: lines, buttons: [.init(title: "Send a scout", act: .explore, why: why)])

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
            if march.kind == LiveMarch.carts {
                // Carts carry no army, and go on to where they were sent.
                let owner = own ? "Your" : "\(world.shownName(of: march.owner) ?? "Another player")'s"
                let doing = world.marchLines().first(where: { $0.id == march.id })?.doing ?? "Carts on their way to an ally's city"
                return LiveCard(title: "\(owner) carts", lines: own ? ["\(doing): \(LiveWords.clock(march.arrives - Int(seconds)))"] : ["Carts of goods for an ally."], buttons: [])
            }
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
            // Clear ground of strand, plain or heath: an officer may raise a
            // wardstone on it, and anyone may move their city to it.
            guard let ground, [2, 4, 6].contains(ground) else {
                return LiveCard(title: name ?? "Unknown land", lines: lines, buttons: [])
            }
            var buttons: [LiveCard.Button] = []
            let goods = world.stock?.goods(at: seconds) ?? LiveGoods()
            if world.isOfficer {
                buttons.append(.init(title: "Raise a wardstone", act: .raiseWard, why: goods.covers(LiveGoods(timber: 30_000, stone: 30_000)) ? nil : "A wardstone takes 30,000 timber and 30,000 stone."))
            }
            if world.city != nil {
                let away = world.myArmies.isEmpty ? nil : "Bring your armies home before your city moves."
                let dear = goods.covers(LiveSession.moving) ? nil : "Moving your city takes \(LiveSession.moving.words)."
                buttons.append(.init(title: "Move your city here", act: .moveCity, why: away ?? dear))
            }
            return LiveCard(title: name ?? "Unknown land", lines: lines, buttons: buttons)
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
        case .scout:
            if let selected { await scout(at: selected) }
        case .reinforce:
            if let selected { await reinforce(at: selected) }
        case .sendGoods:
            if let selected { await sendGoods(to: selected) }
        case .shutOut(let player): await shutOut(player)
        case .letIn(let player): await letIn(player)
        case .explore:
            if let selected { await explore(at: selected) }
        case .raid:
            if let selected { await raid(at: selected) }
        case .hasten(let job): await speedUp(job: job)
        case .moveCity:
            if let selected { await moveCity(to: selected) }
        case .upgrade(let building): await upgrade(building: building)
        case .build(let kind): await build(kind)
        case .city, .troops: break
        }
    }
}
