import SwiftUI
import SmartSwapsKit

private let recipeMicroTargets: [String: Double] = [
    "calcium_mg": 1000, "iron_mg": 14, "magnesium_mg": 375, "potassium_mg": 2000,
    "zinc_mg": 10, "vitamin_c_mg": 80, "vitamin_d_ug": 5, "vitamin_a_ug": 800,
    "vitamin_e_mg": 12, "vitamin_b1_mg": 1.1, "vitamin_b2_mg": 1.4, "vitamin_b6_mg": 1.4,
    "vitamin_b12_ug": 2.5, "niacin_mg": 16, "folate_ug": 200, "pantothenic_acid_mg": 6,
    "phosphorus_mg": 700, "sodium_mg": 2400, "chloride_mg": 800, "iodide_ug": 150, "betacarotene_ug": 7000,
]

private func recipeScoreLabel(_ score: Int) -> String {
    if score >= 80 { return "Excellent Health" }
    if score >= 65 { return "Good Health" }
    if score >= 50 { return "Moderate Health" }
    return "Low Health"
}
private func recipeScoreColors(_ val: Int) -> (text: Color, bg: Color) {
    if val >= 75 { return (Colors.scoreGreen, Colors.lightGreenBg) }
    if val >= 50 { return (Colors.scoreYellow, Colors.scoreYellowLight) }
    return (Colors.scoreRed, Colors.scoreRedLight)
}

private let knownRecipeSites: [String: String] = [
    "bbc.co.uk": "BBC Good Food", "bbcgoodfood.com": "BBC Good Food", "allrecipes.com": "Allrecipes",
    "food.com": "Food.com", "epicurious.com": "Epicurious", "foodnetwork.com": "Food Network",
    "bonappetit.com": "Bon Appétit", "seriouseats.com": "Serious Eats", "delish.com": "Delish",
    "simplyrecipes.com": "Simply Recipes", "tasty.co": "Tasty", "recipetineats.com": "RecipeTin Eats",
    "jamieoliver.com": "Jamie Oliver", "nigella.com": "Nigella", "hellofresh.com": "Hello Fresh",
    "chefkoch.de": "Chefkoch",
]

private func siteName(for urlString: String) -> String {
    guard let url = URL(string: urlString), var host = url.host else { return "Original Recipe" }
    if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
    if let known = knownRecipeSites[host] { return known }
    let firstSegment = host.split(separator: ".").first.map(String.init) ?? host
    guard !firstSegment.isEmpty else { return "Original Recipe" }
    return firstSegment.prefix(1).uppercased() + firstSegment.dropFirst()
}

/// Port of `app/recipe/[id].tsx` (851 ln). Presented as an iOS sheet, same reasoning as
/// `FoodDetailScreen.swift`. `findBestRecipeSwap` -> `RecipeSwapAlgorithm.findBestRecipeSwap`
/// (see that file's header on why it exists despite PORTING_INVENTORY.md marking the source
/// deleted). The active/base-totals toggle recomputes on every access rather than via
/// `useMemo` - same tradeoff already flagged for the tab screens in PORTING_NOTES.md.
struct RecipeDetailScreen: View {
    var recipeId: String
    var onClose: () -> Void

    @EnvironmentObject private var recipeStore: RecipeStore
    @EnvironmentObject private var foodsStore: FoodsStore
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var favoritesStore: FavoritesStore
    @EnvironmentObject private var inventoryStore: InventoryStore

    @State private var swapsEnabled = false
    @State private var swapsExpanded = false
    @State private var ingredientsExpanded = true
    @State private var stepsExpanded = true
    @State private var microsExpanded = false
    @State private var macrosExpanded = false
    @State private var shoppingListModalVisible = false
    @State private var shoppingServings = 1
    @State private var isAdded = false
    @State private var addedScale: CGFloat = 1
    @State private var showNoIngredientsAlert = false

    private static let headerHeight: CGFloat = 44

    private var recipe: Recipe? { recipeStore.recipes.first { $0.id == recipeId } }
    private var isFav: Bool { recipe.map { favoritesStore.isFavorite(.recipe, $0.id) } ?? false }

