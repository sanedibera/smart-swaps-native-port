import SwiftUI
import SmartSwapsKit

enum SearchSelection {
    case food(FoodItem)
    case recipe(Recipe)
}

/// Port of `SearchScreen.tsx` (772 ln, driven by `app/(tabs)/search.tsx` with
/// `mode="foods"`, and reused as a sheet by `components/SearchModal.tsx`). Replaces the
/// Phase 1 placeholder of the same name.
///
/// `useRouter()`/`router.push` -> `Router` (`@EnvironmentObject`, see `App/Router.swift`).
/// `onSelect`/`onBack`/`rawText` stay as explicit params since they only apply to the
/// correction-picker use (wrapped by `SearchModal`) - the tab instance leaves them `nil`.
/// `useFocusEffect` (re-fetch scans every time the screen regains focus) is approximated
/// with `.onAppear`, which fires on first appearance and on push-back-to but not on every
/// tab reselect the way `useFocusEffect` does - flagged here rather than silently assumed
/// equivalent.
struct SearchScreen: View {
    enum Mode { case foods, swaps }

    var onBack: (() -> Void)? = nil
    var mode: Mode = .foods
    var onSelect: ((SearchSelection) -> Void)? = nil
    var rawText: String? = nil

    @EnvironmentObject private var foodsStore: FoodsStore
    @EnvironmentObject private var favoritesStore: FavoritesStore
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var recipeStore: RecipeStore
    @EnvironmentObject private var router: Router

    @State private var searchQuery = ""
    @State private var searchFilter = "all"
    @State private var scans: [ScanRecord] = []
    @State private var showFilters = false
    @State private var favoritesOnly = false
    @State private var category = "All"
    @State private var nutriScores: Set<String> = []
    @State private var maxCalories: Double = 1000
    @State private var limit = 20
    @State private var scrollY: CGFloat = 0

    private static let filterTabs = ["all", "foods", "recipes", "lists", "receipts"]
    private static let nutriGrades = ["A", "B", "C", "D", "E"]

    private struct Row: Identifiable {
        var id: String
        var type: String // "food" | "recipe" | "list" | "receipt"
        var title: String
        var category: String
        var calories: String
        var score: Int
        var nutriScore: String
        var nutriColor: Color
        var nutriBg: Color
        var iconKey: String?
        var isFavorite: Bool
    }

    private func scoreColors(_ val: Double) -> (fg: Color, bg: Color) {
        if val >= 75 { return (Colors.scoreGreen, Colors.lightGreenBg) }
        if val >= 50 { return (Colors.Local.amber, Colors.Local.amberBg) }
        return (Colors.scoreRed, Colors.Local.redBg)
    }

    private var uniqueCategories: [String] {
        var cats = Set(foodsStore.allFoods.map(\.category))
        cats.insert("All")
        return cats.sorted()
    }

