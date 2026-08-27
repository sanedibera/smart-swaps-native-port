import UIKit

/// Port of the `expo-haptics` call sites (`Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light)`
/// in `ReceiptItemList.tsx`'s edit/delete buttons and `receipts.tsx`'s scan-card tap) onto
/// `UIImpactFeedbackGenerator`. Kept in the app target - `UIKit` isn't available to
/// `SmartSwapsKit`'s macOS target.
enum Haptics {
    static func light() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
}
