import SwiftUI
import SmartSwapsKit

/// Port of `components/SpotlightCard.tsx` (157 ln).
struct SpotlightCard: View {
    var title: String
    var score: Int
    var categoryLabel: String
    var iconName: String
    var calories: String
    var protein: String
    var carbs: String
    var fat: String
    var isHighlighted: Bool = false

    private var caloriesFirstWord: String { String(calories.split(separator: " ").first ?? "") }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: iconName).font(.system(size: 14)).foregroundColor(Colors.primaryGreen)
                Text(categoryLabel.uppercased())
                    .font(.system(size: 11, weight: .bold)).tracking(0.8)
                    .foregroundColor(Colors.primaryGreen)
            }
            .padding(.bottom, 12)

            HStack(alignment: .center) {
                Text(title)
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundColor(Colors.textPrimary)
                    .padding(.trailing, 10)
                Spacer()
                ZStack {
                    Circle().stroke(Colors.primaryGreen, lineWidth: 4)
                    Text("\(score)").font(.system(size: 20, weight: .heavy)).foregroundColor(Colors.primaryGreen)
                }
                .frame(width: 56, height: 56)
            }
            .padding(.bottom, 20)

            HStack(spacing: 0) {
                macroBlock(caloriesFirstWord, "Calories")
                divider
                macroBlock(protein, "Protein")
                divider
                macroBlock(carbs, "Carbs")
                divider
                macroBlock(fat, "Fat")
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(isHighlighted ? Colors.cardBackground : Colors.inputBackground)
            .cornerRadius(16)
        }
        .padding(20)
        .background(isHighlighted ? Color(hex: 0xEBF3EC) : Colors.cardBackground)
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(isHighlighted ? Color(hex: 0xD4E5D8) : .clear, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 6)
        .padding(.bottom, 6)
    }

    private var divider: some View {
        Rectangle().fill(Colors.borderDark).frame(width: 1)
    }

    private func macroBlock(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 14, weight: .bold)).foregroundColor(Colors.textPrimary)
            Text(label).font(.system(size: 11)).foregroundColor(Colors.textMuted)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    SpotlightCard(title: "Grilled Salmon", score: 91, categoryLabel: "Today's Pick",
                  iconName: "star.fill", calories: "412 kcal", protein: "38g", carbs: "12g",
                  fat: "22g", isHighlighted: true)
        .padding()
}