    private var searchResults: [Row] {
        guard mode == .foods else { return [] }
        var rows: [Row] = []
        let q = searchQuery.lowercased()

        if searchFilter == "all" || searchFilter == "foods" {
            var fResults = foodsStore.allFoods
            if !q.isEmpty { fResults = fResults.filter { $0.name.lowercased().contains(q) || $0.category.lowercased().contains(q) } }
            if !nutriScores.isEmpty { fResults = fResults.filter { guard let g = $0.nutri_grade else { return false }; return nutriScores.contains(g.uppercased()) } }
            if favoritesOnly { fResults = fResults.filter { favoritesStore.isFavorite(.food, $0.id) } }
            if maxCalories < 1000 { fResults = fResults.filter { $0.nutrients_per_100.kcal <= maxCalories } }
            rows += fResults.map { f in
                let sc = scoreColors(Double(f.health_score))
                return Row(id: f.id, type: "food", title: f.name, category: f.category,
                           calories: "\(JSNumber.roundToInt(f.nutrients_per_100.kcal)) kcal / 100g",
                           score: JSNumber.roundToInt(f.health_score),
                           nutriScore: f.nutri_grade.map { "NUTRI SCORE \($0.uppercased())" } ?? "UNGRADED",
                           nutriColor: sc.fg, nutriBg: sc.bg, iconKey: f.icon_key,
                           isFavorite: favoritesStore.isFavorite(.food, f.id))
            }
        }

        if searchFilter == "all" || searchFilter == "recipes" {
            var rResults = recipeStore.recipes
            if !q.isEmpty { rResults = rResults.filter { $0.name.lowercased().contains(q) } }
            rows += rResults.map { r in
                let sc = scoreColors(Double(r.health_score))
                return Row(id: r.id, type: "recipe", title: r.name, category: "Recipe",
                           calories: "\(JSNumber.roundToInt(r.totals.kcal)) kcal", score: r.health_score,
                           nutriScore: "", nutriColor: sc.fg, nutriBg: sc.bg, iconKey: nil,
                           isFavorite: favoritesStore.isFavorite(.food, r.id))
            }
        }

        if searchFilter == "all" || searchFilter == "lists" || searchFilter == "receipts" {
            var sResults = scans
            if searchFilter == "lists" { sResults = sResults.filter { $0.isShoppingList == true } }
            if searchFilter == "receipts" { sResults = sResults.filter { $0.isShoppingList != true } }
            if !q.isEmpty { sResults = sResults.filter { ($0.recipeName ?? $0.date).lowercased().contains(q) } }
            rows += sResults.map { s in
                let sc = scoreColors(s.averageScore)
                return Row(id: s.id, type: s.isShoppingList == true ? "list" : "receipt",
                           title: s.recipeName ?? (s.isShoppingList == true ? "Shopping List" : "Receipt"),
                           category: s.date, calories: "\(s.items.count) items",
                           score: JSNumber.roundToInt(s.averageScore), nutriScore: "",
                           nutriColor: sc.fg, nutriBg: sc.bg, iconKey: nil,
                           isFavorite: favoritesStore.isFavorite(.food, s.id))
            }
        }

        return rows
    }

    private struct SwapRow: Identifiable { var id: String; var from: FoodItem; var to: FoodItem; var improvement: Int }

