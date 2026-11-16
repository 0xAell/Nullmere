import Foundation

/// The symbols the realm's screens draw beside their words, by the
/// module's own numbers: SF Symbols' names, so the Mac draws them as it
/// draws its own.
public enum LiveIcons {
    /// Each kind of building, as the module numbers them (1 the Keep to 19
    /// the Forge); a plain building for any other.
    public static func building(_ kind: Int) -> String {
        let all = [
            1: "building.columns.fill", 2: "leaf.fill", 3: "tree.fill", 4: "mountain.2.fill", 5: "drop.fill", 6: "shippingbox.fill",
            7: "shield.fill", 8: "scope", 9: "hare.fill", 10: "hammer.fill", 11: "cross.case.fill", 12: "square.stack.3d.up.fill",
            13: "binoculars.fill", 14: "book.fill", 15: "flag.fill", 16: "mug.fill", 17: "cart.fill", 18: "eye.fill", 19: "flame.fill",
        ]
        return all[kind] ?? "building.2.fill"
    }

    /// Each kind of soldier (1 spearmen, 2 archers, 3 riders, 4 mangonels):
    /// the symbol of the building that trains them.
    public static func troop(_ kind: Int) -> String {
        building([1: 7, 2: 8, 3: 9, 4: 10][kind] ?? 0)
    }
}
