import SwiftUI

/// Phase 6 — the SwiftUI equivalent of expo-router's file-based navigation, per
/// `app/_layout.tsx`: a single root `Stack` wrapping `(tabs)`, with `food/[id]` and
/// `recipe/[id]` declared `presentation: 'modal'` (everything else - `settings`,
/// `receipt/[id]`, `scan-receipt` - is an implicit plain push, since they're sibling files
/// under `app/` with no explicit `<Stack.Screen>` override).
///
/// One `NavigationStack` wraps the whole `TabView` here too, matching the RN structure where
/// pushing a sibling route covers the tab bar entirely rather than living inside one tab's
/// own stack. `food`/`recipe` are `.sheet`-presented from `RootView` using this router's
/// published ids rather than push routes, matching the modal presentation.
@MainActor
final class Router: ObservableObject {
    enum Tab: Hashable { case home, recipes, receipts, search }

    enum PushRoute: Hashable {
        case settings
        case receipt(String)
        case scan
    }

    @Published var selectedTab: Tab = .home
    @Published var path = NavigationPath()
    @Published var presentedFoodId: String?
    @Published var presentedRecipeId: String?

    func openFood(_ id: String) { presentedFoodId = id }
    func openRecipe(_ id: String) { presentedRecipeId = id }
    func closeFood() { presentedFoodId = nil }
    func closeRecipe() { presentedRecipeId = nil }

    func openSettings() { path.append(PushRoute.settings) }
    func openReceipt(_ id: String) { path.append(PushRoute.receipt(id)) }
    func openScan() { path.append(PushRoute.scan) }

    /// `router.push('/receipts')` from a screen pushed on top of `(tabs)` (e.g. after a scan
    /// completes): pop back to the tab view and switch to Receipts, matching expo-router
    /// resolving a tab-group route from outside the group.
    func goToReceiptsTab() {
        path = NavigationPath()
        selectedTab = .receipts
    }
}

/// Wraps a bare `String` id so it can drive `.sheet(item:)`, which needs `Identifiable`.
struct IdentifiableID: Identifiable, Hashable {
    var id: String
}
