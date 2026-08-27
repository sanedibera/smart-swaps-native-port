import SwiftUI

/// Ported from `styles.ts` → `globalStyles`. Values are the iOS branch of each
/// `Platform.select` (shadow, not elevation/boxShadow).
private struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .background(Colors.white)
            .cornerRadius(24)
            .shadow(color: Colors.shadowColor.opacity(0.04), radius: 12, x: 0, y: 6)
    }
}

/// `scrollContent`: horizontal 20, top 10, bottom 100 (clears the tab bar).
private struct ScrollContentStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 100)
    }
}

private struct BadgeStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .clipShape(Capsule())
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.buttonText())
            .foregroundColor(Colors.white)
            .padding(.vertical, 14)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .background(Colors.primaryGreen)
            .cornerRadius(14)
            .padding(.top, 12)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.buttonText())
            .foregroundColor(Colors.textPrimary)
            .padding(.vertical, 14)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .background(Colors.cardBackground)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Colors.border, lineWidth: 1))
            .cornerRadius(14)
            .padding(.top, 12)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

extension View {
    func cardStyle() -> some View { modifier(CardStyle()) }
    func scrollContentStyle() -> some View { modifier(ScrollContentStyle()) }
    func badgeStyle() -> some View { modifier(BadgeStyle()) }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}
