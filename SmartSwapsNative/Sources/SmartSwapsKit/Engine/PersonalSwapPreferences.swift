import Foundation

/// Port of `app/engine/personalSwapPreferences.ts`.
///
/// Not a neural network and no training loop: a small set of per-user multipliers nudged
/// by an exponential moving average on each accept/reject, stored only on device.
public actor PersonalSwapPreferences {
    public static let shared = PersonalSwapPreferences()

    private static let STORAGE_KEY = "swap_personal_preferences_v1"
    private static let LEARNING_RATE = 0.15
    private static let MIN_MULTIPLIER = 0.3   // a disliked category is suppressed, never zeroed
    private static let MAX_MULTIPLIER = 1.8   // a liked category is boosted, not made all-powerful

    struct Prefs: Codable {
        var bySwissCategory: [String: Double] = [:]
        var byFoodId: [String: Double] = [:]
    }

    private var cache: Prefs?

    private func load() async -> Prefs {
        if let cache { return cache }
        let raw = await KeyValueStore.shared.getItem(Self.STORAGE_KEY)
        if let raw, let d = raw.data(using: .utf8),
           let p = try? JSONDecoder().decode(Prefs.self, from: d) {
            cache = p
        } else {
            cache = Prefs()
        }
        return cache!
    }

    private func save(_ prefs: Prefs) async {
        cache = prefs
        // Storage failure shouldn't crash the app - worst case personalization just does
        // not persist this session. Not worth surfacing.
        if let d = try? JSONEncoder().encode(prefs), let s = String(data: d, encoding: .utf8) {
            await KeyValueStore.shared.setItem(Self.STORAGE_KEY, s)
        }
    }

    private func clamp(_ x: Double) -> Double {
        Swift.max(Self.MIN_MULTIPLIER, Swift.min(Self.MAX_MULTIPLIER, x))
    }

    public func recordSwapAccepted(_ swissCategory: String, _ foodId: String) async {
        var prefs = await load()
        let currentCat = prefs.bySwissCategory[swissCategory] ?? 1.0
        let currentFood = prefs.byFoodId[foodId] ?? 1.0
        prefs.bySwissCategory[swissCategory] =
            clamp(currentCat + Self.LEARNING_RATE * (Self.MAX_MULTIPLIER - currentCat) * 0.3)
        prefs.byFoodId[foodId] =
            clamp(currentFood + Self.LEARNING_RATE * (Self.MAX_MULTIPLIER - currentFood) * 0.5)
        await save(prefs)
    }

    public func recordSwapRejected(_ swissCategory: String, _ foodId: String) async {
        var prefs = await load()
        let currentCat = prefs.bySwissCategory[swissCategory] ?? 1.0
        let currentFood = prefs.byFoodId[foodId] ?? 1.0
        prefs.bySwissCategory[swissCategory] =
            clamp(currentCat - Self.LEARNING_RATE * (currentCat - Self.MIN_MULTIPLIER) * 0.3)
        prefs.byFoodId[foodId] =
            clamp(currentFood - Self.LEARNING_RATE * (currentFood - Self.MIN_MULTIPLIER) * 0.5)
        await save(prefs)
    }

    /// Combines the category-level (broader, more data) and food-specific (sharper, less
    /// data) signals by averaging, so a brand-new food in a disliked category is still
    /// suppressed somewhat.
    public func applyPersonalPreference(_ baseScore: Double, _ swissCategory: String,
                                        _ foodId: String) async -> Double {
        let prefs = await load()
        let catMultiplier = prefs.bySwissCategory[swissCategory] ?? 1.0
        let foodMultiplier = prefs.byFoodId[foodId] ?? 1.0
        return baseScore * ((catMultiplier + foodMultiplier) / 2)
    }

    public func resetPersonalPreferences() async { await save(Prefs()) }
}
