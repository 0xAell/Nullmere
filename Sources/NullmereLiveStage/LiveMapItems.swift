import Foundation
import NullmereCore
import NullmereLive
import NullmereModels

/// One thing on the map as VoiceOver reads it: the player's city, another
/// city, an army, a barrow or a site, each where it lies in the window,
/// saying what it is and how it stands.
public struct LiveMapItem: Equatable, Identifiable, Sendable {
    public enum Kind: Equatable, Sendable {
        case home, city, army, ownArmy, barrow, site, gate, ward
    }

    public let hex: LiveHex
    public let kind: Kind
    public let label: String
    public var id: String { "\(kind)-\(hex.packed)" }
}

extension LiveSession {
    /// Everything in the window VoiceOver reads, the player's own city
    /// first, then their armies, then every other city, army, barrow,
    /// site, gate and wardstone, the nearest to the player's city first;
    /// each labelled by its card's title and first line.
    public func mapItems() -> [LiveMapItem] {
        guard let window else { return [] }
        let home = world.city?.hex ?? window.centre
        let seconds = now
        let layout = HexLayout(size: 1)
        var hexes = Set(world.places.keys.filter { window.local($0) != nil })
        for march in world.marches.values {
            let at = march.position(at: seconds)
            let on = layout.hex(atX: at.x, y: at.y)
            let hex = LiveHex(q: on.q, r: on.r)
            if window.local(hex) != nil { hexes.insert(hex) }
        }
        let items: [LiveMapItem] = hexes.compactMap { hex in
            let chosen = selection(at: hex)
            let kind: LiveMapItem.Kind
            switch chosen {
            case .home: kind = .home
            case .city: kind = .city
            case .army(_, let own): kind = own ? .ownArmy : .army
            case .barrow: kind = .barrow
            case .site: kind = .site
            case .gate: kind = .gate
            case .ward: kind = .ward
            case .land: return nil
            }
            let card = card(for: chosen)
            let label = card.lines.first.map { "\(card.title). \($0)" } ?? card.title
            return LiveMapItem(hex: hex, kind: kind, label: label)
        }
        func rank(_ kind: LiveMapItem.Kind) -> Int { kind == .home ? 0 : (kind == .ownArmy ? 1 : 2) }
        return items.sorted { (rank($0.kind), $0.hex.distance(to: home), $0.hex.packed) < (rank($1.kind), $1.hex.distance(to: home), $1.hex.packed) }
    }

    /// Where a hex of the world stands in a view of a size, at the height
    /// of the land there; nil where it lies outside the window drawn.
    public func viewPoint(of hex: LiveHex, in size: CGSize) -> CGPoint? {
        guard let local = window?.local(hex) else { return nil }
        let height = land().map { Double($0.relief.height(of: local)) } ?? 0
        return camera.viewPoint(of: local, height: height, in: size)
    }
}
