import SwiftUI
import SmartSwapsKit

/// Port of `app/(tabs)/index.tsx` (415 ln, "Today" tab, titled "Groceries"). Replaces the
/// Phase 1 placeholder. `ActionSheetIOS.showActionSheetWithOptions` -> `.confirmationDialog`;
/// the RN Android branch (`Alert.alert` with one row per option) has no separate Swift path
/// since this port is iOS-only.
struct HomeScreen: View {
    @EnvironmentObject private var foodsStore: FoodsStore
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var inventoryStore: InventoryStore
    @EnvironmentObject private var router: Router

    @State private var searchVisible = false
    @State private var nutritionModalVisible = false
    @State private var dietaryPickerVisible = false
    @State private var scrollY: CGFloat = 0

    private static let dietaryOptions: [DietaryPreference] = [.balanced, .highProtein, .lowCarb, .vegetarian, .vegan]

    private var currentPreference: DietaryPreference { profileStore.profile.dietaryPreference.first ?? .balanced }

    private var avgWeeklyPoints: Int {
        let scans = inventoryStore.scans
        guard !scans.isEmpty else { return 0 }
        let total = scans.reduce(0.0) { $0 + $1.averageScore }
        return JSNumber.roundToInt(total / Double(scans.count))
    }

    private var uniquePurchasedFoods: [FoodItem] {
        var map: [String: FoodItem] = [:]
        var order: [String] = []
        for scan in inventoryStore.scans {
            for item in scan.items {
                guard let id = item.matchedFoodId, let food = foodsStore.byId[id] else { continue }
                if map[id] == nil { order.append(id) }
                map[id] = food
            }
        }
        return order.compactMap { map[$0] }
    }

    private struct CarouselPlan {
        var spotlight: FoodItem?
        var items: [FoodItem]
        var initialScrollIndex: Int
    }

