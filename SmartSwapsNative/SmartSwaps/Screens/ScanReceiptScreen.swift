import SwiftUI
import PhotosUI
import AVFoundation
import SmartSwapsKit

/// Port of `app/scan-receipt.tsx` (465 ln). `expo-image-picker`'s camera capture ->
/// `UIImagePickerController` wrapped in `CameraPicker` below (SwiftUI has no built-in camera
/// capture view); library selection -> `PhotosPicker` (`PhotosUI`, iOS 16+), the modern
/// SwiftUI-native equivalent rather than `UIImagePickerController`'s library mode. Both paths
/// converge on the same `processImage(uri:)` the source uses, round-tripping the picked image
/// through a temp JPEG file so `NativeOcr.recognize(uri:)` keeps the same file-URI contract
/// the original native module had, rather than growing a UIImage-specific overload.
struct ScanReceiptScreen: View {
    @EnvironmentObject private var foodsStore: FoodsStore
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var inventoryStore: InventoryStore
    @EnvironmentObject private var router: Router

    private enum ProgressStatus { case idle, reading, matching, enriching, calculating, done }

    @State private var isProcessing = false
    @State private var results: [ParsedReceiptItem]?
    @State private var progressStatus: ProgressStatus = .idle
    @State private var progressCurrent = 0
    @State private var progressTotal = 0
    @State private var currentScanId: String?
    @State private var currentScanDate: String?
    @State private var errorAlert: String?

