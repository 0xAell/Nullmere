import Foundation
import NullmereLive
@testable import NullmereLiveStage
import NullmereModels
import NullmereRealm
import NullmereTestSupport
import NullmereWorld
import XCTest

/// How long the rebuilt realm's frame takes to stage: a crowded
/// neighbourhood about the player's city, every city in the window
/// standing and an army out from each, sites and barrows between, staged
/// frame after frame as the map draws it. The Mac's CI prints the figure
/// beside its others (perf/baseline.json).
@MainActor
final class LiveStagingTimeTests: XCTestCase {
    private static func n(_ value: Int) -> JSONValue { .number(Double(value)) }
    private static func n(_ value: UInt64) -> JSONValue { .number(Double(value)) }

    /// The hexes from one to another, a step at a time.
    private static func way(from: LiveHex, to: LiveHex) -> [LiveHex] {
        let steps = max(from.distance(to: to), 1)
        return (0...steps).map { step in
            let t = Double(step) / Double(steps)
            // Along the line in cube coordinates, rounded to the nearest hex.
            let (x, z) = (Double(from.q) + (Double(to.q) - Double(from.q)) * t, Double(from.r) + (Double(to.r) - Double(from.r)) * t)
            let y = -x - z
            var (rx, ry, rz) = (x.rounded(), y.rounded(), z.rounded())
            let (dx, dy, dz) = (abs(rx - x), abs(ry - y), abs(rz - z))
            if dx > dy && dx > dz { rx = -ry - rz } else if dy > dz { ry = -rx - rz } else { rz = -rx - ry }
            return LiveHex(q: Int(rx), r: Int(rz))
        }
    }

    private static func encoded(_ way: [LiveHex]) -> String {
        way.flatMap { hex -> [UInt8] in
            let (q, r) = (UInt16(bitPattern: Int16(hex.q)), UInt16(bitPattern: Int16(hex.r)))
            return [UInt8(q & 0xFF), UInt8(q >> 8), UInt8(r & 0xFF), UInt8(r >> 8)]
        }.map { String(format: "%02x", $0) }.joined()
    }

    /// The sample's realm (Ada's city at 10, -4) with a city of another
    /// player on every third hex about it within eleven, an army out from
    /// each to the next, and a site or a barrow beside every other city.
    static func crowded() -> (rows: [String: [[JSONValue]]], cities: Int, armies: Int) {
        var rows = LiveSample.rows()
        let home = LiveHex(q: 10, r: -4)
        let taken = Set([home, LiveHex(q: 14, r: -4), LiveHex(q: 12, r: -2), LiveHex(q: 8, r: -2)])
        var spots: [LiveHex] = []
        for dq in stride(from: -11, through: 11, by: 3) {
            for dr in stride(from: -11, through: 11, by: 3) {
                let hex = LiveHex(q: home.q + dq, r: home.r + dr)
                let far = hex.distance(to: home)
                if (2...11).contains(far), !taken.contains(hex) { spots.append(hex) }
            }
        }
        for (index, hex) in spots.enumerated() {
            let id = UInt64(100 + index)
            rows["player", default: []].append([n(id), n(9), .string("Holder \(index)"), n(1_000), .bool(true), n(1_000)])
            rows["city", default: []].append([n(id), n(id), n(hex.packed), .string("Holder \(index)"), n(1 + index % 12), n(1_000), n(1_000), n(1)])
            rows["place", default: []].append([n(hex.packed), n(1), n(id)])
            // Beside it, a site or a barrow.
            let beside = LiveHex(q: hex.q + 1, r: hex.r)
            if index.isMultiple(of: 2) {
                rows["site", default: []].append([n(500 + index), n(beside.packed), n(1 + index % 4), n(1 + index % 5), n(60_000), n(0)])
                rows["place", default: []].append([n(beside.packed), n(2), n(500 + index)])
            } else {
                rows["barrow", default: []].append([n(500 + index), n(beside.packed), n(1 + index % 5), n(0)])
                rows["place", default: []].append([n(beside.packed), n(3), n(500 + index)])
            }
            // And its army on the way to the next city, some of the way there.
            let next = spots[(index + 1) % spots.count]
            let route = encoded(way(from: hex, to: next))
            rows["march", default: []].append([n(1_000 + index), n(id), n(id), n(LiveMarch.attack), n(LiveMarch.going), n(hex.packed), n(next.packed),
                                               n(UInt64(100 + (index + 1) % spots.count)), n(2_000), n(2_000 + 30 + index), n(200 + 40 * index),
                                               .string(route), n(1)])
        }
        return (rows, spots.count, spots.count)
    }

