import Foundation

/// Port of `app/engine/swapAlgorithm.ts`.
///
/// The extensive rationale comments in the source (why isLiquid checks the name only,
/// why OILS_FATS is category-only, why the meat name check keeps its ungated form) are
/// load-bearing documentation of measurements already made. They are preserved in
/// abbreviated form here; the TS file remains the full record.
public enum SwapAlgorithm {

    static let STOP_WORDS: Set<String> = ["and", "the", "with", "organic", "raw", "fried",
                                          "without", "fat", "pan", "in", "of", "for", "a"]
    static let UNSWEETENED_KEYWORDS = ["zero", "diet", "plain", "unsweetened", "no sugar"]
    static let SWEETENED_KEYWORDS = ["sweet", "sugar", "syrup", "honey", "sweetened",
                                     "chocolate", "candy", "pastry", "cola", "cookie", "cake"]
    static let LIQUID_KEYWORDS = ["drink", "juice", "beverage", "milk", "soda", "water",
                                  "cola", "liquid", "tea", "coffee", "stock", "broth",
                                  "cream", "sahne"]
    static let RESTRICTED_KEYWORDS = ["alcohol", "beer", "wine", "energy drink", "liquor",
                                      "vodka", "rum", "whiskey", "spirit"]
    static let RAW_INGREDIENT_KEYWORDS = ["flour", "starch", "dried", "powder"]

    private static let reNonAlnum = JSRegex("[^a-z0-9 ]", "g")

