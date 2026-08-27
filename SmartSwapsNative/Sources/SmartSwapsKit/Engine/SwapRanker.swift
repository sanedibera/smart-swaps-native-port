import Foundation

/// Port of `app/engine/swapRanker.ts` (153 ln) - a logistic-regression swap-quality ranker.
/// Dead in the app itself (PORTING_INVENTORY.md §5.1 - nothing in `app/`/`components/` calls
/// `predictSwapQuality`/`combineWithExistingScore`), kept per its own header note. Needed here
/// because `swapTrainingLog.ts`'s `logSwapDecision` calls `extractSwapFeatures`.
public enum SwapRanker {
    // Learned from swap_training_rows.json via scripts/trainSwapRanker.ts. Weights apply to
    // STANDARDIZED features - do not change without retraining; they must move together.
    private static let scalerMean: [String: Double] = [
        "cosine_sim": 0.900981, "same_swiss_category": 0.606481, "liquid_mismatch": 0.185185,
        "raw_ingredient_mismatch": 0.064815, "delta_kcal": -7.388889, "delta_sugar_g": -0.277315,
        "delta_fat_g": -1.253704, "delta_satfat_g": 0.142130, "delta_protein_g": 1.648148,
    ]
    private static let scalerScale: [String: Double] = [
        "cosine_sim": 0.048455, "same_swiss_category": 0.488530, "liquid_mismatch": 0.388448,
        "raw_ingredient_mismatch": 0.246199, "delta_kcal": 170.331693, "delta_sugar_g": 15.280673,
        "delta_fat_g": 16.712775, "delta_satfat_g": 9.896176, "delta_protein_g": 7.108419,
    ]
    private static let weights: [(String, Double)] = [
        ("cosine_sim", 0.0127), ("same_swiss_category", 1.1753), ("liquid_mismatch", -0.6130),
        ("raw_ingredient_mismatch", -0.5563), ("delta_kcal", 0.3884), ("delta_sugar_g", -0.3948),
        ("delta_fat_g", -0.2681), ("delta_satfat_g", -0.0711), ("delta_protein_g", -0.1188),
    ]
    private static let intercept = -0.7826

    public struct SwapFeatures: Codable {
        /// `nil` means "no real embedding for this pair" - stays nullable so
        /// `predictSwapQuality` can skip the term rather than guess a value.
        public var cosine_sim: Double?
        public var same_swiss_category: Int
        public var liquid_mismatch: Int
        public var raw_ingredient_mismatch: Int
        public var delta_kcal: Double
        public var delta_sugar_g: Double
        public var delta_fat_g: Double
        public var delta_satfat_g: Double
        public var delta_protein_g: Double

        func value(for key: String) -> Double? {
            switch key {
            case "cosine_sim": return cosine_sim
            case "same_swiss_category": return Double(same_swiss_category)
            case "liquid_mismatch": return Double(liquid_mismatch)
            case "raw_ingredient_mismatch": return Double(raw_ingredient_mismatch)
            case "delta_kcal": return delta_kcal
            case "delta_sugar_g": return delta_sugar_g
            case "delta_fat_g": return delta_fat_g
            case "delta_satfat_g": return delta_satfat_g
            case "delta_protein_g": return delta_protein_g
            default: return nil
            }
        }
    }

    private static func sigmoid(_ x: Double) -> Double { 1 / (1 + exp(-x)) }

    public static func predictSwapQuality(_ features: SwapFeatures) -> Double {
        var z = intercept
        for (key, weight) in weights {
            guard let raw = features.value(for: key) else { continue }
            let standardized = (raw - (scalerMean[key] ?? 0)) / (scalerScale[key] ?? 1)
            z += weight * standardized
        }
        return sigmoid(z)
    }

    public static func extractSwapFeatures(_ source: FoodItem, _ candidate: FoodItem, cosineSim: Double?,
                                            liquidMismatch: Int, rawIngredientMismatch: Int) -> SwapFeatures {
        let sn = source.nutrients_per_100
        let cn = candidate.nutrients_per_100
        return SwapFeatures(
            cosine_sim: cosineSim,
            same_swiss_category: source.swiss_category == candidate.swiss_category ? 1 : 0,
            liquid_mismatch: liquidMismatch,
            raw_ingredient_mismatch: rawIngredientMismatch,
            delta_kcal: cn.kcal - sn.kcal,
            delta_sugar_g: cn.sugars_g - sn.sugars_g,
            delta_fat_g: cn.fat_g - sn.fat_g,
            delta_satfat_g: cn.saturated_fat_g - sn.saturated_fat_g,
            delta_protein_g: cn.protein_g - sn.protein_g
        )
    }

    public static func combineWithExistingScore(_ existingScore: Double, _ learnedProbability: Double) -> Double {
        let multiplier = 0.5 + learnedProbability
        return existingScore * multiplier
    }
}
