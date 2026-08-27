import Foundation

/// Port of `app/engine/culinaryFilter.ts`.
///
/// NOT a second ranking algorithm. findBestSwaps stays the single engine that decides
/// what is nutritionally better; this runs on top of its ranked output for the recipe
/// screen and answers a question ranking cannot - would a cook accept this substitution
/// in THIS dish? Candidates are vetoed, never re-scored.
public enum CulinaryFilter {

    public enum CulinaryFunction: String {
        case FAT, SWEETENER, CHEMICAL_LEAVENING, YEAST, EGG, DAIRY_LIQUID, FLOUR_STARCH, NONE
    }

    /// Iteration order is the JS object key order and decides which function wins when a
    /// name matches more than one.
    private static let FUNCTION_ORDER: [CulinaryFunction] = [
        .FAT, .SWEETENER, .CHEMICAL_LEAVENING, .YEAST, .EGG, .DAIRY_LIQUID, .FLOUR_STARCH,
    ]

    private static let FUNCTION_KEYWORDS: [CulinaryFunction: [String]] = [
        .FAT: ["oil", "butter", "margarine", "lard", "shortening"],
        // The sugar alcohols and syrup sugars are here because they are the substitutes
        // that matter most for this role and none contains the word "sugar": without them
        // "Sugar white" -> "Xylitol powder (E 967)" would be vetoed as a function mismatch.
        .SWEETENER: ["sugar", "honey", "syrup", "sweetener", "agave", "xylitol", "sorbitol",
                     "mannitol", "erythritol", "stevia", "molasses", "treacle", "dextrose",
                     "glucose", "fructose", "maltose", "lactose", "saccharin", "aspartame"],
        .CHEMICAL_LEAVENING: ["baking powder", "baking soda", "bicarbonate"],
        .YEAST: ["yeast"],
        .EGG: ["egg"],
        .DAIRY_LIQUID: ["milk", "cream", "buttermilk"],
        .FLOUR_STARCH: ["flour", "starch", "cornflour", "cornstarch"],
    ]

    /// A name keyword is never enough on its own - a name mentions an ingredient far more
    /// often than it IS that ingredient. This is what stops "Pink salmon in oil, canned"
    /// claiming FAT, which is how every cooking oil once got swapped for canned fish.
    private static let FUNCTION_CATEGORIES: [CulinaryFunction: [String]] = [
        .FAT: ["Fats and oils"],
        .SWEETENER: ["Sugar, honey and confectionery"],
        .CHEMICAL_LEAVENING: ["Seasonings and condiments"],
        .YEAST: ["Seasonings and condiments"],
        .EGG: ["Cereals and cereal products"],
        .DAIRY_LIQUID: ["Milk and dairy products", "Legumes, nuts and seeds"],
        .FLOUR_STARCH: ["Cereals and cereal products", "Potatoes and starches"],
    ]

    /// A keyword followed by one of these describes what a food was made with, without,
    /// or in the style of - not what it is. "Fruit gum sugar-free" is a sweet.
    private static let NEGATING_QUALIFIERS = ["free", "coated", "cured", "reduced", "based",
                                              "flavoured", "flavored", "style"]

    private static let FUNCTION_REGEXES: [CulinaryFunction: JSRegex] = {
        var out: [CulinaryFunction: JSRegex] = [:]
        for fn in FUNCTION_ORDER {
            let kws = FUNCTION_KEYWORDS[fn]!.map { DietaryFilter.escapeRegex($0) }
            out[fn] = JSRegex("\\b(?:" + kws.joined(separator: "|") + ")\\b(?!-(?:"
                              + NEGATING_QUALIFIERS.joined(separator: "|") + ")\\b)")
        }
        return out
    }()

    /// Past one of these a food name stops describing the food and starts listing what
    /// went into it: "Jam extra quality, WITH fructose..." is jam. Truncating at the
    /// boundary beat a "keyword must be in the first N words" rule, which at N=3 also
    /// discarded "Durum wheat wholemeal flour" and "Vegetable deep-frying oil".
    private static let DESCRIPTION_BOUNDARY = JSRegex("\\b(?:made from|with|from|containing|fortified)\\b")

    /// The job an ingredient does in a recipe, or NONE.
    public static func getCulinaryFunction(_ food: FoodItem) -> CulinaryFunction {
        let fullName = food.name.lowercased()
        let boundary = DESCRIPTION_BOUNDARY.search(fullName)
        let name: String
        if boundary == -1 {
            name = fullName
        } else {
            // `search` returns a UTF-16 offset, matching JS's String.prototype.search.
            let u = Array(fullName.utf16)
            name = String(decoding: u[0..<boundary], as: UTF16.self)
        }
        let topCategory = String(food.swiss_category.split(separator: "/", omittingEmptySubsequences: false).first ?? "")
        for fn in FUNCTION_ORDER {
            guard FUNCTION_REGEXES[fn]!.test(name) else { continue }
            guard FUNCTION_CATEGORIES[fn]!.contains(topCategory) else { continue } // mentions it, is not it
            return fn
        }
        return .NONE
    }

