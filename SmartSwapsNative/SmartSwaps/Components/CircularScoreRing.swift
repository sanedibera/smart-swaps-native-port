import SwiftUI
import SmartSwapsKit

/// Port of `components/CircularScoreRing.tsx` (78 ln). An SVG ring in the source; SwiftUI's
/// `Circle().trim()` reproduces the same stroke-dasharray/-dashoffset math directly.
struct CircularScoreRing: View {
    var percentage: Double
    var size: CGFloat = 40
    var strokeWidth: CGFloat = 4

    private var safePercentage: Double { min(max(percentage, 0), 100) }

    private var color: Color {
        if safePercentage >= 70 { return Colors.scoreGreen }
        if safePercentage >= 40 { return Colors.scoreYellow }
        return Colors.scoreRed
    }

    private var lightColor: Color {
        if safePercentage >= 70 { return Colors.scoreGreenLight }
        if safePercentage >= 40 { return Colors.scoreYellowLight }
        return Colors.scoreRedLight
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(lightColor, lineWidth: strokeWidth)
            Circle()
                .trim(from: 0, to: safePercentage / 100)
                .stroke(color, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(JSNumber.roundToInt(safePercentage))")
                .font(.system(size: size * 0.35, weight: .bold))
                .foregroundColor(color)
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    HStack(spacing: 20) {
        CircularScoreRing(percentage: 85, size: 90, strokeWidth: 10)
        CircularScoreRing(percentage: 55, size: 60, strokeWidth: 6)
        CircularScoreRing(percentage: 20, size: 40, strokeWidth: 4)
    }
    .padding()
}
