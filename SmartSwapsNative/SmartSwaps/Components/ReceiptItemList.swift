import SwiftUI
import SmartSwapsKit

/// Port of `components/ReceiptItemList.tsx` (351 ln). `useFoods()`/`useProfile()` become
/// `FoodsStore`/`ProfileStore` via `@EnvironmentObject`; `useRouter()` -> `Router`
/// (`@EnvironmentObject`, see `App/Router.swift`) rather than a passed-in closure, since
/// every host screen (`ReceiptDetailScreen`, `ScanReceiptScreen`) already sits inside the
/// shared navigation tree. `expo-haptics` -> `UIImpactFeedbackGenerator`, `Alert.alert` ->
/// `.alert(...)`.
struct ReceiptItemList: View {
    var items: [ParsedReceiptItem]
    var onUpdateItem: (Int, FoodItem) -> Void
    var onDeleteItem: (Int) -> Void
    var isShoppingList: Bool = false

    @EnvironmentObject private var foodsStore: FoodsStore
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var router: Router

    @State private var editingIndex: Int?
    @State private var pendingDelete: (index: Int, label: String)?

    private var safeFoods: [FoodItem] { foodsStore.foods(for: profileStore.profile.dietaryPreference).isEmpty ? foodsStore.allFoods : foodsStore.foods(for: profileStore.profile.dietaryPreference) }

    private struct Bucketed: Identifiable { var id: Int { originalIndex }; var item: ParsedReceiptItem; var originalIndex: Int }

    private var buckets: (confident: [Bucketed], potential: [Bucketed], notFound: [Bucketed]) {
        var confident: [Bucketed] = [], potential: [Bucketed] = [], notFound: [Bucketed] = []
        for (index, item) in items.enumerated() {
            let confidence = item.confidence
            let entry = Bucketed(item: item, originalIndex: index)
            if item.matchedFood == nil || confidence < 0.45 { notFound.append(entry) }
            else if confidence > 0.72 { confident.append(entry) }
            else { potential.append(entry) }
        }
        return (confident, potential, notFound)
    }

