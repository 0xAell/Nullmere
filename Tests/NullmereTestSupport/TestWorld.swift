import NullmereLand

/// A world made as the turn-based game made an age's world, without its
/// rules: the land's generator's map, seats round the lake and streams,
/// and a seat raised on each, for tests of how the land and its cities are
/// drawn and heard. The same seed text, Houses, radius, lake and streams
/// make the same map the game made, and the seats' holds take the ids the
/// game gave them (each House's seat founded before its two companies).
public struct TestWorld: Sendable {
    public let map: WorldMap
    /// One seat for each House, about the lake.
    public let seats: [Hex]
    /// Each stream's course, from its spring to its mouth; none unless asked.
    public let streams: [[Hex]]
    /// A seat raised on each, the Houses' in turn.
    public var holds: [Hold]

    public init(seedText: String, houses: Int = 5, radius: Int = 24, lake: Lake = .round, rivers: Bool = false) {
        let world = WorldGenerator(seed: Seed.from(seedText), radius: radius, houseCount: houses, lake: lake, rivers: rivers).generate()
        map = world.map
        seats = world.seats
        streams = world.streams
        holds = world.seats.enumerated().map { index, seat in
            Hold(id: 1 + 3 * index, name: "Seat \(index + 1)", owner: index, position: seat, isSeat: true, foundedWatch: 1)
        }
    }
}