    static func normalizeString(_ str: String) -> [String] {
        let cleaned = reNonAlnum.replaceAll(str.lowercased(), "")
        return cleaned.split(separator: " ", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { $0.count > 2 && !STOP_WORDS.contains($0) }
    }

    /// Word-boundary keyword match. Every keyword-list check in this file goes through it
    /// rather than a substring test: measured collisions include "tea" in "steak" (73
    /// foods), "cola" in "chocolate" (232), "cream" in "cream cheese" (151), "cake" in
    /// "pancake" (38). The regex is built once per list and cached, as in the source -
    /// two full passes over the 7,140-food database cost 148ms of regex compilation
    /// before that change and 8ms after.
    private static func makeKeywordRegex(_ keywords: [String]) -> JSRegex {
        let escaped = keywords.map { DietaryFilter.escapeRegex($0) }
        return JSRegex("\\b(?:" + escaped.joined(separator: "|") + ")\\b")
    }

    private static let reUnsweetened = makeKeywordRegex(UNSWEETENED_KEYWORDS)
    private static let reSweetened = makeKeywordRegex(SWEETENED_KEYWORDS)
    private static let reLiquid = makeKeywordRegex(LIQUID_KEYWORDS)
    private static let reRestricted = makeKeywordRegex(RESTRICTED_KEYWORDS)
    private static let reRawIngredient = makeKeywordRegex(RAW_INGREDIENT_KEYWORDS)

    @inline(__always)
    private static func contains(_ str: String, _ re: JSRegex) -> Bool { re.test(str.lowercased()) }

    /// Deliberately checks the food's own NAME only, not category text. Category labels
    /// are broad umbrellas - "Milk, cream and cheese" covers liquid milk AND solid
    /// cheese, so matching keywords against that shared label made Whipping cream and
    /// Mozzarella both register as liquid.
    public static func isLiquid(_ food: FoodItem) -> Bool { contains(food.name, reLiquid) }

    public static func isRawIngredient(_ food: FoodItem) -> Bool {
        contains(food.name, reRawIngredient)
    }

    static func isRestricted(_ food: FoodItem) -> Bool {
        contains(food.name, reRestricted)
            || contains("\(food.category) \(food.swiss_category)", reRestricted)
    }

    static let MEAT_KEYWORDS = ["meat", "poultry", "mince", "sausage"]
    static let OILS_FATS_KEYWORDS = ["fat", "fats", "oil", "oils"]
    static let DAIRY_KEYWORDS = ["milk", "dairy", "cheese", "yoghurt"]
    static let GRAINS_KEYWORDS = ["cereal", "bread", "pasta", "rice", "grain"]
    static let VEG_KEYWORDS = ["vegetable"]
    static let PLANT_ALT_KEYWORDS = ["vegan", "plant-based", "plant based", "tofu",
                                     "seitan", "soy", "soya", "texturised", "texturized"]
    static let FRUIT_KEYWORDS = ["fruit"]
    static let SWEETS_KEYWORDS = ["sweet", "sugar", "chocolate"]
    static let BEVERAGES_KEYWORDS = ["beverage", "drink", "juice"]

    private static let reMeat = makeKeywordRegex(MEAT_KEYWORDS)
    private static let reOilsFats = makeKeywordRegex(OILS_FATS_KEYWORDS)
    private static let reDairy = makeKeywordRegex(DAIRY_KEYWORDS)
    private static let reGrains = makeKeywordRegex(GRAINS_KEYWORDS)
    private static let reVeg = makeKeywordRegex(VEG_KEYWORDS)
    private static let rePlantAlt = makeKeywordRegex(PLANT_ALT_KEYWORDS)
    private static let reFruit = makeKeywordRegex(FRUIT_KEYWORDS)
    private static let reSweets = makeKeywordRegex(SWEETS_KEYWORDS)
    private static let reBeverages = makeKeywordRegex(BEVERAGES_KEYWORDS)

    /// Maps broad Swiss categories to equivalence groups so vegan swaps for dairy/meat
    /// stay reachable. Order matters and is measured - see the source for each case.
    static func getEquivalenceGroup(_ swissCategory: String, _ name: String) -> String {
        let lowerCat = swissCategory.lowercased()

        // Meat MUST come before oils/fats: "Meat and meat products/Fat and offal" is a
        // meat subcategory whose own string contains "fat".
        if contains(lowerCat, reMeat) || contains(name, reMeat) { return "MEAT_ALT" }

        // OILS_FATS is decided by CATEGORY ONLY. In this dataset "fat"/"oil" appear in
        // names as nutritional descriptors far more often than as food identity
        // ("Yogurt mild, min. 3.5 % fat"). Checking the name routed 1,096 foods here
        // that do not belong.
        if contains(lowerCat, reOilsFats) { return "OILS_FATS" }

        // Unlike MEAT_ALT, the dairy name check is almost pure noise, so it is gated on a
        // plant-alternative marker: 292 name-only matches drop to 6, all genuine.
        if contains(lowerCat, reDairy) || (contains(name, reDairy) && contains(name, rePlantAlt)) {
            return "DAIRY_ALT"
        }
        if contains(lowerCat, reGrains) { return "GRAINS" }
        if contains(lowerCat, reVeg) || contains(name, reVeg) { return "VEG" }
        if contains(lowerCat, reFruit) { return "FRUIT" }
        if contains(lowerCat, reSweets) { return "SWEETS" }
        if contains(lowerCat, reBeverages) { return "BEVERAGES" }

        // Default to the first part of the swiss category string.
        return String(lowerCat.split(separator: "/", omittingEmptySubsequences: false).first ?? "")
    }

    public struct SwapResult {
        public let candidate: FoodItem
        public var score: Double
        public init(candidate: FoodItem, score: Double) {
            self.candidate = candidate
            self.score = score
        }
    }

    /// Foods the labeling pass called `raw_produce` - 278 whole, minimally processed
    /// fruit and veg.
    private static let RAW_PRODUCE_ROLE = FoodAttributesStore.ROLE_LABELS.firstIndex(of: "raw_produce") ?? -1
    /// Only suppress produce that is ALSO in good shape. "Banana dried" (47) and
    /// "Carrot pickled" (58) keep their suggestions; fresh produce sits well above.
    private static let WHOLE_FOOD_MIN_SCORE = 65.0

    public enum SwapSuppressionReason: String { case already_healthy, whole_food }

    /// Why we are DELIBERATELY not suggesting swaps for this food, or nil if we would.
    ///
    /// "No swaps" has two different meanings and the UI was showing one message for both.
    /// Measured on real receipt data: 37 of 51 raw-produce items scanned were getting
    /// suggestions, and cucumber, tomato, courgette, lettuce and spinach ALL resolved to
    /// "Curly kale raw".
    public static func swapSuppressionReason(_ food: FoodItem) -> SwapSuppressionReason? {
        if food.health_score >= 80 { return .already_healthy }
        if let attrs = FoodAttributesStore.getAttributes(food.id),
           attrs.culinaryRole == RAW_PRODUCE_ROLE,
           food.health_score >= WHOLE_FOOD_MIN_SCORE {
            return .whole_food
        }
        return nil
    }

    public static func evaluateSwap(_ currentFood: FoodItem, _ candidate: FoodItem) -> Double {
        var score = 0.0

        // 1. Core health score jumps
        let scoreDiff = candidate.health_score - currentFood.health_score
        if scoreDiff > 0 {
            score += sqrt(scoreDiff) * 5
            if scoreDiff >= 10 && scoreDiff <= 40 { score += 40 }
        }

        // 2. Exact Swiss category match
        if currentFood.swiss_category == candidate.swiss_category { score += 300 }

        // 3. Name overlap
        let currentWords = normalizeString(currentFood.name)
        let candidateWords = normalizeString(candidate.name)
        let overlap = currentWords.filter { candidateWords.contains($0) }.count
        if overlap > 0 { score += Double(overlap) * 150 }

        // Sweet-to-unsweet bonus. The original tested !containsKeywords(UNSWEETENED),
        // true for almost every name, giving a spurious +150 to nearly every pair.
        let currentIsSweet = contains(currentFood.name, reSweetened)
        let candidateIsUnsweet = contains(candidate.name, reUnsweetened)
        if currentIsSweet && candidateIsUnsweet { score += 150 }

        // 4. Targeted macro optimisation by category group
        let group = getEquivalenceGroup(currentFood.swiss_category, currentFood.name)
        let currNutrients = currentFood.nutrients_per_100
        let candNutrients = candidate.nutrients_per_100

        if group == "OILS_FATS" {
            let satFatDiff = currNutrients.saturated_fat_g - candNutrients.saturated_fat_g
            score += satFatDiff * 15
        } else if group == "DAIRY_ALT" {
            let sugarDiff = currNutrients.sugars_g - candNutrients.sugars_g
            let fatDiff = currNutrients.fat_g - candNutrients.fat_g
            score += sugarDiff * 8
            score += fatDiff * 6
            // Dairy is a primary calcium source - a plant alternative that quietly drops
            // calcium is a real downside of this exact swap category.
            let calciumDiff = candNutrients.micros.calcium_mg - currNutrients.micros.calcium_mg
            score += (calciumDiff / 50) * 4
        } else if group == "MEAT_ALT" {
            let proteinDiff = candNutrients.protein_g - currNutrients.protein_g
            let satFatDiff = currNutrients.saturated_fat_g - candNutrients.saturated_fat_g
            score += proteinDiff * 8
            score += satFatDiff * 10
            let ironDiff = candNutrients.micros.iron_mg - currNutrients.micros.iron_mg
            score += ironDiff * 8
        } else {
            let sugarDiff = currNutrients.sugars_g - candNutrients.sugars_g
            score += (sugarDiff > 0 ? sugarDiff * 4 : sugarDiff * 2)
        }

        // Salt and fibre matter for every category.
        let saltDiff = currNutrients.salt_g - candNutrients.salt_g
        let fiberDiff = candNutrients.fiber_g - currNutrients.fiber_g
        score += saltDiff * ((group == "OILS_FATS" || group == "DAIRY_ALT") ? 12 : 20)
        score += fiberDiff * 5

        // 5. Calorie parity
        let currentKcal = JSNumber.or(currNutrients.kcal, 1)
        let candKcal = candNutrients.kcal
        let kcalRatio = candKcal / currentKcal
        if kcalRatio >= 0.8 && kcalRatio <= 1.2 { score += 40 }
        if kcalRatio > 1.5 || kcalRatio < 0.5 { score -= 100 }

        return score
    }

    /// Policy knobs for callers whose context changes what counts as a swap worth
    /// offering. NOT a second algorithm - only these two gates move.
    public struct SwapPolicy {
        /// Minimum health-score gain a candidate must offer. Default 10.
        public var minImprovement: Double?
        /// Consider whole produce that swapSuppressionReason() would silence. Default false.
        public var allowWholeFoods: Bool
        public init(minImprovement: Double? = nil, allowWholeFoods: Bool = false) {
            self.minImprovement = minImprovement
            self.allowWholeFoods = allowWholeFoods
        }
        public static let none = SwapPolicy()
    }

    public static func findBestSwaps(
        _ badFood: FoodItem,
        _ allFoods: [FoodItem],
        _ count: Int = 3,
        _ dietaryPreference: [String] = ["Balanced"],
        _ policy: SwapPolicy = .none
    ) -> [SwapResult] {
        let minImprovement = policy.minImprovement ?? 10

        let suppression = swapSuppressionReason(badFood)
        if let suppression, !(suppression == .whole_food && policy.allowWholeFoods) {
            return []
        }

        let targetGroup = getEquivalenceGroup(badFood.swiss_category, badFood.name)
        let targetIsLiquid = isLiquid(badFood)

        // Base pool: every filter that has NOTHING to do with category taxonomy.
        // Applied as four sequential passes, exactly as the source does, because the
        // resulting element ORDER feeds the tie-breaks below.
        var basePool = allFoods.filter {
            $0 !== badFood && $0.health_score >= badFood.health_score + minImprovement
        }
        basePool = basePool.filter { isLiquid($0) == targetIsLiquid }
        basePool = basePool.filter { DietaryFilter.isAllowedForDiet($0, dietaryPreference) }
        basePool = basePool.filter { !isRestricted($0) }

        // Strict categorisation filter.
        let strictCandidates = basePool.filter { f in
            if f.swiss_category == badFood.swiss_category { return true }
            let candGroup = getEquivalenceGroup(f.swiss_category, f.name)
            if candGroup == targetGroup {
                let broadGroups = ["VEG", "FRUIT", "GRAINS", "SWEETS", "SNACKS"]
                if broadGroups.contains(targetGroup) {
                    // Require them to be much closer, like same subcategory.
                    let fParts = f.swiss_category.split(separator: "/", omittingEmptySubsequences: false)
                    let bParts = badFood.swiss_category.split(separator: "/", omittingEmptySubsequences: false)
                    let fSub = fParts.count > 1 ? String(fParts[1]) : nil
                    let bSub = bParts.count > 1 ? String(bParts[1]) : nil
                    // JS: `return fSub && bSub && fSub === bSub` - an undefined or an
                    // empty-string subcategory is falsy and fails the test.
                    guard let fSub, let bSub, !fSub.isEmpty, !bSub.isEmpty else { return false }
                    return fSub == bSub
                }
                return true
            }
            return false
        }

        // Hand-tuned score, kept only as a deterministic tiebreak below.
        var scoredCandidates = strictCandidates.map {
            SwapResult(candidate: $0, score: evaluateSwap(badFood, $0))
        }

        // Learned ranker layer. The model's probability IS the score; evaluateSwap is
        // still computed as a stable tiebreak when two candidates score identically
        // (common for near-duplicate BLS preparation variants), because without it their
        // order depends on filter order and can change between runs.
        var handScore = [String: Double](minimumCapacity: scoredCandidates.count)
        let badIsLiquid = isLiquid(badFood)
        let badIsRaw = isRawIngredient(badFood)
        for i in scoredCandidates.indices {
            let sc = scoredCandidates[i]
            handScore[sc.candidate.id] = sc.score
            let liquidMismatch = badIsLiquid != isLiquid(sc.candidate) ? 1 : 0
            let rawIngredientMismatch = badIsRaw != isRawIngredient(sc.candidate) ? 1 : 0
            let cosineSim = FoodEmbeddings.embeddingCosine(badFood.id, sc.candidate.id)
            let features = SwapGbm.extractGbmFeatures(
                source: badFood, candidate: sc.candidate, cosineSim: cosineSim,
                liquidMismatch: liquidMismatch, rawIngredientMismatch: rawIngredientMismatch)
            scoredCandidates[i].score = SwapGbm.predictSwapQualityGbm(features)
        }

        let sorted = JSSort.sorted(scoredCandidates) { a, b in
            JSNumber.or(b.score - a.score,
                        (handScore[b.candidate.id] ?? 0) - (handScore[a.candidate.id] ?? 0))
        }
        return Array(sorted.prefix(count))
    }

    /// Async variant that also applies the on-device personal preference layer.
    public static func findBestSwapsPersonalized(
        _ badFood: FoodItem,
        _ allFoods: [FoodItem],
        _ count: Int = 3,
        _ dietaryPreference: [String] = ["Balanced"]
    ) async -> [SwapResult] {
        // Pull more candidates than needed since personalization can reorder the ranking.
        let base = findBestSwaps(badFood, allFoods, count * 3, dietaryPreference)
        var personalized: [SwapResult] = []
        for r in base {
            let adjusted = await PersonalSwapPreferences.shared.applyPersonalPreference(
                r.score, r.candidate.swiss_category, r.candidate.id)
            personalized.append(SwapResult(candidate: r.candidate, score: adjusted))
        }
        let sorted = JSSort.sorted(personalized) { a, b in b.score - a.score }
        return Array(sorted.prefix(count))
    }
}
