import Foundation
import NullmereCore
import NullmereModels
@testable import NullmereWorld

// The turn-based game as the world drew it: what the world's own code no
// longer reads, nor the rebuilt realm's stage, kept beside the tests that
// still build their worlds from the old rules, until they and the rules go
// (docs/core-split.md, step 5).

extension TileTexture {
    /// The tile texture's bytes for a keeper of the old game: its map, what
    /// it has seen and sees, and whose land each tile is. `visible` and
    /// `owners` may be passed when already worked out, and `ground` when
    /// the map hasn't changed, as the session did on every change.
    static func bytes(for state: GameState, viewer: Int, visible: [Bool]? = nil, owners: [Int?]? = nil,
                      ground: Ground? = nil) -> [UInt8] {
        let map = state.map
        let ground = ground.flatMap { $0.map == map ? $0 : nil } ?? Ground(map: map)
        var bytes = ground.bytes
        let visible = visible ?? state.visibility(for: viewer)
        let explored = state.houses[viewer].explored
        let owners = owners ?? state.territory()
        let holdTiles = Set(state.holds.compactMap { map.index(of: $0.position) })
        // Each hold's colour, found once rather than for every tile.
        var colourOf: [Int: Int] = [:]
        for hold in state.holds { colourOf[hold.id] = state.houses[hold.owner].sigil + 1 }
        for index in 0..<map.count {
            let seen = visible[index] ? 2 : (explored[index] ? 1 : 0)
            guard seen > 0 else { continue }
            let offset = ground.offsets[index]
            var owner = 0
            if let holdID = owners[index], let colour = colourOf[holdID] {
                owner = colour
            }
            // A known hold lights the country round it: the feature byte's top bit.
            if holdTiles.contains(index) {
                bytes[offset + 1] |= TileTexture.holdFlag
            }
            bytes[offset + 1] |= UInt8(seen) * TileTexture.seenStep
            let named = min(owner, TileTexture.mostOwner)
            bytes[offset + 3] = UInt8(truncatingIfNeeded: named)
            bytes[offset] |= UInt8(truncatingIfNeeded: named >> 8) << 4
        }
        return bytes
    }
}

extension WorldStage {
    /// Where the foe stands that each company standing in a field of
    /// battle presses hand to hand, by the company's id. Two companies that
    /// fight hand to hand beside each other press each other, paired first
    /// where each fights the other (`Fighter.foe`), then where one of them
    /// fights the other, then any two beside each other, the lowest ids
    /// first; each pressed by one foe at most, so no company presses into a
    /// flank turned toward another. A company of them left unpaired presses
    /// a foe beside it that holds its ground (one of the bows or engines, or
    /// another left unpaired), the one it fights first; so the fronts meet
    /// and never pass through each other. One that fights at a distance,
    /// bows and engines, presses no foe; nor one with none beside it.
    static func handToHand(in state: GameState) -> [Int: Hex] {
        var found: [Int: Hex] = [:]
        for field in state.fieldsOfBattle {
            let standing = field.fighters.filter(\.standing).compactMap { fighter in
                state.unit(fighter.unit).map { (fighter: fighter, at: $0.position) }
            }
            guard standing.count > 1 else { continue }
            func closeIn(_ fighter: Fighter) -> Bool { fighter.kind.isMilitary && fighter.kind.range <= 1 }
            let hand = standing.filter { closeIn($0.fighter) }.sorted { $0.fighter.unit < $1.fighter.unit }
            // Every two beside each other on opposite sides that both fight
            // hand to hand, by how surely they fight each other.
            var pairs: [(rank: Int, low: Int, high: Int, lowAt: Hex, highAt: Hex)] = []
            for (index, one) in hand.enumerated() {
                for other in hand.dropFirst(index + 1) where other.fighter.side != one.fighter.side && other.at.distance(to: one.at) == 1 {
                    let named = (one.fighter.foe == other.fighter.unit ? 1 : 0) + (other.fighter.foe == one.fighter.unit ? 1 : 0)
                    pairs.append((2 - named, one.fighter.unit, other.fighter.unit, one.at, other.at))
                }
            }
            pairs.sort { ($0.rank, $0.low, $0.high) < ($1.rank, $1.low, $1.high) }
            var paired = Set<Int>()
            for pair in pairs where !paired.contains(pair.low) && !paired.contains(pair.high) {
                paired.formUnion([pair.low, pair.high])
                found[pair.low] = pair.highAt
                found[pair.high] = pair.lowAt
            }
            // Those left unpaired press a foe beside them that holds its ground.
            for (fighter, at) in hand where !paired.contains(fighter.unit) {
                let still = standing.filter { other in
                    other.fighter.side != fighter.side && other.at.distance(to: at) == 1 && !paired.contains(other.fighter.unit)
                }
                let foe = still.first { $0.fighter.unit == fighter.foe } ?? still.min { $0.fighter.unit < $1.fighter.unit }
                if let foe { found[fighter.unit] = foe.at }
            }
        }
        return found
    }

