import SwiftUI

/// Matches `(tabs)/_layout.tsx`'s `ClassicTabLayout` branch: a blurred, transparent tab bar
/// tinted `primaryGreen` active / `textMuted` inactive, SF Symbols at the sizes the RN screen
/// renders on iOS.
///
/// `(tabs)/_layout.tsx` branches on `isLiquidGlassAvailable()` to a `NativeTabs`
/// (iOS 26+ Liquid Glass) presentation instead. That branch is deferred — see
/// PORTING_NOTES.md "Still uncertain / open" — until real tab content exists to
/// verify it against, rather than guessing at API surface with nothing behind it.
///
/// Phase 6: the whole app lives under one `NavigationStack` + `Router` (see `Router.swift`),
/// matching `app/_layout.tsx`'s single root `Stack` wrapping `(tabs)` with `food`/`recipe`
/// as global modals.
struct RootView: View {
    // Nesting order matches `_layout.tsx`: Profile -> Favorites -> Settings -> Inventory.
    @StateObject private var profileStore = ProfileStore()
    @StateObject private var favoritesStore = FavoritesStore()
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var inventoryStore = InventoryStore()
    @StateObject private var recipeStore = RecipeStore.shared
    @StateObject private var foodsStore = FoodsStore.shared
    @StateObject private var router = Router()

    init() {
        configureTabBarAppearance()
    }

    var body: some View {
        Group {
            // PORTING_INVENTORY.md §4's correction to the brief: the RN providers render
            // NOTHING (`if (!isLoaded) return null`) until their AsyncStorage reads resolve,
            // rather than showing defaults while loading. Reproduced here rather than the
            // brief's "show defaults" instruction, since rule 1 makes the RN code win.
            // `InventoryProvider` does NOT gate on its own load - matches the source.
            if profileStore.isLoaded && favoritesStore.isLoaded && settingsStore.isLoaded {
                navigationRoot
                    .onAppear {
                        // `useFoods()`/`useRecipes()` load lazily on first hook use in RN;
                        // here that's the first screen mount, which is always the tab root.
                        foodsStore.load()
                    }
                    .onChange(of: foodsStore.isLoaded) { loaded in
                        if loaded { recipeStore.load(foodsStore: foodsStore) }
                    }
            } else {
                Color(Colors.background).ignoresSafeArea()
            }
        }
        .environmentObject(profileStore)
        .environmentObject(favoritesStore)
        .environmentObject(settingsStore)
        .environmentObject(inventoryStore)
        .environmentObject(recipeStore)
        .environmentObject(foodsStore)
        .environmentObject(router)
    }

    private var navigationRoot: some View {
        NavigationStack(path: $router.path) {
            tabs
                .navigationDestination(for: Router.PushRoute.self) { route in
                    switch route {
                    case .settings:
                        SettingsScreen()
                    case .receipt(let id):
                        ReceiptDetailScreen(scanId: id)
                    case .scan:
                        ScanReceiptScreen()
                    }
                }
        }
        .sheet(item: Binding(
            get: { router.presentedFoodId.map(IdentifiableID.init) },
            set: { router.presentedFoodId = $0?.id }
        )) { item in
            FoodDetailScreen(foodId: item.id, onClose: { router.closeFood() })
        }
        .sheet(item: Binding(
            get: { router.presentedRecipeId.map(IdentifiableID.init) },
            set: { router.presentedRecipeId = $0?.id }
        )) { item in
            RecipeDetailScreen(recipeId: item.id, onClose: { router.closeRecipe() })
        }
    }

    private var tabs: some View {
        TabView(selection: $router.selectedTab) {
            HomeScreen()
                .tabItem { tabLabel("Home", systemImage: "house.fill") }
                .tag(Router.Tab.home)

            RecipesScreen()
                .tabItem { tabLabel("Recipes", systemImage: "fork.knife") }
                .tag(Router.Tab.recipes)

            ReceiptsScreen()
                .tabItem { tabLabel("Receipts", systemImage: "list.bullet.rectangle") }
                .tag(Router.Tab.receipts)

            SearchScreen()
                .tabItem { tabLabel("Search", systemImage: "magnifyingglass") }
                .tag(Router.Tab.search)
        }
        .tint(Colors.primaryGreen)
    }

    @ViewBuilder
    private func tabLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
    }

    /// `tabBarStyle`: `position: absolute`, `backgroundColor: transparent` on
    /// iOS with a `BlurView` (`intensity={90}`) behind it, `borderTopWidth: 0`.
    private func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterialLight)
        appearance.shadowColor = .clear

        let active = UIColor(Colors.primaryGreen)
        let inactive = UIColor(Colors.textMuted)
        let labelFont = UIFont.systemFont(ofSize: 10, weight: .medium)

        for itemAppearance in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
            itemAppearance.normal.iconColor = inactive
            itemAppearance.normal.titleTextAttributes = [.foregroundColor: inactive, .font: labelFont]
            itemAppearance.selected.iconColor = active
            itemAppearance.selected.titleTextAttributes = [.foregroundColor: active, .font: labelFont]
        }

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

#Preview {
    RootView()
}
