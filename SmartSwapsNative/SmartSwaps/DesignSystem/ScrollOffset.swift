import SwiftUI

/// Shared scroll-offset tracker for every screen that hosts `GlassHeader`/`LargeTitle`
/// (Search, Recipes, Receipts, Home — Phase 5). SwiftUI has no `Animated.ScrollView`
/// equivalent, so `GlassHeader.scrollY` is fed from this instead: a `GeometryReader` inside
/// the scroll content reports its offset via a `PreferenceKey`, compatible back to iOS 14
/// (the view-aligned/`onScrollGeometryChange` scroll APIs are iOS 17+, past this port's 16.4
/// deployment target).
private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Place as the first child of the scroll content; `coordinateSpace` must match the
/// enclosing `TrackableScrollView`'s.
struct ScrollOffsetReporter: View {
    var coordinateSpace: String
    var body: some View {
        GeometryReader { geo in
            Color.clear.preference(key: ScrollOffsetPreferenceKey.self, value: -geo.frame(in: .named(coordinateSpace)).minY)
        }
        .frame(height: 0)
    }
}

/// A `ScrollView` that reports its offset to `onOffsetChange`. `content` should start with a
/// `ScrollOffsetReporter(coordinateSpace: "scroll")`.
struct TrackableScrollView<Content: View>: View {
    var showsIndicators = true
    var onOffsetChange: (CGFloat) -> Void = { _ in }
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(showsIndicators: showsIndicators) {
            content
        }
        .coordinateSpace(name: "scroll")
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { onOffsetChange($0) }
    }
}
