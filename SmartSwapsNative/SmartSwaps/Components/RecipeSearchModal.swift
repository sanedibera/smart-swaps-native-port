import SwiftUI
import SmartSwapsKit

/// Port of `components/RecipeSearchModal.tsx` (346 ln). `useRecipes()`/`useProfile()`/
/// `useFavorites()` -> `RecipeStore`/`ProfileStore`/`FavoritesStore` via `@EnvironmentObject`.
/// `router.push` -> `onSelectRecipe` closure, same pattern as `ReceiptItemList.swift`.
struct RecipeSearchModal: View {
    var onClose: () -> Void
    var onSelectRecipe: ((String) -> Void)? = nil
    var initialQuery: String = ""

    @EnvironmentObject private var recipeStore: RecipeStore
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var favorites: FavoritesStore

    @State private var searchQuery: String
    @State private var category = "All"
    @State private var maxCalories: Double = 1500
    @State private var minScore: Double = 0
    @State private var favoritesOnly = false
    @State private var showFilters = false
    @State private var limit = 20

    private static let categories = ["All", "Breakfast", "Lunch", "Dinner", "Snack", "Dessert"]

    init(onClose: @escaping () -> Void, onSelectRecipe: ((String) -> Void)? = nil, initialQuery: String = "") {
        self.onClose = onClose
        self.onSelectRecipe = onSelectRecipe
        self.initialQuery = initialQuery
        _searchQuery = State(initialValue: initialQuery)
    }

    private var searchResults: [Recipe] {
        var results = recipeStore.recipes
        let prefs = profileStore.profile.dietaryPreference

        if prefs.contains(.vegetarian) {
            results = results.filter { r in !r.ingredients.contains { $0.food?.category == "Meat" || $0.food?.category == "Fish" } }
        }
        if prefs.contains(.vegan) {
            results = results.filter { r in
                !r.ingredients.contains {
                    $0.food?.category == "Meat" || $0.food?.category == "Fish" || $0.food?.category == "Dairy"
                        || ($0.food?.swiss_category.lowercased().contains("egg") ?? false)
                }
            }
        }
        if !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            let q = searchQuery.lowercased()
            results = results.filter { r in
                r.name.lowercased().contains(q)
                    || r.ingredients.contains { $0.raw_text.lowercased().contains(q) || ($0.food?.name.lowercased().contains(q) ?? false) }
            }
        }
        if category != "All" {
            results = results.filter { $0.subcategory.lowercased().contains(category.lowercased()) }
        }
        if maxCalories < 1500 {
            results = results.filter { (($0.totals.kcal) / Double($0.serves > 0 ? $0.serves : 1)) <= maxCalories }
        }
        if minScore > 0 {
            results = results.filter { Double($0.health_score) >= minScore }
        }
        results.sort { $0.health_score > $1.health_score }
        if favoritesOnly {
            results = results.filter { favorites.isFavorite(.recipe, $0.id) }
        }
        return results
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            if showFilters { filters }
            resultsList
        }
        .background(Colors.white)
        .onChange(of: searchQuery) { _ in limit = 20 }
        .onChange(of: category) { _ in limit = 20 }
        .onChange(of: maxCalories) { _ in limit = 20 }
        .onChange(of: minScore) { _ in limit = 20 }
        .onChange(of: favoritesOnly) { _ in limit = 20 }
    }

    private var header: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "chevron.down").font(.system(size: 24)).foregroundColor(Colors.textPrimary)
            }.buttonStyle(.plain)
            Spacer()
            Text("Search Recipes").font(.system(size: 18, weight: .bold)).foregroundColor(Colors.textPrimary)
            Spacer()
            Button(action: { showFilters.toggle() }) {
                Image(systemName: showFilters ? "slider.horizontal.3" : "slider.horizontal.3")
                    .font(.system(size: 22))
                    .foregroundColor(showFilters ? Colors.primaryGreen : Colors.textPrimary)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 16)
        .overlay(Rectangle().fill(Colors.border).frame(height: 0.5), alignment: .bottom)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 18)).foregroundColor(Colors.textMuted)
            TextField("Search by name or ingredient...", text: $searchQuery)
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Colors.border, lineWidth: 1))
        .padding(20)
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Filters").font(.system(size: 16, weight: .bold)).foregroundColor(Colors.textPrimary)
                Spacer()
                Button("Clear all") {
                    category = "All"; maxCalories = 1500; minScore = 0; searchQuery = ""; favoritesOnly = false
                }.font(.system(size: 14, weight: .semibold)).foregroundColor(Colors.primaryGreen)
            }
            .padding(.bottom, 16)

            HStack {
                Text("Favorites Only").font(.system(size: 15, weight: .bold)).foregroundColor(Colors.textPrimary)
                Spacer()
                Toggle("", isOn: $favoritesOnly).labelsHidden().tint(Colors.primaryGreen)
            }
            .padding(.bottom, 20)

            Text("MEAL TYPE").font(.system(size: 12, weight: .bold)).tracking(0.5).foregroundColor(Colors.textMuted)
                .padding(.bottom, 8)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.categories, id: \.self) { c in
                        let selected = category == c
                        Button(action: { category = c }) {
                            Text(c).font(.system(size: 13, weight: .semibold))
                                .foregroundColor(selected ? Colors.white : Colors.textSecondary)
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                .background(selected ? Colors.primaryGreen : Colors.white)
                                .overlay(RoundedRectangle(cornerRadius: 20).stroke(selected ? Colors.primaryGreen : Colors.border, lineWidth: 1))
                                .cornerRadius(20)
                        }.buttonStyle(.plain)
                    }
                }
            }

            LiquidSlider(maxSliderVal: 1500, initialValue: maxCalories, title: "Max Calories per serving", unit: "kcal") { maxCalories = $0 }
                .padding(.top, 16)
            LiquidSlider(maxSliderVal: 100, initialValue: minScore, title: "Min Health Score", unit: "pts") { minScore = $0 }
                .padding(.top, 16)
        }
        .padding(.horizontal, 20).padding(.bottom, 20)
        .overlay(Rectangle().fill(Colors.border).frame(height: 0.5), alignment: .bottom)
    }

    private var resultsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(searchResults.count) recipes found")
                    .font(.system(size: 14, weight: .medium)).foregroundColor(Colors.textSecondary)
                    .padding(.bottom, 16)

                ForEach(searchResults.prefix(limit)) { recipe in
                    RecipeCard(recipe: recipe, onPress: {
                        onClose()
                        onSelectRecipe?(recipe.id)
                    }, variant: .small)
                }

                if searchResults.count > limit {
                    Button(action: { limit += 10 }) {
                        Text("Load 10 More").font(.system(size: 16, weight: .semibold)).foregroundColor(Colors.primaryGreen)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Colors.background).cornerRadius(8)
                    }.buttonStyle(.plain).padding(.vertical, 16)
                }

                if searchResults.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "magnifyingglass").font(.system(size: 48)).foregroundColor(Colors.border)
                        Text("No recipes found").font(.system(size: 18, weight: .semibold)).foregroundColor(Colors.textPrimary)
                        Text("Try adjusting your search or filters.").font(.system(size: 14)).foregroundColor(Colors.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                }
            }
            .padding(20)
        }
    }
}

#Preview {
    RecipeSearchModal(onClose: {})
        .environmentObject(RecipeStore.shared)
        .environmentObject(ProfileStore())
        .environmentObject(FavoritesStore())
        .environmentObject(InventoryStore())
}
