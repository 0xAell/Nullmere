import Foundation

/// Something of the player's standing idle that could be at work, told as
/// a reminder: a builder free while something may be built, the Academy
/// idle while something may be studied, a training ground training no one
/// while soldiers may be trained, a chest of the day waiting to be opened.
public struct LiveIdle: Equatable, Identifiable, Sendable {
    public enum Kind: String, Sendable {
        case builders, academy, training, chest
    }

    public let kind: Kind
    public var id: String { kind.rawValue }
    public let words: String
    /// The part of a destination that answers it, as the palette names
    /// parts: "city", "studies", "troops" or "day".
    public let part: String
}

extension LiveWorld {
    /// What stands idle that could be at work now, in the order a city is
    /// run: its builders, its Academy, its training grounds, its chests.
    public func idle(at seconds: Double) -> [LiveIdle] {
        guard let city else { return [] }
        var all: [LiveIdle] = []
        let raising = jobs.filter { $0.kind == LiveJob.raise }.count
        let free = max(city.builders - raising, 0)
        if free > 0, buildingLines(at: seconds).contains(where: { $0.block == nil && $0.next != nil }) {
            all.append(LiveIdle(kind: .builders, words: free == 1 ? "A builder is free" : "\(free) builders are free", part: "city"))
        }
        if !jobs.contains(where: { $0.kind == LiveJob.study }), studyLines(at: seconds).contains(where: { $0.block == nil && $0.next != nil }) {
            all.append(LiveIdle(kind: .academy, words: "The Academy is idle", part: "studies"))
        }
        let grounds = trainLines(at: seconds).filter { line in line.job == nil && line.tiers.contains { $0.block == nil } }
        if let first = grounds.first {
            all.append(LiveIdle(kind: .training, words: grounds.count == 1 ? "The \(first.name) trains no one" : "\(grounds.count) training grounds train no one",
                                part: "troops"))
        }
        let ready = chestLines(at: seconds).filter(\.ready).count
        if ready > 0 {
            all.append(LiveIdle(kind: .chest, words: ready == 1 ? "A chest of the day waits" : "\(ready) chests of the day wait", part: "day"))
        }
        return all
    }
}
