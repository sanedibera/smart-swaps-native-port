import SwiftUI
import SmartSwapsKit

private func subcategoryIcon(_ subcategory: String) -> String {
    let s = subcategory.lowercased()
    if s.contains("breakfast") { return "sun.max" }
    if s.contains("lunch") { return "cloud.sun" }
    if s.contains("dinner") || s.contains("supper") { return "moon" }
    if s.contains("snack") { return "cup.and.saucer" }
    if s.contains("dessert") { return "birthday.cake" }
    return "fork.knife"
}

private func subcategoryColors(_ subcategory: String) -> (bg: Color, fg: Color) {
    let s = subcategory.lowercased()
    if s.contains("breakfast") { return (Colors.Local.subcatAmberBg, Colors.Local.subcatAmber) }
    if s.contains("lunch") { return (Colors.Local.subcatOrangeBg, Colors.Local.subcatOrange) }
    if s.contains("dinner") || s.contains("supper") { return (Colors.Local.subcatPurpleBg, Colors.Local.subcatPurple) }
    if s.contains("snack") { return (Colors.Local.amberBg, Colors.Local.subcatYellow) }
    if s.contains("dessert") { return (Colors.Local.subcatPinkBg, Colors.Local.subcatPink) }
    return (Colors.lightGreenBg, Colors.primaryGreen)
}

private func scoreColors(_ score: Int) -> (text: Color, bg: Color) {
    if score >= 75 { return (Colors.scoreGreen, Colors.lightGreenBg) }
    if score >= 50 { return (Colors.scoreYellow, Colors.scoreYellowLight) }
    return (Colors.scoreRed, Colors.scoreRedLight)
}

private func scoreLabel(_ score: Int) -> String {
    if score >= 80 { return "Excellent Health" }
    if score >= 65 { return "Good Health" }
    if score >= 50 { return "Moderate Health" }
    return "Low Health"
}

/// Port of `components/RecipeCard.tsx` (364 ln). `isFavorite`/`toggleFavorite` come from
/// `FavoritesStore` and `ownedFoodIds` from `InventoryStore` via `@EnvironmentObject`,
/// matching the RN version reaching into `useFavorites()`/`useInventory()` internally rather
/// than taking them as props — the prop signature (`recipe`, `onPress`, `variant`) is 1:1.
struct RecipeCard: View {
    var recipe: Recipe
    var onPress: () -> Void
    var variant: Variant = .small

    enum Variant { case large, small }

    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var inventory: InventoryStore

    private var isFav: Bool { favorites.isFavorite(.recipe, recipe.id) }
    private var ownedCount: Int {
        recipe.ingredients.reduce(0) { acc, ing in
            guard let fid = ing.food_id, inventory.ownedFoodIds.contains(fid) else { return acc }
            return acc + 1
        }
    }

    var body: some View {
        Button(action: onPress) {
            if variant == .large { largeCard } else { smallCard }
        }
        .buttonStyle(.plain)
    }

    private var largeCard: some View {
        let icon = subcategoryColors(recipe.subcategory)
        let score = scoreColors(recipe.health_score)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill").font(.system(size: 10)).foregroundColor(Colors.primaryGreen)
                    Text("TODAY'S FEATURED RECIPE").font(.system(size: 9, weight: .bold)).tracking(0.4)
                        .foregroundColor(Colors.primaryGreen)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Colors.lightGreenBg).cornerRadius(8)

                Spacer()