    func testTheRebuiltRealmsFrameIsStagedWithinAFrame() async throws {
        let crowd = Self.crowded()
        XCTAssertGreaterThan(crowd.cities, 30, "a crowded neighbourhood")
        let session = LiveSession(line: StandInLine(rows: crowd.rows)) { 2_015 }
        await session.open()
        // The first frame furnishes the land, once for the window.
        let first = session.frame(time: 0)
        XCTAssertGreaterThan(first.instanceCount, 0, "staged")
        let keeps = first.batches.filter { batch in
            switch batch.key {
            case .keep, .keepOf: return true
            default: return false
            }
        }
        XCTAssertGreaterThanOrEqual(keeps.reduce(0) { $0 + $1.instances.count }, crowd.cities, "every city standing")

        // As the map asks for it: only what a laptop's window shows, about
        // her city at the opening's scale.
        let size = CGSize(width: 1512, height: 982)
        let whole = session.frame(time: 0.5).instanceCount
        let seen = session.frame(time: 0.5, size: size).instanceCount
        XCTAssertLessThanOrEqual(seen, whole)
        XCTAssertGreaterThan(seen, first.fixed.reduce(0) { $0 + $1.instances.count }, "What the view shows is staged")
        let narrow = session.frame(time: 0.5, size: CGSize(width: 320, height: 200)).instanceCount
        XCTAssertLessThan(narrow, seen, "and what a narrow view can't show is left out")
        // Each frame timed by the thread's own clock, as the plain work that
        // paces it is: staging is the work of one thread, and a shared
        // runner that takes the thread away for a while (run 1124: a median
        // of 17.6 ms by the wall's clock, a slowest twentieth of 29) adds
        // nothing to it. The wall's clock is told beside it.
        var times: [Double] = []
        var walls: [Double] = []
        var models = 0
        for index in 1...180 {
            let started = CalibrationTests.threadCPUSeconds(), wall = Date()
            let frame = session.frame(time: Double(index) / 60, size: size)
            times.append((CalibrationTests.threadCPUSeconds() - started) * 1_000)
            walls.append(Date().timeIntervalSince(wall) * 1_000)
            models = frame.instanceCount
        }
        times.sort()
        walls.sort()
        let p50 = times[times.count / 2], p95 = times[times.count * 95 / 100]
        print("PERF staging the rebuilt realm's frame: \(models) of \(whole) models in view, \(crowd.cities + 2) cities and \(crowd.armies + 3) armies in the window, "
            + "p50 \(String(format: "%.2f", p50)) ms, p95 \(String(format: "%.2f", p95)) ms of the thread's time; "
            + "by the wall's clock p50 \(String(format: "%.2f", walls[walls.count / 2])) ms, p95 \(String(format: "%.2f", walls[walls.count * 95 / 100])) ms")
        print("PERFMETRIC live.stage.cpu.p50 \(String(format: "%.3f", p50))")
        print("PERFMETRIC live.stage.cpu.p95 \(String(format: "%.3f", p95))")
        // The runner's pace beside it: the calibration's plain work, timed
        // as CalibrationTests times it, against its baseline. A shared
        // runner twice as slow stages twice as slowly (CI run 1117, the
        // plain work at 853.6 ms, staged at 17.3 against runs 1111 and
        // 1116's 11): the frame is held at the pace the game is played at,
        // the slowness of a runner taken out of it, up to twice, as
        // scripts/perf-check.py takes it out of every CPU figure.
        let pace = Self.pace()
        print("PERF staging paced: the plain work at x\(String(format: "%.2f", pace)) its baseline, p50 \(String(format: "%.2f", p50 / pace)) ms at its pace")
        // Where it goes, part by part, over as many frames again.
        session.stagingParts = [:]
        for index in 1...180 { _ = session.frame(time: Double(index) / 60, size: size) }
        let parts = try XCTUnwrap(session.stagingParts)
        XCTAssertEqual(Set(parts.keys), ["cities read", "places read", "cities staged", "armies read", "places staged", "armies staged", "detail", "ways"])
        print("PERF staging by part, each frame's mean: " + parts.sorted { $0.value > $1.value }
            .map { "\($0.key) \(String(format: "%.2f", $0.value / 180)) ms" }.joined(separator: ", "))
        session.stagingParts = nil
        #if os(macOS)
        // Held on the Mac, where the game is played; elsewhere only told.
        XCTAssertLessThan(p50 / pace, 16.7, "staged within a frame at sixty frames a second")
        #endif
    }

    /// The calibration's baseline: its plain work's best, in milliseconds,
    /// on the runners the CPU baselines were set on (perf/baseline.json).
    static let plainWorkBaseline = 353.0

    /// How much slower than the baseline this runner does the plain work
    /// now, the best of three, at least one and at most twice.
    static func pace() -> Double {
        var best = Double.infinity
        for _ in 0..<3 {
            let started = CalibrationTests.threadCPUSeconds()
            var folded = 0
            for round in 0..<6 {
                folded ^= CalibrationTests.plainWork(seed: UInt64(round))
            }
            precondition(folded != 0)
            best = min(best, (CalibrationTests.threadCPUSeconds() - started) * 1000)
        }
        return min(max(best / plainWorkBaseline, 1), 2)
    }

    func testTheRunnersPaceIsTakenOutUpToTwice() {
        let pace = Self.pace()
        XCTAssertGreaterThanOrEqual(pace, 1)
        XCTAssertLessThanOrEqual(pace, 2)
        // The baseline is the calibration's own, as perf-check holds it.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        if let baseline = try? String(contentsOf: root.appendingPathComponent("perf/baseline.json"), encoding: .utf8),
           let at = baseline.range(of: "\"calibration.cpu\": {") {
            let entry = baseline[at.upperBound...].prefix { $0 != "}" }
            XCTAssertTrue(entry.contains("\"baseline\": \(Int(Self.plainWorkBaseline)),"), String(entry))
        }
    }
}
