import SwiftUI
import SmartSwapsKit

/// Port of `app/settings.tsx` (808 ln). Pushed (not modal) in the RN source, hidden from the
/// tab bar - Phase 6 wires the actual push transition; this file is a complete, standalone,
/// previewable screen exactly like the tab screens.
///
/// Mocks `expo-clipboard` exactly like the RN source does (`settings.tsx`'s own inline mock,
/// already recorded in `PORTING_NOTES.md` "Bugs faithfully reproduced" #7): `setStringAsync`
/// no-ops, `getStringAsync` always returns `"[]"`. Export/Import Shopping Lists therefore
/// always silently exports nothing and imports 0 lists - reproduced deliberately, not a bug
/// introduced by this port.
private enum MockClipboard {
    static func setStringAsync(_ text: String) async {}
    static func getStringAsync() async -> String { "[]" }
}

struct SettingsScreen: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var settingsStore: SettingsStore

    private enum Tab { case profile, privacy }
    @State private var activeTab: Tab = .profile

    @State private var inputModal: InputModalState?
    @State private var pickerModal: PickerModalState?

    @State private var trainingLogCount = 0
    @State private var matchLogCount = 0
    @State private var shoppingListCount = 0

    @State private var shareText: ShareItem?
    @State private var alertState: AlertState?

    private struct InputModalState: Identifiable {
        var id: String { key }
        var key: String
        var title: String
        var unit: String
        var value: String
    }
    private struct PickerModalState: Identifiable {
        var id: String { key }
        var key: String
        var title: String
        var options: [String]
        var value: String
    }
    private struct ShareItem: Identifiable { var id: String { text }; var text: String }
    private struct AlertState: Identifiable {
        var id: String { title }
        var title: String
        var message: String
        var destructiveTitle: String?
        var onDestructive: (() -> Void)?
    }

    private static let dietOptions: [DietaryPreference] = [.balanced, .highProtein, .lowCarb, .vegetarian, .vegan]
    private static let activityOptions = ["Sedentary", "Lightly Active", "Moderately Active", "Very Active", "Extra Active"]
    private static let weightGoalOptions = ["-0.5 kg", "-0.25 kg", "stay", "+0.25 kg", "+0.5 kg"]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                tabSwitcher
                if activeTab == .profile { profileTab } else { privacyTab }
            }
            .padding(.bottom, 100)
        }
        .background(Colors.background)
        .navigationTitle("Settings")
        .onAppear { Task { await loadCounts() } }
        // Centered transparent-overlay card, matching RN's `transparent animationType="fade"`
        // `<Modal>` - same pattern `NutritionModal.swift` (Phase 4) already established,
        // rather than a system `.sheet` (which anchors to the bottom, not centered).
        .overlay { if let state = inputModal { InputModalView(state: state, onSave: saveInput, onCancel: { inputModal = nil }) } }
        .sheet(item: $pickerModal) { state in PickerModalView(state: state, onSave: savePicker, onCancel: { pickerModal = nil }) }
        .sheet(item: $shareText) { item in ActivityView(items: [item.text]) }
        .alert(alertState?.title ?? "", isPresented: Binding(get: { alertState != nil }, set: { if !$0 { alertState = nil } })) {
            if let destructiveTitle = alertState?.destructiveTitle, let onDestructive = alertState?.onDestructive {
                Button("Cancel", role: .cancel) {}
                Button(destructiveTitle, role: .destructive) { onDestructive() }
            } else {
                Button("OK") {}
            }
        } message: {
            Text(alertState?.message ?? "")
        }
    }

    private func loadCounts() async {
        trainingLogCount = await SwapTrainingLog.shared.getTrainingLogCount()
        matchLogCount = await MatchLog.shared.getMatchLogCount()
        let scans = await StorageService.getScans()
        shoppingListCount = scans.filter { $0.isShoppingList == true }.count
    }

    private var tabSwitcher: some View {
        HStack(spacing: 0) {
            tabButton("Profile & Diet", .profile)
            tabButton("Privacy & Data", .privacy)
        }
        .padding(4)
        .background(Colors.inputBackground)
        .cornerRadius(8)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .padding(.top, 16)
    }

    private func tabButton(_ title: String, _ tab: Tab) -> some View {
        let selected = activeTab == tab
        return Button(action: { activeTab = tab }) {
            Text(title)
                .font(.system(size: 14, weight: selected ? .semibold : .medium))
                .foregroundColor(selected ? Colors.textPrimary : Colors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(selected ? Colors.white : Color.clear)
                .cornerRadius(6)
                .shadow(color: .black.opacity(selected ? 0.1 : 0), radius: 1, x: 0, y: 1)
        }.buttonStyle(.plain)
    }

    // MARK: - Profile tab

    @ViewBuilder
    private var profileTab: some View {
        SettingsGroup(title: "Nutrition Target") {
            SettingsRow(sfSymbol: "bolt.fill", iconBg: Colors.systemOrange, title: "Daily Calories", isLast: true) {
                Text("\(JSNumber.toLocaleStringDE(Double(profileStore.targetCalories))) kcal").settingsValue()
            }
        }

        SettingsGroup(title: "Personal Info") {
            SettingsRow(sfSymbol: "person.fill", iconBg: Colors.systemBlue, title: "Biological Sex",
                        onPress: { openPicker("sex", "Biological Sex", ["Male", "Female"], profileStore.profile.sex.rawValue) }) {
                HStack(spacing: 6) { Text(profileStore.profile.sex.rawValue).settingsValue(); chevron }
            }
            SettingsRow(sfSymbol: "calendar", iconBg: Colors.systemPink, title: "Age",
                        onPress: { openInput("age", "Age", "yrs", String(profileStore.profile.age)) }) {
                (Text("\(profileStore.profile.age) ") + Text("yrs").foregroundColor(Colors.systemGray)).settingsValue()
            }
            SettingsRow(sfSymbol: "dumbbell.fill", iconBg: Colors.systemIndigo, title: "Weight",
                        onPress: { openInput("weight", "Weight", "kg", trimmedNumber(profileStore.profile.weight)) }) {
                (Text("\(trimmedNumber(profileStore.profile.weight)) ") + Text("kg").foregroundColor(Colors.systemGray)).settingsValue()
            }
            SettingsRow(sfSymbol: "figure.stand", iconBg: Colors.systemPurple, title: "Height", isLast: true,
                        onPress: { openInput("height", "Height", "cm", trimmedNumber(profileStore.profile.height)) }) {
                (Text("\(trimmedNumber(profileStore.profile.height)) ") + Text("cm").foregroundColor(Colors.systemGray)).settingsValue()
            }
        }

        SettingsGroup(title: "Goals") {
            SettingsRow(sfSymbol: "figure.run", iconBg: Colors.systemOrange, title: "Activity Level",
                        onPress: { openPicker("activityLevel", "Activity Level", Self.activityOptions, profileStore.profile.activityLevel.rawValue) }) {
                HStack(spacing: 6) { Text(profileStore.profile.activityLevel.rawValue).settingsValue(); chevron }
            }
            SettingsRow(sfSymbol: "arrow.down.right.circle.fill", iconBg: Colors.systemGreen, title: "Weight Goal", isLast: true,
                        onPress: { openPicker("weightGoal", "Weight Goal", Self.weightGoalOptions, profileStore.profile.weightGoal.rawValue) }) {
                HStack(spacing: 6) { Text(profileStore.profile.weightGoal.rawValue).settingsValue(); chevron }
            }
        }

        SettingsGroup(title: "Dietary Preferences") {
            ForEach(Array(Self.dietOptions.enumerated()), id: \.element) { index, diet in
                SettingsRow(sfSymbol: "fork.knife",
                            iconBg: profileStore.profile.dietaryPreference.contains(diet) ? Colors.systemGreen : Colors.systemGray,
                            title: diet.rawValue, isLast: index == Self.dietOptions.count - 1,
                            onPress: { toggleDiet(diet) }) {
                    if profileStore.profile.dietaryPreference.contains(diet) {
                        Image(systemName: "checkmark").font(.system(size: 20)).foregroundColor(Colors.systemBlue)
                    }
                }
            }
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").font(.system(size: 14)).foregroundColor(Colors.systemGray2)
    }

    private func trimmedNumber(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(v)
    }

    private func openInput(_ key: String, _ title: String, _ unit: String, _ value: String) {
        inputModal = InputModalState(key: key, title: title, unit: unit, value: value)
    }
    private func openPicker(_ key: String, _ title: String, _ options: [String], _ value: String) {
        pickerModal = PickerModalState(key: key, title: title, options: options, value: value)
    }

    private func saveInput(_ state: InputModalState, _ newValue: String) {
        guard let num = Double(newValue.replacingOccurrences(of: ",", with: ".")), num > 0 else {
            inputModal = nil
            return
        }
        profileStore.updateProfile { profile in
            switch state.key {
            case "age": profile.age = Int(num)
            case "weight": profile.weight = num
            case "height": profile.height = num
            default: break
            }
        }
        inputModal = nil
    }

    private func savePicker(_ state: PickerModalState, _ newValue: String) {
        profileStore.updateProfile { profile in
            switch state.key {
            case "sex": if let s = Sex(rawValue: newValue) { profile.sex = s }
            case "activityLevel": if let a = ActivityLevel(rawValue: newValue) { profile.activityLevel = a }
            case "weightGoal": if let w = WeightGoal(rawValue: newValue) { profile.weightGoal = w }
            default: break
            }
        }
        pickerModal = nil
    }

    private func toggleDiet(_ diet: DietaryPreference) {
        profileStore.updateProfile { profile in
            var current = profile.dietaryPreference
            if diet == .balanced {
                current = [.balanced]
            } else {
                current.removeAll { $0 == .balanced }
                if current.contains(diet) { current.removeAll { $0 == diet } } else { current.append(diet) }
                if current.isEmpty { current = [.balanced] }
            }
            profile.dietaryPreference = current
        }
    }

    // MARK: - Privacy tab

    @ViewBuilder
    private var privacyTab: some View {
        SettingsGroup(title: "Scanning") {
            SettingsRow(sfSymbol: "cloud.fill", iconBg: Colors.systemTeal, title: "Look up branded products online (beta)", isLast: true) {
                Toggle("", isOn: Binding(
                    get: { settingsStore.settings.offLookupEnabled },
                    set: { value in settingsStore.updateSettings { $0.offLookupEnabled = value } }
                )).labelsHidden().tint(Colors.primaryGreen)
            }
        }
        if settingsStore.settings.offLookupEnabled {
            hint("Branded products the offline database can't recognize (e.g. \"Pringles\") will be looked up online via Open Food Facts. This sends the scanned product name over the network and is still being tuned - occasionally it may pick the wrong item.")
        }

        SettingsGroup(title: "Personalization") {
            SettingsRow(sfSymbol: "arrow.counterclockwise", iconBg: Colors.systemGray, title: "Reset Swap Preferences", onPress: confirmResetSwapPreferences) { chevron }
            SettingsRow(sfSymbol: "square.and.arrow.up", iconBg: Colors.systemBlue, title: "Export Local Swap Data", onPress: exportTrainingLog) {
                HStack(spacing: 6) { Text("\(trainingLogCount)").settingsValue(); chevron }
            }
            SettingsRow(sfSymbol: "trash.fill", iconBg: Colors.systemRed, title: "Delete Local Swap Data", isLast: true, onPress: confirmDeleteTrainingLog) {
                HStack(spacing: 6) {
                    Text("\(trainingLogCount) entries").settingsValue().foregroundColor(trainingLogCount > 0 ? Colors.systemRed : Colors.systemGray)
                    chevron
                }
            }
        }
        hint("Swap suggestions adapt on-device as you like or dismiss them. \"Reset Swap Preferences\" forgets the learned multipliers. \"Delete Local Swap Data\" removes the anonymized decision log (\(trainingLogCount) entries). Neither action affects your profile or receipts.")

        SettingsGroup(title: "Shopping Lists") {
            SettingsRow(sfSymbol: "arrow.down.doc", iconBg: Colors.systemTeal, title: "Import Shopping Lists", onPress: { Task { await importShoppingLists() } }) { chevron }
            SettingsRow(sfSymbol: "square.and.arrow.up", iconBg: Colors.systemBlue, title: "Export Shopping Lists", onPress: { Task { await exportShoppingLists() } }) {
                HStack(spacing: 6) { Text("\(shoppingListCount)").settingsValue(); chevron }
            }
            SettingsRow(sfSymbol: "trash.fill", iconBg: Colors.systemRed, title: "Delete All Shopping Lists", isLast: true, onPress: confirmDeleteShoppingLists) {
                HStack(spacing: 6) {
                    Text("\(shoppingListCount) lists").settingsValue().foregroundColor(shoppingListCount > 0 ? Colors.systemRed : Colors.systemGray)
                    chevron
                }
            }
        }

        SettingsGroup(title: "Matcher Diagnostics") {
            SettingsRow(sfSymbol: "square.and.arrow.up", iconBg: Colors.systemBlue, title: "Export Match Diagnostics", onPress: exportMatchLog) {
                HStack(spacing: 6) { Text("\(matchLogCount)").settingsValue(); chevron }
            }
            SettingsRow(sfSymbol: "trash.fill", iconBg: Colors.systemRed, title: "Delete Match Diagnostics", isLast: true, onPress: confirmDeleteMatchLog) {
                HStack(spacing: 6) {
                    Text("\(matchLogCount) entries").settingsValue().foregroundColor(matchLogCount > 0 ? Colors.systemRed : Colors.systemGray)
                    chevron
                }
            }
        }
        hint("Every scan line the matcher wasn't confident about (\"Potential Match\" or \"Not Found\") is logged locally with its raw receipt text, so it can be shared as a precise bug report. Confident matches aren't logged. Nothing here is sent anywhere unless you tap Export.")

        SettingsGroup(title: "About") {
            hint("Food icons by OpenMoji (openmoji.org), licensed under CC BY-SA 4.0. All icons are bundled with the app and stored on your device — nothing is downloaded over the network.")
                .padding(.horizontal, 16).padding(.vertical, 12)
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundColor(Colors.systemGray).lineSpacing(4)
            .padding(.horizontal, 32).padding(.top, 8)
    }

    private func exportTrainingLog() {
        Task {
            do { shareText = ShareItem(text: try await SwapTrainingLog.shared.exportTrainingLogJSON()) }
            catch { alertState = AlertState(title: "Nothing to Export Yet", message: "No local swap decisions recorded yet.", destructiveTitle: nil, onDestructive: nil) }
        }
    }
    private func exportMatchLog() {
        Task {
            do { shareText = ShareItem(text: try await MatchLog.shared.exportMatchLogJSON()) }
            catch { alertState = AlertState(title: "Nothing to Export Yet", message: "No weak matches logged yet.", destructiveTitle: nil, onDestructive: nil) }
        }
    }
    private func confirmResetSwapPreferences() {
        alertState = AlertState(title: "Reset Swap Preferences",
                                 message: "This forgets which swap suggestions you've liked or dismissed. It won't affect your profile or scan history.",
                                 destructiveTitle: "Reset", onDestructive: { Task { await PersonalSwapPreferences.shared.resetPersonalPreferences() } })
    }
    private func confirmDeleteTrainingLog() {
        alertState = AlertState(title: "Delete Local Swap Data",
                                 message: "This will permanently delete all \(trainingLogCount) locally recorded swap decisions. Your profile and receipt history are not affected.",
                                 destructiveTitle: "Delete", onDestructive: { Task { await SwapTrainingLog.shared.clearTrainingLog(); trainingLogCount = 0 } })
    }
    private func confirmDeleteMatchLog() {
        alertState = AlertState(title: "Delete Match Diagnostics",
                                 message: "This will permanently delete all \(matchLogCount) locally logged low-confidence scan lines. Your profile and receipt history are not affected.",
                                 destructiveTitle: "Delete", onDestructive: { Task { await MatchLog.shared.clearMatchLog(); matchLogCount = 0 } })
    }
    private func confirmDeleteShoppingLists() {
        alertState = AlertState(title: "Delete All Shopping Lists", message: "This will permanently delete all your shopping lists.",
                                 destructiveTitle: "Delete", onDestructive: {
            Task {
                let scans = await StorageService.getScans()
                for scan in scans where scan.isShoppingList == true { await StorageService.deleteScan(id: scan.id) }
                shoppingListCount = 0
            }
        })
    }

    private func exportShoppingLists() async {
        let scans = await StorageService.getScans()
        let lists = scans.filter { $0.isShoppingList == true }
        guard !lists.isEmpty else {
            alertState = AlertState(title: "No Shopping Lists", message: "You have no shopping lists to export.", destructiveTitle: nil, onDestructive: nil)
            return
        }
        guard let data = try? JSONEncoder().encode(lists), let json = String(data: data, encoding: .utf8) else { return }
        await MockClipboard.setStringAsync(json)
        alertState = AlertState(title: "Exported", message: "Your shopping lists have been copied to the clipboard.", destructiveTitle: nil, onDestructive: nil)
    }

    private func importShoppingLists() async {
        let text = await MockClipboard.getStringAsync()
        guard let data = text.data(using: .utf8), let lists = try? JSONDecoder().decode([ScanRecord].self, from: data) else {
            alertState = AlertState(title: "Import Failed", message: "Clipboard does not contain valid shopping list data.", destructiveTitle: nil, onDestructive: nil)
            return
        }
        for list in lists {
            await StorageService.saveScan(id: list.id, date: list.date, items: list.items,
                                           averageScore: list.averageScore, isShoppingList: list.isShoppingList,
                                           recipeName: list.recipeName)
        }
        let updated = await StorageService.getScans()
        shoppingListCount = updated.filter { $0.isShoppingList == true }.count
        alertState = AlertState(title: "Imported", message: "Successfully imported \(lists.count) shopping lists.", destructiveTitle: nil, onDestructive: nil)
    }
}

// MARK: - Reusable settings group/row

private struct SettingsGroup<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.system(size: 13, weight: .semibold)).foregroundColor(Colors.systemGray)
                .padding(.leading, 32)
            VStack(spacing: 0) { content }
                .background(Colors.cardBackground)
                .cornerRadius(10)
                .padding(.horizontal, 16)
        }
        .padding(.top, 28)
    }
}

