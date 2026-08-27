import SwiftUI

// RN fontWeight -> SwiftUI Font.Weight, per the standard numeric scale
// (400 regular, 500 medium, 600 semibold, 700 bold, 800 heavy).
//
// Font: styles.ts pairs these with `fontFamily: "Nunito_500Medium"` on the tab
// bar only, via expo-font. PORTING_INVENTORY.md §1 (⚠ FLAG 1) found no font
// file bundled and no `useFonts()` call anywhere in app/ or components/, so on
// the running app that string resolves to nothing and every text node,
// including the tab bar, renders in San Francisco. Per rule 1 of the brief
// ("when the RN code and this brief disagree, the RN code wins") this port
// uses the system font throughout — recorded as a decided deviation in
// PORTING_NOTES.md ("SF Pro, not Nunito"), not an open question.
enum Typography {
    static func title() -> Font { .system(size: 32, weight: .heavy) }
    static func sectionTitle() -> Font { .system(size: 20, weight: .bold) }
    static func subtitle() -> Font { .system(size: 14, weight: .regular) }
    static func bodyText() -> Font { .system(size: 14, weight: .regular) }
    static func badgeText() -> Font { .system(size: 13, weight: .semibold) }
    static func buttonText() -> Font { .system(size: 16, weight: .semibold) }
    /// Tab bar label — `tabBarLabelStyle.fontSize` in (tabs)/_layout.tsx.
    static func tabLabel() -> Font { .system(size: 10, weight: .medium) }
}

private struct TitleStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.font(Typography.title()).tracking(-0.5).foregroundColor(Colors.textPrimary)
    }
}

private struct SectionTitleStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.font(Typography.sectionTitle()).foregroundColor(Colors.textPrimary)
    }
}

private struct SubtitleStyle: ViewModifier {
    func body(content: Content) -> some View {
        // lineHeight 20 at fontSize 14 -> +6pt line spacing, RN's convention of
        // extra leading rather than a total line box.
        content.font(Typography.subtitle()).foregroundColor(Colors.textSecondary).lineSpacing(6)
    }
}

private struct BodyTextStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.font(Typography.bodyText()).foregroundColor(Colors.textSecondary).lineSpacing(6)
    }
}

extension View {
    func titleText() -> some View { modifier(TitleStyle()) }
    func sectionTitleText() -> some View { modifier(SectionTitleStyle()) }
    func subtitleText() -> some View { modifier(SubtitleStyle()) }
    func bodyText() -> some View { modifier(BodyTextStyle()) }
}
