import SwiftUI

/// Ported verbatim from `styles.ts` → `COLORS`. Exact hex values, no palette
/// normalisation — keep new colors here rather than deriving from these.
enum Colors {
    // Backgrounds
    static let background = Color(hex: 0xFFFFFF)
    static let cardBackground = Color(hex: 0xF7F9F6)
    static let inputBackground = Color(hex: 0xF0F3F0)

    // Brand
    static let primaryGreen = Color(hex: 0x3B964E)
    static let primaryGreenDark = Color(hex: 0x286635)
    static let lightGreenBg = Color(hex: 0xEBF5ED)

    // Neutral
    static let textPrimary = Color(hex: 0x1E221F)
    static let textSecondary = Color(hex: 0x606A62)
    static let textMuted = Color(hex: 0x8C968E)
    static let border = Color(hex: 0xE6EAE5)
    static let borderDark = Color(hex: 0xD1D7CE)

    // Semantic / score
    static let scoreGreen = Color(hex: 0x3B964E)
    static let scoreGreenLight = Color(hex: 0xE8F5E9)
    static let scoreYellow = Color(hex: 0xD97706)
    static let scoreYellowLight = Color(hex: 0xFEF3C7)
    static let scoreRed = Color(hex: 0xDC2626)
    static let scoreRedLight = Color(hex: 0xFEE2E2)

    // Misc
    static let shadowColor = Color(hex: 0x0F1D11)
    static let white = Color(hex: 0xFFFFFF)

    // System (iOS-like defaults, RN's hardcoded copies — not UIColor.system*)
    static let systemBlue = Color(hex: 0x007AFF)
    static let systemOrange = Color(hex: 0xFF9500)
    static let systemRed = Color(hex: 0xFF3B30)
    static let systemPink = Color(hex: 0xFF2D55)
    static let systemPurple = Color(hex: 0xAF52DE)
    static let systemIndigo = Color(hex: 0x5856D6)
    static let systemTeal = Color(hex: 0x00C7BE)
    static let systemGreen = Color(hex: 0x34C759)
    static let systemGray = Color(hex: 0x8E8E93)
    static let systemGrayLight = Color(hex: 0xEFEFF4)
    static let systemGray2 = Color(hex: 0xC6C6C8)

    // Macro colors
    static let macroCarbs = Color(hex: 0xFF9500)
    static let macroSugars = Color(hex: 0xFFCC00)
    static let macroFat = Color(hex: 0xFF2D55)
    static let macroSatFat = Color(hex: 0xFF9F0A)
    static let macroProtein = Color(hex: 0x32ADE6)
    static let macroFiber = Color(hex: 0x34C759)
    static let macroSalt = Color(hex: 0x8E8E93)

    /// One-off colors used inline in screens/components, never added to RN's
    /// `COLORS` object either — kept separate per PORTING_INVENTORY.md §1 so a
    /// reader can tell "named palette" from "screen literal" apart, same as the source.
    enum Local {
        // Shopping-list blue family
        static let shoppingBg = Color(hex: 0xF0FAFF)
        static let shoppingChip = Color(hex: 0xD0EFFF)
        static let shoppingBorder = Color(hex: 0xBFE7FF)
        static let shoppingBlue = Color(hex: 0x0084C9)
        static let shoppingBlueDark = Color(hex: 0x005480)
        static let shoppingBlueDarker = Color(hex: 0x006599)
        static let shoppingAltBg = Color(hex: 0xF0F8FF)
        static let shoppingAltChip = Color(hex: 0xB3E0FF)

        // Amber score family (SearchScreen / food/[id])
        static let amber = Color(hex: 0xF5A623)
        static let amberBg = Color(hex: 0xFFF8E1)
        static let redBg = Color(hex: 0xFFEBEE)
        static let nutrientAmber = Color(hex: 0xF59E0B)

        // RecipeCard subcategory palette
        static let subcatAmberBg = Color(hex: 0xFEF3C7)
        static let subcatAmber = Color(hex: 0xD97706)
        static let subcatOrangeBg = Color(hex: 0xFFF3E0)
        static let subcatOrange = Color(hex: 0xF57C00)
        static let subcatPurpleBg = Color(hex: 0xEDE7F6)
        static let subcatPurple = Color(hex: 0x6D28D9)
        static let subcatPinkBg = Color(hex: 0xFCE4EC)
        static let subcatPink = Color(hex: 0xC2185B)
        static let subcatYellow = Color(hex: 0xF9A825)

        // Screen backgrounds
        static let screenBg1 = Color(hex: 0xF7F9F7)
        static let screenBg2 = Color(hex: 0xF9FAF9)
        static let screenBg3 = Color(hex: 0xFAFAFA)
    }
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
