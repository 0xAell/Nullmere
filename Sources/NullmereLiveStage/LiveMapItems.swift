import Foundation
import NullmereCore
import NullmereLive
import NullmereModels

/// One thing on the map as VoiceOver reads it: the player's city, another
/// city, an army, a barrow, a site or a cairn, each where it lies in the window,
/// saying what it is and how it stands.
public struct LiveMapItem: Equatable, Identifiable, Sendable {
    public enum Kind: Equatable, Sendable {
        case home, city, army, ownArmy, barrow, site, gate, ward, cairn
    }

    public let hex: LiveHex
    public let kind: Kind
    public let label: String
    public var id: String { "\(kind)-\(hex.packed)" }
}

extension LiveSession {
    /// Everything in the window VoiceOver reads, the player's own city
    /// first, then their armies, then every other city, army, barrow,
    /// site, gate, wardstone and cairn, the nearest to the player's city first;
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
            case .cairn: kind = .cairn
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

/// A city's name as it hangs over the city on the map: whose, at what
/// level of its Keep, and whether it is the player's own or an ally's.
public struct LiveCityLabel: Equatable, Identifiable, Sendable {
    public let id: UInt64
    public let words: String
    public let point: CGPoint
    public let own: Bool
    public let ally: Bool
}

extension LiveSession {
    /// How far above the heart of a city's hex its name hangs, in points.
    public static let labelLift: CGFloat = 34

    /// The names over the cities in a view of a size: each city in the
    /// window whose name would hang within the view, under its owner's name
    /// as others read it and its Keep's level.
    public func cityLabels(in size: CGSize) -> [LiveCityLabel] {
        world.cities.values.sorted { $0.id < $1.id }.compactMap { city in
            guard let at = viewPoint(of: city.hex, in: size) else { return nil }
            let point = CGPoint(x: at.x, y: at.y - LiveSession.labelLift)
            guard point.x > 0, point.x < size.width, point.y > 0, point.y < size.height else { return nil }
            let name = world.shownName(of: city.owner) ?? city.name
            return LiveCityLabel(id: city.id, words: "\(name) · \(city.keep)", point: point, own: city.owner == world.me?.id, ally: world.isAlly(city.owner))
        }
    }
}
