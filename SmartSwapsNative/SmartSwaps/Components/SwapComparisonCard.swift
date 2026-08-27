import SwiftUI
import SmartSwapsKit

/// Port of `components/SwapComparisonCard.tsx` (408 ln). `isFavorite`/`toggleFavorite` from
/// `FavoritesStore`, `findRecipesForFood` from `RecipeStore`, both `@EnvironmentObject` —
/// same reasoning as `RecipeCard.swift`. `LayoutAnimation.easeInEaseOut` on expand/collapse
/// becomes a plain SwiftUI `withAnimation(.easeInOut)`.
struct SwapComparisonCard: View {
    var fromFood: FoodItem
    var toFood: FoodItem
    var improvement: Int
    var onPressFrom: (() -> Void)? = nil
    var onPressTo: (() -> Void)? = nil

    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var recipeStore: RecipeStore
    @State private var expanded = false

    private var swapId: String { "\(fromFood.id)-\(toFood.id)" }
    private var isFav: Bool { favorites.isFavorite(.swap, swapId) }
    private var linkedRecipes: [Recipe] { Array(recipeStore.findRecipesForFood(fromFood.id).prefix(2)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            badgesRow
            headerComparison
            Rectangle().fill(Colors.border).frame(height: 0.5).padding(.vertical, 16)
            toggleRow
            if expanded { expandedContent }
        }
        .padding(20)
        .background(Colors.cardBackground)
        .cornerRadius(24)
        .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 4)
    }

    private var badgesRow: some View {
        HStack {
            HStack(spacing: 8) {
                Text("FEATURED").font(.system(size: 10, weight: .heavy)).tracking(0.5)
                    .foregroundColor(Colors.primaryGreenDark)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color(hex: 0xEBF5ED)).cornerRadius(6)
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right").font(.system(size: 14)).foregroundColor(Colors.primaryGreen)
                    Text("+\(improvement) pt Better Score").font(.system(size: 13, weight: .bold)).foregroundColor(Colors.primaryGreen)
                }
            }
            Spacer()
            Button(action: { favorites.toggleFavorite(.swap, swapId) }) {
                Image(systemName: isFav ? "heart.fill" : "heart").font(.system(size: 22))
                    .foregroundColor(isFav ? Color(hex: 0xFF3B30) : Colors.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 16)
    }

    private var headerComparison: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(fromFood.name).font(.system(size: 16, weight: .heavy)).foregroundColor(Colors.textPrimary)
                    .lineLimit(2).frame(minHeight: 40, alignment: .top)
                Text("\(JSNumber.roundToInt(fromFood.health_score)) pt").font(.system(size: 12, weight: .heavy)).foregroundColor(Color(hex: 0xD97706))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color(hex: 0xFEF3C7)).cornerRadius(6)
                Text("\(JSNumber.roundToInt(fromFood.nutrients_per_100.kcal)) kcal").font(.system(size: 13)).foregroundColor(Colors.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onTapGesture { onPressFrom?() }

            Circle().stroke(Colors.primaryGreen, lineWidth: 1).background(Circle().fill(Colors.white))
                .frame(width: 32, height: 32)
                .overlay(Image(systemName: "arrow.right").font(.system(size: 16)).foregroundColor(Colors.primaryGreen))

            VStack(alignment: .trailing, spacing: 4) {
                Text(toFood.name).font(.system(size: 16, weight: .heavy)).foregroundColor(Colors.textPrimary)
                    .lineLimit(2).multilineTextAlignment(.trailing).frame(minHeight: 40, alignment: .top)
                Text("\(JSNumber.roundToInt(toFood.health_score)) pt").font(.system(size: 12, weight: .heavy)).foregroundColor(Colors.primaryGreen)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Colors.lightGreenBg).cornerRadius(6)
                Text("\(JSNumber.roundToInt(toFood.nutrients_per_100.kcal)) kcal").font(.system(size: 13)).foregroundColor(Colors.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .onTapGesture { onPressTo?() }
        }
    }

    private var toggleRow: some View {
        Button(action: { withAnimation(.easeInOut) { expanded.toggle() } }) {
            HStack {
                Text("Click to see side-by-side nutrients").font(.system(size: 14, weight: .medium)).foregroundColor(Colors.textSecondary)
                Spacer()
                Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 16)).foregroundColor(Colors.primaryGreen)
            }
        }
        .buttonStyle(.plain)
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SIDE-BY-SIDE NUTRITION PROFILE (% DV)")
                .font(.system(size: 12, weight: .heavy)).tracking(0.5).foregroundColor(Colors.textMuted)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 16)

            let n1 = fromFood.nutrients_per_100
            let n2 = toFood.nutrients_per_100
            comparisonRow("Calories", Double(JSNumber.roundToInt(n1.kcal)), Double(JSNumber.roundToInt(n2.kcal)), true)
            comparisonRow("Protein (g)", n1.protein_g, n2.protein_g, false)
            comparisonRow("Carbs (g)", n1.carbs_g, n2.carbs_g, true)
            comparisonRow("Sugars (g)", n1.sugars_g, n2.sugars_g, true)
            comparisonRow("Fat (g)", n1.fat_g, n2.fat_g, true)
            comparisonRow("Saturated Fat (g)", n1.saturated_fat_g, n2.saturated_fat_g, true)
            comparisonRow("Fiber (g)", n1.fiber_g, n2.fiber_g, false)
            comparisonRow("Salt (g)", n1.salt_g, n2.salt_g, true)

            recipesSection
        }
        .padding(16)
        .background(Colors.background)
        .cornerRadius(16)
        .padding(.top, 20)
    }

    private func fmt(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) != 0 ? String(format: "%.1f", v) : String(Int(v))
    }

    private func comparisonRow(_ label: String, _ fromVal: Double, _ toVal: Double, _ isLowerBetter: Bool) -> some View {
        let maxVal = max(fromVal, toVal, 1)
        let fromPct = fromVal / maxVal
        let toPct = toVal / maxVal
        let isFromBetter = isLowerBetter ? fromVal <= toVal : fromVal >= toVal
        let isToBetter = isLowerBetter ? toVal <= fromVal : toVal >= fromVal
        let fromColor = isFromBetter ? Colors.scoreGreen : Color(hex: 0xFF9500)
        let toColor = isToBetter ? Colors.scoreGreen : Color(hex: 0xFF9500)

        return VStack(spacing: 4) {
            HStack(alignment: .lastTextBaseline) {
                Text(label).font(.system(size: 14, weight: .semibold)).foregroundColor(Colors.textSecondary)
                Spacer()
                Text(fmt(fromVal)).font(.system(size: 14, weight: .heavy)).foregroundColor(fromColor).frame(width: 40, alignment: .trailing)
                Text(fmt(toVal)).font(.system(size: 14, weight: .heavy)).foregroundColor(toColor).frame(width: 40, alignment: .trailing)
            }
            HStack(spacing: 8) {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 4).fill(fromColor).frame(width: geo.size.width * fromPct, height: 8)
                    }
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: 0xE6EAE5)))
                }
                .frame(height: 8)
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 4).fill(toColor).frame(width: geo.size.width * toPct, height: 8)
                        Spacer(minLength: 0)
                    }
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: 0xE6EAE5)))
                }
                .frame(height: 8)
            }
        }
        .padding(.bottom, 12)
    }

    private var recipesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle().fill(Colors.border).frame(height: 0.5)
            Text("Where to use this swap:").font(.system(size: 14, weight: .bold)).foregroundColor(Colors.textPrimary)

            if linkedRecipes.isEmpty {
                Text("No linked recipes found for \(fromFood.name)")
                    .font(.system(size: 12)).italic().foregroundColor(Colors.textMuted)
            } else {
                HStack {
                    ForEach(linkedRecipes) { recipe in
                        VStack(spacing: 8) {
                            Circle().fill(Color(hex: 0xEBEBEB)).frame(width: 60, height: 60)
                                .overlay(Image(systemName: "fork.knife").font(.system(size: 20)).foregroundColor(Colors.primaryGreen))
                            Text(recipe.name).font(.system(size: 12, weight: .semibold)).foregroundColor(Colors.textPrimary)
                                .multilineTextAlignment(.center).lineLimit(2)
                            Text(recipe.subcategory).font(.system(size: 10, weight: .semibold)).foregroundColor(Colors.primaryGreen)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(Colors.cardBackground)
                        .cornerRadius(12)
                    }
                }
            }
        }
        .padding(.top, 24)
    }
}

#Preview {
    let from = FoodItem(id: "a", name: "White Bread", name_de: nil, category: "Grain",
                         swiss_category: "grain/bread", health_score: 42, nutri_grade: "D",
                         nova_group: 4, swap_suggestion_id: nil, icon_key: nil,
                         nutrients_per_100: FoodNutrients())
    let to = FoodItem(id: "b", name: "Whole Wheat Bread", name_de: nil, category: "Grain",
                       swiss_category: "grain/bread", health_score: 74, nutri_grade: "B",
                       nova_group: 3, swap_suggestion_id: nil, icon_key: nil,
                       nutrients_per_100: FoodNutrients())
    return SwapComparisonCard(fromFood: from, toFood: to, improvement: 32)
        .padding()
        .environmentObject(FavoritesStore())
        .environmentObject(RecipeStore.shared)
}
