import Foundation
import SwiftUI
import SmartSwapsKit

/// Port of `app/useFoods.ts` (95 ln). The RN version caches `allFoods`/the search index/the
/// icon library at MODULE scope so the (expensive) DB read + index build happens once per
/// app session, not once per screen mount; `.shared` here is that same one-per-process cache.
@MainActor
public final class FoodsStore: ObservableObject {
    public static let shared = FoodsStore()

    @Published public private(set) var allFoods: [FoodItem] = []
    @Published public private(set) var foodIndex: FoodIndexData?
    @Published public private(set) var iconLibrary: [String: String] = [:]
    @Published public private(set) var isLoaded = false

    /// `foods.byId` - `RecipeMath.hydrateRecipes` and inventory resolution both need
    /// id -> FoodItem, matching the JS `Map<string, FoodItem>` built ad hoc at each call site.
    public var byId: [String: FoodItem] {
        Dictionary(allFoods.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private init() {}

    public func load() {
        guard !isLoaded else { return }
        do {
            try DatabaseService.shared.open()
            let foods = try DatabaseService.shared.getAllFoods()
            let icons = try DatabaseService.shared.getIconLibrary()
            allFoods = foods
            foodIndex = FoodIndex.buildFoodIndex(foods)
            iconLibrary = icons
            isLoaded = true
        } catch {
            // Matches the source's silent-catch-and-log pattern elsewhere in the data layer;
            // an empty foods list is a visibly broken app, so this is worth surfacing loudly
            // in development rather than pretending to have loaded.
            assertionFailure("FoodsStore.load() failed: \(error)")
        }
    }

    /// `useFoods.ts`'s dietary-preference filter (the `foods` return value, as opposed to
    /// the unfiltered `allFoods`).
    public func foods(for dietaryPreference: [DietaryPreference]) -> [FoodItem] {
        var filtered = allFoods
        if dietaryPreference.contains(.vegetarian) {
            filtered = filtered.filter { !$0.category.contains("Meat") && !$0.category.contains("Fish") }
        }
        if dietaryPreference.contains(.vegan) {
            filtered = filtered.filter {
                !$0.category.contains("Meat") && !$0.category.contains("Fish")
                    && !$0.category.contains("Dairy") && !$0.swiss_category.lowercased().contains("egg")
            }
        }
        if dietaryPreference.contains(.highProtein) {
            filtered = filtered.filter { $0.nutrients_per_100.protein_g >= 15 }
        }
        if dietaryPreference.contains(.lowCarb) {
            filtered = filtered.filter { $0.nutrients_per_100.carbs_g <= 20 }
        }
        return filtered
    }
}

/// Port of `useFoods.ts`'s `getIconForCategory` - the Ionicons fallback glyph for a food
/// with no `icon_key`/failed SVG. SF Symbol names chosen for closest optical match; two
/// (egg, generic grain/nutrition) have no precise SF equivalent per PORTING_INVENTORY.md
/// §7.3's own flag, and are approximated here rather than bundling the Ionicons originals.
/// Symbol name availability has not been checked against a live SF Symbols catalog (no
/// Xcode in this container) - verify before shipping.
public func getIconForCategory(_ category: String) -> String {
    let cat = category.lowercased()
    if cat.contains("meat") || cat.contains("sausage") || cat.contains("poultry") { return "fork.knife" }
    if cat.contains("fish") || cat.contains("seafood") { return "fish" }
    if cat.contains("dairy") || cat.contains("egg") || cat.contains("milk") || cat.contains("cheese") { return "carton" }
    if cat.contains("fruit") || cat.contains("vegetable") { return "leaf" }
    if cat.contains("drink") || cat.contains("beverage") || cat.contains("water") { return "drop" }
    if cat.contains("sweet") || cat.contains("pastry") || cat.contains("sugar") { return "birthday.cake" }
    if cat.contains("cereal") || cat.contains("grain") || cat.contains("bread") || cat.contains("pantry") { return "basket" }
    return "takeoutbag.and.cup.and.straw"
}