    @State private var showCamera = false
    @State private var photosPickerItem: PhotosPickerItem?
    @State private var showCameraPermissionAlert = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            if let results {
                resultsView(results)
            } else {
                captureView
            }
        }
        .background(Colors.background)
        .navigationTitle(results != nil ? "Scan Results" : "Scan Receipt")
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                showCamera = false
                if let image { Task { await processImage(image) } }
            }
            .ignoresSafeArea()
        }
        .onChange(of: photosPickerItem) { newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    await processImage(image)
                }
                photosPickerItem = nil
            }
        }
        .alert("OCR Error", isPresented: Binding(get: { errorAlert != nil }, set: { if !$0 { errorAlert = nil } })) {
            Button("OK") {}
        } message: {
            Text(errorAlert ?? "")
        }
        .alert("Permission needed", isPresented: $showCameraPermissionAlert) {
            Button("OK") {}
        } message: {
            Text("Camera permission is required to take photos.")
        }
    }

    private func handleTakePhoto() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCamera = true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted { showCamera = true } else { showCameraPermissionAlert = true }
        default:
            showCameraPermissionAlert = true
        }
    }

    // MARK: - Capture UI

    private var captureView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Take a picture of your grocery bill to check the health score of your purchases.")
                .font(.system(size: 16)).foregroundColor(Colors.textSecondary).lineSpacing(8)
                .padding(.bottom, 32)

            if isProcessing {
                progressCard
            } else {
                VStack(spacing: 16) {
                    Button(action: { Task { await handleTakePhoto() } }) {
                        HStack {
                            Image(systemName: "camera").font(.system(size: 22))
                            Text("Take Photo").font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(Colors.white)
                        .frame(maxWidth: .infinity).frame(height: 56)
                        .background(Colors.primaryGreen).cornerRadius(14)
                    }.buttonStyle(.plain)

                    PhotosPicker(selection: $photosPickerItem, matching: .images) {
                        HStack {
                            Image(systemName: "photo").font(.system(size: 22))
                            Text("Choose from Library").font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(Colors.textPrimary)
                        .frame(maxWidth: .infinity).frame(height: 56)
                        .background(Colors.cardBackground)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Colors.border, lineWidth: 1))
                        .cornerRadius(14)
                    }
                }
                .padding(.bottom, 48)
            }

            Text("How it works").sectionTitleText().padding(.bottom, 8)
            howItWorksRow("camera", "Take a clear picture of your receipt")
            howItWorksRow("magnifyingglass", "We identify the groceries you bought using on-device AI")
            howItWorksRow("sparkles", "Get smart swaps based on your diet")
        }
        .padding(24)
    }

    private func howItWorksRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 16).fill(Colors.lightGreenBg).frame(width: 52, height: 52)
                .overlay(Image(systemName: icon).font(.system(size: 24)).foregroundColor(Colors.primaryGreen))
            Text(text).font(.system(size: 16, weight: .medium)).foregroundColor(Colors.textPrimary)
        }
        .padding(.bottom, 24)
    }

    private var progressCard: some View {
        VStack {
            switch progressStatus {
            case .reading:
                HStack(spacing: 12) { ProgressView().tint(Colors.primaryGreen); Text("Reading receipt text...").font(.system(size: 16, weight: .semibold)).foregroundColor(Colors.textSecondary) }
            case .matching:
                VStack {
                    Text("Matching items (\(progressCurrent) of \(progressTotal))...").font(.system(size: 16, weight: .semibold)).foregroundColor(Colors.textSecondary)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4).fill(Colors.lightGreenBg)
                            RoundedRectangle(cornerRadius: 4).fill(Colors.primaryGreen)
                                .frame(width: geo.size.width * CGFloat(progressCurrent) / CGFloat(max(1, progressTotal)))
                        }
                    }
                    .frame(height: 8).padding(.top, 16)
                }
            case .enriching:
                HStack(spacing: 12) { ProgressView().tint(Colors.primaryGreen); Text("Looking up branded products...").font(.system(size: 16, weight: .semibold)).foregroundColor(Colors.textSecondary) }
            case .calculating:
                HStack(spacing: 12) { ProgressView().tint(Colors.primaryGreen); Text("Calculating smart swaps...").font(.system(size: 16, weight: .semibold)).foregroundColor(Colors.textSecondary) }
            case .done:
                HStack(spacing: 12) { Image(systemName: "checkmark.circle.fill").font(.system(size: 24)).foregroundColor(Colors.primaryGreen); Text("Done!").font(.system(size: 16, weight: .semibold)).foregroundColor(Colors.primaryGreen) }
            case .idle:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .cardStyle()
        .padding(.bottom, 48)
    }

    // MARK: - Results UI

    private func resultsView(_ results: [ParsedReceiptItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("We found \(results.count) items on your receipt.")
                .font(.system(size: 16)).foregroundColor(Colors.textSecondary).lineSpacing(8)
                .padding(.bottom, 32)

            ReceiptItemList(items: results, onUpdateItem: { index, food in Task { await handleUpdateItem(index: index, newFood: food) } },
                             onDeleteItem: { index in Task { await handleDeleteItem(index: index) } })

            Button(action: { router.goToReceiptsTab() }) {
                Text("View in Recent Receipts").font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Colors.primaryGreen).cornerRadius(14)
            }.buttonStyle(.plain).padding(.top, 12)
        }
        .padding(24)
    }

    // MARK: - Processing pipeline

    private func processImage(_ image: UIImage) async {
        guard let uri = writeTempJPEG(image) else { return }
        isProcessing = true
        results = nil
        progressStatus = .reading

        do {
            let recognized = try await NativeOcr.recognize(uri: uri)
            let lines = recognized.blocks.flatMap { $0.lines.map(\.text) }

            await OverrideStore.shared.load()

            progressStatus = .matching
            progressCurrent = 0
            progressTotal = lines.count

            let deps = ResolveProduct.Deps(allFoods: foodsStore.allFoods, foodIndexData: foodsStore.foodIndex)
            var parsedItems: [ParsedReceiptItem] = []
            let chunkSize = 4
            var i = 0
            while i < lines.count {
                let chunk = lines[i..<min(i + chunkSize, lines.count)]
                for line in chunk {
                    if let parsed = ResolveProduct.resolveProductLine(line, deps) {
                        parsedItems.append(parsed)
                    }
                }
                progressCurrent = min(i + chunkSize, lines.count)
                i += chunkSize
                await Task.yield()
            }

            if settingsStore.settings.offLookupEnabled { progressStatus = .enriching }
            let enrichedItems = await ResolveProduct.enrichWithOff(parsedItems, deps, settingsStore.settings.offLookupEnabled)

            Task { await MatchLog.shared.logWeakMatches(enrichedItems) }

            progressStatus = .calculating
            results = enrichedItems

            let pool = foodsStore.foods(for: profileStore.profile.dietaryPreference)
            let safeFoods = pool.isEmpty ? foodsStore.allFoods : pool
            var totalScore = 0.0
            var matchedCount = 0
            for (idx, item) in enrichedItems.enumerated() {
                if let food = item.matchedFood, item.confidence >= 0.45 {
                    totalScore += food.health_score
                    matchedCount += 1
                    if item.confidence > 0.72 {
                        _ = SwapAlgorithm.findBestSwaps(food, safeFoods, 1, profileStore.profile.dietaryPreference.map(\.rawValue))
                    }
                }
                if (idx + 1) % 5 == 0 { await Task.yield() }
            }

            let scanId = UUID().uuidString
            let scanDate = ISO8601DateFormatter().string(from: Date())
            currentScanId = scanId
            currentScanDate = scanDate

            let persistedItems = enrichedItems.map { item in
                PersistedReceiptItem(rawText: item.rawText, matchedFoodId: item.matchedFood?.id, confidence: item.confidence,
                                      source: item.source, displayName: item.displayName, quantity: item.quantity, unit: item.unit)
            }
            let averageScore = matchedCount > 0 ? Double(JSNumber.roundToInt(totalScore / Double(matchedCount))) : 0
            await StorageService.saveScan(id: scanId, date: scanDate, items: persistedItems, averageScore: averageScore)
            await inventoryStore.refreshInventory()

            progressStatus = .done
            try? await Task.sleep(nanoseconds: 500_000_000)
            progressStatus = .idle
        } catch {
            errorAlert = "Failed to process receipt. Make sure you are running a custom dev client."
            progressStatus = .idle
        }
        isProcessing = false
    }

    private func writeTempJPEG(_ image: UIImage) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        do {
            try data.write(to: url)
            return url.absoluteString
        } catch {
            return nil
        }
    }

    private func handleUpdateItem(index: Int, newFood: FoodItem) async {
        guard var results, let scanId = currentScanId, let scanDate = currentScanDate, results.indices.contains(index) else { return }
        let corrected = results[index]
        results[index] = ParsedReceiptItem(rawText: corrected.rawText, matchedFood: newFood, confidence: 1.0,
                                            source: corrected.source, displayName: corrected.displayName,
                                            quantity: corrected.quantity, unit: corrected.unit)
        self.results = results
        await OverrideStore.shared.set(corrected.rawText, newFood.id)
        await persistResults(results, scanId: scanId, scanDate: scanDate)
    }

    private func handleDeleteItem(index: Int) async {
        guard var results, let scanId = currentScanId, let scanDate = currentScanDate, results.indices.contains(index) else { return }
        results.remove(at: index)
        self.results = results
        await persistResults(results, scanId: scanId, scanDate: scanDate)
    }

    private func persistResults(_ results: [ParsedReceiptItem], scanId: String, scanDate: String) async {
        var totalScore = 0.0
        var matchedCount = 0
        for item in results {
            if let food = item.matchedFood {
                totalScore += food.health_score
                matchedCount += 1
            }
        }
        let averageScore = matchedCount > 0 ? Double(JSNumber.roundToInt(totalScore / Double(matchedCount))) : 0
        let persistedItems = results.map { item in
            PersistedReceiptItem(rawText: item.rawText, matchedFoodId: item.matchedFood?.id, confidence: item.confidence,
                                  source: item.source, displayName: item.displayName, quantity: item.quantity, unit: item.unit)
        }
        await StorageService.updateScan(id: scanId, updatedScan: ScanRecord(
            id: scanId, date: scanDate, items: persistedItems, averageScore: averageScore, interactions: []))
        await inventoryStore.refreshInventory()
    }
}

/// `UIImagePickerController` wrapper for camera capture - SwiftUI has no built-in camera
/// capture view (`PhotosPicker` only covers the library).
private struct CameraPicker: UIViewControllerRepresentable {
    var onCapture: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var onCapture: (UIImage?) -> Void
        init(onCapture: @escaping (UIImage?) -> Void) { self.onCapture = onCapture }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onCapture(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCapture(nil)
        }
    }
}

#Preview {
    NavigationStack {
        ScanReceiptScreen()
            .environmentObject(FoodsStore.shared)
            .environmentObject(ProfileStore())
            .environmentObject(SettingsStore())
            .environmentObject(InventoryStore())
            .environmentObject(Router())
    }
}
