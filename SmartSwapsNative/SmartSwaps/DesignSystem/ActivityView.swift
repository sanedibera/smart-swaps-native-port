import SwiftUI
import UIKit

/// Wraps `UIActivityViewController` for the "export via OS share sheet" pattern
/// `swapTrainingLog.ts`/`matchLog.ts` use (`Share.share({ message })`). Present with
/// `.sheet(item:)` rather than SwiftUI's declarative `ShareLink` because the content is only
/// known after an async, possibly-throwing load (`exportTrainingLogJSON()` etc.).
struct ActivityView: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