    private struct IngredientSwap { var name: String; var improvement: Int; var candidate: FoodItem }

    /// Keyed by `food_id` - `nil` values (present-but-empty) are preserved implicitly by
    /// only inserting an entry when a swap is actually found, matching the source's intent
    /// (an ingredient with no `food_id`/no swap simply has no dictionary entry here).
    private func ingredientSwaps(for recipe: Recipe) -> [String: IngredientSwap] {
        var out: [String: IngredientSwap] = [:]
        for ing in recipe.ingredients {
            guard let food = ing.food, food.health_score < 70, let foodId = ing.food_id else { continue }
            guard let swap = RecipeSwapAlgorithm.findBestRecipeSwap(food, foodsStore.allFoods, profileStore.profile.dietaryPreference.map(\.rawValue)) else { continue }
            out[foodId] = IngredientSwap(name: swap.candidate.name,
                                          improvement: JSNumber.roundToInt(swap.candidate.health_score) - JSNumber.roundToInt(food.health_score),
                                          candidate: swap.candidate)
        }
        return out
    }

    private func activeTotalsAndScore(_ recipe: Recipe, _ swaps: [String: IngredientSwap]) -> (FoodNutrients, Int) {
        guard swapsEnabled else { return (recipe.totals, recipe.health_score) }

        var currentTotal = RecipeMath.emptyNutrients()
        var totalKcal = 0.0
        var scoreSum = 0.0

        for ing in recipe.ingredients {
            if let foodId = ing.food_id, let swap = swaps[foodId] {
                let newNuts = RecipeMath.scaleNutrients(swap.candidate.nutrients_per_100, grams: ing.grams)
                currentTotal = RecipeMath.addNutrients(currentTotal, newNuts)
                totalKcal += newNuts.kcal
                scoreSum += swap.candidate.health_score * newNuts.kcal
            } else if let nutrients = ing.nutrients {
                currentTotal = RecipeMath.addNutrients(currentTotal, nutrients)
                totalKcal += nutrients.kcal
                if let food = ing.food { scoreSum += food.health_score * nutrients.kcal }
            }
        }

        let serves = recipe.serves > 0 ? recipe.serves : 1
        let finalTotals = RecipeMath.divideNutrients(currentTotal, by: Double(serves))
        let hScore = totalKcal > 0 ? JSNumber.roundToInt(scoreSum / totalKcal) : 50
        return (finalTotals, hScore)
    }

