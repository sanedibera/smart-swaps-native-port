import SwiftUI
import SmartSwapsKit

/// Port of `components/GlassHeader.tsx` (281 ln) — see PORTING_NOTES.md for the exact
/// fade-band math this reproduces (`FADE_EXTENSION`, `FADE_STEPS`, quadratic ease-out alpha).
///
/// `scrollY` replaces the RN `Animated.Value`: SwiftUI has no direct equivalent, so screens
/// that host this (Phase 5) track their own scroll offset (a `PreferenceKey` on the
/// `ScrollView`'s content) and pass it in as a plain `CGFloat`. The three interpolations
/// (large-title fade/slide, blur fade-in, small-title cross-fade) are reproduced as pure
/// functions of that value with the same input ranges as the source.
private let fadeExtension: CGFloat = 44
private let fadeSteps = 10

func navBlurGradient(headerHeight: CGFloat) -> (stops: [Gradient.Stop], solidStop: CGFloat) {
    let total = headerHeight + fadeExtension
    let solidStop = headerHeight / total
    let fadeSpan = 1 - solidStop
    var stops: [Gradient.Stop] = [
        .init(color: .black, location: 0),
        .init(color: .black, location: solidStop),
    ]
    for i in 0..<fadeSteps {
        let t = Double(i + 1) / Double(fadeSteps)
        let location = solidStop + fadeSpan * CGFloat(t)
        let alpha = t == 1 ? 0 : pow(1 - t, 2)
        stops.append(.init(color: .black.opacity(alpha), location: location))
    }
    return (stops, solidStop)
}

/// A genuine native progressive blur: `.bar` material (the same material UINavigationBar and
/// UITabBar use — SwiftUI's equivalent of `tint="systemChromeMaterial"`), masked by the
/// gradient above so it feathers to nothing over `FADE_EXTENSION` points instead of a hard edge.
struct NavBlur: View {
    var headerHeight: CGFloat

    var body: some View {
        let (stops, _) = navBlurGradient(headerHeight: headerHeight)
        Rectangle()
            .fill(.bar)
            .frame(height: headerHeight + fadeExtension)
            .mask(LinearGradient(gradient: Gradient(stops: stops), startPoint: .top, endPoint: .bottom))
            .allowsHitTesting(false)
    }
}

/// Compact iOS nav bar height (UINavigationBar's collapsed/non-large-title height).
let headerContentHeight: CGFloat = 44

/// A floating glass capsule button mirroring the iOS 26 liquid-glass back button. Falls back
/// to a white circle with a soft shadow — this port always takes the fallback for now (see
/// PORTING_NOTES.md on the deferred `isLiquidGlassAvailable()`/`NativeTabs` branch).
struct GlassCircleButton<Content: View>: View {
    var onPress: (() -> Void)? = nil
    @ViewBuilder var content: Content

    var body: some View {
        Button(action: { onPress?() }) {
            content
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.9))
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

struct GlassHeader<Left: View>: View {
    var title: String
    var onSettingsPress: (() -> Void)? = nil
    var scrollY: CGFloat = 0
    @ViewBuilder var leftAccessory: Left
    /// `nil` reproduces the RN `!rightAccessory` check that swaps in the settings button.
    var rightAccessory: AnyView? = nil

    @Environment(\.safeAreaInsetsTop) private var safeAreaTop

    private var headerHeight: CGFloat { safeAreaTop + headerContentHeight }

    private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { min(max(v, lo), hi) }
    private func interp(_ x: CGFloat, _ inLo: CGFloat, _ inHi: CGFloat, _ outLo: CGFloat, _ outHi: CGFloat) -> CGFloat {
        let t = clamp((x - inLo) / (inHi - inLo), 0, 1)
        return outLo + (outHi - outLo) * t
    }

    private var blurOpacity: Double { Double(interp(scrollY, 0, 38, 0, 1)) }
    private var smallTitleOpacity: Double { Double(interp(scrollY, 14, 34, 0, 1)) }
    private var smallTitleTranslateY: CGFloat { interp(scrollY, 14, 34, 6, 0) }

    var body: some View {
        ZStack {
            NavBlur(headerHeight: headerHeight)
                .opacity(blurOpacity)
                .frame(maxHeight: .infinity, alignment: .top)

            HStack {
                leftAccessory
                Spacer()
                if let rightAccessory {
                    rightAccessory
                } else if let onSettingsPress {
                    GlassCircleButton(onPress: onSettingsPress) {
                        Image(systemName: "gearshape").font(.system(size: 22)).foregroundColor(Colors.textPrimary)
                    }
                }
            }
            .padding(.horizontal, 16)

            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Colors.textPrimary)
                .lineLimit(1)
                .opacity(smallTitleOpacity)
                .offset(y: smallTitleTranslateY)
        }
        .frame(height: headerHeight)
        .padding(.top, safeAreaTop)
        .frame(maxWidth: .infinity)
    }
}

/// The big bold iOS-style large title — place as the first item in the screen's scrollable
/// content, fed the same `scrollY` passed to `GlassHeader`, so it cross-fades into the
/// compact title as you scroll instead of being covered by the bar.
struct LargeTitle: View {
    var title: String
    var scrollY: CGFloat = 0

    private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { min(max(v, lo), hi) }

    private var opacity: Double {
        let t = clamp(scrollY / 26, 0, 1)
        return Double(1 - t)
    }
    private var translateY: CGFloat { -8 * clamp(scrollY / 26, 0, 1) }

    var body: some View {
        Text(title)
            .font(.system(size: 34, weight: .heavy))
            .tracking(0.37)
            .foregroundColor(Colors.textPrimary)
            .padding(.bottom, 4)
            .opacity(opacity)
            .offset(y: translateY)
    }
}

private struct SafeAreaInsetsTopKey: EnvironmentKey {
    static let defaultValue: CGFloat = 47 // Typical notch/Dynamic Island device top inset.
}

extension EnvironmentValues {
    var safeAreaInsetsTop: CGFloat {
        get { self[SafeAreaInsetsTopKey.self] }
        set { self[SafeAreaInsetsTopKey.self] = newValue }
    }
}

#Preview {
    ZStack(alignment: .top) {
        ScrollView {
            VStack(alignment: .leading) {
                LargeTitle(title: "Home")
                ForEach(0..<20) { i in
                    Text("Row \(i)").padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 60)
        }
        GlassHeader(title: "Home", onSettingsPress: {}, leftAccessory: { EmptyView() })
    }
}
