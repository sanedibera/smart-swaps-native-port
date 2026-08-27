import Foundation

/// Port of `app/engine/swapTrainingLog.ts` (91 ln). Local, anonymized accept/reject log -
/// numeric features plus a label only, no food id/name. Nothing here uploads or transmits
/// anything; `exportTrainingLog` only hands the rows to the OS share sheet on the user's
/// own initiative (see `PORTING_NOTES.md`).
public actor SwapTrainingLog {
    public static let shared = SwapTrainingLog()

    private static let storageKey = "swap_training_log_v1"
    private static let maxRows = 2000

    public struct Row: Codable {
        public var features: SwapRanker.SwapFeatures
        public var label: String // "GOOD" | "BAD"
        public var is_good: Int  // 0 | 1

        enum CodingKeys: String, CodingKey {
            case label, is_good
            case cosine_sim, same_swiss_category, liquid_mismatch, raw_ingredient_mismatch
            case delta_kcal, delta_sugar_g, delta_fat_g, delta_satfat_g, delta_protein_g
        }

        public init(features: SwapRanker.SwapFeatures, label: String, is_good: Int) {
            self.features = features
            self.label = label
            self.is_good = is_good
        }

        // `SwapFeatures`' fields are flattened into the row in JS (object spread), not nested.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            label = try c.decode(String.self, forKey: .label)
            is_good = try c.decode(Int.self, forKey: .is_good)
            features = SwapRanker.SwapFeatures(
                cosine_sim: try c.decodeIfPresent(Double.self, forKey: .cosine_sim),
                same_swiss_category: try c.decode(Int.self, forKey: .same_swiss_category),
                liquid_mismatch: try c.decode(Int.self, forKey: .liquid_mismatch),
                raw_ingredient_mismatch: try c.decode(Int.self, forKey: .raw_ingredient_mismatch),
                delta_kcal: try c.decode(Double.self, forKey: .delta_kcal),
                delta_sugar_g: try c.decode(Double.self, forKey: .delta_sugar_g),
                delta_fat_g: try c.decode(Double.self, forKey: .delta_fat_g),
                delta_satfat_g: try c.decode(Double.self, forKey: .delta_satfat_g),
                delta_protein_g: try c.decode(Double.self, forKey: .delta_protein_g)
            )
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(label, forKey: .label)
            try c.encode(is_good, forKey: .is_good)
            try c.encodeIfPresent(features.cosine_sim, forKey: .cosine_sim)
            try c.encode(features.same_swiss_category, forKey: .same_swiss_category)
            try c.encode(features.liquid_mismatch, forKey: .liquid_mismatch)
            try c.encode(features.raw_ingredient_mismatch, forKey: .raw_ingredient_mismatch)
            try c.encode(features.delta_kcal, forKey: .delta_kcal)
            try c.encode(features.delta_sugar_g, forKey: .delta_sugar_g)
            try c.encode(features.delta_fat_g, forKey: .delta_fat_g)
            try c.encode(features.delta_satfat_g, forKey: .delta_satfat_g)
            try c.encode(features.delta_protein_g, forKey: .delta_protein_g)
        }
    }

    struct ExportError: Error { let message: String }

    private func loadLog() async -> [Row] {
        guard let raw = await KeyValueStore.shared.getItem(Self.storageKey),
              let data = raw.data(using: .utf8),
              let rows = try? JSONDecoder().decode([Row].self, from: data) else { return [] }
        return rows
    }

    private func saveLog(_ rows: [Row]) async {
        let capped = Array(rows.suffix(Self.maxRows))
        if let data = try? JSONEncoder().encode(capped), let s = String(data: data, encoding: .utf8) {
            await KeyValueStore.shared.setItem(Self.storageKey, s)
        }
    }

    public func logSwapDecision(source: FoodItem, candidate: FoodItem, accepted: Bool,
                                 liquidMismatch: Int, rawIngredientMismatch: Int) async {
        let features = SwapRanker.extractSwapFeatures(source, candidate, cosineSim: nil,
                                                        liquidMismatch: liquidMismatch,
                                                        rawIngredientMismatch: rawIngredientMismatch)
        let row = Row(features: features, label: accepted ? "GOOD" : "BAD", is_good: accepted ? 1 : 0)
        var rows = await loadLog()
        rows.append(row)
        await saveLog(rows)
    }

    public func getTrainingLogCount() async -> Int { await loadLog().count }

    /// Returns the JSON payload to hand to the OS share sheet. Throws when there's nothing
    /// to export, matching the source's `throw new Error(...)`.
    public func exportTrainingLogJSON() async throws -> String {
        let rows = await loadLog()
        guard !rows.isEmpty else { throw ExportError(message: "No local swap decisions recorded yet.") }
        guard let data = try? JSONEncoder().encode(rows), let s = String(data: data, encoding: .utf8) else {
            throw ExportError(message: "No local swap decisions recorded yet.")
        }
        return s
    }

    public func clearTrainingLog() async { await saveLog([]) }
}