    var body: some View {
        Group {
            if let recipe {
                let swaps = ingredientSwaps(for: recipe)
                let (activeTotals, activeHealthScore) = activeTotalsAndScore(recipe, swaps)
                ZStack(alignment: .top) {
                    Colors.white.ignoresSafeArea()
                    ScrollView(showsIndicators: false) {
                        content(recipe, swaps, activeTotals, activeHealthScore)
                            .padding(.top, Self.headerHeight + 8)
                    }
                    NavBlur(headerHeight: Self.headerHeight)
                    header(recipe)
                }
                .onAppear { if shoppingServings == 1 { shoppingServings = recipe.serves > 0 ? recipe.serves : 1 } }
            } else {
                VStack(spacing: 16) {
                    Text("Recipe not found or loading...").foregroundColor(Colors.textMuted)
                    Button("Go back", action: onClose).foregroundColor(Colors.primaryGreen).fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $shoppingListModalVisible) {
            SelectShoppingListModal(onSelect: { listId, newName in
                Task { await generateShoppingList(listId: listId, newListName: newName) }
            }, onClose: { shoppingListModalVisible = false })
                .environmentObject(inventoryStore)
        }
        .alert("This recipe has no ingredients to add!", isPresented: $showNoIngredientsAlert) {
            Button("OK") {}
        }
    }

    private func header(_ recipe: Recipe) -> some View {
        HStack {
            GlassCircleButton(onPress: onClose) {
                Image(systemName: "xmark").font(.system(size: 18, weight: .semibold)).foregroundColor(Colors.textPrimary)
            }
            Spacer()
            GlassCircleButton(onPress: { favoritesStore.toggleFavorite(.recipe, recipe.id) }) {
                Image(systemName: isFav ? "heart.fill" : "heart").font(.system(size: 18))
                    .foregroundColor(isFav ? Color(hex: 0xFF3B30) : Colors.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: Self.headerHeight)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func content(_ recipe: Recipe, _ swaps: [String: RecipeDetailScreen.IngredientSwap], _ totals: FoodNutrients, _ activeScore: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            titleBlock(recipe)
            scoreCard(activeScore)
            swapsCard(recipe, swaps)
            shoppingListCard(recipe)
            ingredientsSection(recipe, swaps)
            stepsSection(recipe)
            nutritionSection(totals)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 120)
    }

    private func titleBlock(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(recipe.subcategory.uppercased()).font(.system(size: 12, weight: .bold)).tracking(0.5).foregroundColor(Colors.textMuted)
            Text(recipe.name).font(.system(size: 24, weight: .heavy)).foregroundColor(Colors.textPrimary).lineSpacing(4).padding(.top, 4).padding(.bottom, 8)
            HStack(spacing: 5) {
                Image(systemName: "clock").font(.system(size: 14)).foregroundColor(Colors.textSecondary)
                Text(recipe.time ?? "").font(.system(size: 13, weight: .medium)).foregroundColor(Colors.textSecondary)
                Spacer().frame(width: 12)
                Image(systemName: "speedometer").font(.system(size: 14)).foregroundColor(Colors.textSecondary)
                Text(recipe.difficulty ?? "").font(.system(size: 13, weight: .medium)).foregroundColor(Colors.textSecondary)
                if recipe.serves > 1 {
                    Spacer().frame(width: 12)
                    Image(systemName: "person.2").font(.system(size: 14)).foregroundColor(Colors.textSecondary)
                    Text("\(recipe.serves) servings").font(.system(size: 13, weight: .medium)).foregroundColor(Colors.textSecondary)
                }
            }
            Text(recipe.dish_type).font(.system(size: 12)).foregroundColor(Colors.textMuted).padding(.top, 6)

            if let url = URL(string: recipe.url) {
                Link(destination: url) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.forward.square").font(.system(size: 13)).foregroundColor(Colors.primaryGreen)
                        (Text("Recipe from ").font(.system(size: 12)).foregroundColor(Colors.primaryGreen)
                            + Text(siteName(for: recipe.url)).font(.system(size: 12, weight: .bold)).foregroundColor(Colors.primaryGreen))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Colors.lightGreenBg).cornerRadius(10)
                }
                .padding(.top, 10)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    private func scoreCard(_ activeScore: Int) -> some View {
        let colors = recipeScoreColors(activeScore)
        return VStack(alignment: .leading, spacing: 6) {
            Text("MEAL HEALTH SCORE").font(.system(size: 10, weight: .bold)).tracking(0.6).foregroundColor(Colors.textMuted)
            HStack {
                HStack(alignment: .bottom, spacing: 0) {
                    Text("\(activeScore)").font(.system(size: 44, weight: .heavy)).foregroundColor(colors.text)
                    Text("/100").font(.system(size: 18, weight: .medium)).foregroundColor(Colors.textMuted).padding(.leading, 4).padding(.bottom, 6)
                }
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "rosette").font(.system(size: 14)).foregroundColor(colors.text)
                    Text(recipeScoreLabel(activeScore)).font(.system(size: 13, weight: .bold)).foregroundColor(colors.text)
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Colors.white)
                .overlay(Capsule().stroke(colors.text.opacity(0.25), lineWidth: 1.5))
                .clipShape(Capsule())
            }
        }
        .padding(18)
        .background(Colors.lightGreenBg)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Colors.border, lineWidth: 1))
        .cornerRadius(20)
        .padding(.bottom, 14)
    }

