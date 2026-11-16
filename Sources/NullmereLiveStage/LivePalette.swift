import Foundation
import NullmereLive

/// Something the player can do from the keyboard, in words to search by:
/// open a part of a destination, go to a place on the map, or do one of
/// the things the city can do this moment.
public struct LiveCommand: Equatable, Identifiable, Sendable {
    public enum Act: Equatable, Sendable {
        /// Open a part of a destination, by its name (`LiveSession.parts`).
        case open(String)
        /// Turn the view to a hex and choose what is there.
        case go(LiveHex)
        case build(Int)
        case upgrade(UInt64)
        case learn(Int)
        case claimTask
        case openChest(Int)
        case forge(Int)
        case hire
        case claimPrize(contest: Int, place: Int)
        case promote(building: UInt64, from: Int, to: Int, count: UInt64)
        case claimBoons
        case helpAll
        /// Buy one of a thing from the alliance's stores.
        case buy(Int)
    }

    public let title: String
    public let act: Act
    public var id: String { title }
}

extension LiveSession {
    /// The parts of the destinations, by the names the palette opens them
    /// by and the words it shows, in the order the destinations hold them.
    public static let parts: [(name: String, title: String)] = [
        ("city", "Buildings"), ("troops", "Troops"), ("studies", "Studies"), ("forge", "Forge"), ("day", "Today"), ("alliance", "Alliance"),
        ("realm", "The Mere"), ("rankings", "Rankings"), ("chat", "Chat"), ("reports", "Reports and letters"),
    ]

