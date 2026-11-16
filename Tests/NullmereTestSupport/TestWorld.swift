import NullmereLand

/// A world made as the turn-based game made an age's world, without its
/// rules: the land's generator's map, seats round the lake and streams, a
/// seat raised on each and the two companies that stood beside it, for
/// tests of how the land, its cities and its companies are drawn and
/// heard. The same seed text, Houses, radius, lake and streams make the
/// same map the game made, and the seats and companies take the ids and
/// the places the game gave them: each House's seat founded, then its
/// Lantern and its Spear set on the first open ground about it.
public struct TestWorld: Sendable {
    /// A company as the game first set it out.
    public struct Company: Sendable, Equatable {
        public let id: Int
        public let kind: UnitKind
        public let owner: Int
        public let position: Hex
    }

    public let map: WorldMap
    /// One seat for each House, about the lake.
    public let seats: [Hex]
    /// Each stream's course, from its spring to its mouth; none unless asked.
    public let streams: [[Hex]]
    /// A seat raised on each, the Houses' in turn.
    public var holds: [Hold]
    /// Each House's Lantern and Spear, beside its seat.
    public var companies: [Company]

    public init(seedText: String, houses: Int = 5, radius: Int = 24, lake: Lake = .round, rivers: Bool = false) {
        let world = WorldGenerator(seed: Seed.from(seedText), radius: radius, houseCount: houses, lake: lake, rivers: rivers).generate()
        map = world.map
        seats = world.seats
        streams = world.streams
        var holds: [Hold] = []
        var companies: [Company] = []
        var next = 1
        for (index, seat) in world.seats.enumerated() {
            holds.append(Hold(id: next, name: "Seat \(index + 1)", owner: index, position: seat, isSeat: true, foundedWatch: 1))
            next += 1
            for kind in [UnitKind.lantern, .spear] {
                // The first open ground about the seat: land a company can
                // stand on, no company there, no other House's hold.
                let spot = seat.spiral(3).first { hex in
                    guard let tile = world.map[hex], tile.terrain.isPassable else { return false }
                    return !companies.contains { $0.position == hex } && (holds.first { $0.position == hex }.map { $0.owner == index } ?? true)
                }
                guard let spot else { continue }
                companies.append(Company(id: next, kind: kind, owner: index, position: spot))
                next += 1
            }
        }
        self.holds = holds
        self.companies = companies
    }
}
