import Foundation

/// `services/storage.ts` `SwapInteraction`.
public struct SwapInteraction: Codable, Equatable {
    public enum Action: String, Codable { case accepted, dismissed, ignored }
    public var fromFoodId: String
    public var toFoodId: String
    public var action: Action
    public var timestamp: String

    public init(fromFoodId: String, toFoodId: String, action: Action, timestamp: String) {
        self.fromFoodId = fromFoodId
        self.toFoodId = toFoodId
        self.action = action
        self.timestamp = timestamp
    }
}

/// `services/storage.ts` `ScanRecord`. Also doubles as the shopping-list type - a shopping
/// list is a `ScanRecord` with `isShoppingList: true`, matching the RN source (there is no
/// separate `ShoppingList` interface).
public struct ScanRecord: Identifiable, Codable, Equatable {
    public var id: String
    public var date: String
    public var items: [PersistedReceiptItem]
    public var averageScore: Double
    public var interactions: [SwapInteraction]
    public var isShoppingList: Bool?
    public var recipeName: String?

    public init(id: String, date: String, items: [PersistedReceiptItem], averageScore: Double,
                interactions: [SwapInteraction], isShoppingList: Bool? = nil,
                recipeName: String? = nil) {
        self.id = id
        self.date = date
        self.items = items
        self.averageScore = averageScore
        self.interactions = interactions
        self.isShoppingList = isShoppingList
        self.recipeName = recipeName
    }
}

/// `ParsedReceiptItem` (`Engine/ReceiptParser.swift`) holds a live `FoodItem` reference,
/// which is right for in-memory matching but cannot round-trip through `Codable` - the JS
/// original serializes the *matched food's plain object* into `@smart_swaps_scans`, not a
/// reference. This is that serialized shape: `matchedFoodId` is looked up against
/// `FoodsStore.allFoods` when a persisted scan is read back for display.
public struct PersistedReceiptItem: Codable, Equatable {
    public var rawText: String
    public var matchedFoodId: String?
    public var confidence: Double
    public var source: String?
    public var displayName: String?
    public var quantity: Double?
    public var unit: String?

    public init(rawText: String, matchedFoodId: String?, confidence: Double, source: String? = nil,
                displayName: String? = nil, quantity: Double? = nil, unit: String? = nil) {
        self.rawText = rawText
        self.matchedFoodId = matchedFoodId
        self.confidence = confidence
        self.source = source
        self.displayName = displayName
        self.quantity = quantity
        self.unit = unit
    }

    public func resolved(in foods: [String: FoodItem]) -> ParsedReceiptItem {
        ParsedReceiptItem(rawText: rawText, matchedFood: matchedFoodId.flatMap { foods[$0] },
                           confidence: confidence, source: source, displayName: displayName,
                           quantity: quantity, unit: unit)
    }
}

/// `FavoritesContext.tsx` `FavoritesState`, persisted at `@smart_swaps_favorites`.
public struct FavoritesState: Codable, Equatable {
    public var foods: [String]
    public var swaps: [String]
    public var recipes: [String]

    public init(foods: [String] = [], swaps: [String] = [], recipes: [String] = []) {
        self.foods = foods
        self.swaps = swaps
        self.recipes = recipes
    }
}

public enum FavoriteType: String {
    case food, swap, recipe
}