    /// Every command there is at a moment: the player's city and each army
    /// out to go to; every part of every destination to open; the task to
    /// claim once it is done; each building that may be built or raised,
    /// each topic that may be studied, each of the day's chests that may
    /// be opened, the soldiers each training building may raise a tier,
    /// each piece the Forge may make, each thing the alliance's stores
    /// sell that the player's honour buys, another commander to take
    /// on and each contest's prize reached, now; and the nearest barrow the
    /// player may attack, the nearest cairn their scouts have not found,
    /// and the nearest site of each good no one works, to go to.
    public func commands(at seconds: Double) -> [LiveCommand] {
        var all: [LiveCommand] = []
        if let city = world.city {
            all.append(LiveCommand(title: "Go to your city", act: .go(city.hex)))
        }
        for line in world.marchLines() {
            let place = line.march.stands ? line.march.to : (line.march.route.last ?? line.march.to)
            all.append(LiveCommand(title: "Go to your army: \(line.doing)", act: .go(place)))
        }
        for part in LiveSession.parts {
            all.append(LiveCommand(title: "Open \(part.title)", act: .open(part.name)))
        }
        if let task = world.task, world.isDone(task) {
            all.append(LiveCommand(title: "Claim the task: \(task.words)", act: .claimTask))
        }
        for line in world.buildingLines(at: seconds) where line.block == nil {
            guard let next = line.next else { continue }
            if let building = line.building, line.level > 0 {
                all.append(LiveCommand(title: "Raise the \(line.name) to level \(next.level)", act: .upgrade(building.id)))
            } else {
                all.append(LiveCommand(title: "Build a \(line.name)", act: .build(line.kind)))
            }
        }
        for line in world.studyLines(at: seconds) where line.block == nil {
            guard let next = line.next else { continue }
            all.append(LiveCommand(title: "Study \(line.name) to level \(next.level)", act: .learn(line.topic)))
        }
        for chest in world.chestLines(at: seconds) where chest.ready {
            all.append(LiveCommand(title: "Open the day's chest at \(chest.marks) marks", act: .openChest(chest.id)))
        }
        for line in world.trainLines(at: seconds) {
            guard let raise = world.promotion(line, at: seconds), raise.count > 0 else { continue }
            let name = line.tiers.first?.soldier.name ?? line.name
            all.append(LiveCommand(title: "Raise \(LiveWords.grouped(raise.count)) tier \(raise.from) \(name) to tier \(raise.to)",
                                   act: .promote(building: line.building.id, from: raise.from, to: raise.to, count: raise.count)))
        }
        for line in world.forgeLines(at: seconds) where line.block == nil {
            all.append(LiveCommand(title: "Make a piece at the Forge: \(line.pattern.name)", act: .forge(line.pattern.piece)))
        }
        let pleas = world.pleasToHelp.count
        if pleas > 0 {
            all.append(LiveCommand(title: "Help your allies with \(pleas) \(pleas == 1 ? "work" : "works")", act: .helpAll))
        }
        if !world.boons.isEmpty {
            all.append(LiveCommand(title: "Claim your alliance's gifts: \(world.boonGoods.words)", act: .claimBoons))
        }
        for line in world.storeLines() where line.block == nil {
            all.append(LiveCommand(title: "Buy \(line.ware.name.lowercased()) for \(LiveWords.grouped(line.honour)) honour", act: .buy(line.ware.item)))
        }
        if world.city != nil, world.hireBlock(at: seconds) == nil {
            all.append(LiveCommand(title: "Take on another commander", act: .hire))
        }
        for prize in world.prizes {
            let tally = world.tallies.filter { $0.trial == prize.trial }.max { $0.round < $1.round }
            guard let tally, tally.points >= prize.points, !tally.hasClaimed(prize.place) else { continue }
            let name = world.trials[prize.trial]?.name ?? "the contest"
            all.append(LiveCommand(title: "Claim the prize of \(name) at \(prize.points) points", act: .claimPrize(contest: prize.trial, place: prize.place)))
        }
        if let home = world.city?.hex {
            func nearest<T>(_ things: [T], _ hex: (T) -> LiveHex) -> T? {
                things.min { (hex($0).distance(to: home), hex($0).packed) < (hex($1).distance(to: home), hex($1).packed) }
            }
            let may = world.hunt?.mayAttack ?? 1
            if let barrow = nearest(world.barrows.values.filter { $0.level <= may && $0.fighter == 0 }, \.hex) {
                all.append(LiveCommand(title: "Go to the nearest barrow you may attack, of level \(barrow.level)", act: .go(barrow.hex)))
            }
            if let cairn = nearest(world.cairns.values.filter { !world.hasFound($0) }, \.hex) {
                all.append(LiveCommand(title: "Go to the nearest cairn your scouts have not found, of level \(cairn.level)", act: .go(cairn.hex)))
            }
            for (index, good) in LiveSession.goods.enumerated() {
                if let site = nearest(world.sites.values.filter { $0.kind == index + 1 && $0.gatherer == 0 }, \.hex) {
                    all.append(LiveCommand(title: "Go to the nearest \(good.lowercased()) site, of level \(site.level)", act: .go(site.hex)))
                }
            }
        }
        return all
    }

    /// The commands whose words hold every word searched for, whatever
    /// their case; all of them for nothing searched.
    public func commands(matching search: String, at seconds: Double) -> [LiveCommand] {
        let words = search.lowercased().split(separator: " ").map(String.init)
        return commands(at: seconds).filter { command in
            let title = command.title.lowercased()
            return words.allSatisfy { title.contains($0) }
        }
    }

    /// Does what a command says: goes, or asks the realm. The part of a
    /// destination to open, where the command opens one.
    @discardableResult
    public func perform(_ command: LiveCommand) async -> String? {
        switch command.act {
        case .open(let part):
            return part
        case .go(let hex):
            go(to: hex)
            selected = hex
        case .build(let kind): await build(kind)
        case .upgrade(let building): await upgrade(building: building)
        case .learn(let topic): await learn(topic: topic)
        case .claimTask: await claimTask()
        case .openChest(let chest): await openChest(chest)
        case .forge(let piece): await forge(piece: piece)
        case .hire: await hire()
        case .claimPrize(let contest, let place): await claimPrize(contest: contest, place: place)
        case .promote(let building, let from, let to, let count): await promote(building: building, from: from, to: to, count: count)
        case .claimBoons: await claimBoons()
        case .helpAll: await helpAll()
        case .buy(let item): await buy(item: item)
        }
        return nil
    }
}
