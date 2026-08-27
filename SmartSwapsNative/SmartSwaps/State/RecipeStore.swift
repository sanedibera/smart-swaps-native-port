import Foundation
import SwiftUI
import SmartSwapsKit

/// Port of `app/useRecipes.ts`'s React wrapper (295 ln total; the pure math is
/// `SmartSwapsKit.RecipeMath`). Session-cached like `FoodsStore`, and depends on it for
/// `allFoods` the same way the RN hook depends on `useFoods()`.
@MainActor
public final class RecipeStore: ObservableObject {
    public static let shared = RecipeStore()

    @Published public private(set) var recipes: [Recipe] = []
    @Published public private(set) var isLoaded = false

    private init() {}

    public func load(foodsStore: FoodsStore = .shared) {
        guard !isLoaded else { return }
        guard foodsStore.isLoaded else {
            assertionFailure("RecipeStore.load() called before FoodsStore finished loading")
            return
        }
        do {
            let raw = try DatabaseService.shared.getAllRecipes()
            recipes = RecipeMath.hydrateRecipes(raw, foods: foodsStore.byId)
            isLoaded = true
        } catch {
            assertionFailure("RecipeStore.load() failed: \(error)")
        }
    }

    public func findRecipesForFood(_ foodId: String) -> [Recipe] {
        recipes.filter { recipe in recipe.ingredients.contains { $0.food_id == foodId } }
    }
}
