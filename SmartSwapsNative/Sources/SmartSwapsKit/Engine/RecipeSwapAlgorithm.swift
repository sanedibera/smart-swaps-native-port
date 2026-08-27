import Foundation

/// Port of `app/engine/recipeSwapAlgorithm.ts` (177 ln) - recipe-specific ingredient swap
/// matching, deliberately a different pipeline from `SwapAlgorithm.findBestSwaps` (see the
/// source's own header on functional-role matching vs. general nutrient-similarity ranking).
/// See `FoodVectors.swift`'s header on why this file is ported despite PORTING_INVENTORY.md
/// calling it deleted - it exists in the tree actually being ported.
public enum RecipeSwapAlgorithm {
    public enum CulinaryRole: String {
        case fat = "FAT", sweetener = "SWEETENER", chemicalLeavening = "CHEMICAL_LEAVENING",
             yeast = "YEAST", egg = "EGG", dairyLiquid = "DAIRY_LIQUID", flourStarch = "FLOUR_STARCH",
             protein = "PROTEIN", seasoning = "SEASONING", vegetable = "VEGETABLE", fruit = "FRUIT", other = "OTHER"
    }

    private static let coarseRoles: Set<CulinaryRole> = [.vegetable, .fruit, .other]

    private static let roleKeywords: [(CulinaryRole, [String])] = [
        (.fat, ["oil", "butter", "margarine", "lard", "shortening"]),
        (.sweetener, ["sugar", "honey", "syrup", "sweetener", "agave"]),
        (.chemicalLeavening, ["baking powder", "baking soda", "bicarbonate"]),
        (.yeast, ["yeast"]),
        (.egg, ["egg"]),
        (.dairyLiquid, ["milk", "cream", "buttermilk"]),
        (.flourStarch, ["flour", "starch", "cornflour", "cornstarch"]),
        (.protein, ["chicken", "beef", "pork", "turkey", "fish", "salmon", "tuna", "tofu", "lentil", "bean", "mince", "sausage"]),
        (.seasoning, ["salt", "pepper", "spice", "herb", "seasoning", "vanilla", "cinnamon"]),
    ]

    /// A name match alone isn't enough for these roles - real data had compound/prepared
    /// items (a "Garlic in oil, canned" or a mushroom called "milk cap") name-match a role
    /// unrelated to them. Require the top-level category to NOT be one of these too.
    private static let categoryExcludeForRole: [CulinaryRole: Set<String>] = [
        .fat: ["Vegetables", "Fruit", "Soups and stocks", "Prepared dishes", "Potatoes and starches"],
        .dairyLiquid: ["Vegetables", "Fruit", "Soups and stocks", "Prepared dishes", "Potatoes and starches"],
    ]

    private static let roleRegexes: [CulinaryRole: JSRegex] = {
        var out: [CulinaryRole: JSRegex] = [:]
        for (role, keywords) in roleKeywords {
            let escaped = keywords.map { NSRegularExpression.escapedPattern(for: $0) }
            out[role] = JSRegex(#"\b(?:"# + escaped.joined(separator: "|") + #")\b"#)
        }
        return out
    }()

    /// Best-effort functional role for an ingredient. Falls back to the food's broad
    /// category (vegetable/fruit) and finally OTHER - see `coarseRoles` for why those three
    /// buckets never actually produce a swap suggestion.
    public static func getCulinaryRole(_ food: FoodItem) -> CulinaryRole {
        let name = food.name.lowercased()
        let topCategory = String(food.swiss_category.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")

        for (role, _) in roleKeywords {
            guard let regex = roleRegexes[role], regex.test(name) else { continue }
            if let excluded = categoryExcludeForRole[role], excluded.contains(topCategory) { continue }
            return role
        }

        if topCategory == "Vegetables" { return .vegetable }
        if topCategory == "Fruit" { return .fruit }
        return .other
    }

    public struct RecipeSwapResult {
        public let candidate: FoodItem
        public let score: Double
        public let vectorSimilarity: Double
    }

    private static let minHealthImprovement = 10.0

    /// Finds the single best recipe-appropriate swap for an ingredient, or `nil` if nothing
    /// clears the bar - including "this ingredient's role isn't precise enough to trust
    /// automatically" (`coarseRoles`). Returning `nil` on purpose is the point.
    public static func findBestRecipeSwap(_ ingredientFood: FoodItem, _ allFoods: [FoodItem],
                                           _ dietaryPreference: [String] = ["Balanced"]) -> RecipeSwapResult? {
        if ingredientFood.health_score >= 75 { return nil }

        let role = getCulinaryRole(ingredientFood)
        if coarseRoles.contains(role) { return nil }

        let targetIsLiquid = SwapAlgorithm.isLiquid(ingredientFood)
        let targetIsRaw = SwapAlgorithm.isRawIngredient(ingredientFood)

        var candidates = allFoods.filter { f in
            f.id != ingredientFood.id
                && f.health_score >= ingredientFood.health_score + Int(minHealthImprovement)
                && getCulinaryRole(f) == role
                && SwapAlgorithm.isLiquid(f) == targetIsLiquid
                && SwapAlgorithm.isRawIngredient(f) == targetIsRaw
        }

        if dietaryPreference.contains("Vegetarian") {
            candidates = candidates.filter { $0.category != "Meat" && $0.category != "Fish" }
        }
        if dietaryPreference.contains("Vegan") {
            candidates = candidates.filter { $0.category != "Meat" && $0.category != "Fish" && $0.category != "Dairy" }
        }

        var best: RecipeSwapResult?
        for candidate in candidates {
            var score = SwapAlgorithm.evaluateSwap(ingredientFood, candidate)

            let features = SwapRanker.extractSwapFeatures(ingredientFood, candidate, cosineSim: nil,
                                                            liquidMismatch: 0, rawIngredientMismatch: 0)
            score = SwapRanker.combineWithExistingScore(score, SwapRanker.predictSwapQuality(features))

            let vectorSimilarity = FoodVectors.computeVectorSimilarity(ingredientFood, candidate)
            score *= 0.7 + 0.6 * vectorSimilarity

            if best == nil || score > best!.score {
                best = RecipeSwapResult(candidate: candidate, score: score, vectorSimilarity: vectorSimilarity)
            }
        }

        return best
    }
}
