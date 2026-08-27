import Foundation
import SwiftUI
import SmartSwapsKit

/// Port of `SettingsContext.tsx` (70 ln) - app-behavior feature flags, separate from
/// `ProfileStore` (nutrition/health-goal state). Persisted at `@smart_swaps_settings`.
@MainActor
public final class SettingsStore: ObservableObject {
    private static let key = "@smart_swaps_settings"

    public struct Settings: Codable, Equatable {
        /// Defaults false: the OFF category-bridge can pick a confidently wrong same-category
        /// neighbour and hasn't been tuned against a labelled eval set (see PORT_TO_SWIFT_PROMPT.md
        /// and the imported PR notes). Scanning stays fully offline unless the user opts in.
        public var offLookupEnabled = false
        public init() {}
    }

    @Published public var settings = Settings()
    @Published public private(set) var isLoaded = false

    public init() {
        Task { await load() }
    }

    private func load() async {
        if let json = await KeyValueStore.shared.getItem(Self.key),
           let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(Settings.self, from: data) {
            settings = decoded
        }
        isLoaded = true
    }

    public func updateSettings(_ mutate: (inout Settings) -> Void) {
        mutate(&settings)
        let snapshot = settings
        Task {
            if let data = try? JSONEncoder().encode(snapshot), let json = String(data: data, encoding: .utf8) {
                await KeyValueStore.shared.setItem(Self.key, json)
            }
        }
    }
}