    private var carouselPlan: CarouselPlan {
        let foods = foodsStore.foods(for: profileStore.profile.dietaryPreference)
        let purchased = uniquePurchasedFoods
        var items: [FoodItem] = []

        if !purchased.isEmpty {
            let pool = foods.isEmpty ? foodsStore.allFoods : foods
            var candidateOrder: [String] = []
            var candidates: [String: FoodItem] = [:]
            for badFood in purchased {
                let swaps = SwapAlgorithm.findBestSwaps(badFood, pool, 2, profileStore.profile.dietaryPreference.map(\.rawValue))
                for swap in swaps where candidates[swap.candidate.id] == nil {
                    candidates[swap.candidate.id] = swap.candidate
                    candidateOrder.append(swap.candidate.id)
                }
            }
            items = candidateOrder.compactMap { candidates[$0] }
        }

        if items.count < 5 {
            let existingIds = Set(items.map(\.id))
            let healthy = foods.filter { $0.health_score >= 60 && !existingIds.contains($0.id) }
            let shuffled = JSSort.sorted(healthy) { _, _ in 0.5 - Double.random(in: 0..<1) }
            items += shuffled.prefix(5 - items.count)
        }

        items = Array(items.prefix(5))

        let spotlight = items.first ?? foods.first
        let recommended = items.count > 1 ? Array(items.dropFirst()) : []
        let centerIndex = recommended.count / 2

        var finalItems = recommended
        if let spotlight {
            finalItems = Array(recommended.prefix(centerIndex)) + [spotlight] + Array(recommended.dropFirst(centerIndex))
        }

        return CarouselPlan(spotlight: spotlight, items: finalItems, initialScrollIndex: spotlight != nil ? centerIndex : 0)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Colors.background.ignoresSafeArea()

            if !foodsStore.isLoaded {
                ProgressView().tint(Colors.primaryGreen)
            } else {
                TrackableScrollView(showsIndicators: false, onOffsetChange: { scrollY = $0 }) {
                    ScrollOffsetReporter(coordinateSpace: "scroll")
                    content
                }

                GlassHeader(title: "Groceries", onSettingsPress: { router.openSettings() }, scrollY: scrollY, leftAccessory: { EmptyView() })
            }
        }
        .sheet(isPresented: $searchVisible) { SearchModal() }
        .overlay { if nutritionModalVisible { NutritionModal(isPresented: $nutritionModalVisible) } }
        .confirmationDialog("Dietary Preference", isPresented: $dietaryPickerVisible, titleVisibility: .visible) {
            ForEach(Self.dietaryOptions, id: \.self) { option in
                Button(option.rawValue) { profileStore.updateProfile { $0.dietaryPreference = [option] } }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            LargeTitle(title: "Groceries", scrollY: scrollY)

            HStack(alignment: .top) {
                Text("Smart Nutrition Guide").subtitleText()
                Spacer()
                Button(action: { nutritionModalVisible = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill").font(.system(size: 14))
                        Text("\(JSNumber.toLocaleStringDE(Double(profileStore.targetCalories))) kcal").font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(Colors.primaryGreenDark)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Colors.lightGreenBg).cornerRadius(12)
                }.buttonStyle(.plain)
            }
            .padding(.bottom, 6)

            Button(action: { router.openSettings() }) {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 14))
                    Text("Personalise • \(profileStore.profile.dietaryPreference.contains(.balanced) ? "Recommended" : profileStore.profile.dietaryPreference.map(\.rawValue).joined(separator: ", "))")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(Colors.primaryGreen)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Colors.white)
                .overlay(Capsule().stroke(Colors.borderDark, lineWidth: 1))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 16)

            HealthPointsCard(percentage: Double(avgWeeklyPoints), onScanPress: { router.openScan() })

            if !inventoryStore.shoppingLists.isEmpty {
                shoppingListsSection
            }

            HStack {
                Text("Food carousel").sectionTitleText()
                Spacer()
                Button(action: { dietaryPickerVisible = true }) {
                    Text(currentPreference.rawValue).font(.system(size: 12, weight: .bold)).foregroundColor(Colors.primaryGreen)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(Colors.lightGreenBg).cornerRadius(12)
                }.buttonStyle(.plain)
            }
            .padding(.top, 10).padding(.bottom, 12)

            let plan = carouselPlan
            CoverFlowCarousel(data: plan.items, keyExtractor: { item, _ in item.id }, initialScrollIndex: plan.initialScrollIndex) { item, _ in
                Button(action: { router.openFood(item.id) }) {
                    SpotlightCard(
                        title: item.name, score: JSNumber.roundToInt(item.health_score),
                        categoryLabel: item.id == plan.spotlight?.id ? "TODAY'S SPOTLIGHT" : "RECOMMENDED",
                        iconName: getIconForCategory(item.category),
                        calories: "\(JSNumber.roundToInt(item.nutrients_per_100.kcal)) kcal / 100g",
                        protein: "\(JSNumber.roundToInt(item.nutrients_per_100.protein_g))g",
                        carbs: "\(JSNumber.roundToInt(item.nutrients_per_100.carbs_g))g",
                        fat: "\(JSNumber.roundToInt(item.nutrients_per_100.fat_g))g",
                        isHighlighted: item.id == plan.spotlight?.id
                    )
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, -20)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 120)
    }

    private var shoppingListsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your Shopping Lists").sectionTitleText()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(inventoryStore.shoppingLists) { list in
                        let previewFoods = Array(list.items.compactMap { $0.matchedFoodId.flatMap { foodsStore.byId[$0] } }.prefix(3))
                        Button(action: { router.openReceipt(list.id) }) {
                            HStack {
                                Circle().fill(Color(hex: 0xD0EFFF)).frame(width: 48, height: 48)
                                    .overlay(Image(systemName: "basket").font(.system(size: 24)).foregroundColor(Color(hex: 0x0084C9)))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(list.recipeName?.isEmpty == false ? list.recipeName! : "Shopping List")
                                        .font(.system(size: 16, weight: .heavy)).foregroundColor(Color(hex: 0x005480)).lineLimit(1)
                                    HStack(spacing: 6) {
                                        Text("\(list.items.count) items").font(.system(size: 13, weight: .semibold)).foregroundColor(Colors.textSecondary)
                                        if !previewFoods.isEmpty {
                                            HStack(spacing: 4) {
                                                ForEach(previewFoods, id: \.id) { food in
                                                    Circle().fill(Color(hex: 0xD0EFFF)).frame(width: 18, height: 18)
                                                        .overlay(Image(systemName: getIconForCategory(food.category)).font(.system(size: 10)).foregroundColor(Color(hex: 0x0084C9)))
                                                }
                                                if list.items.count > 3 {
                                                    Text("+\(list.items.count - 3)").font(.system(size: 11, weight: .bold)).foregroundColor(Color(hex: 0x0084C9))
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(.leading, 12)
                                Spacer(minLength: 12)
                                Image(systemName: "chevron.right").font(.system(size: 20)).foregroundColor(Colors.textMuted)
                            }
                            .padding(20)
                            .frame(width: 300)
                            .background(Color(hex: 0xF0FAFF))
                            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(hex: 0xD0EFFF), lineWidth: 1))
                            .cornerRadius(20)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.horizontal, -20)
            .mask(
                LinearGradient(stops: [
                    .init(color: .clear, location: 0), .init(color: .black, location: 0.06),
                    .init(color: .black, location: 0.94), .init(color: .clear, location: 1),
                ], startPoint: .leading, endPoint: .trailing)
            )
        }
        .padding(.top, 16).padding(.bottom, 12)
    }
}

#Preview {
    HomeScreen()
        .environmentObject(FoodsStore.shared)
        .environmentObject(ProfileStore())
        .environmentObject(InventoryStore())
        .environmentObject(Router())
}
