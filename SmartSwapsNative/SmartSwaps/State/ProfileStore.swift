import Foundation
import SwiftUI
import SmartSwapsKit

/// Port of `ProfileContext.tsx` (163 ln). Persisted at `@smart_swaps_profile`, defaults
/// Female/23/50kg/170cm/Lightly Active/stay/[Balanced] until the async load resolves.
///
/// PORTING_INVENTORY.md §4's correction to the brief applies here: the RN provider renders
/// `null` (nothing) until its AsyncStorage read resolves, rather than showing defaults while
/// loading - `isLoaded` is exposed so the root view can reproduce that empty-until-hydrated
/// gate instead of flashing default values.
@MainActor
public final class ProfileStore: ObservableObject {
    private static let key = "@smart_swaps_profile"

    @Published public var profile: Profile = .default
    @Published public private(set) var isLoaded = false

    public var targetCalories: Int { ProfileMath.targetCalories(for: profile) }
    public var targetMacros: TargetMacros { ProfileMath.targetMacros(for: profile) }
    public var targetMacroPercentages: TargetMacroPercentages { ProfileMath.targetMacroPercentages(for: profile) }

    public init() {
        Task { await load() }
    }

    private func load() async {
        if let json = await KeyValueStore.shared.getItem(Self.key),
           let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(Profile.self, from: data) {
            profile = decoded
        }
        isLoaded = true
    }

    public func updateProfile(_ mutate: (inout Profile) -> Void) {
        mutate(&profile)
        let snapshot = profile
        Task {
            if let data = try? JSONEncoder().encode(snapshot),
               let json = String(data: data, encoding: .utf8) {
                await KeyValueStore.shared.setItem(Self.key, json)
            }
        }
    }
}
