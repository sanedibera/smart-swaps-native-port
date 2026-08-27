import SwiftUI
import SmartSwapsKit

/// Port of `components/NutritionModal.tsx` (405 ln). `useProfile()` -> `ProfileStore` via
/// `@EnvironmentObject`. The RN spring/opacity entrance animation is reproduced with SwiftUI's
/// `.transition`/`.animation` rather than hand-matching friction/tension constants — a
/// spring is a spring, but the two systems don't share units.
struct NutritionModal: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var profileStore: ProfileStore

    @State private var infoAlertTitle: String?
    @State private var infoAlertMessage: String = ""

    private static let macroDescriptions: [String: String] = [
        "Protein": "Protein is essential for building and repairing tissues, including muscle. It also plays a key role in the production of enzymes and hormones.",
        "Carbohydrates": "Carbohydrates are your body's primary energy source. They fuel your brain, kidneys, heart muscles, and central nervous system.",
        "Sugars": "Naturally occurring sugars provide quick energy. However, limiting added sugars is important for heart health and preventing energy crashes.",
        "Total Fat": "Fats provide dense energy, support cell growth, and protect your organs. They also help your body absorb essential fat-soluble vitamins.",
        "Saturated Fat": "While some saturated fat is fine, replacing it with unsaturated fats can help lower cholesterol levels and reduce cardiovascular risks.",
        "Dietary Fiber": "Fiber aids in digestion and helps regulate blood sugar levels. It also contributes to satiety, keeping you feeling full for longer.",
        "Salt": "Salt is necessary for fluid balance and nerve function. However, excess sodium can lead to high blood pressure and strain your heart.",
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()

            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        budgetCard
                        Text("MACRONUTRIENT SPLIT")
                            .font(.system(size: 11, weight: .bold)).tracking(1).foregroundColor(Colors.systemGray)
                            .padding(.bottom, 16)
                        macroRows
                        Text("RECOMMENDED MICRONUTRIENTS")
                            .font(.system(size: 11, weight: .bold)).tracking(1).foregroundColor(Colors.systemGray)
                            .padding(.bottom, 16).padding(.top, 8)
                        microRows
                    }
                    .padding(20)
                }
                footer
            }
            .background(Color.white)
            .cornerRadius(24)
            .frame(maxHeight: UIScreen.main.bounds.height * 0.85)
            .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
            .padding(20)
        }
        .alert(infoAlertTitle ?? "", isPresented: Binding(get: { infoAlertTitle != nil }, set: { if !$0 { infoAlertTitle = nil } })) {
            Button("OK") {}
        } message: {
            Text(infoAlertMessage)
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 12) {
                Circle().fill(Colors.lightGreenBg).frame(width: 40, height: 40)
                    .overlay(Image(systemName: "flame.fill").font(.system(size: 16)).foregroundColor(Colors.primaryGreen))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily Nutrient Guide").font(.system(size: 18, weight: .bold)).foregroundColor(Colors.textPrimary)
                    Text("BASED ON YOUR PROFILE").font(.system(size: 11, weight: .bold)).tracking(0.5).foregroundColor(Colors.systemGray)
                }
            }
            Spacer()
            Button(action: { isPresented = false }) {
                Image(systemName: "xmark").font(.system(size: 20)).foregroundColor(Color(hex: 0x666666))
                    .frame(width: 32, height: 32)
                    .background(Colors.systemGrayLight).clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .overlay(Rectangle().fill(Color(hex: 0xF0F0F0)).frame(height: 1), alignment: .bottom)
    }

    private var budgetCard: some View {
        let p = profileStore.profile
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Daily Budget:").font(.system(size: 15, weight: .medium)).foregroundColor(Colors.textSecondary)
                Spacer()
                Text("\(JSNumber.toLocaleStringDE(Double(profileStore.targetCalories))) kcal")
                    .font(.system(size: 16, weight: .heavy)).foregroundColor(Colors.textPrimary)
            }
            Text("Optimised for: \(p.sex.rawValue), \(p.age) yrs, \(Int(p.weight))kg, \(Int(p.height))cm (\(p.activityLevel.rawValue)) with \"\(p.dietaryPreference.map(\.rawValue).joined(separator: ", "))\" dietary preference.")
                .font(.system(size: 13)).foregroundColor(Colors.textMuted).lineSpacing(4)
        }
        .padding(16)
        .background(Colors.cardBackground)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Colors.border, lineWidth: 1))
        .padding(.bottom, 24)
    }

    private func macroRow(_ color: Color, _ name: String, _ valueG: Int, _ pct: Double?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 8) {
                    Circle().fill(color).frame(width: 8, height: 8)
                    Text(name).font(.system(size: 15, weight: .semibold)).foregroundColor(Colors.textPrimary)
                    Button(action: {
                        infoAlertTitle = name
                        infoAlertMessage = Self.macroDescriptions[name] ?? ""
                    }) {
                        Image(systemName: "info.circle").font(.system(size: 16)).foregroundColor(Colors.systemGray)
                    }.buttonStyle(.plain)
                }
                Spacer()
                if let pct {
                    Text("\(valueG)g (\(JSNumber.roundToInt(pct * 100))%)")
                        .font(.system(size: 15, weight: .bold)).foregroundColor(Colors.textPrimary)
                } else {
                    Text("\(valueG)g").font(.system(size: 15, weight: .bold)).foregroundColor(Colors.textPrimary)
                }
            }
            if let pct {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(Colors.systemGrayLight)
                        RoundedRectangle(cornerRadius: 3).fill(color).frame(width: geo.size.width * CGFloat(min(pct, 1)))
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(.bottom, 16)
    }

    private var macroRows: some View {
        let m = profileStore.targetMacros
        let pct = profileStore.targetMacroPercentages
        return VStack(alignment: .leading, spacing: 0) {
            macroRow(Colors.macroProtein, "Protein", m.protein, pct.protein)
            macroRow(Colors.macroCarbs, "Carbohydrates", m.carbs, pct.carbs)
            macroRow(Colors.macroSugars, "Sugars", m.sugars, pct.sugars)
            macroRow(Colors.macroFat, "Total Fat", m.fat, pct.fat)
            macroRow(Colors.macroSatFat, "Saturated Fat", m.satFat, pct.satFat).padding(.leading, 16)
            macroRow(Colors.macroFiber, "Dietary Fiber", m.fiber, nil)
            macroRow(Colors.macroSalt, "Salt", m.salt, nil)
        }
    }

    private var microRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Micronutrients.getRecommendedMicros(sex: profileStore.profile.sex), id: \.key) { micro in
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        HStack(spacing: 6) {
                            Text(micro.name).font(.system(size: 14, weight: .semibold)).foregroundColor(Colors.textPrimary)
                            Button(action: {
                                infoAlertTitle = micro.name
                                infoAlertMessage = micro.description
                            }) {
                                Image(systemName: "info.circle").font(.system(size: 16)).foregroundColor(Colors.systemGray)
                            }.buttonStyle(.plain)
                        }
                        Spacer()
                        HStack(alignment: .lastTextBaseline, spacing: 3) {
                            Text(fmtMicro(micro.amount)).font(.system(size: 14, weight: .bold)).foregroundColor(Colors.textPrimary)
                            Text(micro.unit).font(.system(size: 12, weight: .semibold)).foregroundColor(Colors.textSecondary)
                        }
                    }
                    Rectangle().fill(Colors.border).frame(height: 1).padding(.top, 12)
                }
                .padding(.bottom, 16)
            }
        }
    }

    private var footer: some View {
        Button(action: { isPresented = false }) {
            Text("Got it!").font(.system(size: 16, weight: .semibold)).foregroundColor(Colors.white)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(Colors.primaryGreen).cornerRadius(14)
        }
        .buttonStyle(.plain)
        .padding(20)
        .overlay(Rectangle().fill(Colors.border).frame(height: 1), alignment: .top)
        .background(Colors.white)
    }

    private func fmtMicro(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.1f", v)
    }
}

#Preview {
    NutritionModal(isPresented: .constant(true))
        .environmentObject(ProfileStore())
}