                if ownedCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle").font(.system(size: 12)).foregroundColor(Colors.white)
                        Text("\(ownedCount)/\(recipe.ingredients.count) INGREDIENTS")
                            .font(.system(size: 9, weight: .bold)).tracking(0.4).foregroundColor(Colors.white)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Colors.primaryGreen).cornerRadius(8)
                }
            }
            .padding(.bottom, 14)

            HStack(alignment: .top, spacing: 14) {
                RoundedRectangle(cornerRadius: 16).fill(icon.bg)
                    .frame(width: 60, height: 60)
                    .overlay(Image(systemName: subcategoryIcon(recipe.subcategory)).font(.system(size: 28)).foregroundColor(icon.fg))

                VStack(alignment: .leading, spacing: 3) {
                    Text(recipe.subcategory.uppercased()).font(.system(size: 10, weight: .bold)).tracking(0.3)
                        .foregroundColor(Colors.primaryGreen)
                    Text(recipe.name).font(.system(size: 17, weight: .heavy)).foregroundColor(Colors.textPrimary)
                        .lineLimit(2)
                    Text(recipe.dish_type).font(.system(size: 11)).foregroundColor(Colors.textMuted)
                }

                Spacer(minLength: 0)

                Button(action: { favorites.toggleFavorite(.recipe, recipe.id) }) {
                    Image(systemName: isFav ? "heart.fill" : "heart")
                        .font(.system(size: 20))
                        .foregroundColor(isFav ? Color(hex: 0xFF3B30) : Colors.textMuted)
                }
                .buttonStyle(.plain)
            }

            Rectangle().fill(Colors.border).frame(height: 1).padding(.vertical, 14)

            HStack(alignment: .top) {
                HStack(spacing: 6) {
                    Image(systemName: "clock").font(.system(size: 14)).foregroundColor(Colors.textSecondary)
                    Text(recipe.time ?? "").font(.system(size: 12, weight: .medium)).foregroundColor(Colors.textSecondary)
                    Image(systemName: "speedometer").font(.system(size: 14)).foregroundColor(Colors.textSecondary)
                    Text(recipe.difficulty ?? "").font(.system(size: 12, weight: .medium)).foregroundColor(Colors.textSecondary)
                    Image(systemName: "person.2").font(.system(size: 14)).foregroundColor(Colors.textSecondary)
                    Text("\(recipe.serves) servings").font(.system(size: 12, weight: .medium)).foregroundColor(Colors.textSecondary)
                }
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "rosette").font(.system(size: 11)).foregroundColor(score.text)
                    Text(scoreLabel(recipe.health_score)).font(.system(size: 11, weight: .bold)).foregroundColor(score.text)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(score.bg).cornerRadius(20)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(score.text.opacity(0.19), lineWidth: 1))
            }

            HStack {
                Text("\(JSNumber.roundToInt(recipe.kcal_total)) kcal / serving")
                    .font(.system(size: 12, weight: .medium)).foregroundColor(Colors.textSecondary)
                Spacer()
                HStack(alignment: .lastTextBaseline, spacing: 1) {
                    Text("\(recipe.health_score)").font(.system(size: 16, weight: .heavy)).foregroundColor(score.text)
                    Text("/100").font(.system(size: 11)).foregroundColor(score.text)
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(score.bg).cornerRadius(12)
            }
            .padding(.top, 10)
        }
        .padding(20)
        .background(Colors.white)
        .cornerRadius(24)
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Colors.border, lineWidth: 1))
        .shadow(color: Colors.shadowColor.opacity(0.04), radius: 12, x: 0, y: 6)
        .padding(.bottom, 20)
    }

    private var smallCard: some View {
        let icon = subcategoryColors(recipe.subcategory)
        let score = scoreColors(recipe.health_score)
        return HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 13).fill(icon.bg)
                .frame(width: 46, height: 46)
                .overlay(Image(systemName: subcategoryIcon(recipe.subcategory)).font(.system(size: 18)).foregroundColor(icon.fg))

            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.subcategory.uppercased()).font(.system(size: 10, weight: .bold)).tracking(0.3)
                    .foregroundColor(Colors.primaryGreen)
                Text(recipe.name).font(.system(size: 14, weight: .bold)).foregroundColor(Colors.textPrimary).lineLimit(1)
                HStack(spacing: 3) {
                    Image(systemName: "clock").font(.system(size: 11)).foregroundColor(Colors.textMuted)
                    Text(recipe.time ?? "").font(.system(size: 11)).foregroundColor(Colors.textMuted)
                    Text("·").font(.system(size: 11)).foregroundColor(Colors.textMuted)
                    Image(systemName: "speedometer").font(.system(size: 11)).foregroundColor(Colors.textMuted)
                    Text(recipe.difficulty ?? "").font(.system(size: 11)).foregroundColor(Colors.textMuted)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 8) {
                    if ownedCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle").font(.system(size: 10)).foregroundColor(Colors.white)
                            Text("\(ownedCount)/\(recipe.ingredients.count)").font(.system(size: 8, weight: .bold)).foregroundColor(Colors.white)
                        }
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Colors.primaryGreen).cornerRadius(8)
                    }
                    Button(action: { favorites.toggleFavorite(.recipe, recipe.id) }) {
                        Image(systemName: isFav ? "heart.fill" : "heart")
                            .font(.system(size: 17))
                            .foregroundColor(isFav ? Color(hex: 0xFF3B30) : Colors.textMuted)
                    }
                    .buttonStyle(.plain)
                }
                Text("\(recipe.health_score)").font(.system(size: 12, weight: .bold)).foregroundColor(score.text)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(score.bg).cornerRadius(8)
            }
        }
        .padding(14)
        .background(Colors.white)
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Colors.border, lineWidth: 1))
        .shadow(color: Colors.shadowColor.opacity(0.03), radius: 6, x: 0, y: 2)
        .padding(.bottom, 10)
    }
}

#Preview {
    let food = FoodItem(id: "f1", name: "Chicken Breast", name_de: nil, category: "Meat",
                         swiss_category: "meat/poultry", health_score: 82, nutri_grade: "B",
                         nova_group: 1, swap_suggestion_id: nil, icon_key: nil,
                         nutrients_per_100: FoodNutrients())
    let recipe = Recipe(id: "r1", name: "Grilled Chicken Bowl", url: "", image: nil, serves: 2,
                         subcategory: "Dinner", dish_type: "Bowl",
                         ingredients: [RecipeIngredient(raw_text: "200g chicken", food_id: "f1", food: food, grams: 200, kcal: 330, nutrients: nil)],
                         steps: [], totals: FoodNutrients(), health_score: 78, kcal_total: 420,
                         time: "25 min", difficulty: "Easy")
    return VStack {
        RecipeCard(recipe: recipe, onPress: {}, variant: .large)
        RecipeCard(recipe: recipe, onPress: {}, variant: .small)
    }
    .padding()
    .environmentObject(FavoritesStore())
    .environmentObject(InventoryStore())
}
