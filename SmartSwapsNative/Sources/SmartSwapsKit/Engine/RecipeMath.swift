import Foundation

/// Port of the pure functions in `app/useRecipes.ts` (295 ln) - not itself one of
/// `app/engine/`'s files (it's a hook module), but deterministic and side-effect-free
/// the same way, so it lives alongside the other engine ports rather than in a view/store.
/// `RecipesStore` (the app-target `State/` layer) wraps `hydrateRecipes` with the session
/// cache `useRecipes.ts` keeps at module scope.
public enum RecipeMath {
    private static let unitToGrams: [String: Double] = [
        "tbsp": 15, "tablespoon": 15, "tablespoons": 15,
        "tsp": 5, "teaspoon": 5, "teaspoons": 5,
        "cup": 240, "cups": 240,
        "ml": 1, "milliliter": 1, "milliliters": 1,
        "l": 1000, "liter": 1000, "liters": 1000,
        "g": 1, "gram": 1, "grams": 1,
        "kg": 1000, "kilogram": 1000, "kilograms": 1000,
        "oz": 28.35, "ounce": 28.35, "ounces": 28.35,
        "lb": 453.6, "pound": 453.6, "pounds": 453.6,
        "egg": 55, "eggs": 55,
        "onion": 110, "onions": 110,
        "clove": 5, "cloves": 5,
        "slice": 30, "slices": 30,
        "handful": 30, "handfuls": 30,
        "bunch": 50, "bunches": 50,
        "pinch": 1, "pinches": 1,
        "can": 400, "cans": 400,
        "jar": 300, "jars": 300,
    ]

    private static let fractionMap: [(String, String)] = [
        ("½", "0.5"), ("¼", "0.25"), ("¾", "0.75"), ("⅓", "0.333"), ("⅔", "0.667"),
    ]

