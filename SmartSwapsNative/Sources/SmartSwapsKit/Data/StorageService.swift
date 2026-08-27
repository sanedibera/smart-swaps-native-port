import Foundation

/// Port of `app/services/storage.ts` (86 ln) - the `AsyncStorage`-backed scan/interaction
/// log, now on `KeyValueStore`. Every method swallows its own errors (matching the source's
/// `catch (e) { console.error(...) }`, never throwing) and `saveScan` prepends
/// (`[newScan, ...existing]`) so the newest scan is always index 0.
public enum StorageService {
    private static let scansKey = "@smart_swaps_scans"
    private static let interactionsKey = "@smart_swaps_interactions"

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        return e
    }()
    private static let decoder = JSONDecoder()

    /// `Omit<ScanRecord, 'interactions'>` - a new scan always starts with an empty log.
    public static func saveScan(id: String, date: String, items: [PersistedReceiptItem],
                                 averageScore: Double, isShoppingList: Bool? = nil,
                                 recipeName: String? = nil) async {
        do {
            var existing = await getScans()
            let newScan = ScanRecord(id: id, date: date, items: items, averageScore: averageScore,
                                      interactions: [], isShoppingList: isShoppingList,
                                      recipeName: recipeName)
            existing.insert(newScan, at: 0)
            let data = try encoder.encode(existing)
            await KeyValueStore.shared.setItem(scansKey, String(data: data, encoding: .utf8) ?? "[]")
        } catch {
            // Matches the source: log and swallow, never throw.
        }
    }

    public static func updateScan(id: String, updatedScan: ScanRecord) async {
        do {
            var existing = await getScans()
            if let index = existing.firstIndex(where: { $0.id == id }) {
                existing[index] = updatedScan
                let data = try encoder.encode(existing)
                await KeyValueStore.shared.setItem(scansKey, String(data: data, encoding: .utf8) ?? "[]")
            }
        } catch {}
    }

    public static func deleteScan(id: String) async {
        var existing = await getScans()
        existing.removeAll { $0.id == id }
        if let data = try? encoder.encode(existing) {
            await KeyValueStore.shared.setItem(scansKey, String(data: data, encoding: .utf8) ?? "[]")
        }
    }

    public static func getScans() async -> [ScanRecord] {
        guard let json = await KeyValueStore.shared.getItem(scansKey),
              let data = json.data(using: .utf8),
              let scans = try? decoder.decode([ScanRecord].self, from: data) else {
            return []
        }
        return scans
    }

    public static func logSwapInteraction(fromFoodId: String, toFoodId: String,
                                           action: SwapInteraction.Action) async {
        var existing: [SwapInteraction] = []
        if let json = await KeyValueStore.shared.getItem(interactionsKey),
           let data = json.data(using: .utf8),
           let decoded = try? decoder.decode([SwapInteraction].self, from: data) {
            existing = decoded
        }
        let iso = ISO8601DateFormatter().string(from: Date())
        existing.append(SwapInteraction(fromFoodId: fromFoodId, toFoodId: toFoodId, action: action, timestamp: iso))
        if let data = try? encoder.encode(existing) {
            await KeyValueStore.shared.setItem(interactionsKey, String(data: data, encoding: .utf8) ?? "[]")
        }
    }

    public static func clearScans() async {
        await KeyValueStore.shared.removeItem(scansKey)
    }
}
