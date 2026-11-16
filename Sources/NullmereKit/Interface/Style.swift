import AppKit
import LauncherCore
import LauncherKit
import NullmereCore
import NullmereWorld
import Observation
import SwiftUI

/// Nullmere's few colours: pale, cold type over the dark, the launcher's
/// own, and the colours of the Houses (matching the world shader).
enum Palette {
    static let ink = LauncherKit.Palette.ink
    static let glow = LauncherKit.Palette.glow
    static let good = Color(red: 0.62, green: 0.84, blue: 0.70)
    /// Warning red, pale enough to read as words, a dot or a comma and all.
    static let bad = Color(red: 0.95, green: 0.64, blue: 0.60)
    /// The glow, as words: lifted toward the ink so small type in it reads.
    static let glowWords = Color(red: 0.74, green: 0.82, blue: 0.94)
    static let panel = Color(red: 0.02, green: 0.025, blue: 0.035)

    /// One colour for each House that may sit around the lake, in the order
    /// of their names: the twelve elder Houses' first, each plainly apart,
    /// then the younger Houses' of lakes of up to ninety-six seats, each
    /// still its own beside any other, then the widest lakes' (see
    /// `HousePalette.widestLakes`). The world's shaders take the same, made
    /// linear.
    static let houseRGB: [RGB] = [
        RGB(0.86, 0.74, 0.47),
        RGB(0.70, 0.27, 0.25),
        RGB(0.30, 0.60, 0.60),
        RGB(0.58, 0.44, 0.74),
        RGB(0.78, 0.80, 0.84),
        RGB(0.86, 0.50, 0.26),
        RGB(0.46, 0.68, 0.38),
        RGB(0.80, 0.56, 0.68),
        RGB(0.36, 0.48, 0.84),
        RGB(0.55, 0.52, 0.22),
        RGB(0.40, 0.78, 0.86),
        RGB(0.88, 0.36, 0.50),
        RGB(0.690, 0.900, 0.270),
        RGB(0.847, 0.270, 0.900),
        RGB(0.192, 0.640, 0.192),
        RGB(0.540, 0.900, 0.630),
        RGB(0.270, 0.900, 0.322),
        RGB(0.280, 0.200, 0.660),
        RGB(0.630, 0.630, 0.900),
        RGB(0.640, 0.464, 0.448),
        RGB(0.270, 0.900, 0.742),
        RGB(0.900, 0.900, 0.630),
        RGB(0.165, 0.550, 0.422),
        RGB(0.511, 0.694, 0.730),
        RGB(0.730, 0.639, 0.365),
        RGB(0.900, 0.540, 0.900),
        RGB(0.410, 0.820, 0.512),
        RGB(0.495, 0.360, 0.900),
        RGB(0.717, 0.820, 0.574),
        RGB(0.270, 0.638, 0.900),
        RGB(0.321, 0.550, 0.275),
        RGB(0.485, 0.820, 0.246),
        RGB(0.900, 0.795, 0.270),
        RGB(0.385, 0.440, 0.550),
        RGB(0.697, 0.328, 0.820),
        RGB(0.219, 0.517, 0.730),
        RGB(0.630, 0.900, 0.877),
        RGB(0.219, 0.730, 0.517),
        RGB(0.820, 0.246, 0.390),
        RGB(0.900, 0.360, 0.765),
        RGB(0.602, 0.730, 0.511),
        RGB(0.645, 0.730, 0.219),
        RGB(0.730, 0.438, 0.608),
        RGB(0.347, 0.730, 0.219),
        RGB(0.787, 0.900, 0.450),
        RGB(0.900, 0.600, 0.540),
        RGB(0.448, 0.544, 0.640),
        RGB(0.550, 0.385, 0.522),
        RGB(0.365, 0.730, 0.669),
        RGB(0.730, 0.395, 0.365),
        RGB(0.750, 0.450, 0.900),
        RGB(0.540, 0.900, 0.360),
        RGB(0.574, 0.820, 0.779),
        RGB(0.450, 0.562, 0.900),
        RGB(0.649, 0.820, 0.410),
        RGB(0.900, 0.630, 0.742),
        RGB(0.900, 0.323, 0.270),
        RGB(0.320, 0.640, 0.427),
        RGB(0.820, 0.547, 0.410),
        RGB(0.640, 0.379, 0.192),
        RGB(0.820, 0.676, 0.246),
        RGB(0.717, 0.574, 0.820),
        RGB(0.453, 0.640, 0.192),
        RGB(0.730, 0.560, 0.219),
        RGB(0.640, 0.320, 0.587),
        RGB(0.900, 0.270, 0.637),
        RGB(0.246, 0.820, 0.629),
        RGB(0.219, 0.730, 0.304),
        RGB(0.730, 0.292, 0.474),
        RGB(0.450, 0.900, 0.787),
        RGB(0.550, 0.403, 0.330),
        RGB(0.540, 0.750, 0.900),
        RGB(0.270, 0.848, 0.900),
        RGB(0.730, 0.566, 0.511),
        RGB(0.536, 0.550, 0.385),
        RGB(0.219, 0.730, 0.730),
        RGB(0.365, 0.578, 0.730),
        RGB(0.779, 0.820, 0.328),
        RGB(0.360, 0.900, 0.585),
        RGB(0.220, 0.495, 0.550),
        RGB(0.270, 0.428, 0.900),
        RGB(0.820, 0.492, 0.793),
        RGB(0.448, 0.640, 0.528),
        RGB(0.637, 0.270, 0.900),
        RGB(0.328, 0.697, 0.820),
        RGB(0.900, 0.675, 0.360),
        RGB(0.900, 0.900, 0.360),
        RGB(0.820, 0.492, 0.547),
        RGB(0.385, 0.550, 0.468),
        RGB(0.246, 0.820, 0.437),
        RGB(0.820, 0.246, 0.724),
        RGB(0.620, 0.292, 0.730),
        RGB(0.519, 0.492, 0.820),
        RGB(0.820, 0.676, 0.574),
        RGB(0.900, 0.450, 0.360),
        RGB(0.587, 0.640, 0.320),
    ] + HousePalette.widestLakes.map(RGB.init(hex:))
    static let houses: [Color] = houseRGB.map(\.colour)

