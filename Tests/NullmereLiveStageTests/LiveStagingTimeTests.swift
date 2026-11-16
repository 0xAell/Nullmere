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
        var times: [Double] = []
        var models = 0
        for index in 1...180 {
            let started = Date()
            let frame = session.frame(time: Double(index) / 60, size: size)
            times.append(Date().timeIntervalSince(started) * 1_000)
            models = frame.instanceCount
        }
        times.sort()
        let p50 = times[times.count / 2], p95 = times[times.count * 95 / 100]
        print("PERF staging the rebuilt realm's frame: \(models) of \(whole) models in view, \(crowd.cities + 2) cities and \(crowd.armies + 3) armies in the window, "
            + "p50 \(String(format: "%.2f", p50)) ms, p95 \(String(format: "%.2f", p95)) ms")
        print("PERFMETRIC live.stage.cpu.p50 \(String(format: "%.3f", p50))")
        print("PERFMETRIC live.stage.cpu.p95 \(String(format: "%.3f", p95))")
        #if os(macOS)
        // Held on the Mac, where the game is played; elsewhere only told.
        XCTAssertLessThan(p50, 16.7, "staged within a frame at sixty frames a second")
        #endif
    }
}
