import SwiftUI
import SmartSwapsKit

/// Port of `app/(tabs)/recipes.tsx` (350 ln). Replaces the Phase 1 placeholder.
struct RecipesScreen: View {
    @EnvironmentObject private var foodsStore: FoodsStore
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var favoritesStore: FavoritesStore
    @EnvironmentObject private var recipeStore: RecipeStore
    @EnvironmentObject private var inventoryStore: InventoryStore
    @EnvironmentObject private var router: Router

    @State private var selectedCategory = "All"
    @State private var searchVisible = false
    @State private var limit = 10
    @State private var scrollY: CGFloat = 0

    private static let categories = ["All", "Breakfast", "Lunch", "Dinner", "Snack", "Dessert"]

    /// `relevantFoodIds` - foods actually in stock this week, plus their top-2 swap
    /// candidates, used to bias recipe ordering toward what's in the kitchen right now.
    private var relevantFoodIds: Set<String> {
        var ids = Set<String>()
        let safeFoods = foodsStore.foods(for: profileStore.profile.dietaryPreference)
        let pool = safeFoods.isEmpty ? foodsStore.allFoods : safeFoods
        for scan in inventoryStore.scans {
            for item in scan.items {
                guard let foodId = item.matchedFoodId, let food = foodsStore.byId[foodId] else { continue }
                ids.insert(food.id)
                let swaps = SwapAlgorithm.findBestSwaps(food, pool, 2, profileStore.profile.dietaryPreference.map(\.rawValue))
                for swap in swaps { ids.insert(swap.candidate.id) }
            }
        }
        return ids
    }

    private var filtered: [Recipe] {
        var recipes = recipeStore.recipes
        let prefs = profileStore.profile.dietaryPreference
        if prefs.contains(.vegetarian) {
            recipes = recipes.filter { r in !r.ingredients.contains { $0.food?.category == "Meat" || $0.food?.category == "Fish" } }
        }
        if prefs.contains(.vegan) {
            recipes = recipes.filter { r in
                !r.ingredients.contains {
                    $0.food?.category == "Meat" || $0.food?.category == "Fish" || $0.food?.category == "Dairy"
                        || ($0.food?.swiss_category.lowercased().contains("egg") ?? false)
                }
            }
        }
        if selectedCategory != "All" {
            recipes = recipes.filter { $0.subcategory.lowercased().contains(selectedCategory.lowercased()) }
        }

        let relevant = relevantFoodIds
        func relevance(_ r: Recipe) -> Int { r.ingredients.reduce(0) { acc, ing in (ing.food.map { relevant.contains($0.id) } ?? false) ? acc + 1 : acc } }

        return recipes.sorted { a, b in
            let ra = relevance(a), rb = relevance(b)
            if ra != rb { return rb < ra }
            return b.health_score < a.health_score
        }
    }

    private var featured: Recipe? { filtered.first }
    private var rest: [Recipe] { filtered.count > 1 ? Array(filtered.dropFirst()) : [] }
    private var visibleRest: [Recipe] { Array(rest.prefix(limit)) }
    private var hasMore: Bool { rest.count > limit }
    private var likedRecipes: [Recipe] { recipeStore.recipes.filter { favoritesStore.isFavorite(.recipe, $0.id) } }

    var body: some View {
        ZStack(alignment: .top) {
            Colors.background.ignoresSafeArea()

            TrackableScrollView(showsIndicators: false, onOffsetChange: { scrollY = $0 }) {
                ScrollOffsetReporter(coordinateSpace: "scroll")
                content
            }

            GlassHeader(title: "Recipes", onSettingsPress: nil, scrollY: scrollY, leftAccessory: { EmptyView() })
        }
        .sheet(isPresented: $searchVisible) {
            RecipeSearchModal(onClose: { searchVisible = false }, onSelectRecipe: { router.openRecipe($0) })
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            LargeTitle(title: "Recipes", scrollY: scrollY)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles").font(.system(size: 12)).foregroundColor(Colors.primaryGreen)
                    Text("SMART RECIPE ENGINE · \(recipeStore.recipes.count) RECIPES")
                        .font(.system(size: 10, weight: .bold)).tracking(0.3).foregroundColor(Colors.primaryGreen)
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Colors.lightGreenBg).cornerRadius(8)

                Text("Personalized recipes matched to your dietary goals. Tap any to see full nutrition & smart swaps.")
                    .subtitleText()
            }
            .padding(.bottom, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.categories, id: \.self) { cat in
                        let selected = selectedCategory == cat
                        Button(action: { selectedCategory = cat; limit = 10 }) {
                            Text(cat).font(.system(size: 13, weight: .semibold))
                                .foregroundColor(selected ? Colors.white : Colors.textSecondary)
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                .background(selected ? Colors.primaryGreen : Colors.white)
                                .overlay(RoundedRectangle(cornerRadius: 20).stroke(selected ? Colors.primaryGreen : Colors.border, lineWidth: 1))
                                .cornerRadius(20)
                        }.buttonStyle(.plain)
                    }
                }
            }
            .padding(.bottom, 20)

            if let featured {
                RecipeCard(recipe: featured, onPress: { router.openRecipe(featured.id) }, variant: .large)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text("Your Favorite Recipes").sectionTitleText().padding(.bottom, 12)
                if likedRecipes.isEmpty {
                    Text("No favorite recipes yet. Tap the heart on any recipe to save it here!")
                        .font(.system(size: 14)).italic().foregroundColor(Colors.textMuted)
                        .padding(.vertical, 12)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(likedRecipes) { recipe in
                                RecipeCard(recipe: recipe, onPress: { router.openRecipe(recipe.id) }, variant: .small)
                                    .frame(width: 280)
                            }
                        }
                    }
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 8)

            if !rest.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Popular Recipes").sectionTitleText().padding(.bottom, 8)
                    ForEach(visibleRest) { recipe in
                        RecipeCard(recipe: recipe, onPress: { router.openRecipe(recipe.id) }, variant: .small)
                    }
                    if hasMore {
                        Button(action: { limit += 20 }) {
                            Text("Load 20 More").font(.system(size: 14, weight: .semibold)).foregroundColor(Colors.primaryGreen)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(Colors.cardBackground)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Colors.border, lineWidth: 1))
                                .cornerRadius(12)
                        }.buttonStyle(.plain).padding(.top, 16).padding(.bottom, 8)
                    }
                }
                .padding(.top, likedRecipes.isEmpty ? 24 : 16)
            }

            if filtered.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "fork.knife").font(.system(size: 40)).foregroundColor(Colors.border)
                    Text("No recipes in this category yet.").font(.system(size: 14, weight: .medium)).foregroundColor(Colors.textMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 120)
    }
}

#Preview {
    RecipesScreen()
        .environmentObject(FoodsStore.shared)
        .environmentObject(ProfileStore())
        .environmentObject(FavoritesStore())
        .environmentObject(RecipeStore.shared)
        .environmentObject(InventoryStore())
        .environmentObject(Router())
}