    private static let unitPattern = JSRegex(
        #"(\d+\.?\d*)\s*(tbsp|tablespoon|tsp|teaspoon|cup|ml|l\b|kg|g\b|gram|oz|ounce|lb|pound|egg|onion|clove|slice|handful|bunch|pinch|can|jar)"#,
        "i")
    private static let leadingNumberPattern = JSRegex(#"^(\d+\.?\d*)\s"#)

    /// "200g spinach", "1 tbsp olive oil", "2 eggs" -> grams. Ported verbatim from
    /// `useRecipes.ts`'s `parseGrams`, JSRegex throughout for JS `\b` semantics.
    public static func parseGrams(_ raw: String) -> Double {
        if raw.isEmpty { return 50 }
        var text = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for (frac, val) in fractionMap {
            text = text.replacingOccurrences(of: frac, with: val)
        }
        text = text.replacingOccurrences(of: ",", with: ".")

        if let m = unitPattern.match(text), let qtyStr = m[1], let unit = m[2] {
            let qty = Double(qtyStr) ?? 0
            let gramsPerUnit = unitToGrams[unit.lowercased()] ?? 1
            return JSNumber.round(qty * gramsPerUnit)
        }

        if let m = leadingNumberPattern.match(text), let qtyStr = m[1] {
            let qty = Double(qtyStr) ?? 0
            if qty <= 10 { return JSNumber.round(qty * 30) }
            return JSNumber.round(qty)
        }

        return 50
    }

    public static func emptyNutrients() -> FoodNutrients { FoodNutrients() }

    public static func scaleNutrients(_ n: FoodNutrients, grams: Double) -> FoodNutrients {
        let f = grams / 100
        var out = FoodNutrients()
        out.kcal = n.kcal * f
        out.protein_g = n.protein_g * f
        out.carbs_g = n.carbs_g * f
        out.sugars_g = n.sugars_g * f
        out.fat_g = n.fat_g * f
        out.saturated_fat_g = n.saturated_fat_g * f
        out.fiber_g = n.fiber_g * f
        out.salt_g = n.salt_g * f
        for key in Micros.keysInDeclarationOrder {
            out.micros[key] = n.micros[key] * f
        }
        return out
    }

    public static func addNutrients(_ a: FoodNutrients, _ b: FoodNutrients) -> FoodNutrients {
        var out = FoodNutrients()
        out.kcal = a.kcal + b.kcal
        out.protein_g = a.protein_g + b.protein_g
        out.carbs_g = a.carbs_g + b.carbs_g
        out.sugars_g = a.sugars_g + b.sugars_g
        out.fat_g = a.fat_g + b.fat_g
        out.saturated_fat_g = a.saturated_fat_g + b.saturated_fat_g
        out.fiber_g = a.fiber_g + b.fiber_g
        out.salt_g = a.salt_g + b.salt_g
        for key in Micros.keysInDeclarationOrder {
            out.micros[key] = a.micros[key] + b.micros[key]
        }
        return out
    }

    public static func divideNutrients(_ n: FoodNutrients, by divisor: Double) -> FoodNutrients {
        if divisor == 0 { return n }
        return scaleNutrients(n, grams: 100 / divisor)
    }

    /// Step-count/ingredient-count heuristic, `useRecipes.ts`'s `estimateTimeDifficulty`.
    public static func estimateTimeDifficulty(steps: [String], linkedIngredientCount: Int) -> (time: String, difficulty: String) {
        let stepCount = steps.count
        let totalLength = steps.joined().count
        let difficulty = (linkedIngredientCount >= 7 || totalLength > 600) ? "Medium" : "Easy"
        let minutes = 10 + stepCount * 5 + linkedIngredientCount * 2
        let time: String
        if minutes < 60 {
            time = "\(minutes) min"
        } else {
            let hours = (Double(minutes) / 60 * 10).rounded() / 10
            time = "\(JSNumber.toString(hours)) hr"
        }
        return (time, difficulty)
    }

    /// `useRecipes.ts`'s `useEffect` hydration body, minus the React caching wrapper
    /// (that's `RecipesStore`'s job). `foods` is keyed by id, matching the JS `Map`.
    public static func hydrateRecipes(_ raw: [RecipeRaw], foods: [String: FoodItem]) -> [Recipe] {
        raw.map { r in
            let ingredients: [RecipeIngredient] = r.ingredients.map { ing in
                let grams = parseGrams(ing.raw_text)
                let food = ing.food_id.flatMap { foods[$0] }
                let scaled = food.map { scaleNutrients($0.nutrients_per_100, grams: grams) }
                return RecipeIngredient(raw_text: ing.raw_text, food_id: ing.food_id, food: food,
                                         grams: grams, kcal: scaled?.kcal ?? 0, nutrients: scaled)
            }

            let totalRaw = ingredients.reduce(emptyNutrients()) { acc, ing in
                guard let n = ing.nutrients else { return acc }
                return addNutrients(acc, n)
            }

            let serves = r.serves > 0 ? r.serves : 1
            let totals = divideNutrients(totalRaw, by: Double(serves))

            let linked = ingredients.filter { $0.food != nil && $0.kcal > 0 }
            let totalKcal = linked.reduce(0.0) { $0 + $1.kcal }
            let healthScore = totalKcal > 0
                ? JSNumber.roundToInt(linked.reduce(0.0) { $0 + Double($1.food!.health_score) * $1.kcal } / totalKcal)
                : 50

            let linkedIngredientCount = (r.ingredients).filter { $0.food_id != nil }.count
            let (time, difficulty) = estimateTimeDifficulty(steps: r.steps, linkedIngredientCount: linkedIngredientCount)

            return Recipe(id: r.id, name: r.name, url: r.url, image: r.image, serves: r.serves,
                           subcategory: r.subcategory, dish_type: r.dish_type, ingredients: ingredients,
                           steps: r.steps, totals: totals, health_score: healthScore,
                           kcal_total: totals.kcal, time: time, difficulty: difficulty)
        }
    }
}
