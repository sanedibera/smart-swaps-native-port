import SwiftUI

/// Port of `components/CoverFlowCarousel.tsx` (124 ln). Infinite loop via a tripled data
/// array with a silent jump back to the middle set at the ends (`onMomentumScrollEnd`);
/// per-item scale 0.85->1, opacity 0.5->1, ±45° Y rotation and inward translateX driven by
/// distance from center — all clamped, all computed from a single scroll offset.
///
/// SwiftUI has no direct `Animated.ScrollView` + `scrollEventThrottle` equivalent that stays
/// on the 16.4 deployment target (the view-aligned scroll-snap API is iOS 17+), so this drives
/// the same math from a `DragGesture` over a fixed `HStack` instead of a real `ScrollView` —
/// the geometry and the loop-jump are faithful; the exact momentum/deceleration feel of
/// `decelerationRate="fast"` is a SwiftUI spring approximation, not UIScrollView physics.
struct CoverFlowCarousel<T, ItemContent: View>: View {
    var data: [T]
    var keyExtractor: (T, Int) -> String
    var initialScrollIndex: Int = 0
    @ViewBuilder var renderItem: (T, Int) -> ItemContent

    @State private var index: Int
    @State private var dragTranslation: CGFloat = 0

    private var itemWidth: CGFloat { UIScreen.main.bounds.width * 0.78 }
    private var dataLength: Int { data.count }
    private var loopedData: [T] { data + data + data }

    init(data: [T], keyExtractor: @escaping (T, Int) -> String, initialScrollIndex: Int = 0,
         @ViewBuilder renderItem: @escaping (T, Int) -> ItemContent) {
        self.data = data
        self.keyExtractor = keyExtractor
        self.initialScrollIndex = initialScrollIndex
        self.renderItem = renderItem
        _index = State(initialValue: data.count + initialScrollIndex)
    }

    var body: some View {
        let w = itemWidth
        GeometryReader { _ in
            HStack(spacing: 0) {
                ForEach(Array(loopedData.enumerated()), id: \.offset) { i, item in
                    let distance = CGFloat(i - index) - dragTranslation / w
                    let clamped = min(max(distance, -1), 1)
                    let scale = 1 - abs(clamped) * 0.15
                    let opacity = 1 - abs(clamped) * 0.5
                    let rotation = -clamped * 45
                    let translateX = clamped * -w * 0.15

                    renderItem(item, i % dataLength)
                        .frame(width: w)
                        .padding(.horizontal, 8)
                        .scaleEffect(scale)
                        .opacity(opacity)
                        .rotation3DEffect(.degrees(rotation), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
                        .offset(x: translateX)
                }
            }
            .offset(x: -CGFloat(index) * w + w / 2 - (UIScreen.main.bounds.width) / 2 + w / 2 + dragTranslation)
        }
        .frame(height: 260)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { dragTranslation = $0.translation.width }
                .onEnded { value in
                    let threshold = w * 0.2
                    var newIndex = index
                    if value.translation.width < -threshold { newIndex += 1 }
                    else if value.translation.width > threshold { newIndex -= 1 }
                    withAnimation(.interactiveSpring()) {
                        dragTranslation = 0
                        index = newIndex
                    }
                    // Loop illusion: silently jump back into the middle copy once the edges
                    // are reached, exactly like the RN `onMomentumScrollEnd` handler.
                    if newIndex < dataLength {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { index = newIndex + dataLength }
                    } else if newIndex >= dataLength * 2 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { index = newIndex - dataLength }
                    }
                }
        )
        .padding(.vertical, 4)
    }
}

#Preview {
    CoverFlowCarousel(data: Array(1...5), keyExtractor: { item, _ in "\(item)" }) { item, _ in
        RoundedRectangle(cornerRadius: 24)
            .fill(Colors.cardBackground)
            .overlay(Text("Card \(item)").font(.headline))
            .frame(height: 220)
    }
}
