import SwiftUI

/// The rebuilt realm's screens are written in three sizes of type and
/// three levels of emphasis, on one surface (`panelBackground`); nothing
/// on them is sized or weighted otherwise (`LiveTokensTests` holds them
/// to it). Colours that say something, a refusal's red or a timer's
/// glow, are not emphasis and keep their own.
enum LiveType {
    /// Small words under a line: what something costs, or why not; and
    /// the small capitals of a heading.
    static let small: CGFloat = 11
    /// What most lines say.
    static let body: CGFloat = 12
    /// A title: what a card or a list is of.
    static let title: CGFloat = 14
}

/// How strongly words stand out.
enum LiveEmphasis {
    /// What is read first: names, titles, what is happening.
    static var primary: Color { Palette.ink }
    /// What is read next: details, how far along, what it gives.
    static var secondary: Color { Palette.text(0.72) }
    /// What is read last: what is past, or not yet.
    static var tertiary: Color { Palette.text(0.55) }
}
