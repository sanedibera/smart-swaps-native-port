import Foundation

/// Port of `app/services/matchLog.ts` (94 ln) - local log of scan lines the matcher wasn't
/// confident about, so a bug report comes with the raw OCR text and the matcher's actual
/// answer already attached. Same privacy treatment as `SwapTrainingLog`.
public actor MatchLog {
    public static let shared = MatchLog()

    private static let storageKey = "match_diagnostic_log_v1"
    private static let maxRows = 500
    /// Mirrors `ReceiptItemList`'s "confident" bucket cutoff - keep in sync.
    public static let confidentThreshold = 0.72

    public struct Row: Codable {
        public var rawText: String
        public var matchedFoodId: String?
        public var matchedName: String?
        public var confidence: Double
        public var tier: String?
        public var timestamp: String
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

    /// Call once per completed scan with the full item list; only the weak ones get appended.
    public func logWeakMatches(_ items: [ParsedReceiptItem]) async {
        let weak = items.filter { $0.matchedFood == nil || $0.confidence < Self.confidentThreshold }
        guard !weak.isEmpty else { return }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let newRows = weak.map { item in
            Row(rawText: item.rawText, matchedFoodId: item.matchedFood?.id,
                matchedName: item.matchedFood?.name_de ?? item.matchedFood?.name,
                confidence: item.confidence, tier: item.source, timestamp: timestamp)
        }
        var rows = await loadLog()
        rows.append(contentsOf: newRows)
        await saveLog(rows)
    }

    public func getMatchLogCount() async -> Int { await loadLog().count }

    public func exportMatchLogJSON() async throws -> String {
        let rows = await loadLog()
        guard !rows.isEmpty else { throw ExportError(message: "No weak matches logged yet.") }
        guard let data = try? JSONEncoder().encode(rows), let s = String(data: data, encoding: .utf8) else {
            throw ExportError(message: "No weak matches logged yet.")
        }
        return s
    }

    public func clearMatchLog() async { await saveLog([]) }
}
