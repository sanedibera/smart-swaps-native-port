import Foundation

/// Port of `app/engine/swapGbm.ts` - the distilled gradient-boosted-tree swap ranker.
public enum SwapGbm {

    private struct Tree: Decodable {
        let feature: [Int]
        let threshold: [Double]
        let left: [Int]
        let right: [Int]
        let value: [Double]
        let defaultLeft: [Int]
    }
    private struct Model: Decodable {
        let featureNames: [String]
        let baseScore: Double
        let learningRate: Double
        let trees: [Tree]
    }

    /// Feature order is part of the model's contract - the trees index into this vector
    /// by position, so a reordering feeds every split the wrong variable and produces
    /// confident nonsense rather than an error.
    public static let FEATURE_NAMES = [
        "cosine_sim", "same_swiss_category", "liquid_mismatch", "raw_ingredient_mismatch",
        "delta_kcal", "delta_sugar_g", "delta_fat_g", "delta_satfat_g", "delta_protein_g",
        "delta_fiber_g", "delta_salt_g", "delta_health_score", "kcal_ratio",
        "sensory_distance", "same_culinary_role", "same_prep_state",
        "delta_glycemic_load", "delta_satiety", "adds_caffeine", "time_of_day_overlap",
    ]

    private static let model: Model = {
        let m = try! JSONDecoder().decode(Model.self, from: Resources.data("swapGbm.data.json"))
        // Same assertion the TS module makes at import time, for the same reason.
        precondition(m.featureNames == FEATURE_NAMES,
                     "swapGbm: feature order does not match the trained model")
        return m
    }()

    public static var treeCount: Int { model.trees.count }

    /// Matches the rounding scripts/build-pair-slates.ts applied when writing the training
    /// corpus. Without it the trees see values at a different precision than the
    /// thresholds were fit against.
    @inline(__always) private static func r3(_ x: Double) -> Double { JSNumber.round(x * 1000) / 1000 }
    @inline(__always) private static func r4(_ x: Double) -> Double { JSNumber.round(x * 10000) / 10000 }

    private static let ANY_TIME_BIT = 1 << 4   // TIMES = [breakfast, lunch, dinner, snack, any]

    private static func popcount(_ n: Int) -> Int { n.nonzeroBitCount }

    /// Builds the 20-feature vector for one (source, candidate) pair, in FEATURE_NAMES
    /// order. `nil` entries are intentional and must not become 0.
    public static func extractGbmFeatures(
        source: FoodItem, candidate: FoodItem,
        cosineSim: Double?, liquidMismatch: Int, rawIngredientMismatch: Int
    ) -> [Double?] {
        let sn = source.nutrients_per_100
        let cn = candidate.nutrients_per_100
        let a = FoodAttributesStore.getAttributes(source.id)
        let b = FoodAttributesStore.getAttributes(candidate.id)

        var sensoryDistance: Double? = nil
        var sameRole: Double? = nil
        var samePrep: Double? = nil
        var dGl: Double? = nil
        var dSatiety: Double? = nil
        var addsCaffeine: Double? = nil
        var timeOverlap: Double? = nil

        if let a, let b {
            var sum = 0.0
            for k in 0..<a.sensory.count { sum += abs(Double(a.sensory[k] - b.sensory[k])) }
            sensoryDistance = r4(sum / Double(a.sensory.count * 10))
            sameRole = a.culinaryRole == b.culinaryRole ? 1 : 0
            samePrep = a.prepState == b.prepState ? 1 : 0
            dGl = Double(b.glycemicLoad - a.glycemicLoad)
            dSatiety = Double(b.satiety - a.satiety)
            addsCaffeine = (!a.caffeine && b.caffeine) ? 1 : 0

            let bCount = popcount(b.timeOfDayMask)
            if bCount == 0 {
                timeOverlap = 0
            } else {
                let shared = (a.timeOfDayMask & ANY_TIME_BIT) != 0
                    ? bCount
                    : popcount(b.timeOfDayMask & (a.timeOfDayMask | ANY_TIME_BIT))
                timeOverlap = r4(Double(shared) / Double(bCount))
            }
        }

        return [
            cosineSim,
            source.swiss_category == candidate.swiss_category ? 1 : 0,
            Double(liquidMismatch),
            Double(rawIngredientMismatch),
            r3(cn.kcal - sn.kcal),
            r3(cn.sugars_g - sn.sugars_g),
            r3(cn.fat_g - sn.fat_g),
            r3(cn.saturated_fat_g - sn.saturated_fat_g),
            r3(cn.protein_g - sn.protein_g),
            r3(cn.fiber_g - sn.fiber_g),
            r3(cn.salt_g - sn.salt_g),
            candidate.health_score - source.health_score,
            r4(cn.kcal / JSNumber.or(sn.kcal, 1)),
            sensoryDistance,
            sameRole,
            samePrep,
            dGl,
            dSatiety,
            addsCaffeine,
            timeOverlap,
        ]
    }

    private static func predictTree(_ t: Tree, _ x: [Double?]) -> Double {
        var node = 0
        while t.feature[node] != -1 {
            let v = x[t.feature[node]]
            let goLeft: Bool
            if let v, !v.isNaN {
                goLeft = v < t.threshold[node]
            } else {
                goLeft = t.defaultLeft[node] == 1
            }
            node = goLeft ? t.left[node] : t.right[node]
        }
        return t.value[node]
    }

    /// Probability in [0,1] that this candidate is a good swap.
    public static func predictSwapQualityGbm(_ features: [Double?]) -> Double {
        var f = model.baseScore
        for t in model.trees { f += model.learningRate * predictTree(t, features) }
        return 1 / (1 + exp(-f))
    }
}