private struct SettingsRow<Trailing: View>: View {
    var sfSymbol: String
    var iconBg: Color
    var title: String
    var isLast: Bool = false
    var onPress: (() -> Void)? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            Button(action: { onPress?() }) {
                HStack {
                    RoundedRectangle(cornerRadius: 6).fill(iconBg).frame(width: 28, height: 28)
                        .overlay(Image(systemName: sfSymbol).font(.system(size: 14)).foregroundColor(.white))
                    Text(title).font(.system(size: 16)).foregroundColor(Colors.textPrimary).padding(.leading, 16)
                    Spacer()
                    trailing
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(onPress == nil)

            if !isLast {
                Rectangle().fill(Colors.systemGray2).frame(height: 0.5).padding(.leading, 60)
            }
        }
    }
}

private extension Text {
    func settingsValue() -> some View { self.font(.system(size: 16)).foregroundColor(Colors.systemGray) }
}

// MARK: - Modals

private struct InputModalView: View {
    var state: SettingsScreen.InputModalState
    var onSave: (SettingsScreen.InputModalState, String) -> Void
    var onCancel: () -> Void
    @State private var value: String

    init(state: SettingsScreen.InputModalState, onSave: @escaping (SettingsScreen.InputModalState, String) -> Void, onCancel: @escaping () -> Void) {
        self.state = state; self.onSave = onSave; self.onCancel = onCancel
        _value = State(initialValue: state.value)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea().onTapGesture(perform: onCancel)
            VStack(spacing: 16) {
                Text("Enter \(state.title)").font(.system(size: 18, weight: .bold)).foregroundColor(Colors.textPrimary)
                HStack {
                    TextField("", text: $value).keyboardType(.decimalPad).font(.system(size: 18, weight: .semibold))
                    Text(state.unit).font(.system(size: 16, weight: .semibold)).foregroundColor(Colors.textMuted)
                }
                .padding(.horizontal, 16).frame(height: 50)
                .background(Colors.inputBackground).cornerRadius(12)

                HStack(spacing: 12) {
                    Button(action: onCancel) {
                        Text("Cancel").font(.system(size: 16, weight: .semibold)).foregroundColor(Colors.textSecondary)
                            .frame(maxWidth: .infinity).frame(height: 48).background(Colors.inputBackground).cornerRadius(12)
                    }.buttonStyle(.plain)
                    Button(action: { onSave(state, value) }) {
                        Text("Save").font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 48).background(Colors.primaryGreen).cornerRadius(12)
                    }.buttonStyle(.plain)
                }
            }
            .padding(24)
            .background(Colors.white)
            .cornerRadius(16)
            .padding(40)
        }
    }
}

private struct PickerModalView: View {
    var state: SettingsScreen.PickerModalState
    var onSave: (SettingsScreen.PickerModalState, String) -> Void
    var onCancel: () -> Void
    @State private var value: String

    init(state: SettingsScreen.PickerModalState, onSave: @escaping (SettingsScreen.PickerModalState, String) -> Void, onCancel: @escaping () -> Void) {
        self.state = state; self.onSave = onSave; self.onCancel = onCancel
        _value = State(initialValue: state.value)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel", action: onCancel).foregroundColor(Colors.textSecondary)
                Spacer()
                Text(state.title).font(.system(size: 16, weight: .bold)).foregroundColor(Colors.textPrimary)
                Spacer()
                Button("Done") { onSave(state, value) }.foregroundColor(Colors.primaryGreen).fontWeight(.semibold)
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
            .overlay(Rectangle().fill(Colors.border).frame(height: 0.5), alignment: .bottom)

            Picker("", selection: $value) {
                ForEach(state.options, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.wheel)
        }
        .presentationDetents([.height(280)])
    }
}

#Preview {
    NavigationStack {
        SettingsScreen()
            .environmentObject(ProfileStore())
            .environmentObject(SettingsStore())
    }
}
