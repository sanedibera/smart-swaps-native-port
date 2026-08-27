import SwiftUI

@main
struct SmartSwapsApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                // app.json: "userInterfaceStyle": "light", and every screen
                // hardcodes light colors (PORTING_INVENTORY.md §1) — no dark
                // palette exists to derive from.
                .preferredColorScheme(.light)
        }
    }
}
