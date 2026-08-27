import SwiftUI
import SmartSwapsKit

private let receiptMicroTargets: [String: Double] = [
    "calcium_mg": 1000, "iron_mg": 14, "magnesium_mg": 375, "potassium_mg": 2000,
    "zinc_mg": 10, "vitamin_c_mg": 80, "vitamin_d_ug": 5, "vitamin_a_ug": 800,
    "vitamin_e_mg": 12, "vitamin_b1_mg": 1.1, "vitamin_b2_mg": 1.4, "vitamin_b6_mg": 1.4,
    "vitamin_b12_ug": 2.5, "niacin_mg": 16, "folate_ug": 200, "phosphorus_mg": 700,
    "sodium_mg": 2000, "iodide_ug": 150,
]

/// Port of `app/receipt/[id].tsx` (500 ln). Pushed (not modal, unlike food/recipe detail) -
/// `Router.openReceipt` pushes it onto the shared `NavigationStack`. The native back chevron
/// (`headerBackButtonDisplayMode: 'minimal'` at the root `Stack` level) comes for free from
/// `NavigationStack`; the source's own `headerBlurEffect: 'none'` override plus its
/// separately-rendered `<NavBlur>` become a hidden system toolbar background with `NavBlur`
/// layered behind the content instead, so the feathered fade isn't fighting a second, opaque
/// system material.
struct ReceiptDetailScreen: View {
    var scanId: String

    @EnvironmentObject private var foodsStore: FoodsStore
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var inventoryStore: InventoryStore
    @Environment(\.dismiss) private var dismiss

