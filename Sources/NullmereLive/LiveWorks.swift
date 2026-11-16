import Foundation

/// A work under way in the player's city, named: a building being
/// raised, soldiers training, the wounded being healed, a study.
public struct LiveWork: Equatable, Identifiable, Sendable {
    public let job: LiveJob
    public var id: UInt64 { job.id }
    /// What it is: "the Farm to level 3", "40 tier 1 Spearmen", "the
    /// healing of 12 wounded", "Tillage to level 2".
    public let words: String
}

extension LiveWorld {
    /// What hastening a work by a quarter of what is left of it costs, as
    /// the module's catalogue has it.
    public static let hastening = LiveGoods(grain: 300, timber: 300, stone: 300)

    /// The works under way in the player's city, the soonest done first,
    /// each named; none that is all but done.
    public func works(at seconds: Double) -> [LiveWork] {
        let trains = trainLines(at: seconds)
        let studies = studyLines(at: seconds)
        return jobs.filter { $0.left(at: seconds) > 1 }.sorted { ($0.ends, $0.id) < ($1.ends, $1.id) }.map { job in
            let words: String
            switch job.kind {
            case LiveJob.raise:
                let kind = buildings.first { $0.id == job.subject }?.kind
                let name = kind.flatMap { blueprint($0, level: 1)?.name } ?? "a building"
                words = "the \(name) to level \(job.level)"
            case LiveJob.train:
                let name = trains.first { $0.building.id == job.subject }?.tiers.first?.soldier.name ?? "soldiers"
                words = "\(LiveWords.grouped(job.amount)) tier \(job.level) \(name)"
            case LiveJob.heal:
                words = "the healing of \(LiveWords.grouped(job.amount)) wounded"
            case LiveJob.study:
                let name = studies.first { UInt64($0.topic) == job.subject }?.name ?? "a study"
                words = "\(name) to level \(job.level)"
            default:
                words = "a work"
            }
            return LiveWork(job: job, words: words)
        }
    }
}
