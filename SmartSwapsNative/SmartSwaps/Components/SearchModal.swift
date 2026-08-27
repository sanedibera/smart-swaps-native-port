import SwiftUI
import SmartSwapsKit

/// Port of `components/SearchModal.tsx` (24 ln) - a thin `Modal` wrapper around
/// `SearchScreen`, presented as an iOS sheet (matches `presentationStyle="pageSheet"`) by
/// whichever screen shows it (see `ReceiptItemList.swift`'s usage).
///
/// Phase 6 fix: this previously called `SearchScreen()` with no arguments at all, silently
/// dropping `mode`/`onSelect`/`rawText` - a leftover from Phase 4, written before
/// `SearchScreen` was a real screen. Now forwards them for real; `onSelect` only carries a
/// `FoodItem` (this modal's contract, matching `ReceiptItemList`'s correction-picker use),
/// so a `.recipe` selection is ignored here - same simplification already noted for
/// `ReceiptDetailScreen`/`ScanReceiptScreen`'s "Add Item via Search" in PORTING_NOTES.md.
struct SearchModal: View {
    enum Mode { case foods, swaps }

    var mode: Mode = .foods
    var onSelect: ((FoodItem) -> Void)? = nil
    var rawText: String? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SearchScreen(
            onBack: { dismiss() },
            mode: mode == .swaps ? .swaps : .foods,
            onSelect: onSelect.map { select in
                { (selection: SearchSelection) in
                    if case .food(let food) = selection { select(food) }
                }
            },
            rawText: rawText
        )
    }
}