    @State private var scan: ScanRecord?
    @State private var searchModalVisible = false
    @State private var macrosExpanded = false
    @State private var microsExpanded = false
    @State private var isEditingTitle = false
    @State private var editTitleText = ""

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EEE, MMMM d, yyyy"
        return f
    }()
    private static func parseDate(_ s: String) -> Date {
        ISO8601DateFormatter().date(from: s) ?? {
            let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.date(from: s) ?? Date()
        }()
    }

    private struct Totals {
        var kcal = 0.0, protein_g = 0.0, carbs_g = 0.0, sugars_g = 0.0, fat_g = 0.0
        var saturated_fat_g = 0.0, fiber_g = 0.0, salt_g = 0.0
        var micros: [String: Double] = [:]
    }

    private func computeTotals(_ scan: ScanRecord) -> Totals {
        var t = Totals()
        for item in scan.items {
            guard let food = item.matchedFoodId.flatMap({ foodsStore.byId[$0] }) else { continue }
            let factor = (item.quantity ?? 100) / 100
            let n = food.nutrients_per_100
            t.kcal += n.kcal * factor
            t.protein_g += n.protein_g * factor
            t.carbs_g += n.carbs_g * factor
            t.sugars_g += n.sugars_g * factor
            t.fat_g += n.fat_g * factor
            t.saturated_fat_g += n.saturated_fat_g * factor
            t.fiber_g += n.fiber_g * factor
            t.salt_g += n.salt_g * factor
            for key in Micros.keysInDeclarationOrder {
                t.micros[key, default: 0] += n.micros[key] * factor
            }
        }
        return t
    }

    var body: some View {
        Group {
            if let scan {
                ZStack(alignment: .top) {
                    Color(hex: 0xF9FAF9).ignoresSafeArea()
                    ScrollView(showsIndicators: false) {
                        content(scan)
                            .padding(.top, 8)
                    }
                    NavBlur(headerHeight: 44).allowsHitTesting(false)
                }
                .toolbarBackground(.hidden, for: .navigationBar)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .principal) { titleView(scan) } }
            } else {
                Color(hex: 0xF9FAF9).ignoresSafeArea()
            }
        }
        .onAppear { Task { await load() } }
        .sheet(isPresented: $searchModalVisible) {
            SearchModal(mode: .foods, onSelect: { food in Task { await handleAddItem(food: food) } })
        }
    }

    private func load() async {
        let scans = await StorageService.getScans()
        if let found = scans.first(where: { $0.id == scanId }) {
            scan = found
            editTitleText = found.recipeName?.isEmpty == false ? found.recipeName! : "Shopping List"
        }
    }

    private func titleView(_ scan: ScanRecord) -> some View {
        Group {
            if scan.isShoppingList == true, isEditingTitle {
                TextField("", text: $editTitleText)
                    .font(.system(size: 17, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 200)
                    .onSubmit { Task { await saveTitleEdit() } }
            } else {
                Button(action: { if scan.isShoppingList == true { isEditingTitle = true } }) {
                    HStack(spacing: 6) {
                        Text(scan.isShoppingList == true ? (scan.recipeName?.isEmpty == false ? scan.recipeName! : "Shopping List") : "Receipt Details")
                            .font(.system(size: 17, weight: .semibold)).foregroundColor(Colors.textPrimary)
                        if scan.isShoppingList == true {
                            Image(systemName: "pencil").font(.system(size: 13)).foregroundColor(Colors.textMuted)
                        }
                    }
                }.buttonStyle(.plain).disabled(scan.isShoppingList != true)
            }
        }
    }

    @ViewBuilder
    private func content(_ scan: ScanRecord) -> some View {
        let isList = scan.isShoppingList == true
        let targetMultiplier: Double = isList ? 7 : 1
        let listTargetCalories = Double(profileStore.targetCalories) * targetMultiplier
        let macros = profileStore.targetMacros
        let targetMacros = (
            protein: listTargetCalories * 0.2 / 4, carbs: listTargetCalories * 0.5 / 4,
            sugars: listTargetCalories * 0.1 / 4, fat: listTargetCalories * 0.3 / 9,
            satFat: listTargetCalories * 0.1 / 9, fiber: 30.0 * targetMultiplier, salt: 6.0 * targetMultiplier
        )
        _ = macros

        VStack(alignment: .leading, spacing: 0) {
            summaryCard(scan)

            Text("Items (\(scan.items.count))").font(.system(size: 20, weight: .bold)).foregroundColor(Color(hex: 0x1A1A1A)).padding(.bottom, 16)
            ReceiptItemList(items: scan.items.map { $0.resolved(in: foodsStore.byId) },
                             onUpdateItem: { index, food in Task { await handleUpdateItem(index: index, newFood: food) } },
                             onDeleteItem: { index in Task { await handleDeleteItem(index: index) } },
                             isShoppingList: isList)

            if isList {
                Button(action: { searchModalVisible = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle").font(.system(size: 20))
                        Text("Add Item via Search").font(.system(size: 16, weight: .bold))
                    }
                    .foregroundColor(Colors.primaryGreen)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Colors.lightGreenBg).cornerRadius(12)
                }.buttonStyle(.plain).padding(.top, 16)
            }

            let totals = computeTotals(scan)
            VStack(alignment: .leading, spacing: 0) {
                Text("List Nutrition").font(.system(size: 20, weight: .bold)).foregroundColor(Color(hex: 0x1A1A1A)).padding(.bottom, 16)

                Button(action: { withAnimation(.easeInOut) { macrosExpanded.toggle() } }) {
                    HStack(spacing: 8) {
                        Image(systemName: "chart.pie").font(.system(size: 15)).foregroundColor(Colors.primaryGreen)
                        Text(macrosExpanded ? "Hide Macronutrients" : "Show Macronutrients").font(.system(size: 14, weight: .bold)).foregroundColor(Colors.primaryGreen)
                        Spacer()
                        Image(systemName: macrosExpanded ? "chevron.up" : "chevron.down").font(.system(size: 15)).foregroundColor(Colors.primaryGreen)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(Colors.lightGreenBg).cornerRadius(12)
                }.buttonStyle(.plain).padding(.bottom, 14)

                if macrosExpanded {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(isList ? "MACRONUTRIENTS (WEEKLY TARGET)" : "MACRONUTRIENTS")
                            .font(.system(size: 12, weight: .bold)).tracking(0.5).foregroundColor(Colors.textMuted).padding(.bottom, 16)
                        NutrientRow(label: "Calories", value: totals.kcal, target: listTargetCalories, unit: " kcal", isLowerBetter: true)
                        NutrientRow(label: "Protein", value: totals.protein_g, target: targetMacros.protein, unit: "g", isLowerBetter: false)
                        NutrientRow(label: "Carbs", value: totals.carbs_g, target: targetMacros.carbs, unit: "g", isLowerBetter: true)
                        NutrientRow(label: "Sugars", value: totals.sugars_g, target: targetMacros.sugars, unit: "g", isLowerBetter: true)
                        NutrientRow(label: "Fat", value: totals.fat_g, target: targetMacros.fat, unit: "g", isLowerBetter: true)
                        NutrientRow(label: "Saturated Fat", value: totals.saturated_fat_g, target: targetMacros.satFat, unit: "g", isLowerBetter: true)
                        NutrientRow(label: "Fiber", value: totals.fiber_g, target: targetMacros.fiber, unit: "g", isLowerBetter: false)
                        NutrientRow(label: "Salt", value: totals.salt_g, target: targetMacros.salt, unit: "g", isLowerBetter: true)
                    }
                    .padding(18).background(Colors.white)
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Colors.border, lineWidth: 1))
                    .cornerRadius(20).shadow(color: Colors.shadowColor.opacity(0.04), radius: 8, x: 0, y: 2)
                    .padding(.bottom, 14)
                }

                Button(action: { withAnimation(.easeInOut) { microsExpanded.toggle() } }) {
                    HStack(spacing: 8) {
                        Image(systemName: "testtube.2").font(.system(size: 15)).foregroundColor(Colors.primaryGreen)
                        Text(microsExpanded ? "Hide Micronutrients" : "Show Micronutrients").font(.system(size: 14, weight: .bold)).foregroundColor(Colors.primaryGreen)
                        Spacer()
                        Image(systemName: microsExpanded ? "chevron.up" : "chevron.down").font(.system(size: 15)).foregroundColor(Colors.primaryGreen)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(Colors.lightGreenBg).cornerRadius(12)
                }.buttonStyle(.plain)

                if microsExpanded {
                    let rows: [(String, String, String, Bool)] = [
                        ("Calcium", "calcium_mg", "mg", false), ("Iron", "iron_mg", "mg", false),
                        ("Magnesium", "magnesium_mg", "mg", false), ("Potassium", "potassium_mg", "mg", false),
                        ("Zinc", "zinc_mg", "mg", false), ("Vitamin C", "vitamin_c_mg", "mg", false),
                        ("Vitamin D", "vitamin_d_ug", "μg", false), ("Vitamin A", "vitamin_a_ug", "μg", false),
                        ("Vitamin E", "vitamin_e_mg", "mg", false), ("Vitamin B1", "vitamin_b1_mg", "mg", false),
                        ("Vitamin B2", "vitamin_b2_mg", "mg", false), ("Vitamin B6", "vitamin_b6_mg", "mg", false),
                        ("Vitamin B12", "vitamin_b12_ug", "μg", false), ("Niacin", "niacin_mg", "mg", false),
                        ("Folate", "folate_ug", "μg", false), ("Phosphorus", "phosphorus_mg", "mg", false),
                        ("Sodium", "sodium_mg", "mg", true), ("Iodine", "iodide_ug", "μg", false),
                    ]
                    VStack(alignment: .leading, spacing: 0) {
                        Text(isList ? "ESSENTIAL MICRONUTRIENTS (WEEKLY TARGET)" : "ESSENTIAL MICRONUTRIENTS")
                            .font(.system(size: 12, weight: .bold)).tracking(0.5).foregroundColor(Colors.textMuted).padding(.bottom, 16)
                        ForEach(rows, id: \.1) { label, key, unit, lowerBetter in
                            NutrientRow(label: label, value: totals.micros[key] ?? 0,
                                        target: (receiptMicroTargets[key] ?? 1) * targetMultiplier, unit: unit, isLowerBetter: lowerBetter)
                        }
                    }
                    .padding(18).background(Colors.white)
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Colors.border, lineWidth: 1))
                    .cornerRadius(20).shadow(color: Colors.shadowColor.opacity(0.04), radius: 8, x: 0, y: 2)
                }
            }
            .padding(.top, 24)

            if isList {
                Button(action: { Task { await deleteList() } }) {
                    HStack(spacing: 8) {
                        Image(systemName: "trash").font(.system(size: 18))
                        Text("Delete Shopping List").font(.system(size: 16, weight: .bold))
                    }
                    .foregroundColor(Color(hex: 0xFF3B30))
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Color(hex: 0xFFF0F0)).cornerRadius(12)
                }.buttonStyle(.plain).padding(.top, 24).padding(.bottom, 40)
            }
        }
        .padding(24)
    }

    private func summaryCard(_ scan: ScanRecord) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(Self.dateFormatter.string(from: Self.parseDate(scan.date))).font(.system(size: 16, weight: .semibold)).foregroundColor(Colors.textSecondary)
            HStack {
                Text("Overall Health Score").font(.system(size: 15, weight: .medium)).foregroundColor(Colors.textPrimary)
                Spacer()
                Text("\(JSNumber.roundToInt(scan.averageScore)) / 100").font(.system(size: 24, weight: .heavy)).foregroundColor(Colors.primaryGreen)
            }
        }
        .padding(20)
        .background(scan.isShoppingList == true ? Color(hex: 0xF0F8FF) : Colors.white)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(scan.isShoppingList == true ? Color(hex: 0xB3E0FF) : Colors.border, lineWidth: 1))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.02), radius: 4, x: 0, y: 2)
        .padding(.bottom, 32)
    }

    private func saveTitleEdit() async {
        isEditingTitle = false
        guard var current = scan, current.recipeName != editTitleText.trimmingCharacters(in: .whitespaces) else { return }
        current.recipeName = editTitleText.trimmingCharacters(in: .whitespaces)
        await saveScanUpdates(current)
    }

    private func saveScanUpdates(_ updated: ScanRecord) async {
        scan = updated
        await StorageService.updateScan(id: updated.id, updatedScan: updated)
        await inventoryStore.refreshInventory()
    }

    private func recalculateAndUpdate(_ newItems: [PersistedReceiptItem]) async {
        guard let scan else { return }
        var totalScore = 0.0
        var matchedCount = 0
        for item in newItems {
            if let food = item.matchedFoodId.flatMap({ foodsStore.byId[$0] }) {
                totalScore += food.health_score
                matchedCount += 1
            }
        }
        let averageScore = matchedCount > 0 ? Double(JSNumber.roundToInt(totalScore / Double(matchedCount))) : 0
        var updated = scan
        updated.items = newItems
        updated.averageScore = averageScore
        await saveScanUpdates(updated)
    }

    private func handleUpdateItem(index: Int, newFood: FoodItem) async {
        guard let scan, scan.items.indices.contains(index) else { return }
        var newItems = scan.items
        let corrected = newItems[index]
        newItems[index] = PersistedReceiptItem(rawText: corrected.rawText, matchedFoodId: newFood.id, confidence: 1.0,
                                                source: corrected.source, displayName: corrected.displayName,
                                                quantity: corrected.quantity, unit: corrected.unit)
        await OverrideStore.shared.set(corrected.rawText, newFood.id)
        await recalculateAndUpdate(newItems)
    }

    private func handleDeleteItem(index: Int) async {
        guard let scan, scan.items.indices.contains(index) else { return }
        var newItems = scan.items
        newItems.remove(at: index)
        await recalculateAndUpdate(newItems)
    }

    private func handleAddItem(food: FoodItem) async {
        guard let scan else { return }
        let newItem = PersistedReceiptItem(rawText: food.name, matchedFoodId: food.id, confidence: 1.0,
                                            source: "local", quantity: 100, unit: "g")
        await recalculateAndUpdate(scan.items + [newItem])
        searchModalVisible = false
    }

    private func deleteList() async {
        guard let scan else { return }
        await StorageService.deleteScan(id: scan.id)
        await inventoryStore.refreshInventory()
        dismiss()
    }
}

#Preview {
    NavigationStack {
        ReceiptDetailScreen(scanId: "preview")
    }
    .environmentObject(FoodsStore.shared)
    .environmentObject(ProfileStore())
    .environmentObject(InventoryStore())
    .environmentObject(Router())
}
