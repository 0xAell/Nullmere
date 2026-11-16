import Foundation

extension LiveWorld {
    /// What happened between two moments of the player's realm, in a few
    /// words each, as a toast tells it: each work of the city done (a
    /// building raised, soldiers trained or healed, a study learnt), each
    /// army home, each report and letter come, and each army that has set
    /// out against the player's city. Nothing where either moment is
    /// before the player has a city.
    public static func news(from before: LiveWorld, to after: LiveWorld, at seconds: Double) -> [String] {
        guard before.city != nil, let home = after.city, before.city?.id == home.id else { return [] }
        var told: [String] = []
        // A work is gone from the city's list only when it is done.
        let still = Set(after.jobs.map(\.id))
        for job in before.jobs where !still.contains(job.id) {
            if let words = before.done(job) { told.append(words) }
        }
        let out = Set(after.myMarches.map(\.id))
        for march in before.myMarches where !out.contains(march.id) && march.state == LiveMarch.returning {
            let load = before.hauls.first { $0.march == march.id }?.goods ?? LiveGoods()
            told.append(load.isNone ? "Your army is home." : "Your army is home with \(load.words).")
        }
        let known = Set(before.reports.map(\.id))
        for report in after.reports where !known.contains(report.id) {
            let first = report.words.prefix { $0 != "." }
            told.append(report.kind == LiveReport.warning ? report.words : "A report: \(first).")
        }
        let letters = Set(before.letters.map(\.id))
        for letter in after.lettersReceived where !letters.contains(letter.id) {
            told.append("A letter from \(after.shownName(of: letter.sender) ?? letter.name).")
        }
        // Allies' help with the player's own works, as it comes.
        let mine = after.me?.id
        for plea in after.pleas where plea.asker == mine {
            let had = before.pleas.first { $0.job == plea.job }?.helped ?? 0
            let more = plea.helped - had
            guard more > 0 else { continue }
            let work: String
            switch plea.work {
            case LiveJob.raise: work = "your building"
            case LiveJob.train: work = "your training"
            case LiveJob.heal: work = "your healing"
            default: work = "your studies"
            }
            told.append(more == 1 ? "An ally helped with \(work)." : "\(more) allies helped with \(work).")
        }
        // A rally an ally has called, while there is time to join it.
        let called = Set(before.rallies.map(\.id))
        for rally in after.rallies where !called.contains(rally.id) && rally.caller != mine && rally.state == LiveRally.mustering {
            told.append(after.rallyWords(rally, at: seconds))
        }
        let gifts = Set(before.boons.map(\.id))
        for boon in after.boons where !gifts.contains(boon.id) {
            told.append("A gift from \(after.shownName(of: boon.giver) ?? "an ally")'s barrow: \(boon.goods.words).")
        }
        let threatened = Set(before.threats(at: seconds).map(\.id))
        for threat in after.threats(at: seconds) where !threatened.contains(threat.id) && threat.march.state == LiveMarch.going {
            told.append(threat.words)
        }
        return told
    }

    /// A work of the city, done, in words; nil for one the world can't name.
    func done(_ job: LiveJob) -> String? {
        let building = buildings.first { $0.id == job.subject }
        switch job.kind {
        case LiveJob.raise:
            guard let kind = building?.kind, let name = blueprint(kind, level: 1)?.name else { return nil }
            return "The \(name) stands at level \(job.level)."
        case LiveJob.train:
            guard let kind = building?.kind, let soldier = (1...16).compactMap({ soldier($0, tier: job.level) }).first(where: { $0.building == kind }) else { return nil }
            return "\(LiveWords.grouped(job.amount)) \(soldier.name) of tier \(job.level) are ready."
        case LiveJob.heal:
            return "\(LiveWords.grouped(job.amount)) wounded are healed."
        case LiveJob.study:
            guard let name = study(Int(job.subject), level: job.level)?.name else { return nil }
            return "\(name) is learnt to level \(job.level)."
        default:
            return nil
        }
    }
}