    /// Within FAT, pourable oil and solid fat are not interchangeable, and nothing
    /// upstream separates them - isLiquid has no entry for "oil", so an oil and a stick of
    /// butter both read as non-liquid.
    private static let SOLID_FAT_MARKERS = JSRegex("\\b(?:butter|margarine|lard|shortening|spread|tallow)\\b")
    private static let reOils = JSRegex("\\boils?\\b")

    private static func isPourableOil(_ food: FoodItem) -> Bool {
        let name = food.name.lowercased()
        return reOils.test(name) && !SOLID_FAT_MARKERS.test(name)
    }

    // Indexes into FoodAttributes.sensory: sweet, salty, sour, bitter, umami, fatty_rich,
    // creamy, crunchy. sour and bitter are deliberately absent from TASTE_AXES - they are
    // degenerate in this asset (86% and 91% of foods share one value).
    private static let SWEET = 0, SALTY = 1, UMAMI = 4, FATTY = 5, CREAMY = 6
    private static let TASTE_AXES = [SWEET, SALTY, UMAMI, FATTY, CREAMY]

    /// Calibrated against hand-labelled pairs, not picked by feel. A tight global limit
    /// vetoed salted butter -> rendered butter and whipping cream -> sour cream, which are
    /// the health swaps this app exists to make.
    private static let MAX_AXIS_DRIFT = 7
    /// Every good pair drifts at most 1 on sweet and every bad pair at most 2, so 4 costs
    /// nothing while still blocking a substitution that would sweeten the dish outright.
    private static let MAX_SWEET_DRIFT = 4
    private static let TASTE_PRESENT = 6

    private static let COOKING_VERBS = JSRegex("\\b(?:boiled|stewed|fried|braised|baked|grilled|steamed|roasted|poached|deep-fried|cooked)\\b")

    public enum DishFlavour: String { case SWEET, SAVOURY }

    /// Chosen by measuring six candidate rules against recipes whose subcategory makes the
    /// answer obvious. sweetShare >= 0.25 scored 85% on sweet dishes and 92% on savoury,
    /// beating count-versus-count rules that lose desserts because butter and salt are in
    /// most baking recipes and label salty 8.
    private static let SWEET_DISH_SHARE = 0.25

    /// Whether a dish reads as sweet or savoury, from its own ingredients rather than its
    /// recipe subcategory - which separates cleanly at the extremes but overlaps in the
    /// middle, where "Breakfast" and "Picnics" each hold both kinds.
    public static func getDishFlavour(_ ingredientFoods: [FoodItem]) -> DishFlavour {
        var sweet = 0, n = 0
        for food in ingredientFoods {
            guard let attrs = FoodAttributesStore.getAttributes(food.id) else { continue }
            n += 1
            if attrs.sensory[SWEET] >= TASTE_PRESENT { sweet += 1 }
        }
        // No evidence: savoury is the larger class in the corpus.
        if n == 0 { return .SAVOURY }
        return Double(sweet) / Double(n) >= SWEET_DISH_SHARE ? .SWEET : .SAVOURY
    }

    private static let SEASONING_ROLE = FoodAttributesStore.ROLE_LABELS.firstIndex(of: "condiment_seasoning") ?? -1
    private static let COOKED_PREP = FoodAttributesStore.PREP_LABELS.firstIndex(of: "cooked_ready_to_eat") ?? -1

