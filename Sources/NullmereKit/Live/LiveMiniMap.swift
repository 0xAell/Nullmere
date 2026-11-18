import CoreGraphics
import NullmereLive
import NullmereLiveStage
import SwiftUI

/// The whole realm small, in the corner: its grounds, every city on it
/// (the player's own brightest, an ally's green), the holy sites as small
/// diamonds (the player's alliance's green, another's grey, the Unquiet's
/// dark), and a ring where the view looks; a click anywhere on it looks
/// there.
struct LiveMiniMap: View {
    let session: LiveSession

    /// How wide it stands, in points.
    static let side: CGFloat = 168

    var body: some View {
        if let map = session.minimap, let image = LiveMiniMap.image(of: map) {
            let height = LiveMiniMap.side * CGFloat(map.height) / CGFloat(map.width)
            let world = session.world
            let look = map.place(of: session.look)
            ZStack {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.none)
                Canvas { context, size in
                    for city in world.cities.values {
                        let at = map.place(of: city.hex)
                        let own = city.owner == world.me?.id
                        let ally = world.isAlly(city.owner)
                        let r: CGFloat = own ? 3 : (ally ? 2.5 : 1.5)
                        let dot = CGRect(x: at.u * size.width - r, y: at.v * size.height - r, width: 2 * r, height: 2 * r)
                        context.fill(Path(ellipseIn: dot), with: .color(own ? .white : (ally ? Palette.good : Color(white: 0.75))))
                    }
                    let alliance = world.myMembership?.alliance
                    for shrine in world.shrines.values {
                        let at = map.place(of: shrine.hex)
                        let (x, y) = (at.u * size.width, at.v * size.height)
                        var diamond = Path()
                        diamond.addLines([CGPoint(x: x, y: y - 3), CGPoint(x: x + 3, y: y), CGPoint(x: x, y: y + 3), CGPoint(x: x - 3, y: y)])
                        diamond.closeSubpath()
                        let ours = shrine.holder != 0 && shrine.holder == alliance
                        context.fill(diamond, with: .color(ours ? Palette.good : (shrine.holder == 0 ? Color(white: 0.2) : Color(white: 0.75))))
                        context.stroke(diamond, with: .color(.white.opacity(0.7)), lineWidth: 0.5)
                    }
                    let ring = CGRect(x: look.u * size.width - 7, y: look.v * size.height - 7, width: 14, height: 14)
                    context.stroke(Path(ellipseIn: ring), with: .color(.white.opacity(0.9)), lineWidth: 1)
                }
            }
            .frame(width: LiveMiniMap.side, height: height)
            .contentShape(Rectangle())
            .onTapGesture { point in
                session.go(to: map.hex(atU: point.x / LiveMiniMap.side, v: point.y / height))
            }
            .padding(4)
            .panelBackground()
            .accessibilityElement()
            .accessibilityLabel("The whole realm, small")
            .accessibilityHint("Click anywhere on it to look there.")
            .accessibilityAddTraits(.isImage)
        }
    }

    /// Each ground's colour on the small map, as the module numbers grounds:
    /// deep water, shallows, strand, salt, plain, wood, heath and mountain.
    static let colours: [[UInt8]] = [[13, 31, 51], [31, 77, 97], [178, 166, 128], [217, 214, 204], [92, 133, 71], [46, 82, 46], [115, 107, 77], [128, 128, 133]]

    /// The small map's grounds as an image, a pixel to each; what is not
    /// told left clear.
    static func image(of map: LiveMinimap) -> CGImage? {
        var bytes = [UInt8](repeating: 0, count: map.width * map.height * 4)
        for (index, ground) in map.grounds.enumerated() where Int(ground) < colours.count {
            let colour = colours[Int(ground)]
            (bytes[index * 4], bytes[index * 4 + 1], bytes[index * 4 + 2], bytes[index * 4 + 3]) = (colour[0], colour[1], colour[2], 255)
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: map.width, height: map.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: map.width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
