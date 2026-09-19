import SwiftUI
#if !SKIP
import GoogleMobileAds
#endif

#if !SKIP

/// An adaptive AdMob banner that takes no space until an ad has loaded, and none at all for Premium users.
struct AdBanner: View {
    @ObservedObject private var ads = AdManager.shared
    @State private var width: CGFloat = 0
    @State private var loadedHeight: CGFloat = 0

    var body: some View {
        if !ads.isAdFree, ads.sdkStarted, let unitID = ads.bannerUnitID {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: loadedHeight)
                .background(GeometryReader { proxy in
                    Color.clear
                        .onAppear { width = proxy.size.width }
                        .onChange(of: proxy.size.width) { width = $0 }
                })
                .overlay(alignment: .top) {
                    if width >= 320 {
                        // The banner always gets its full ad size (AdMob rejects a zero-height view);
                        // the container stays collapsed and clips it until an ad has loaded.
                        BannerAdView(unitID: unitID, width: width) { loadedHeight = $0 }
                            .frame(width: width, height: currentOrientationAnchoredAdaptiveBanner(width: width).size.height)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .animation(.easeOut(duration: 0.2), value: loadedHeight)
        }
    }
}

private struct BannerAdView: UIViewRepresentable {
    let unitID: String
    let width: CGFloat
    let onHeightChange: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onHeightChange: onHeightChange) }

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: currentOrientationAnchoredAdaptiveBanner(width: width))
        banner.adUnitID = unitID
        banner.delegate = context.coordinator
        banner.rootViewController = AdManager.topViewController()
        banner.load(Request())
        context.coordinator.loadedWidth = width
        return banner
    }

    func updateUIView(_ banner: BannerView, context: Context) {
        // Reload at the new width after rotation or a layout change.
        guard width > 0, abs(width - context.coordinator.loadedWidth) > 1 else { return }
        context.coordinator.loadedWidth = width
        banner.adSize = currentOrientationAnchoredAdaptiveBanner(width: width)
        banner.load(Request())
    }

    final class Coordinator: NSObject, BannerViewDelegate {
        let onHeightChange: (CGFloat) -> Void
        var loadedWidth: CGFloat = 0

        init(onHeightChange: @escaping (CGFloat) -> Void) {
            self.onHeightChange = onHeightChange
        }

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            onHeightChange(bannerView.adSize.size.height)
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            onHeightChange(0)
        }
    }
}

#else

// TODO(android): host a real AdMob Android `AdView` here via a Compose `AndroidView`
// (Skip transpiles this `View` into a Composable, so the interop lives in this one
// file). Renders nothing until then, matching "no banner loaded yet" behavior.
struct AdBanner: View {
    var body: some View {
        EmptyView()
    }
}

#endif
