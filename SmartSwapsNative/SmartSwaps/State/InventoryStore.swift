import Foundation
import SwiftUI
import SmartSwapsKit

/// Port of `InventoryContext.tsx` (70 ln). `ownedFoodIds` = matched foods from non-shopping-
/// list scans dated on/after the Monday of the current week - "what you actually bought this
/// week", not everything ever scanned.
@MainActor
public final class InventoryStore: ObservableObject {
    @Published public private(set) var ownedFoodIds: Set<String> = []
    @Published public private(set) var shoppingLists: [ScanRecord] = []
    @Published public private(set) var scans: [ScanRecord] = []

    public init() {
        Task { await refreshInventory() }
    }

    public func refreshInventory() async {
        let allScans = await StorageService.getScans()

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFormatterNoFraction = ISO8601DateFormatter()
        func parseDate(_ s: String) -> Date? {
            isoFormatter.date(from: s) ?? isoFormatterNoFraction.date(from: s)
        }

        let lists = allScans
            .filter { $0.isShoppingList == true }
            .sorted { (parseDate($0.date) ?? .distantPast) > (parseDate($1.date) ?? .distantPast) }

        // Monday-based week start, matching `now.getDate() - day + (day === 0 ? -6 : 1)`
        // where JS `getDay()` is 0=Sunday...6=Saturday.
        let now = Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let jsDay = calendar.component(.weekday, from: now) - 1 // 0=Sun...6=Sat
        let daysSinceMonday = jsDay == 0 ? 6 : jsDay - 1
        let startOfWeek = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -daysSinceMonday, to: now) ?? now)

        var newOwned = Set<String>()
        for scan in allScans {
            if scan.isShoppingList == true { continue }
            guard let scanDate = parseDate(scan.date), scanDate >= startOfWeek else { continue }
            for item in scan.items {
                if let id = item.matchedFoodId {
                    newOwned.insert(id)
                }
            }
        }

        ownedFoodIds = newOwned
        shoppingLists = lists
        scans = allScans
    }
}