    /// Why a cook would reject this substitution, or nil if it passes. A reason string
    /// rather than a boolean so every rejection stays traceable to its rule.
    public static func culinaryVeto(_ ingredient: FoodItem, _ candidate: FoodItem,
                                    _ dishFlavour: DishFlavour) -> String? {
        // 1. PRODUCE - ruled entirely by the substitution table, because nothing else in
        //    the data separates "kale for spinach" from "garlic for tomato".
        let ingIsProduce = ProduceGroups.isProduce(ingredient)
        let candIsProduce = ProduceGroups.isProduce(candidate)
        if ingIsProduce || candIsProduce {
            if ingIsProduce != candIsProduce { return "produce cannot swap for non-produce" }
            let ingGroup = ProduceGroups.getProduceGroup(ingredient)
            let candGroup = ProduceGroups.getProduceGroup(candidate)
            if ingGroup == nil { return "no substitution group for this produce" }
            if ingGroup != candGroup {
                return "produce group \(ingGroup!) -> \(candGroup ?? "none")"
            }
        }

        // 2. FUNCTION - checked before anything else because it is the only rule that can
        //    tell leavening from vinegar.
        let ingFn = getCulinaryFunction(ingredient)
        let candFn = getCulinaryFunction(candidate)
        if ingFn != candFn { return "function \(ingFn.rawValue) -> \(candFn.rawValue)" }
        if ingFn == .FAT && isPourableOil(ingredient) != isPourableOil(candidate) {
            return "fat form: pourable oil vs solid fat"
        }

        // Attributes cover all 7,140 foods today, but the asset is rebuilt independently
        // of foods.json. If either side is unlabeled the remaining rules abstain.
        guard let ingAttrs = FoodAttributesStore.getAttributes(ingredient.id),
              let candAttrs = FoodAttributesStore.getAttributes(candidate.id) else { return nil }

        // 3. ROLE - a cooking fat is not a condiment, a base carb is not a protein.
        if ingAttrs.culinaryRole != candAttrs.culinaryRole {
            let a = FoodAttributesStore.ROLE_LABELS.indices.contains(ingAttrs.culinaryRole)
                ? FoodAttributesStore.ROLE_LABELS[ingAttrs.culinaryRole] : "unknown"
            let b = FoodAttributesStore.ROLE_LABELS.indices.contains(candAttrs.culinaryRole)
                ? FoodAttributesStore.ROLE_LABELS[candAttrs.culinaryRole] : "unknown"
            return "role \(a) -> \(b)"
        }

        // 4a. COOKED FORM from the name. prep_state misses cases - it tags "Shallot fried
        //     without fat (pan)" as uncooked - and this database names preparations
        //     systematically, which makes the name the more reliable signal here.
        //     One-directional: a cooked ingredient may be swapped for an uncooked one.
        if COOKING_VERBS.test(candidate.name.lowercased())
            && !COOKING_VERBS.test(ingredient.name.lowercased()) {
            return "candidate is a cooked preparation, ingredient is not"
        }

        // 4b. PREP STATE - stops a finished dish being offered as an ingredient.
        //     Deliberately one-directional and not an equality check: raw / shelf_stable /
        //     liquid_beverage are packaging artefacts here (whipping cream labels
        //     liquid_beverage, sour cream processed_shelf_stable).
        if candAttrs.prepState == COOKED_PREP && ingAttrs.prepState != COOKED_PREP {
            return "candidate is a cooked dish, ingredient is not"
        }

        // 5. TASTE - the substitution must not rewrite what the ingredient tastes like.
        for axis in TASTE_AXES {
            let drift = abs(ingAttrs.sensory[axis] - candAttrs.sensory[axis])
            let limit = axis == SWEET ? MAX_SWEET_DRIFT : MAX_AXIS_DRIFT
            if drift > limit {
                return "taste drift on \(FoodAttributesStore.SENSORY_AXES[axis]) (\(drift))"
            }
        }

        // 6. SEASONINGS ARE NOT SUBSTITUTABLE. Wine vinegar and black pepper, tomato puree
        //    and dried basil all share the condiment_seasoning role, the same
        //    swiss_category, and identical labels on all five taste axes - and embeddings
        //    do not separate them either (0.60-0.73, overlapping the good pairs).
        if ingFn == .NONE
            && ingAttrs.culinaryRole == SEASONING_ROLE
            && candAttrs.culinaryRole == SEASONING_ROLE {
            return "seasoning with no recipe function - defines the dish, not interchangeable"
        }

        // 7. DISH - a candidate may not introduce a flavour the dish is not built around,
        //    unless the ingredient it replaces already carried it.
        if dishFlavour == .SAVOURY
            && candAttrs.sensory[SWEET] >= TASTE_PRESENT
            && ingAttrs.sensory[SWEET] < TASTE_PRESENT {
            return "sweet candidate in a savoury dish"
        }
        if dishFlavour == .SWEET
            && (candAttrs.sensory[SALTY] >= TASTE_PRESENT || candAttrs.sensory[UMAMI] >= TASTE_PRESENT)
            && ingAttrs.sensory[SALTY] < TASTE_PRESENT && ingAttrs.sensory[UMAMI] < TASTE_PRESENT {
            return "savoury candidate in a sweet dish"
        }

        return nil
    }

    public struct PickOptions {
        /// Foods the user already has, from InventoryContext.
        public var ownedFoodIds: Set<String>?
        /// Only accept a candidate the user already owns, and only require that it is not
        /// nutritionally worse. Used for the "cook with what is in the fridge" pass.
        public var requireOwned: Bool
        public init(ownedFoodIds: Set<String>? = nil, requireOwned: Bool = false) {
            self.ownedFoodIds = ownedFoodIds
            self.requireOwned = requireOwned
        }
        public static let none = PickOptions()
    }

    /// The best culinarily acceptable swap from an already nutrition-ranked list, or nil.
    /// `ranked` must arrive in findBestSwaps order - this walks it in that order and takes
    /// the first survivor, so nutrition still decides among the acceptable candidates.
    public static func pickCulinarySwap(
        _ ingredient: FoodItem,
        _ ranked: [SwapAlgorithm.SwapResult],
        _ dishFlavour: DishFlavour,
        _ options: PickOptions = .none
    ) -> SwapAlgorithm.SwapResult? {
        for entry in ranked {
            if options.requireOwned {
                guard options.ownedFoodIds?.contains(entry.candidate.id) == true else { continue }
                if entry.candidate.health_score < ingredient.health_score { continue }
            }
            if culinaryVeto(ingredient, entry.candidate, dishFlavour) == nil { return entry }
        }
        return nil
    }
}
