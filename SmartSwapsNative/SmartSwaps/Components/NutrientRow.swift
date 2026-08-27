import SwiftUI
import SmartSwapsKit

/// Port of `components/NutrientRow.tsx` (81 ln).
func nutriBarColor(_ pct: Double, isLowerBetter: Bool) -> Color {
    if isLowerBetter {
        if pct <= 40 { return Colors.scoreGreen }
        if pct <= 70 { return Colors.Local.nutrientAmber }
        return Colors.scoreRed
    } else {
        if pct >= 65 { return Colors.scoreGreen }
        if pct >= 35 { return Colors.Local.nutrientAmber }
        return Colors.scoreRed
    }
}

private func nutrientPct(_ value: Double, _ target: Double) -> Int {
    if target == 0 { return 0 }
    return min(100, JSNumber.roundToInt(value / target * 100))
}

private func fmt(_ value: Double, decimals: Int = 1) -> String {
    value.truncatingRemainder(dividingBy: 1) != 0
        ? String(format: "%.\(decimals)f", value)
        : String(JSNumber.roundToInt(value))
}

struct NutrientRow: View {
    var label: String
    var value: Double
    var target: Double
    var unit: String
    var isLowerBetter: Bool

    private var pct: Int { nutrientPct(value, target) }
    private var barColor: Color { nutriBarColor(Double(pct), isLowerBetter: isLowerBetter) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Colors.textPrimary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(fmt(value)) \(unit)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Colors.textPrimary)
                    Text("\(pct)% of target")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(barColor)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Colors.border)
                    RoundedRectangle(cornerRadius: 3).fill(barColor)
                        .frame(width: geo.size.width * CGFloat(pct) / 100)
                }
            }
            .frame(height: 6)
            .padding(.top, 6)
        }
        .padding(.bottom, 12)
    }
}

#Preview {
    VStack {
        NutrientRow(label: "Protein", value: 45.3, target: 90, unit: "g", isLowerBetter: false)
        NutrientRow(label: "Saturated Fat", value: 18, target: 20, unit: "g", isLowerBetter: true)
    }
    .padding()
}