    private var swapResults: [SwapRow] {
        guard mode == .swaps else { return [] }
        var baseFoods = foodsStore.allFoods
        if !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            let q = searchQuery.lowercased()
            baseFoods = Array(baseFoods.filter { $0.name.lowercased().contains(q) || $0.category.lowercased().contains(q) }.prefix(10))
        } else {
            let lowScore = baseFoods.filter { $0.health_score < 50 }
            // `sort(() => 0.5 - Math.random())` - see PORTING_NOTES.md §"Still uncertain": same
            // algorithm and non-uniform bias via JSSort, not the same sequence (unseedable).
            baseFoods = Array(JSSort.sorted(lowScore) { _, _ in 0.5 - Double.random(in: 0..<1) }.prefix(20))
        }
        let safeFoods = foodsStore.foods(for: profileStore.profile.dietaryPreference)
        let pool = safeFoods.isEmpty ? foodsStore.allFoods : safeFoods
        return baseFoods.compactMap { badFood in
            let best = SwapAlgorithm.findBestSwaps(badFood, pool, 1, profileStore.profile.dietaryPreference.map(\.rawValue))
            guard let top = best.first else { return nil }
            return SwapRow(id: "\(badFood.id)-\(top.candidate.id)", from: badFood, to: top.candidate,
                            improvement: JSNumber.roundToInt(top.candidate.health_score) - JSNumber.roundToInt(badFood.health_score))
        }
    }

    private var isSearching: Bool { !searchQuery.isEmpty || showFilters }

    var body: some View {
        ZStack(alignment: .top) {
            Colors.background.ignoresSafeArea()

            TrackableScrollView(showsIndicators: false, onOffsetChange: { scrollY = $0 }) {
                ScrollOffsetReporter(coordinateSpace: "scroll")
                content
            }
            .padding(.top, 0)

            GlassHeader(title: "Search", onSettingsPress: nil, scrollY: scrollY, leftAccessory: {
                if let onBack {
                    GlassCircleButton(onPress: onBack) {
                        Image(systemName: "xmark").font(.system(size: 18, weight: .semibold)).foregroundColor(Colors.textPrimary)
                    }
                }
            }, rightAccessory: AnyView(
                GlassCircleButton(onPress: { showFilters.toggle() }) {
                    Image(systemName: "line.3.horizontal.decrease").font(.system(size: 20, weight: .semibold))
                        .foregroundColor(showFilters ? Colors.primaryGreen : Colors.textPrimary)
                }
            ))
        }
        .onAppear { Task { scans = await StorageService.getScans() } }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            LargeTitle(title: "Search", scrollY: scrollY).padding(.horizontal, 20)

            if let rawText {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CORRECTING ITEM").font(.system(size: 13, weight: .bold)).foregroundColor(Colors.primaryGreenDark)
                    Text("\"\(rawText)\"").font(.system(size: 16)).italic().foregroundColor(Colors.textPrimary)
                }
                .padding(12)
                .background(Colors.lightGreenBg)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Colors.scoreGreen, lineWidth: 1))
                .cornerRadius(12)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }

            if rawText == nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Self.filterTabs, id: \.self) { f in
                            let selected = searchFilter == f
                            Button(action: { searchFilter = f }) {
                                Text(f.prefix(1).uppercased() + f.dropFirst())
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(selected ? Colors.white : Colors.textSecondary)
                                    .padding(.horizontal, 16).padding(.vertical, 8)
                                    .background(selected ? Colors.primaryGreen : Colors.white)
                                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(selected ? Colors.primaryGreen : Colors.border, lineWidth: 1))
                                    .cornerRadius(20)
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 16)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 18)).foregroundColor(Colors.textMuted)
                TextField("Search thousands of foods...", text: $searchQuery)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(Colors.white)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Colors.border, lineWidth: 1))
            .cornerRadius(14)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            if showFilters { filterPanel }

            Text(sectionLabel)
                .font(.system(size: 11, weight: .bold)).tracking(0.8).foregroundColor(Colors.textMuted)
                .padding(.horizontal, 20)
                .padding(.top, isSearching ? 24 : 10)
                .padding(.bottom, 10)

            resultsList
        }
        .padding(.top, 8)
        .padding(.bottom, 100)
    }

    private var sectionLabel: String {
        switch mode {
        case .swaps: return isSearching ? "SWAP RESULTS (\(swapResults.count))" : "DISCOVER SMART SWAPS"
        case .foods: return isSearching ? "RESULTS (\(searchResults.count))" : "POPULAR FOODS"
        }
    }

    private var filterPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Favorites Only").font(.system(size: 15, weight: .bold)).foregroundColor(Colors.textPrimary)
                Spacer()
                Toggle("", isOn: $favoritesOnly).labelsHidden().tint(Colors.primaryGreen)
            }.padding(.bottom, 20)

            HStack {
                Text("Filters").font(.system(size: 16, weight: .bold)).foregroundColor(Colors.textPrimary)
                Spacer()
                Button("Clear all") {
                    category = "All"; maxCalories = 1000; nutriScores = []; favoritesOnly = false; searchQuery = ""
                }.font(.system(size: 14, weight: .semibold)).foregroundColor(Colors.primaryGreen)
            }.padding(.bottom, 16)

            Text("CATEGORY").font(.system(size: 12, weight: .bold)).tracking(0.5).foregroundColor(Colors.textMuted).padding(.bottom, 8)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(uniqueCategories, id: \.self) { cat in
                        let selected = category == cat
                        Button(action: { category = cat }) {
                            Text(cat).font(.system(size: 13, weight: .semibold))
                                .foregroundColor(selected ? Colors.white : Colors.textSecondary)
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                .background(selected ? Colors.primaryGreen : Colors.white)
                                .overlay(RoundedRectangle(cornerRadius: 20).stroke(selected ? Colors.primaryGreen : Colors.border, lineWidth: 1))
                                .cornerRadius(20)
                        }.buttonStyle(.plain)
                    }
                }
            }

            Text("NUTRI SCORE").font(.system(size: 12, weight: .bold)).tracking(0.5).foregroundColor(Colors.textMuted).padding(.top, 16)
            HStack(spacing: 8) {
                ForEach(Self.nutriGrades, id: \.self) { grade in
                    let selected = nutriScores.contains(grade)
                    Button(action: { if selected { nutriScores.remove(grade) } else { nutriScores.insert(grade) } }) {
                        Text(grade).font(.system(size: 15, weight: .bold))
                            .foregroundColor(selected ? Colors.white : Colors.textMuted)
                            .frame(width: 40, height: 40)
                            .background(selected ? Colors.primaryGreen : Colors.inputBackground)
                            .overlay(Circle().stroke(selected ? Colors.primaryGreen : Colors.border, lineWidth: 1))
                            .clipShape(Circle())
                    }.buttonStyle(.plain)
                }
            }.padding(.bottom, 20).padding(.top, 8)

            LiquidSlider(maxSliderVal: 1000, initialValue: maxCalories, title: "Max Calories (/ 100g)", unit: "kcal") { maxCalories = $0 }
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.4), lineWidth: 1))
        .cornerRadius(20)
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    @ViewBuilder
    private var resultsList: some View {
        VStack(spacing: 0) {
            if mode == .swaps {
                ForEach(swapResults.prefix(limit)) { swap in
                    SwapComparisonCard(fromFood: swap.from, toFood: swap.to, improvement: swap.improvement,
                                        onPressFrom: { onBack?(); router.openFood(swap.from.id) },
                                        onPressTo: { onBack?(); router.openFood(swap.to.id) })
                        .padding(.bottom, 16)
                }
            } else {
                ForEach(searchResults.prefix(limit)) { row in
                    resultCard(row)
                }
            }

            let count = mode == .swaps ? swapResults.count : searchResults.count
            if count > limit {
                Button(action: { limit += 20 }) {
                    Text("Load 20 More").font(.system(size: 15, weight: .bold)).foregroundColor(Colors.primaryGreen)
                        .frame(maxWidth: .infinity).padding(16)
                        .background(Colors.lightGreenBg).cornerRadius(14)
                }.buttonStyle(.plain).padding(.top, 10)
            }

            if count == 0 {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.system(size: 40)).foregroundColor(Colors.border)
                    Text("No results match your criteria.").font(.system(size: 14, weight: .medium)).foregroundColor(Colors.textMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
            }
        }
        .padding(.horizontal, 20)
    }

    private func resultCard(_ row: Row) -> some View {
        Button(action: { handleSelect(row) }) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 14).fill(Colors.cardBackground)
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: row.type == "food" ? getIconForCategory(row.category) : (row.type == "list" ? "basket" : (row.type == "receipt" ? "receipt" : "fork.knife")))
                            .font(.system(size: 20))
                            .foregroundColor(Colors.primaryGreen)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(row.title).font(.system(size: 15, weight: .bold)).foregroundColor(Colors.textPrimary).lineLimit(1)
                    Text("\(row.category) • \(row.calories)").font(.system(size: 13)).foregroundColor(Colors.textMuted)
                    if !row.nutriScore.isEmpty {
                        Text(row.nutriScore).font(.system(size: 10, weight: .heavy)).tracking(0.5).foregroundColor(row.nutriColor)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(row.nutriBg).cornerRadius(6)
                    }
                }

                Spacer(minLength: 0)

                VStack {
                    Button(action: { favoritesStore.toggleFavorite(.food, row.id) }) {
                        Image(systemName: row.isFavorite ? "heart.fill" : "heart")
                            .font(.system(size: 20))
                            .foregroundColor(row.isFavorite ? Color(hex: 0xFF3B30) : Colors.textMuted)
                    }.buttonStyle(.plain)
                    Spacer()
                    let scoreColor = scoreColors(Double(row.score)).fg
                    Circle().stroke(scoreColor, lineWidth: 3).frame(width: 34, height: 34)
                        .overlay(Text("\(row.score)").font(.system(size: 12, weight: .heavy)).foregroundColor(scoreColor))
                }
                .frame(height: 60)
            }
            .padding(12)
            .background(Colors.cardBackground)
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 12)
    }

    private func handleSelect(_ row: Row) {
        if let onSelect {
            if row.type == "food", let food = foodsStore.allFoods.first(where: { $0.id == row.id }) {
                onSelect(.food(food))
            } else if row.type == "recipe", let recipe = recipeStore.recipes.first(where: { $0.id == row.id }) {
                onSelect(.recipe(recipe))
            }
            onBack?()
            return
        }
        onBack?()
        switch row.type {
        case "receipt", "list": router.openReceipt(row.id)
        case "recipe": router.openRecipe(row.id)
        default: router.openFood(row.id)
        }
    }
}

#Preview {
    SearchScreen()
        .environmentObject(FoodsStore.shared)
        .environmentObject(FavoritesStore())
        .environmentObject(ProfileStore())
        .environmentObject(RecipeStore.shared)
        .environmentObject(Router())
}