    /// The hue of a mark's light by what it bids (`AllianceMark.Kind.hue`).
    static func markHue(_ kind: AllianceMark.Kind) -> Vec3 {
        Vec3(kind.hue.red, kind.hue.green, kind.hue.blue)
    }

    /// Each tincture's colour, as the interface paints it.
    static func colour(of tincture: Crest.Tincture) -> Vec4 {
        switch tincture {
        case .silver: return Vec4(0.80, 0.82, 0.85, 1)
        case .gold: return Vec4(0.84, 0.66, 0.25, 1)
        case .black: return Vec4(0.10, 0.10, 0.12, 1)
        case .blue: return Vec4(0.20, 0.37, 0.67, 1)
        case .red: return Vec4(0.66, 0.20, 0.18, 1)
        case .green: return Vec4(0.19, 0.49, 0.31, 1)
        case .purple: return Vec4(0.42, 0.26, 0.62, 1)
        }
    }

    /// Each hold's House crest hung on a board beside its gate, facing out:
    /// the shield in its field tincture, its charge laid on it in its own.
    func crestBoards(_ boards: [(hex: Hex, crest: Crest)]) -> [ModelBatch] {
        var placed: [(ModelKey, ModelInstance)] = []
        for board in boards {
            let centre = Relief.centre(of: board.hex)
            let front = HoldLayout.frontAngle(of: board.hex)
            let out = Vec3(Float(cos(Double(front))), 0, Float(sin(Double(front))))
            let side = Vec3(-out.z, 0, out.x)
            let x = centre.x + out.x * WorldStage.crestReach + side.x * WorldStage.crestAside
            let z = centre.z + out.z * WorldStage.crestReach + side.z * WorldStage.crestAside
            let model = Mat4.translation(Vec3(x, ground(atX: x, z: z) - Scatter.sink, z)) * .rotationY(Float(atan2(Double(out.x), Double(out.z))))
            let hex = SIMD2(Int32(board.hex.q), Int32(board.hex.r))
            let charge = Crest.Charge.allCases.firstIndex(of: board.crest.charge) ?? 0
            placed.append((.crestBoard, ModelInstance(model: model, colour: WorldStage.colour(of: board.crest.field), hex: hex)))
            placed.append((.crestCharge(charge), ModelInstance(model: model, colour: WorldStage.colour(of: board.crest.tincture), hex: hex)))
        }
        return WorldStage.batches(placed)
    }
}

extension UnburiedSight {
    /// The fields of dead whose lights hang at `watch`, `darkIn` watches from
    /// the dark of the moon: every one given, unless its dead still lie
    /// quiet, as they do the watch the first of them fell and any watch a
    /// blow is struck on the field or from it (`blows`). The lights kindle
    /// once a field falls quiet, so no battle is fought under them.
    static func kindled(_ fields: [FieldOfDead], watch: Int, darkIn: Int, blows: [FieldBlow] = []) -> [UnburiedSight] {
        guard !fields.isEmpty else { return [] }
        let fought = Set(blows.filter { $0.watch >= watch }.flatMap { [$0.at, $0.from] })
        return fields.compactMap { field in
            guard field.since < watch, !fought.contains(field.at) else { return nil }
            return UnburiedSight(at: field.at, troops: field.troops, darkIn: darkIn)
        }
    }
}

extension Weather {
    /// The weather an omen brings.
    static func of(_ omen: OmenKind?) -> Weather {
        switch omen {
        case .leanWatch?: return .rain
        case .risingMist?: return .mist
        case .stillNight?: return .still
        case .moonsaltBloom?: return .bloom
        case nil: return .clear
        }
    }
}

extension Petition.Plea {
    /// Which of the townsfolk brings a plea of this kind (`Folk`'s
    /// variants): a porter for the masons, a timber carter for the
    /// woodwards, an elder for the healers, a farmhand for the reeve's
    /// folk, a water-carrier for the brewers.
    var folk: Int {
        switch self {
        case .mend: return Folk.porter
        case .douse: return Folk.timberCarter
        case .tend: return Folk.elder
        case .hands: return Folk.farmhand
        case .feast: return Folk.waterCarrier
        }
    }
}
