import SwiftUI
import SmartSwapsKit

/// Port of `app/food/[id].tsx` (716 ln). Presented as an iOS sheet (PORTING_INVENTORY.md §8:
/// `presentation: 'modal'`), so the RN native-stack back chevron becomes a close button here
/// rather than a pushed-screen back arrow - there's nothing under it to pop back to inside a
/// sheet. `useHeaderHeight()`/`Stack.Screen`'s `headerRight` become a small custom floating
/// header bar (close + favorite), matching `GlassCircleButton`'s look, with `NavBlur` behind
/// it exactly as the source renders it as a decorative, non-interactive layer.
struct FoodDetailScreen: View {
    var onClose: () -> Void

    @EnvironmentObject private var foodsStore: FoodsStore
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var favoritesStore: FavoritesStore
    @EnvironmentObject private var inventoryStore: InventoryStore

    private static let swapDisplayCount = 2
    private static let headerHeight: CGFloat = 44

    /// The RN screen reads `id` from the route on every navigation; `router.replace(...)`
    /// (accepting a swap) swaps this screen's content in place rather than pushing/re-
    /// presenting a new one - reproduced here as internal `@State` seeded from `foodId`,
    /// updated by `acceptSwap`, rather than telling `RootView` to represent a new sheet
    /// (which would dismiss-and-reanimate instead of updating in place).
    @State private var currentFoodId: String
    @State private var swapPool: [SwapAlgorithm.SwapResult] = []
    @State private var swapsLoaded = false
    @State private var dismissedSwapIds: Set<String> = []
    @State private var shoppingListModalVisible = false
    @State private var macrosExpanded = true
    @State private var microsExpanded = false
    @State private var isAdded = false
    @State private var addedScale: CGFloat = 1
    @State private var ringScale: CGFloat = 0.8
    @State private var trophyScale: CGFloat = 1

    private static let micronutrientDV: [String: Double] = [
        "Vitamin A": 900, "Vitamin C": 90, "Vitamin D": 20, "Vitamin E": 15, "Vitamin K": 120,
        "Thiamin": 1.2, "Riboflavin": 1.3, "Niacin": 16, "Vitamin B6": 1.7, "Folate": 400,
        "Vitamin B12": 2.4, "Biotin": 30, "Pantothenic Acid": 5, "Calcium": 1300, "Iron": 18,
        "Phosphorus": 1250, "Iodine": 150, "Magnesium": 420, "Zinc": 11, "Selenium": 55,
        "Copper": 0.9, "Manganese": 2.3, "Chromium": 35, "Molybdenum": 45, "Chloride": 2300,
        "Potassium": 4700, "Sodium": 2300,
    ]

    init(foodId: String, onClose: @escaping () -> Void) {
        self.onClose = onClose
        _currentFoodId = State(initialValue: foodId)
    }

    private var food: FoodItem? { foodsStore.allFoods.first { $0.id == currentFoodId } ?? foodsStore.allFoods.first }
    private var isFav: Bool { food.map { favoritesStore.isFavorite(.food, $0.id) } ?? false }

    private var visibleSwaps: [SwapAlgorithm.SwapResult] {
        Array(swapPool.filter { !dismissedSwapIds.contains($0.candidate.id) }.prefix(Self.swapDisplayCount))
    }
    private var isBestInCategory: Bool { swapsLoaded && visibleSwaps.isEmpty && (food?.health_score ?? 0) >= 80 }

    private func scoreColor(_ val: Int) -> Color {
        if val >= 75 { return Colors.scoreGreen }
        if val >= 50 { return Colors.Local.amber }
        return Colors.scoreRed
    }

