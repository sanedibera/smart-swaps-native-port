import SwiftUI
import SmartSwapsKit

/// Port of `components/LiquidSlider.tsx` (72 ln). `@react-native-community/slider` -> SwiftUI
/// `Slider`; thumb tint white (iOS), track `primaryGreen`/`border`, `step: 1`, label reads
/// `"{max}+ {unit}"` once the value reaches the max.
struct LiquidSlider: View {
    var maxSliderVal: Double
    var initialValue: Double
    var title: String
    var unit: String = ""
    var onValueChangeComplete: (Double) -> Void

    @State private var value: Double

    init(maxSliderVal: Double, initialValue: Double, title: String, unit: String = "",
         onValueChangeComplete: @escaping (Double) -> Void) {
        self.maxSliderVal = maxSliderVal
        self.initialValue = initialValue
        self.title = title
        self.unit = unit
        self.onValueChangeComplete = onValueChangeComplete
        _value = State(initialValue: initialValue)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(Colors.textMuted)
                Spacer()
                Text(value >= maxSliderVal ? "\(Int(maxSliderVal))+ \(unit)" : "\(Int(value)) \(unit)")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundColor(Colors.primaryGreen)
            }
            .padding(.top, 8)
            .padding(.bottom, 10)

            Slider(
                value: $value,
                in: 0...maxSliderVal,
                step: 1,
                onEditingChanged: { editing in
                    if !editing { onValueChangeComplete(value) }
                }
            )
            .tint(Colors.primaryGreen)

            HStack {
                Text("0").font(.system(size: 11, weight: .medium)).foregroundColor(Colors.textSecondary)
                Spacer()
                Text("\(JSNumber.roundToInt(maxSliderVal / 2))")
                    .font(.system(size: 11, weight: .medium)).foregroundColor(Colors.textSecondary)
                Spacer()
                Text("\(Int(maxSliderVal))+")
                    .font(.system(size: 11, weight: .medium)).foregroundColor(Colors.textSecondary)
            }
            .padding(.top, -4)
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 12)
    }
}

#Preview {
    LiquidSlider(maxSliderVal: 1500, initialValue: 1500, title: "Max Calories per serving", unit: "kcal") { _ in }
        .padding()
}
