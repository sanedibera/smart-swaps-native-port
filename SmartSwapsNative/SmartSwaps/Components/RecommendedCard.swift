import SwiftUI
import SmartSwapsKit

/// Port of `components/RecommendedCard.tsx` (115 ln). Imported by `(tabs)/index.tsx` but
/// never rendered there (PORTING_INVENTORY.md §9) - ported per the brief anyway, unreferenced
/// same as the source, until Phase 5 wires the Home screen up.
struct RecommendedCard: View {
    var title: String
    var score: Int
    var calories: String
    var iconName: String = "leaf"
    var onPress: (() -> Void)? = nil

    private var scoreColor: Color {
        if score >= 75 { return Colors.scoreGreen }
        if score >= 50 { return Colors.scoreYellow }
        return Colors.scoreRed
    }

    var body: some View {
        Button(action: { onPress?() }) {
            VStack(spacing: 0) {
                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .stroke(scoreColor, lineWidth: 4)
                        .background(Circle().fill(Colors.cardBackground))
                        .frame(width: 54, height: 54)
                        .overlay(
                            Text("\(score)")
                                .font(.system(size: 16, weight: .heavy))
                                .foregroundColor(scoreColor)
                        )
                    Circle()
                        .fill(Colors.lightGreenBg)
                        .frame(width: 20, height: 20)
                        .overlay(Circle().stroke(Colors.white, lineWidth: 1.5))
                        .overlay(Image(systemName: iconName).font(.system(size: 10)).foregroundColor(Colors.primaryGreen))
                        .offset(x: 2, y: 2)
                }
                .padding(.bottom, 10)

                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.bottom, 2)

                Text(calories)
                    .font(.system(size: 11))
                    .foregroundColor(Colors.textMuted)
                    .lineLimit(1)
            }
            .padding(14)
            .frame(width: 135)
            .background(Colors.cardBackground)
            .cornerRadius(20)
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Colors.border, lineWidth: 1))
            .shadow(color: Colors.shadowColor.opacity(0.03), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 6)
    }
}

#Preview {
    HStack {
        RecommendedCard(title: "Greek Yogurt", score: 88, calories: "120 kcal", iconName: "leaf")
        RecommendedCard(title: "Whole Wheat Bread", score: 62, calories: "245 kcal", iconName: "nutrition")
    }
    .padding()
}