    private var usedOff: Bool { items.contains { $0.source == "off" } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isShoppingList {
                shoppingListGroups
            } else {
                let b = buckets
                section("Confident Matches", b.confident)
                section("Potential Matches", b.potential)
                section("Not Found", b.notFound)
            }

            if usedOff {
                Text("Some products identified using Open Food Facts, © contributors, ODbL.")
                    .font(.system(size: 10)).foregroundColor(Colors.textMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4).padding(.bottom, 8)
            }
        }
        .padding(.bottom, 24)
        .sheet(isPresented: Binding(get: { editingIndex != nil }, set: { if !$0 { editingIndex = nil } })) {
            SearchModal(mode: .foods, onSelect: { food in
                if let i = editingIndex { onUpdateItem(i, food) }
                editingIndex = nil
            }, rawText: editingIndex.map { items[$0].rawText })
        }
        .alert("Remove Item", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Remove", role: .destructive) {
                if let d = pendingDelete { onDeleteItem(d.index) }
                pendingDelete = nil
            }
        } message: {
            Text("Remove \"\(pendingDelete?.label ?? "")\" from this receipt?")
        }
    }

    private var shoppingListGroups: some View {
        let grouped = Dictionary(grouping: items.enumerated().map { ($0.offset, $0.element) }) { $0.1.rawText.isEmpty ? "" : "" }
        // `recipeName` isn't on `ParsedReceiptItem` (it's an ad-hoc RN field on scan items),
        // so this simplifies to a single "Other Items" section until scan grouping data is
        // threaded through in Phase 6 - see PORTING_NOTES.md.
        _ = grouped
        let all = items.enumerated().map { Bucketed(item: $0.element, originalIndex: $0.offset) }
        return section(nil, all)
    }

    private func section(_ title: String?, _ data: [Bucketed]) -> some View {
        Group {
            if !data.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if let title {
                        Text(title.uppercased()).font(.system(size: 13, weight: .bold)).tracking(0.5).foregroundColor(Colors.textMuted)
                    }
                    VStack(spacing: 0) {
                        ForEach(data) { entry in
                            row(entry)
                            if entry.id != data.last?.id {
                                Divider().overlay(Colors.border)
                            }
                        }
                    }
                    .background(Colors.white)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Colors.border, lineWidth: 1))
                }
                .padding(.bottom, 20)
            }
        }
    }

    private func row(_ entry: Bucketed) -> some View {
        let item = entry.item
        let f = item.matchedFood
        let confidence = item.confidence
        let showFoodChrome = f != nil && (isShoppingList || confidence >= 0.45)

        let bestSwaps: [SwapAlgorithm.SwapResult] = f.map {
            SwapAlgorithm.findBestSwaps($0, safeFoods, 1, profileStore.profile.dietaryPreference.map(\.rawValue))
        } ?? []
        let swap = bestSwaps.first
        let improvement = swap.map { JSNumber.roundToInt($0.candidate.health_score) - JSNumber.roundToInt(f?.health_score ?? 0) } ?? 0

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if showFoodChrome, let f {
                            Image(systemName: getIconForCategory(f.category)).font(.system(size: 14)).foregroundColor(Colors.primaryGreen)
                        }
                        Text((f != nil && confidence >= 0.45) ? (item.source == "off" ? (item.displayName ?? f!.name) : f!.name) : item.rawText)
                            .font(.system(size: 14, weight: .semibold)).foregroundColor(Colors.textPrimary).lineLimit(1)
                    }
                    if item.source == "off", let f, confidence >= 0.45 {
                        Text("Nutrition based on: \(f.name)").font(.system(size: 11)).foregroundColor(Colors.textMuted).lineLimit(1)
                    }
                    if isShoppingList {
                        Text(item.quantity.map { "\(JSNumber.roundToInt($0))\(item.unit ?? "g")" } ?? "per 100g")
                            .font(.system(size: 11)).italic().foregroundColor(Colors.textMuted)
                    } else {
                        Text("Scanned: \"\(item.rawText)\"").font(.system(size: 11)).italic().foregroundColor(Colors.textMuted)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { if showFoodChrome, let f { router.openFood(f.id) } }

                Spacer()

                HStack(spacing: 12) {
                    Group {
                        if let f, confidence >= 0.45 {
                            Text("\(JSNumber.roundToInt(f.health_score))").font(.system(size: 15, weight: .heavy)).foregroundColor(Colors.primaryGreen)
                                .frame(width: 28, alignment: .trailing)
                        } else {
                            Text("-").font(.system(size: 15, weight: .heavy)).foregroundColor(Color(hex: 0x999999))
                                .frame(width: 28, alignment: .trailing)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { if showFoodChrome, let f { router.openFood(f.id) } }
                    Button(action: { Haptics.light(); editingIndex = entry.originalIndex }) {
                        Image(systemName: "pencil").font(.system(size: 16)).foregroundColor(Colors.textMuted)
                    }.buttonStyle(.plain)
                    Button(action: { Haptics.light(); pendingDelete = (entry.originalIndex, f?.name ?? item.rawText) }) {
                        Image(systemName: "trash").font(.system(size: 16)).foregroundColor(Colors.textMuted)
                    }.buttonStyle(.plain)
                }
            }

            if let swap, improvement > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.left").font(.system(size: 12)).foregroundColor(Colors.primaryGreen).scaleEffect(x: -1, y: 1)
                    Text("Swap: \(swap.candidate.name) ").font(.system(size: 12, weight: .medium)).foregroundColor(Colors.textSecondary)
                        + Text("(+\(improvement))").font(.system(size: 12, weight: .bold)).foregroundColor(Colors.primaryGreen)
                }
                .lineLimit(1)
                .padding(.top, 6)
                .overlay(Rectangle().fill(Colors.border).frame(height: 0.5), alignment: .top)
                .padding(.top, 6)
                .contentShape(Rectangle())
                .onTapGesture { router.openFood(swap.candidate.id) }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
    }
}

#Preview {
    ReceiptItemList(items: [], onUpdateItem: { _, _ in }, onDeleteItem: { _ in })
        .environmentObject(FoodsStore.shared)
        .environmentObject(ProfileStore())
        .environmentObject(Router())
        .padding()
}