    var body: some View {
        Group {
            if let food {
                ZStack(alignment: .top) {
                    Colors.Local.screenBg1.ignoresSafeArea()
                    ScrollView(showsIndicators: false) {
                        content(for: food)
                            .padding(.top, Self.headerHeight + 8)
                    }
                    NavBlur(headerHeight: Self.headerHeight)
                    header(for: food)
                }
            } else {
                ProgressView("Loading food details...").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: currentFoodId) {
            ringScale = 0.8
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { ringScale = 1 }
            await loadSwaps()
        }
        .sheet(isPresented: $shoppingListModalVisible) {
            SelectShoppingListModal(onSelect: { listId, newName in Task { await handleAddToList(listId: listId, newListName: newName) } },
                                     onClose: { shoppingListModalVisible = false })
                .environmentObject(inventoryStore)
        }
    }

    private func header(for food: FoodItem) -> some View {
        HStack {
            GlassCircleButton(onPress: onClose) {
                Image(systemName: "xmark").font(.system(size: 18, weight: .semibold)).foregroundColor(Colors.textPrimary)
            }
            Spacer()
            GlassCircleButton(onPress: { favoritesStore.toggleFavorite(.food, food.id) }) {
                Image(systemName: isFav ? "heart.fill" : "heart").font(.system(size: 18))
                    .foregroundColor(isFav ? Color(hex: 0xFF3B30) : Colors.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: Self.headerHeight)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func content(for food: FoodItem) -> some View {
        let nutrients = food.nutrients_per_100
        VStack(alignment: .leading, spacing: 0) {
            topSection(food)

            if swapsLoaded && visibleSwaps.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Smarter Swaps").font(.system(size: 20, weight: .bold)).foregroundColor(Colors.textPrimary).padding(.bottom, 12)
                    HStack(spacing: 10) {
                        Image(systemName: isBestInCategory ? "trophy.fill" : "trophy")
                            .font(.system(size: 22)).foregroundColor(Colors.primaryGreen)
                            .scaleEffect(trophyScale)
                        Text(food.health_score >= 80 ? "You already have the best option in this category!" : "No healthier swaps found in our database.")
                            .font(.system(size: 14, weight: .semibold)).foregroundColor(Colors.primaryGreen)
                    }
                    .padding(16)
                    .background(Colors.lightGreenBg)
                    .cornerRadius(20)
                }
                .padding(.top, 32)
                .onAppear {
                    guard isBestInCategory else { return }
                    withAnimation(.easeInOut(duration: 0.18)) { trophyScale = 1.3 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) { trophyScale = 1 }
                    }
                }
            }

            if !visibleSwaps.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Smarter Swaps").font(.system(size: 20, weight: .bold)).foregroundColor(Colors.textPrimary).padding(.bottom, 12)
                    ForEach(visibleSwaps, id: \.candidate.id) { swap in
                        swapCard(food, swap)
                    }
                }
                .padding(.top, 32)
            }

            VStack(alignment: .leading, spacing: 0) {
                macrosToggle
                if macrosExpanded { macrosCard(nutrients) }
                microsToggle.padding(.top, macrosExpanded ? 0 : 12)
                if microsExpanded { microsCard(nutrients) }
            }
            .padding(.top, 32)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 40)
    }

    private func topSection(_ food: FoodItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: getIconForCategory(food.category)).font(.system(size: 12)).foregroundColor(Colors.primaryGreen)
                Text(food.category.uppercased()).font(.system(size: 10, weight: .heavy)).tracking(0.5).foregroundColor(Colors.primaryGreen)
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Colors.lightGreenBg).cornerRadius(12)
            .padding(.bottom, 16)

            HStack(alignment: .top) {
                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: 16).fill(Colors.cardBackground).frame(width: 52, height: 52)
                        .overlay(FoodIcon(iconKey: food.icon_key, category: food.category, size: 30))
                    VStack(alignment: .leading, spacing: 8) {
                        Text(food.name).font(.system(size: 32, weight: .heavy)).foregroundColor(Colors.textPrimary).lineSpacing(4)
                        Text("per 100g").font(.system(size: 14)).foregroundColor(Colors.textSecondary)
                        (Text("\(JSNumber.roundToInt(food.nutrients_per_100.kcal)) ").font(.system(size: 24, weight: .heavy)).foregroundColor(Colors.primaryGreen)
                            + Text("kcal / 100g").font(.system(size: 14, weight: .medium)).foregroundColor(Colors.textSecondary))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Circle().stroke(scoreColor(JSNumber.roundToInt(food.health_score)), lineWidth: 6).frame(width: 80, height: 80)
                    .overlay(Text("\(JSNumber.roundToInt(food.health_score))").font(.system(size: 28, weight: .heavy)).foregroundColor(scoreColor(JSNumber.roundToInt(food.health_score))))
                    .scaleEffect(ringScale)
            }

            Button(action: {
                guard !isAdded else { return }
                shoppingListModalVisible = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: isAdded ? "checkmark.circle.fill" : "basket").font(.system(size: 18))
                    Text(isAdded ? "Added to Shopping List!" : "Add to Shopping List").font(.system(size: 15, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(isAdded ? Colors.primaryGreen : Color(hex: 0x0084C9))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .scaleEffect(addedScale)
            .padding(.top, 16)
        }
        .padding(.bottom, 32)
    }

    private func swapCard(_ food: FoodItem, _ swap: SwapAlgorithm.SwapResult) -> some View {
        Button(action: { acceptSwap(food, swap) }) {
            HStack {
                RoundedRectangle(cornerRadius: 16).fill(Color(hex: 0xF5F7F5)).frame(width: 48, height: 48)
                    .overlay(Image(systemName: "leaf").font(.system(size: 24)).foregroundColor(Colors.primaryGreen))
                VStack(alignment: .leading, spacing: 2) {
                    Text("RECOMMENDED").font(.system(size: 10, weight: .heavy)).foregroundColor(Colors.primaryGreen)
                    Text(swap.candidate.name).font(.system(size: 16, weight: .bold)).foregroundColor(Colors.textPrimary)
                    Text(swap.candidate.category).font(.system(size: 12)).foregroundColor(Colors.textSecondary)
                }
                .padding(.leading, 12)
                Spacer(minLength: 8)
                Text("\(JSNumber.roundToInt(swap.candidate.health_score)) / 100").font(.system(size: 12, weight: .bold)).foregroundColor(Colors.primaryGreen)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color(hex: 0xF5F7F5)).cornerRadius(16)
                Button(action: { rejectSwap(food, swap) }) {
                    Image(systemName: "xmark").font(.system(size: 16)).foregroundColor(Colors.textSecondary)
                }.buttonStyle(.plain).padding(.leading, 10)
            }
            .padding(16)
            .background(Colors.white)
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 12)
    }

    private var macrosToggle: some View {
        Button(action: { withAnimation(.easeInOut) { macrosExpanded.toggle() } }) {
            HStack(spacing: 6) {
                Image(systemName: "chart.pie").font(.system(size: 15)).foregroundColor(Colors.primaryGreen)
                Text(macrosExpanded ? "Hide Macronutrients" : "Show Macronutrients").font(.system(size: 13, weight: .semibold)).foregroundColor(Colors.primaryGreenDark)
                Spacer()
                Image(systemName: macrosExpanded ? "chevron.up" : "chevron.down").font(.system(size: 15)).foregroundColor(Colors.primaryGreen)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Colors.lightGreenBg).cornerRadius(12)
        }.buttonStyle(.plain)
    }

    private var microsToggle: some View {
        Button(action: { withAnimation(.easeInOut) { microsExpanded.toggle() } }) {
            HStack(spacing: 6) {
                Image(systemName: "testtube.2").font(.system(size: 15)).foregroundColor(Colors.primaryGreen)
                Text(microsExpanded ? "Hide Micronutrients" : "Show Micronutrients").font(.system(size: 13, weight: .semibold)).foregroundColor(Colors.primaryGreenDark)
                Spacer()
                Image(systemName: microsExpanded ? "chevron.up" : "chevron.down").font(.system(size: 15)).foregroundColor(Colors.primaryGreen)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Colors.lightGreenBg).cornerRadius(12)
        }.buttonStyle(.plain)
    }

    private func macrosCard(_ n: FoodNutrients) -> some View {
        let macros = profileStore.targetMacros
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Per 100g (% of Daily Value)").font(.system(size: 13)).foregroundColor(Colors.textSecondary)
                Spacer()
                Text("Source: BLS 4.0").font(.system(size: 10, weight: .semibold)).foregroundColor(Colors.primaryGreen)
                    .padding(.horizontal, 8).padding(.vertical, 4).background(Colors.lightGreenBg).cornerRadius(8)
            }
            .padding(.bottom, 16)

            nutritionBar("Protein", n.protein_g, "g", Double(macros.protein))
            nutritionBar("Carbohydrates", n.carbs_g, "g", Double(macros.carbs))
            nutritionBar("Sugars", n.sugars_g, "g", Double(macros.sugars))
            nutritionBar("Total Fat", n.fat_g, "g", Double(macros.fat))
            nutritionBar("Saturated Fat", n.saturated_fat_g, "g", Double(macros.satFat))
            nutritionBar("Fiber", n.fiber_g, "g", Double(macros.fiber))
            nutritionBar("Salt", n.salt_g, "g", Double(macros.salt))
        }
        .padding(20)
        .background(Colors.white)
        .cornerRadius(24)
        .shadow(color: .black.opacity(0.03), radius: 12, x: 0, y: 4)
        .padding(.bottom, 16)
    }

    private func nutritionBar(_ label: String, _ value: Double, _ unit: String, _ dv: Double) -> some View {
        let percent = dv != 0 ? JSNumber.roundToInt(value / dv * 100) : 0
        return VStack(spacing: 0) {
            HStack(alignment: .lastTextBaseline) {
                Text(label).font(.system(size: 14, weight: .semibold)).foregroundColor(Colors.textPrimary)
                Spacer()
                Text("\(trimmed(value))\(unit)").font(.system(size: 14, weight: .bold)).foregroundColor(Colors.textPrimary).padding(.trailing, 12)
                Text("\(percent)%").font(.system(size: 14, weight: .bold)).foregroundColor(Colors.primaryGreen).frame(width: 40, alignment: .trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0xF0F0F0))
                    RoundedRectangle(cornerRadius: 2).fill(Colors.primaryGreen)
                        .frame(width: geo.size.width * CGFloat(min(percent, 100)) / 100)
                }
            }
            .frame(height: 4)
            .padding(.top, 8)
        }
        .padding(.bottom, 16)
    }

    private func microsCard(_ n: FoodNutrients) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Vitamins & Minerals (per 100g)").font(.system(size: 16, weight: .heavy)).foregroundColor(Colors.textPrimary).padding(.bottom, 20)
            ForEach(Micros.keysInDeclarationOrder, id: \.self) { key in
                let value = n.micros[key]
                if value != 0 {
                    vitaminRow(formatMicroName(key), value, formatMicroUnit(key))
                }
            }
        }
        .padding(20)
        .background(Colors.white)
        .cornerRadius(24)
        .shadow(color: .black.opacity(0.03), radius: 12, x: 0, y: 4)
    }

    private func vitaminRow(_ label: String, _ value: Double, _ unit: String) -> some View {
        let dv = Self.micronutrientDV[label]
        let percent = dv.map { JSNumber.roundToInt(value / $0 * 100) }
        return HStack {
            Text(label).font(.system(size: 14)).foregroundColor(Colors.textSecondary)
            Spacer()
            Text("\(trimmed(value))\(unit)").font(.system(size: 14, weight: .bold)).foregroundColor(Colors.textPrimary).padding(.trailing, 16)
            Text(percent.map { "\($0)%" } ?? "N/A").font(.system(size: 14, weight: .semibold)).foregroundColor(Colors.primaryGreen).frame(width: 32, alignment: .trailing)
        }
        .padding(.vertical, 12)
        .overlay(Rectangle().fill(Color(hex: 0xF0F0F0)).frame(height: 1), alignment: .bottom)
    }

    private func trimmed(_ v: Double) -> String { JSNumber.toString(v) }

    /// `key.replace(/_(mg|ug)$/i, '').replace(/_/g, ' ')` then title-case, with a
    /// `betacarotene` -> `Beta-Carotene` special case.
    private func formatMicroName(_ key: String) -> String {
        var name = key
        for suffix in ["_mg", "_ug", "_Mg", "_Ug", "_MG", "_UG"] where name.hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
            break
        }
        name = name.replacingOccurrences(of: "_", with: " ")
        if name.lowercased() == "betacarotene" { return "Beta-Carotene" }
        return name.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    private func formatMicroUnit(_ key: String) -> String {
        if key.hasSuffix("_ug") { return "µg" }
        if key.hasSuffix("_mg") { return "mg" }
        return ""
    }

    private func loadSwaps() async {
        guard let food else { return }
        swapsLoaded = false
        dismissedSwapIds = []
        let pool = foodsStore.foods(for: profileStore.profile.dietaryPreference)
        let swaps = await SwapAlgorithm.findBestSwapsPersonalized(food, pool, 8, profileStore.profile.dietaryPreference.map(\.rawValue))
        swapPool = swaps
        swapsLoaded = true
    }

    private func acceptSwap(_ food: FoodItem, _ swap: SwapAlgorithm.SwapResult) {
        Task {
            await PersonalSwapPreferences.shared.recordSwapAccepted(swap.candidate.swiss_category, swap.candidate.id)
            await SwapTrainingLog.shared.logSwapDecision(
                source: food, candidate: swap.candidate, accepted: true,
                liquidMismatch: SwapAlgorithm.isLiquid(food) != SwapAlgorithm.isLiquid(swap.candidate) ? 1 : 0,
                rawIngredientMismatch: SwapAlgorithm.isRawIngredient(food) != SwapAlgorithm.isRawIngredient(swap.candidate) ? 1 : 0)
        }
        currentFoodId = swap.candidate.id
    }

    private func rejectSwap(_ food: FoodItem, _ swap: SwapAlgorithm.SwapResult) {
        Task {
            await PersonalSwapPreferences.shared.recordSwapRejected(swap.candidate.swiss_category, swap.candidate.id)
            await SwapTrainingLog.shared.logSwapDecision(
                source: food, candidate: swap.candidate, accepted: false,
                liquidMismatch: SwapAlgorithm.isLiquid(food) != SwapAlgorithm.isLiquid(swap.candidate) ? 1 : 0,
                rawIngredientMismatch: SwapAlgorithm.isRawIngredient(food) != SwapAlgorithm.isRawIngredient(swap.candidate) ? 1 : 0)
        }
        dismissedSwapIds.insert(swap.candidate.id)
    }

    private func handleAddToList(listId: String?, newListName: String?) async {
        guard let food else { return }
        let newItem = PersistedReceiptItem(rawText: food.name, matchedFoodId: food.id, confidence: 1.0,
                                            source: "local", quantity: 100, unit: "g")

        if let listId {
            if let existing = inventoryStore.shoppingLists.first(where: { $0.id == listId }) {
                var updatedItems = existing.items
                updatedItems.append(newItem)
                let validScores = updatedItems.compactMap { $0.matchedFoodId.flatMap { foodsStore.byId[$0]?.health_score } }
                let avgScore = validScores.isEmpty ? 50 : JSNumber.roundToInt(Double(validScores.reduce(0, +)) / Double(validScores.count))
                await StorageService.updateScan(id: listId, updatedScan: ScanRecord(
                    id: existing.id, date: existing.date, items: updatedItems, averageScore: Double(avgScore),
                    interactions: existing.interactions, isShoppingList: existing.isShoppingList, recipeName: existing.recipeName))
            }
        } else {
            let iso = ISO8601DateFormatter().string(from: Date())
            await StorageService.saveScan(id: UUID().uuidString, date: iso, items: [newItem],
                                           averageScore: Double(food.health_score), isShoppingList: true,
                                           recipeName: (newListName?.isEmpty == false ? newListName! : "Custom List"))
        }

        await inventoryStore.refreshInventory()
        shoppingListModalVisible = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.4)) { addedScale = 1.06 }
            isAdded = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { addedScale = 1 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                isAdded = false
                withAnimation(.spring(response: 0.25, dampingFraction: 0.4)) { addedScale = 1.06 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { addedScale = 1 }
                }
            }
        }
    }
}

#Preview {
    FoodDetailScreen(foodId: "preview", onClose: {})
        .environmentObject(FoodsStore.shared)
        .environmentObject(ProfileStore())
        .environmentObject(FavoritesStore())
        .environmentObject(InventoryStore())
}