    /// A colour as its three parts, for working out how it reads.
    struct RGB: Equatable {
        let red, green, blue: Double

        init(_ red: Double, _ green: Double, _ blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        /// A colour from its bytes of red, green and blue, as 0xRRGGBB.
        init(hex: UInt32) {
            self.init(Double(hex >> 16 & 0xFF) / 255, Double(hex >> 8 & 0xFF) / 255, Double(hex & 0xFF) / 255)
        }

        var colour: Color { Color(red: red, green: green, blue: blue) }

        /// How bright it is to the eye, by the measure contrast is reckoned in.
        var luminance: Double {
            func linear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }

        func contrast(with other: RGB) -> Double {
            let (light, dark) = (max(luminance, other.luminance), min(luminance, other.luminance))
            return (light + 0.05) / (dark + 0.05)
        }

        /// Part of the way to another colour.
        func toward(_ other: RGB, by amount: Double) -> RGB {
            RGB(red + (other.red - red) * amount, green + (other.green - green) * amount, blue + (other.blue - blue) * amount)
        }
    }
    /// The pale type, by the launcher's one rule: as faint as the design
    /// asks, but never too faint to read, and plainer with Increase Contrast.
    static func text(_ opacity: Double) -> Color {
        LauncherKit.Palette.text(opacity)
    }

    /// A line, a track or a mark that isn't type, by the launcher's rule.
    static func line(_ opacity: Double) -> Color {
        LauncherKit.Palette.line(opacity)
    }
}

/// Uppercase, widely tracked type, as in the launcher. Tracking adds
/// space after the last letter; centred capitals take the same before the
/// first, as the launcher's do, so they sit centred over what lies beneath.
struct Caps: View {
    let text: String
    var size: CGFloat = 10
    var weight: Font.Weight = .regular
    var tracking: CGFloat = 0.28
    var centred = false