    private func swapsCard(_ recipe: Recipe, _ swaps: [String: IngredientSwap]) -> some View {
        let activeSwaps = Array(swaps.values)
        return VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(.easeInOut) { swapsExpanded.toggle() } }) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles").font(.system(size: 18)).foregroundColor(Colors.primaryGreen)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Smart Swaps").font(.system(size: 15, weight: .bold)).foregroundColor(Colors.primaryGreen)
                            Text(activeSwaps.isEmpty ? "Tap to explore substitutions" : "\(activeSwaps.count) swap\(activeSwaps.count != 1 ? "s" : "") available")
                                .font(.system(size: 11)).foregroundColor(Colors.textSecondary)
                        }
                    }
                    Spacer()
                    if !activeSwaps.isEmpty {
                        Toggle("", isOn: $swapsEnabled).labelsHidden().tint(Colors.primaryGreen)
                    }
                    Image(systemName: swapsExpanded ? "chevron.up" : "chevron.down").font(.system(size: 18)).foregroundColor(Colors.textMuted).padding(.leading, 10)
                }
            }.buttonStyle(.plain)

            if swapsExpanded {
                if !activeSwaps.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Active Swaps in this recipe:").font(.system(size: 12, weight: .medium)).foregroundColor(Colors.textSecondary)
                        ForEach(recipe.ingredients) { ing in
                            if let foodId = ing.food_id, let swap = swaps[foodId] {
                                HStack {
                                    Text(ing.food?.name ?? ing.raw_text).font(.system(size: 13, weight: .semibold)).foregroundColor(Colors.textPrimary).lineLimit(1)
                                    Image(systemName: "arrow.right").font(.system(size: 13)).foregroundColor(Colors.textMuted).padding(.horizontal, 4)
                                    Text(swap.name).font(.system(size: 13, weight: .bold)).foregroundColor(Colors.primaryGreen).lineLimit(1)
                                    Spacer(minLength: 4)
                                    Text("+\(swap.improvement) pts").font(.system(size: 11, weight: .bold)).foregroundColor(Colors.white)
                                        .padding(.horizontal, 7).padding(.vertical, 3)
                                        .background(Colors.primaryGreen).cornerRadius(8)
                                }
                            }
                        }
                    }
                    .padding(.top, 14)
                } else {
                    Text("All ingredients are already high-scoring — no swaps needed!")
                        .font(.system(size: 13)).italic().foregroundColor(Colors.textMuted)
                        .padding(.top, 12)
                }
            }
        }
        .padding(18)
        .background(Colors.lightGreenBg)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Colors.border, lineWidth: 1))
        .cornerRadius(20)
        .padding(.bottom, 20)
    }

    private func shoppingListCard(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Build a Shopping List").font(.system(size: 15, weight: .bold)).foregroundColor(Color(hex: 0x006599))
            Text("Add missing ingredients to your shopping list").font(.system(size: 12)).foregroundColor(Color(hex: 0x0084C9))

            HStack {
                HStack(spacing: 0) {
                    Button(action: { shoppingServings = max(1, shoppingServings - 1) }) {
                        Image(systemName: "minus").font(.system(size: 16)).foregroundColor(Colors.textPrimary)
                            .frame(width: 28, height: 28).background(Color(hex: 0xF0FAFF)).cornerRadius(8)
                    }.buttonStyle(.plain)
                    Text("\(shoppingServings)").font(.system(size: 14, weight: .bold)).padding(.horizontal, 12)
                    Button(action: { shoppingServings += 1 }) {
                        Image(systemName: "plus").font(.system(size: 16)).foregroundColor(Colors.textPrimary)
                            .frame(width: 28, height: 28).background(Color(hex: 0xF0FAFF)).cornerRadius(8)
                    }.buttonStyle(.plain)
                    Text("servings").font(.system(size: 13)).foregroundColor(Colors.textMuted).padding(.leading, 8)
                }
                .padding(4)
                .background(Colors.white)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xBFE7FF), lineWidth: 1))
                .cornerRadius(12)

                Spacer()

                Button(action: { if !isAdded { shoppingListModalVisible = true } }) {
                    HStack(spacing: 6) {
                        Image(systemName: isAdded ? "checkmark.circle.fill" : "basket").font(.system(size: 16))
                        Text(isAdded ? "Added!" : "Add to List").font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(isAdded ? Colors.primaryGreen : Color(hex: 0x0084C9))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .scaleEffect(addedScale)
            }
            .padding(.top, 12)
        }
        .padding(18)
        .background(Color(hex: 0xF0FAFF))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(hex: 0xBFE7FF), lineWidth: 1))
        .cornerRadius(20)
        .padding(.bottom, 20)
    }

    private func ingredientsSection(_ recipe: Recipe, _ swaps: [String: IngredientSwap]) -> some View {
        let ownedCount = recipe.ingredients.reduce(0) { acc, ing in
            guard let fid = ing.food_id, inventoryStore.ownedFoodIds.contains(fid) else { return acc }
            return acc + 1
        }
        return VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(.easeInOut) { ingredientsExpanded.toggle() } }) {
                HStack {
                    HStack(spacing: 8) {
                        Text("Ingredients (\(recipe.ingredients.count))").font(.system(size: 20, weight: .heavy)).foregroundColor(Colors.textPrimary)
                        if ownedCount > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundColor(Colors.primaryGreen)
                                Text("\(ownedCount) in stock").font(.system(size: 11, weight: .bold)).foregroundColor(Colors.primaryGreen)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Colors.lightGreenBg).cornerRadius(10)
                        }
                    }
                    Spacer()
                    Image(systemName: ingredientsExpanded ? "chevron.up" : "chevron.down").font(.system(size: 20)).foregroundColor(Colors.textMuted)
                }
            }.buttonStyle(.plain).padding(.vertical, 8)

            if ingredientsExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(recipe.ingredients.enumerated()), id: \.offset) { idx, ing in
                        ingredientRow(ing, swaps)
                        if idx < recipe.ingredients.count - 1 {
                            Rectangle().fill(Colors.border).frame(height: 1)
                        }
                    }
                }
                .padding(18)
                .background(Colors.white)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Colors.border, lineWidth: 1))
                .cornerRadius(20)
                .shadow(color: Colors.shadowColor.opacity(0.04), radius: 8, x: 0, y: 2)
                .padding(.bottom, 24)
            }
        }
    }

    private func ingredientRow(_ ing: RecipeIngredient, _ swaps: [String: IngredientSwap]) -> some View {
        let swap = ing.food_id.flatMap { swaps[$0] }
        let isSwappedIn = swapsEnabled && swap != nil
        let displayFood = isSwappedIn ? swap?.candidate : ing.food
        let isOwned = ing.food_id.map { inventoryStore.ownedFoodIds.contains($0) } ?? false
        let kcalRounded: Int = {
            if isSwappedIn, let candidate = swap?.candidate {
                return JSNumber.roundToInt(RecipeMath.scaleNutrients(candidate.nutrients_per_100, grams: ing.grams).kcal)
            }
            return JSNumber.roundToInt(ing.kcal)
        }()
        let scoreColors = displayFood.map { recipeScoreColors(JSNumber.roundToInt($0.health_score)) }

        return VStack(alignment: .leading, spacing: 0) {
            Button(action: { if let displayFood { router.openFood(displayFood.id) } }) {
                HStack(spacing: 8) {
                    if let displayFood {
                        RoundedRectangle(cornerRadius: 9).fill(Colors.cardBackground).frame(width: 30, height: 30)
                            .overlay(FoodIcon(iconKey: displayFood.icon_key, category: displayFood.category, size: 18))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            if isOwned { Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundColor(Colors.primaryGreen) }
                            if isSwappedIn { Image(systemName: "arrow.left.arrow.right").font(.system(size: 11)).foregroundColor(Colors.primaryGreen) }
                            Text(displayFood?.name ?? String(ing.raw_text.split(separator: ",").first ?? Substring(ing.raw_text)))
                                .font(.system(size: 14, weight: .bold)).foregroundColor(Colors.textPrimary)
                        }
                        Text(ing.raw_text).font(.system(size: 12)).foregroundColor(Colors.textMuted).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if kcalRounded > 0 {
                        Text("\(kcalRounded) kcal").font(.system(size: 12, weight: .medium)).foregroundColor(Colors.textSecondary)
                            .padding(.horizontal, 8).padding(.vertical, 4).background(Color(hex: 0xF5F5F5)).cornerRadius(8)
                    }
                    if let displayFood, let scoreColors {
                        Text("Score: \(JSNumber.roundToInt(displayFood.health_score))").font(.system(size: 12, weight: .bold)).foregroundColor(scoreColors.text)
                            .padding(.horizontal, 8).padding(.vertical, 4).background(scoreColors.bg).cornerRadius(8)
                    }
                }
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .disabled(displayFood == nil)

            if let swap, !swapsEnabled {
                Button(action: { router.openFood(swap.candidate.id) }) {
                    HStack(spacing: 6) {
                        Image(systemName: "shuffle").font(.system(size: 13)).foregroundColor(Colors.primaryGreen)
                        Text("Swap suggestion: replace with \(swap.name)").font(.system(size: 12)).foregroundColor(Colors.textSecondary)
                        Spacer(minLength: 4)
                        Text("+\(swap.improvement) pts →").font(.system(size: 12, weight: .bold)).foregroundColor(Colors.primaryGreen)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Color(hex: 0xF0FAF0))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Colors.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    .cornerRadius(10)
                }.buttonStyle(.plain).padding(.bottom, 8)
            }
        }
    }

    private func stepsSection(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(.easeInOut) { stepsExpanded.toggle() } }) {
                HStack {
                    Text("Instructions (\(recipe.steps.count) steps)").font(.system(size: 20, weight: .heavy)).foregroundColor(Colors.textPrimary)
                    Spacer()
                    Image(systemName: stepsExpanded ? "chevron.up" : "chevron.down").font(.system(size: 20)).foregroundColor(Colors.textMuted)
                }
            }.buttonStyle(.plain).padding(.vertical, 8)

            if stepsExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(recipe.steps.enumerated()), id: \.offset) { idx, step in
                        HStack(alignment: .top, spacing: 12) {
                            Circle().fill(Colors.lightGreenBg).frame(width: 26, height: 26)
                                .overlay(Text("\(idx + 1)").font(.system(size: 13, weight: .bold)).foregroundColor(Colors.primaryGreen))
                            Text(step).font(.system(size: 14)).foregroundColor(Colors.textPrimary).lineSpacing(6)
                        }
                        .padding(.vertical, 12)
                        if idx < recipe.steps.count - 1 { Rectangle().fill(Colors.border).frame(height: 1) }
                    }
                }
                .padding(18)
                .background(Colors.white)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Colors.border, lineWidth: 1))
                .cornerRadius(20)
                .shadow(color: Colors.shadowColor.opacity(0.04), radius: 8, x: 0, y: 2)
                .padding(.bottom, 24)
            }
        }
    }

    private func nutritionSection(_ totals: FoodNutrients) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline) {
                Text("Nutrition").font(.system(size: 20, weight: .heavy)).foregroundColor(Colors.textPrimary)
                Spacer()
                Text("% OF DAILY INTAKE (\(JSNumber.roundToInt(Double(profileStore.targetCalories))) KCAL)")
                    .font(.system(size: 9, weight: .bold)).tracking(0.3).foregroundColor(Colors.textMuted)
            }
            .padding(.top, 8).padding(.bottom, 8)

            Button(action: { withAnimation(.easeInOut) { macrosExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.pie").font(.system(size: 15)).foregroundColor(Colors.primaryGreen)
                    Text(macrosExpanded ? "Hide Macronutrients" : "Show Macronutrients").font(.system(size: 13, weight: .semibold)).foregroundColor(Colors.primaryGreen)
                    Spacer()
                    Image(systemName: macrosExpanded ? "chevron.up" : "chevron.down").font(.system(size: 15)).foregroundColor(Colors.primaryGreen)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Colors.lightGreenBg).cornerRadius(12)
            }.buttonStyle(.plain).padding(.bottom, 14)

            if macrosExpanded {
                let macros = profileStore.targetMacros
                VStack(alignment: .leading, spacing: 0) {
                    Text("MACRONUTRIENTS").font(.system(size: 11, weight: .bold)).tracking(0.5).foregroundColor(Colors.primaryGreen)
                        .padding(.bottom, 10)
                        .overlay(Rectangle().fill(Colors.border).frame(height: 1), alignment: .bottom)
                        .padding(.bottom, 14)
                    NutrientRow(label: "Calories", value: totals.kcal, target: Double(profileStore.targetCalories), unit: " kcal", isLowerBetter: true)
                    NutrientRow(label: "Protein", value: totals.protein_g, target: Double(macros.protein), unit: "g", isLowerBetter: false)
                    NutrientRow(label: "Carbs", value: totals.carbs_g, target: Double(macros.carbs), unit: "g", isLowerBetter: true)
                    NutrientRow(label: "Sugars", value: totals.sugars_g, target: Double(macros.sugars), unit: "g", isLowerBetter: true)
                    NutrientRow(label: "Fat", value: totals.fat_g, target: Double(macros.fat), unit: "g", isLowerBetter: true)
                    NutrientRow(label: "Saturated Fat", value: totals.saturated_fat_g, target: Double(macros.satFat), unit: "g", isLowerBetter: true)
                    NutrientRow(label: "Fiber", value: totals.fiber_g, target: Double(macros.fiber), unit: "g", isLowerBetter: false)
                    NutrientRow(label: "Salt", value: totals.salt_g, target: Double(macros.salt), unit: "g", isLowerBetter: true)
                }
                .padding(18)
                .background(Colors.white)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Colors.border, lineWidth: 1))
                .cornerRadius(20)
                .shadow(color: Colors.shadowColor.opacity(0.04), radius: 8, x: 0, y: 2)
                .padding(.bottom, 14)
            }

            Button(action: { withAnimation(.easeInOut) { microsExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: "testtube.2").font(.system(size: 15)).foregroundColor(Colors.primaryGreen)
                    Text(microsExpanded ? "Hide Micronutrients" : "Show Micronutrients").font(.system(size: 13, weight: .semibold)).foregroundColor(Colors.primaryGreen)
                    Spacer()
                    Image(systemName: microsExpanded ? "chevron.up" : "chevron.down").font(.system(size: 15)).foregroundColor(Colors.primaryGreen)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Colors.lightGreenBg).cornerRadius(12)
            }.buttonStyle(.plain)

            if microsExpanded {
                let m = totals.micros
                let rows: [(String, Double, String, String, Bool)] = [
                    ("Calcium", m.calcium_mg, "calcium_mg", "mg", false),
                    ("Iron", m.iron_mg, "iron_mg", "mg", false),
                    ("Magnesium", m.magnesium_mg, "magnesium_mg", "mg", false),
                    ("Potassium", m.potassium_mg, "potassium_mg", "mg", false),
                    ("Zinc", m.zinc_mg, "zinc_mg", "mg", false),
                    ("Vitamin C", m.vitamin_c_mg, "vitamin_c_mg", "mg", false),
                    ("Vitamin D", m.vitamin_d_ug, "vitamin_d_ug", "μg", false),
                    ("Vitamin A", m.vitamin_a_ug, "vitamin_a_ug", "μg", false),
                    ("Vitamin E", m.vitamin_e_mg, "vitamin_e_mg", "mg", false),
                    ("Vitamin B1", m.vitamin_b1_mg, "vitamin_b1_mg", "mg", false),
                    ("Vitamin B2", m.vitamin_b2_mg, "vitamin_b2_mg", "mg", false),
                    ("Vitamin B6", m.vitamin_b6_mg, "vitamin_b6_mg", "mg", false),
                    ("Vitamin B12", m.vitamin_b12_ug, "vitamin_b12_ug", "μg", false),
                    ("Niacin", m.niacin_mg, "niacin_mg", "mg", false),
                    ("Folate", m.folate_ug, "folate_ug", "μg", false),
                    ("Phosphorus", m.phosphorus_mg, "phosphorus_mg", "mg", false),
                    ("Sodium", m.sodium_mg, "sodium_mg", "mg", true),
                    ("Iodine", m.iodide_ug, "iodide_ug", "μg", false),
                ]
                VStack(alignment: .leading, spacing: 0) {
                    Text("ESSENTIAL MICRONUTRIENTS").font(.system(size: 11, weight: .bold)).tracking(0.5).foregroundColor(Colors.primaryGreen)
                        .padding(.bottom, 10)
                        .overlay(Rectangle().fill(Colors.border).frame(height: 1), alignment: .bottom)
                        .padding(.bottom, 14)
                    ForEach(rows, id: \.2) { label, value, key, unit, lowerBetter in
                        NutrientRow(label: label, value: value, target: recipeMicroTargets[key] ?? 1, unit: unit, isLowerBetter: lowerBetter)
                    }
                }
                .padding(18)
                .background(Colors.white)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Colors.border, lineWidth: 1))
                .cornerRadius(20)
                .shadow(color: Colors.shadowColor.opacity(0.04), radius: 8, x: 0, y: 2)
            }
        }
    }

    private func generateShoppingList(listId: String?, newListName: String?) async {
        guard let recipe else { return }
        let scaleFactor = Double(shoppingServings) / Double(recipe.serves > 0 ? recipe.serves : 1)
        guard !recipe.ingredients.isEmpty else {
            showNoIngredientsAlert = true
            return
        }

        let swaps = ingredientSwaps(for: recipe)
        let items: [PersistedReceiptItem] = recipe.ingredients.map { ing in
            let swap = ing.food_id.flatMap { swaps[$0] }
            let displayFood = swapsEnabled ? (swap?.candidate ?? ing.food) : ing.food
            let qty = ing.grams * scaleFactor
            return PersistedReceiptItem(rawText: ing.raw_text, matchedFoodId: displayFood?.id, confidence: 1.0,
                                         source: "recipe", quantity: qty, unit: "g")
        }

        if let listId {
            if let existing = inventoryStore.shoppingLists.first(where: { $0.id == listId }) {
                let updatedItems = existing.items + items
                let validScores = updatedItems.compactMap { $0.matchedFoodId.flatMap { foodsStore.byId[$0]?.health_score } }
                let avgScore = validScores.isEmpty ? 50.0 : Double(JSNumber.roundToInt(validScores.reduce(0, +) / Double(validScores.count)))
                await StorageService.updateScan(id: listId, updatedScan: ScanRecord(
                    id: existing.id, date: existing.date, items: updatedItems, averageScore: avgScore,
                    interactions: existing.interactions, isShoppingList: existing.isShoppingList, recipeName: existing.recipeName))
            }
        } else {
            let validScores = items.compactMap { $0.matchedFoodId.flatMap { foodsStore.byId[$0]?.health_score } }
            let avgScore = validScores.isEmpty ? 50.0 : Double(JSNumber.roundToInt(validScores.reduce(0, +) / Double(validScores.count)))
            let iso = ISO8601DateFormatter().string(from: Date())
            await StorageService.saveScan(id: UUID().uuidString, date: iso, items: items, averageScore: avgScore,
                                           isShoppingList: true, recipeName: (newListName?.isEmpty == false ? newListName! : recipe.name))
        }

        await inventoryStore.refreshInventory()
        shoppingListModalVisible = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.4)) { addedScale = 1.06 }
            isAdded = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { addedScale = 1 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                isAdded = false
                withAnimation(.spring(response: 0.25, dampingFraction: 0.4)) { addedScale = 1.06 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { addedScale = 1 }
                }
            }
        }
    }
}

#Preview {
    RecipeDetailScreen(recipeId: "preview", onClose: {})
        .environmentObject(RecipeStore.shared)
        .environmentObject(FoodsStore.shared)
        .environmentObject(ProfileStore())
        .environmentObject(FavoritesStore())
        .environmentObject(InventoryStore())
        .environmentObject(Router())
}
