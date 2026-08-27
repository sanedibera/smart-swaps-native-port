import SwiftUI
import SmartSwapsKit

/// Port of `components/HealthPointsCard.tsx` (94 ln).
struct HealthPointsCard: View {
    var percentage: Double
    var onScanPress: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 20) {
            CircularScoreRing(percentage: percentage, size: 90, strokeWidth: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text("THIS WEEK")
                    .font(.system(size: 11, weight: .bold)).tracking(0.8)
                    .foregroundColor(Colors.primaryGreen)
                Text("Health Points")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundColor(Colors.textPrimary)
                Text("Scan a receipt to start earning points")
                    .font(.system(size: 13))
                    .foregroundColor(Colors.textSecondary)
                    .lineSpacing(3)
                    .padding(.bottom, 8)

                Button(action: { onScanPress?() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.fill").font(.system(size: 14))
                        Text("Scan a receipt").font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(Colors.white)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .background(Colors.primaryGreen)
                    .cornerRadius(12)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(Colors.cardBackground)
        .cornerRadius(24)
    }
}

#Preview {
    HealthPointsCard(percentage: 68, onScanPress: {})
        .padding()
}