    init(_ text: String, size: CGFloat = 10, weight: Font.Weight = .regular, tracking: CGFloat = 0.28, centred: Bool = false) {
        self.text = text
        self.size = size
        self.weight = weight
        self.tracking = tracking
        self.centred = centred
    }

    var body: some View {
        // Spaced by the size the letters are drawn at, Larger type and all.
        let drawn = TextSize.shared.size(size)
        Text(verbatim: text.uppercased())
            .font(.nmCaps(size, weight: weight))
            .tracking(drawn * tracking)
            .padding(.leading, centred ? drawn * tracking : 0)
            // Read as words, not as capitals to be spelled.
            .accessibilityLabel(Text(verbatim: text))
    }
}

extension Font {
    /// The interface's words at a size, scaled by the reader's choice, and
    /// never under the least that reads: eleven points, whose full stops
    /// and dots still cover whole pixels; and at a weight that holds its
    /// contrast at the size drawn.
    @MainActor
    static func nm(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let drawn = TextSize.shared.size(size, words: true)
        return .system(size: drawn, weight: Font.readable(weight, at: drawn))
    }

    /// The interface's spaced capitals, whose strokes are all full height:
    /// never under nine and a half points.
    @MainActor
    static func nmCaps(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let drawn = TextSize.shared.size(size)
        return .system(size: drawn, weight: Font.readable(weight, at: drawn))
    }

    static func readable(_ weight: Font.Weight, at size: CGFloat) -> Font.Weight {
        TextSize.readable(weight, at: size)
    }
}

/// The dark glass behind panels.
struct PanelBackground: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            // Wholly dark: what lies beneath, the salt flats by moonlight or
            // a token, never shows through behind the type.
            .background(Palette.panel)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Palette.line(0.12), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .chrome("panel")
    }
}

/// What of the window the interface takes, piece by piece: each piece
/// notes where it lies as it is laid out, while a test listens, so the
/// world's share of the screen can be held to a budget.
@MainActor
enum ChromeLedger {
    static var isListening = false {
        didSet { frames = [:] }
    }
    /// Where each kind of piece lies, in the window's points.
    private(set) static var frames: [String: [CGRect]] = [:]

    static func note(_ name: String, _ frame: CGRect) {
        guard isListening, frame.width > 0, frame.height > 0, frames[name]?.contains(frame) != true else { return }
        frames[name, default: []].append(frame)
    }

    /// The share of a window of `size` the pieces cover, sampled every
    /// four points.
    static func covered(of size: CGSize) -> Double {
        let pieces = frames.values.flatMap { $0 }
        var covered = 0, all = 0
        for y in stride(from: 2.0, to: size.height, by: 4) {
            for x in stride(from: 2.0, to: size.width, by: 4) {
                all += 1
                if pieces.contains(where: { $0.contains(CGPoint(x: x, y: y)) }) { covered += 1 }
            }
        }
        return all == 0 ? 0 : Double(covered) / Double(all)
    }
}

extension EnvironmentValues {
    /// Within a card held to a height, its pieces are noted once, by the
    /// card's own frame: what scrolls out of sight is not on the screen.
    @Entry var chromeNotedByCard = false
}

/// Notes where a piece of the interface lies, unless the card it is in
/// notes it.
private struct ChromeNote: ViewModifier {
    let name: String
    @Environment(\.chromeNotedByCard) private var notedByCard

    func body(content: Content) -> some View {
        content.background(GeometryReader { proxy in
            let _ = notedByCard ? () : ChromeLedger.note(name, proxy.frame(in: .global))
            Color.clear
        })
    }
}

extension View {
    /// Notes where this piece of the interface lies, for the budget the
    /// world's share of the screen is held to.
    func chrome(_ name: String) -> some View {
        modifier(ChromeNote(name: name))
    }
}

/// How much of the window's height a card or panel may take: the world is
/// the screen, the interface a little of its edges.
enum ChromeBudget {
    /// But never less than this, so a small window's panels still serve.
    static let leastHeight: CGFloat = 360
    /// The share of the window the world keeps, on every screen.
    static let worldShare: Double = 0.85
}

