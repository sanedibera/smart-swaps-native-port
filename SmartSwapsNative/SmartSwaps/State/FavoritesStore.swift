import Foundation
import SwiftUI
import SmartSwapsKit

/// Port of `FavoritesContext.tsx` (78 ln). Persisted at `@smart_swaps_favorites`; swap ids
/// are `"fromId-toId"`, matching `SwapComparisonCard`'s `${fromFood.id}-${toFood.id}`.
@MainActor
public final class FavoritesStore: ObservableObject {
    private static let key = "@smart_swaps_favorites"

    @Published public private(set) var favorites = FavoritesState()
    @Published public private(set) var isLoaded = false

    public init() {
        Task { await load() }
    }

    private func load() async {
        if let json = await KeyValueStore.shared.getItem(Self.key),
           let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(FavoritesState.self, from: data) {
            favorites = decoded
        }
        isLoaded = true
    }

    public func isFavorite(_ type: FavoriteType, _ id: String) -> Bool {
        list(for: type).contains(id)
    }

    public func toggleFavorite(_ type: FavoriteType, _ id: String) {
        var list = self.list(for: type)
        if let idx = list.firstIndex(of: id) {
            list.remove(at: idx)
        } else {
            list.append(id)
        }
        setList(list, for: type)
        persist()
    }

    private func list(for type: FavoriteType) -> [String] {
        switch type {
        case .food: return favorites.foods
        case .swap: return favorites.swaps
        case .recipe: return favorites.recipes
        }
    }

    private func setList(_ list: [String], for type: FavoriteType) {
        switch type {
        case .food: favorites.foods = list
        case .swap: favorites.swaps = list
        case .recipe: favorites.recipes = list
        }
    }

    private func persist() {
        let snapshot = favorites
        Task {
            if let data = try? JSONEncoder().encode(snapshot),
               let json = String(data: data, encoding: .utf8) {
                await KeyValueStore.shared.setItem(Self.key, json)
            }
        }
    }
}
