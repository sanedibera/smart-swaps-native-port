import SwiftUI
import SmartSwapsKit

/// Port of `components/FoodIcon.tsx` (24 ln). The RN version renders the food's bundled
/// OpenMoji SVG (`icon_library.svg_content`, on-device, no network) via `SvgXml`, falling
/// back to an Ionicons category glyph when there's no `icon_key` or the SVG fails.
///
/// SVG rendering itself is still open — PORTING_NOTES.md "Icon mappings" (Phase 4) calls for
/// pre-rasterising the 85 OpenMoji SVGs into an asset catalog at build time, which needs a
/// build step this container can't run (no Xcode). Until that lands, every food renders via
/// the SF Symbol fallback path below (real, exercised logic - not a stub), even when an
/// `iconKey` is present; `iconLibrary` is threaded through already so swapping in the
/// rasterised-asset lookup later is a one-line change here, not a prop-shape change.
struct FoodIcon: View {
    var iconKey: String? = nil
    var category: String
    var size: CGFloat = 20
    var color: Color = Colors.textSecondary
    var iconLibrary: [String: String] = [:]

    var body: some View {
        Image(systemName: getIconForCategory(category))
            .font(.system(size: size * 0.85))
            .foregroundColor(color)
            .frame(width: size, height: size)
    }
}

#Preview {
    HStack(spacing: 16) {
        FoodIcon(iconKey: nil, category: "Fruit")
        FoodIcon(iconKey: nil, category: "Meat")
        FoodIcon(iconKey: nil, category: "Dairy")
        FoodIcon(iconKey: nil, category: "Beverages")
    }
    .padding()
}