extension View {
    func panelBackground() -> some View {
        modifier(PanelBackground())
    }
}

/// A quiet text button: spaced capitals that brighten on hover.
struct QuietButton: View {
    let title: String
    var size: CGFloat = 10
    var prominent = false
    var enabled = true
    /// A colour for the words, for a button that asks twice.
    var tint: Color?
    /// Whether a listening test may press it; a button that asks twice is
    /// pressed by its own action instead.
    var pressable = true
    /// What VoiceOver and Voice Control call it, where the words shown lean
    /// on what stands beside them: "Build II" in the row of the Walls is
    /// "Build Walls II".
    var name: String?
    /// Why it can't be pressed now, said with it while it can't.
    var why: String?
    let action: () -> Void

    /// The least a button is, either way, so it is easy to hit.
    static let least: CGFloat = 24

    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        let _ = pressable ? PressableButtons.note(title, enabled: enabled, action) : ()
        Button(action: action) {
            Caps(title, size: size, weight: prominent ? .medium : .regular)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(enabled ? (tint ?? Palette.text(hovering || prominent ? 1 : 0.72)) : (tint ?? Palette.ink).opacity(0.3))
                .padding(.horizontal, prominent ? 16 : 8)
                .padding(.vertical, prominent ? 9 : 5)
                .frame(minWidth: Self.least, minHeight: Self.least)
                .background(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Palette.glow.opacity(prominent ? (hovering ? 0.22 : 0.14) : (hovering && enabled ? 0.08 : 0)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(Palette.line(prominent ? 0.35 : 0), lineWidth: 1)
                )
                .overlay(FocusRing(isFocused: focused))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focused)
        .disabled(!enabled)
        .onPointer { hovering = $0 }
        .accessibilityLabel(name ?? title)
        .accessibilityHint(enabled ? "" : why ?? "")
    }
}

/// The ring a control with the keyboard wears, as the plain button style
/// leaves none: for those who move by Tab rather than pointer.
struct FocusRing: View {
    let isFocused: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .strokeBorder(Palette.glow, lineWidth: 1.5)
            .padding(-2)
            .opacity(isFocused ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// A small drawn mark for each resource, in the colour the realm gives it:
/// a sheaf of grain, a fir of the blackwood for timber, a dressed block of
/// stone and a crystal of moonsalt, each lit from above and the left, so
/// each is told by its shape as well as its colour at the size of a word.
struct ResourceGlyph: View {
    let resource: Resource
    var size: CGFloat = 10

    var body: some View {
        DrawnMark(parts: ResourceGlyph.drawing(of: resource), size: size)
    }

    typealias Shade = StoreMarks.Shade

    /// Each resource's colour, as its stores, gains and costs are marked
    /// (`StoreMarks`, which the phone draws from too).
    static func colour(of resource: Resource) -> Shade { StoreMarks.colour(of: resource) }

    /// A resource's mark as filled outlines in a unit square, y down, each
    /// drawn over those before it, with its shade of the resource's colour:
    /// the marks the phone draws, as the rules keep them (`StoreMarks`).
    static func drawing(of resource: Resource) -> [(outline: [CGPoint], colour: Shade)] {
        StoreMarks.drawing(of: resource).map { part in (outline: part.outline.map { CGPoint(x: $0.x, y: $0.y) }, colour: part.colour) }
    }
}

/// Filled outlines in a unit square drawn at `size` points, each in its
/// shade: the store and item marks.
private struct DrawnMark: View {
    let parts: [(outline: [CGPoint], colour: ResourceGlyph.Shade)]
    let size: CGFloat

    var body: some View {
        Canvas { context, canvas in
            for part in parts {
                var path = Path()
                path.addLines(part.outline.map { CGPoint(x: $0.x * canvas.width, y: $0.y * canvas.height) })
                path.closeSubpath()
                context.fill(path, with: .color(Color(red: part.colour.red, green: part.colour.green, blue: part.colour.blue)))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

