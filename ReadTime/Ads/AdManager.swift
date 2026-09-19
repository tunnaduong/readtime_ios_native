import SwiftUI
#if !SKIP
import GoogleMobileAds
import UserMessagingPlatform
import AppTrackingTransparency
#endif

// MARK: - Ads

#if !SKIP

/// Google AdMob interstitials, shown when a reading session ends.
/// IDs come from Info.plist (set in ReadTime/Config/ReadTime.xcconfig); they default to Google's test IDs.
@MainActor
final class AdManager: NSObject, ObservableObject, FullScreenContentDelegate {
    static let shared = AdManager()

    /// Premium users never see ads.
    @Published var isAdFree = false

    private var interstitial: InterstitialAd?
    private var isLoading = false

    private var appOpenAd: AppOpenAd?
    private var appOpenLoadedAt: Date?
    private var isLoadingAppOpen = false
    private var lastAppOpenShownAt: Date?
    private var isShowingAd = false
    private let launchedAt = Date()
    private var onDismiss: (() -> Void)?
    private var started = false

    private var interstitialUnitID: String? {
        let value = (Bundle.main.object(forInfoDictionaryKey: "AdMobInterstitialUnitID") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || value.hasPrefix("$(") ? nil : value
    }

    /// Asks for consent where the law requires it (EEA, UK, and similar), then starts the SDK
    /// and preloads the first ad.
    func start() {
        guard !started else { return }
        #if DEBUG
        // Used when capturing App Store screenshots: `simctl launch … -disableAds YES`.
        if UserDefaults.standard.bool(forKey: "disableAds") {
            isAdFree = true
            return
        }
        #endif
        started = true
        Task { await prepare() }
    }

    /// Google's consent form first (where required), then Apple's tracking prompt, then the SDK.
    private func prepare() async {
        // Returning users who already answered the tracking prompt can start without waiting.
        if ATTrackingManager.trackingAuthorizationStatus != .notDetermined {
            startSDKIfAllowed()
        }

        await withCheckedContinuation { continuation in
            ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters()) { _ in
                continuation.resume()
            }
        }
        if let root = Self.topViewController() {
            try? await ConsentForm.loadAndPresentIfRequired(from: root)
        }

        await requestTrackingAuthorizationIfNeeded()
        startSDKIfAllowed()
    }

    private func requestTrackingAuthorizationIfNeeded() async {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
        // iOS ignores the request unless the app is active, e.g. right after launch.
        for _ in 0..<20 where UIApplication.shared.applicationState != .active {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        _ = await ATTrackingManager.requestTrackingAuthorization()
    }

    /// True once consent allows ads and the SDK has started; banners wait for this.
    @Published private(set) var sdkStarted = false

    var bannerUnitID: String? {
        let value = (Bundle.main.object(forInfoDictionaryKey: "AdMobBannerUnitID") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || value.hasPrefix("$(") ? nil : value
    }

    private func startSDKIfAllowed() {
        guard ConsentInformation.shared.canRequestAds, !sdkStarted else { return }
        sdkStarted = true
        MobileAds.shared.start { [weak self] _ in
            Task { @MainActor in
                self?.loadInterstitial()
                self?.loadAppOpenAd()
            }
        }
    }

    private func loadInterstitial() {
        guard !isAdFree, sdkStarted, interstitial == nil, !isLoading, let unitID = interstitialUnitID else { return }
        isLoading = true
        InterstitialAd.load(with: unitID, request: Request()) { [weak self] ad, _ in
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false
                self.interstitial = ad
                ad?.fullScreenContentDelegate = self
            }
        }
    }

    private var appOpenUnitID: String? {
        let value = (Bundle.main.object(forInfoDictionaryKey: "AdMobAppOpenUnitID") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || value.hasPrefix("$(") ? nil : value
    }

    /// App open ads expire after four hours, per Google's guidance.
    private var hasFreshAppOpenAd: Bool {
        guard appOpenAd != nil, let appOpenLoadedAt else { return false }
        return Date.now.timeIntervalSince(appOpenLoadedAt) < 4 * 3600
    }

    private func loadAppOpenAd() {
        guard !isAdFree, sdkStarted, !isLoadingAppOpen, !hasFreshAppOpenAd, let unitID = appOpenUnitID else { return }
        isLoadingAppOpen = true
        AppOpenAd.load(with: unitID, request: Request()) { [weak self] ad, _ in
            Task { @MainActor in
                guard let self else { return }
                self.isLoadingAppOpen = false
                self.appOpenAd = ad
                self.appOpenLoadedAt = ad == nil ? nil : .now
                ad?.fullScreenContentDelegate = self
                // Cold start: show it only if it arrived within a few seconds of launch,
                // so it never pops up in the middle of using the app.
                if ad != nil, Date.now.timeIntervalSince(self.launchedAt) < 5 {
                    self.showAppOpenAdIfAvailable()
                }
            }
        }
    }

    /// Shows an app open ad when the app opens or returns to the foreground.
    func showAppOpenAdIfAvailable() {
        guard !isAdFree, !isShowingAd else { return }
        // Don't show them back to back when someone quickly switches apps.
        if let lastAppOpenShownAt, Date.now.timeIntervalSince(lastAppOpenShownAt) < 60 { return }
        guard hasFreshAppOpenAd, let appOpenAd, let root = Self.topViewController(), !(root is UIAlertController) else {
            loadAppOpenAd()
            return
        }
        isShowingAd = true
        lastAppOpenShownAt = .now
        appOpenAd.present(from: root)
    }

    /// Shows an interstitial if one is loaded, then calls `completion` once it closes.
    /// Calls `completion` right away when there's no ad (Premium, no consent, still loading, offline).
    func showInterstitial(then completion: @escaping () -> Void) {
        guard !isAdFree, let interstitial, let root = Self.topViewController() else {
            completion()
            loadInterstitial()
            return
        }
        onDismiss = completion
        isShowingAd = true
        interstitial.present(from: root)
    }

    nonisolated func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        let adID = ObjectIdentifier(ad)
        Task { @MainActor in self.finishPresentation(of: adID) }
    }

    nonisolated func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        let adID = ObjectIdentifier(ad)
        Task { @MainActor in self.finishPresentation(of: adID) }
    }

    private func finishPresentation(of adID: ObjectIdentifier) {
        isShowingAd = false
        if let appOpenAd, ObjectIdentifier(appOpenAd) == adID {
            self.appOpenAd = nil
            appOpenLoadedAt = nil
            loadAppOpenAd()
            return
        }
        interstitial = nil
        let completion = onDismiss
        onDismiss = nil
        completion?()
        loadInterstitial()
    }

    static func topViewController() -> UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
        var top = root
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

#else

// TODO(android): wire up the AdMob Android SDK (interstitial/app-open) and the Android
// UMP SDK for consent, via Skip Kotlin interop. There's no Android equivalent of App
// Tracking Transparency; consent is governed by UMP alone there. Stubbed as "no ads"
// for now so the rest of the app can run without a monetization backend.
@MainActor
final class AdManager: NSObject, ObservableObject {
    static let shared = AdManager()

    @Published var isAdFree = false
    @Published private(set) var sdkStarted = false

    var bannerUnitID: String? { nil }

    func start() {}

    func showAppOpenAdIfAvailable() {}

    func showInterstitial(then completion: @escaping () -> Void) {
        completion()
    }
}

#endif
