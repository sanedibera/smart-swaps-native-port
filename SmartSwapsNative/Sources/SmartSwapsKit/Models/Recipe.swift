import Foundation

/// `app/types.ts` `RecipeIngredient` - the hydrated shape (raw DB row + resolved food +
/// parsed grams + scaled nutrients), built by `RecipeMath.hydrateRecipes`.
public struct RecipeIngredient: Identifiable {
    public var id: String { raw_text }
    public var raw_text: String
    public var food_id: String?
    public var food: FoodItem?
    public var grams: Double
    public var kcal: Double
    public var nutrients: FoodNutrients?

    public init(raw_text: String, food_id: String?, food: FoodItem?, grams: Double,
                kcal: Double, nutrients: FoodNutrients?) {
        self.raw_text = raw_text
        self.food_id = food_id
        self.food = food
        self.grams = grams
        self.kcal = kcal
        self.nutrients = nutrients
    }
}

/// `app/types.ts` `Recipe` - the hydrated shape `useRecipes.ts` builds from `RecipeRaw`.
public struct Recipe: Identifiable {
    public var id: String
    public var name: String
    public var url: String
    public var image: String?
    public var serves: Int
    public var subcategory: String
    public var dish_type: String
    public var ingredients: [RecipeIngredient]
    public var steps: [String]
    public var totals: FoodNutrients
    public var health_score: Int
    public var kcal_total: Double
    public var time: String?
    public var difficulty: String?

    public init(id: String, name: String, url: String, image: String?, serves: Int,
                subcategory: String, dish_type: String, ingredients: [RecipeIngredient],
                steps: [String], totals: FoodNutrients, health_score: Int, kcal_total: Double,
                time: String?, difficulty: String?) {
        self.id = id
        self.name = name
        self.url = url
        self.image = image
        self.serves = serves
        self.subcategory = subcategory
        self.dish_type = dish_type
        self.ingredients = ingredients
        self.steps = steps
        self.totals = totals
        self.health_score = health_score
        self.kcal_total = kcal_total
        self.time = time
        self.difficulty = difficulty
    }
}
