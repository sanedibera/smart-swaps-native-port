import SwiftUI
import SmartSwapsKit

/// Port of `app/(tabs)/receipts.tsx` (467 ln). Replaces the Phase 1 placeholder.
/// `useFocusEffect` -> `.onAppear` (see `SearchScreen.swift`'s note on the same tradeoff).
/// `LayoutAnimation.easeInEaseOut` -> `withAnimation(.easeInOut)`, matching other components.
struct ReceiptsScreen: View {
    @EnvironmentObject private var foodsStore: FoodsStore
    @EnvironmentObject private var router: Router
    @State private var scans: [ScanRecord] = []
    @State private var expandedListIds: Set<String> = []
    @State private var scrollY: CGFloat = 0

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoFormatterNoFraction = ISO8601DateFormatter()
    private static func parseDate(_ s: String) -> Date {
        isoFormatter.date(from: s) ?? isoFormatterNoFraction.date(from: s) ?? Date()
    }
    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM d"
        return f
    }()
    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    private var shoppingLists: [ScanRecord] {
        scans.filter { $0.isShoppingList == true }
            .sorted { Self.parseDate($0.date) > Self.parseDate($1.date) }
    }

    private struct WeekGroup: Identifiable {
        var id: TimeInterval { timestamp }
        var timestamp: TimeInterval
        var scans: [ScanRecord]
        var averageScore: Int
    }

    /// Monday-based week key, matching `getWeekKey`'s `d.getDate() - day + (day === 0 ? -6 : 1)`.
    private func weekStart(for date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let jsDay = calendar.component(.weekday, from: date) - 1
        let daysSinceMonday = jsDay == 0 ? 6 : jsDay - 1
        return calendar.startOfDay(for: calendar.date(byAdding: .day, value: -daysSinceMonday, to: date) ?? date)
    }

    private var groupedScans: [WeekGroup] {
        var groups: [TimeInterval: [ScanRecord]] = [:]
        for scan in scans {
            if scan.isShoppingList == true { continue }
            let wk = weekStart(for: Self.parseDate(scan.date)).timeIntervalSince1970
            groups[wk, default: []].append(scan)
        }
        return groups.keys.sorted(by: >).map { key in
            let group = groups[key]!.sorted { Self.parseDate($0.date) > Self.parseDate($1.date) }
            let avg = group.reduce(0.0) { $0 + $1.averageScore } / Double(group.count)
            return WeekGroup(timestamp: key, scans: group, averageScore: JSNumber.roundToInt(avg))
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Colors.background.ignoresSafeArea()

            TrackableScrollView(showsIndicators: false, onOffsetChange: { scrollY = $0 }) {
                ScrollOffsetReporter(coordinateSpace: "scroll")
                content
            }

            GlassHeader(title: "Receipts", onSettingsPress: nil, scrollY: scrollY, leftAccessory: { EmptyView() })
        }
        .onAppear { Task { scans = await StorageService.getScans() } }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            LargeTitle(title: "Receipts", scrollY: scrollY)
            Text("Track your receipts and health points").subtitleText().padding(.bottom, 24).padding(.top, 4)

            Button(action: { router.openScan() }) {
                HStack(spacing: 8) {
                    Image(systemName: "camera.fill").font(.system(size: 20))
                    Text("Scan New Receipt").font(.system(size: 16, weight: .bold))
                }
                .foregroundColor(Colors.white)
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(Colors.primaryGreen).cornerRadius(16)
                .shadow(color: Colors.shadowColor.opacity(0.1), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 24)

            if !shoppingLists.isEmpty {
                shoppingListsSection
            }

            if groupedScans.isEmpty {
                emptyState
            } else {
                historySection
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 120)
    }

    private var shoppingListsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Current Shopping Lists").font(.system(size: 16, weight: .heavy)).foregroundColor(Colors.textPrimary).padding(.bottom, 12)
            ForEach(shoppingLists) { list in
                shoppingListCard(list)
            }
        }
        .padding(.bottom, 24)
    }

    private func shoppingListCard(_ list: ScanRecord) -> some View {
        let isExpanded = expandedListIds.contains(list.id)
        let previewFoods = Array(list.items.compactMap { $0.matchedFoodId.flatMap { foodsStore.byId[$0] } }.prefix(3))

        return VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut) {
                    if isExpanded { expandedListIds.remove(list.id) } else { expandedListIds.insert(list.id) }
                }
            }) {
                HStack {
                    HStack {
                        Circle().fill(Color(hex: 0xD0EFFF)).frame(width: 48, height: 48)
                            .overlay(Image(systemName: "basket").font(.system(size: 24)).foregroundColor(Color(hex: 0x0084C9)))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(list.recipeName?.isEmpty == false ? list.recipeName! : "Shopping List")
                                .font(.system(size: 16, weight: .heavy)).foregroundColor(Color(hex: 0x005480)).lineLimit(1)
                            HStack(spacing: 6) {
                                Text("\(list.items.count) items").font(.system(size: 13)).foregroundColor(Colors.textSecondary)
                                if !isExpanded && !previewFoods.isEmpty {
                                    HStack(spacing: 4) {
                                        ForEach(Array(previewFoods.enumerated()), id: \.offset) { _, food in
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
                    }
                    Spacer()
                    CircularScoreRing(percentage: list.averageScore, size: 44, strokeWidth: 4)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down").font(.system(size: 20)).foregroundColor(Color(hex: 0x0084C9)).padding(.leading, 8)
                }
            }.buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(list.items.prefix(10).enumerated()), id: \.offset) { _, item in
                        let food = item.matchedFoodId.flatMap { foodsStore.byId[$0] }
                        HStack(spacing: 8) {
                            if let food {
                                Image(systemName: getIconForCategory(food.category)).font(.system(size: 14)).foregroundColor(Colors.primaryGreen)
                            }
                            Text(food?.name ?? item.rawText).font(.system(size: 14, weight: .medium)).foregroundColor(Colors.textPrimary).lineLimit(1)
                        }
                    }
                    if list.items.count > 10 {
                        Text("...and \(list.items.count - 10) more items").font(.system(size: 13)).italic().foregroundColor(Colors.textMuted)
                    }
                    Button(action: { Haptics.light(); router.openReceipt(list.id) }) {
                        Text("Open List Details").font(.system(size: 15, weight: .bold)).foregroundColor(Colors.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Color(hex: 0x0084C9)).cornerRadius(12)
                    }.buttonStyle(.plain).padding(.top, 4)
                }
                .padding(.top, 16)
                .overlay(Rectangle().fill(Color(hex: 0xBFE7FF)).frame(height: 0.5), alignment: .top)
                .padding(.top, 16)
            }
        }
        .padding(16)
        .background(Color(hex: 0xF0FAFF))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(hex: 0xD0EFFF), lineWidth: 1))
        .cornerRadius(20)
        .padding(.bottom, 12)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(groupedScans) { group in
                let weekStartDate = Date(timeIntervalSince1970: group.timestamp)
                let weekEndDate = weekStartDate.addingTimeInterval(6 * 24 * 60 * 60)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .lastTextBaseline) {
                        Text("Week of \(Self.shortDateFormatter.string(from: weekStartDate)) - \(Self.shortDateFormatter.string(from: weekEndDate))")
                            .font(.system(size: 13, weight: .bold)).tracking(0.5).foregroundColor(Colors.textSecondary)
                        Spacer()
                        Text("Avg: \(group.averageScore)").font(.system(size: 12, weight: .bold)).foregroundColor(Colors.primaryGreenDark)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Colors.lightGreenBg).cornerRadius(8)
                    }
                    .padding(.bottom, 12)

                    ForEach(group.scans) { scan in
                        Button(action: { Haptics.light(); router.openReceipt(scan.id) }) {
                            HStack {
                                Circle().fill(Colors.lightGreenBg).frame(width: 36, height: 36)
                                    .overlay(Image(systemName: "receipt").font(.system(size: 16)).foregroundColor(Colors.primaryGreen))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Self.weekdayFormatter.string(from: Self.parseDate(scan.date)))
                                        .font(.system(size: 15, weight: .bold)).foregroundColor(Colors.textPrimary)
                                    Text("\(scan.items.count) items matched").font(.system(size: 13)).foregroundColor(Colors.textSecondary)
                                }
                                .padding(.leading, 12)
                                Spacer()
                                CircularScoreRing(percentage: scan.averageScore, size: 44, strokeWidth: 4)
                            }
                            .padding(16)
                            .background(Colors.white)
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Colors.border, lineWidth: 1))
                            .cornerRadius(16)
                            .shadow(color: .black.opacity(0.02), radius: 4, x: 0, y: 2)
                        }.buttonStyle(.plain).padding(.bottom, 12)
                    }
                }
                .padding(.bottom, 20)
            }

            Button(action: { Task { await StorageService.clearScans(); scans = [] } }) {
                Text("Clear History").font(.system(size: 14)).foregroundColor(Colors.textMuted)
                    .frame(maxWidth: .infinity)
            }.buttonStyle(.plain).padding(.top, 4)
        }
        .padding(.bottom, 24)
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Circle().fill(Colors.lightGreenBg).frame(width: 56, height: 56)
                .overlay(Image(systemName: "receipt").font(.system(size: 24)).foregroundColor(Colors.primaryGreen))
                .padding(.bottom, 16)
            Text("No history yet").font(.system(size: 18, weight: .heavy)).foregroundColor(Colors.textPrimary).padding(.bottom, 8)
            Text("Scan your first grocery receipt to get a health rating.")
                .font(.system(size: 13)).foregroundColor(Colors.textSecondary).multilineTextAlignment(.center).lineSpacing(3)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .cardStyle()
    }
}

#Preview {
    ReceiptsScreen()
        .environmentObject(FoodsStore.shared)
        .environmentObject(Router())
}
