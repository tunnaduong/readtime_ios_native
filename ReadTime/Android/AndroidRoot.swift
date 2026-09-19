import SwiftUI

#if SKIP
/// Android entry point, loaded by `Android/app/src/main/kotlin/Main.kt`. Mirrors `ReadTimeApp`,
/// which is iOS-only because Skip apps start from a root view instead of an `App`.
public struct ReadTimeRootView: View {
    @StateObject private var store = ReadingStore()
    @StateObject private var purchases = PurchaseManager()
    @AppStorage(AppearanceMode.storageKey) private var appearance = AppearanceMode.system

    public init() {
    }

    public var body: some View {
        ReadTimeTabView()
            .environmentObject(store)
            .environmentObject(purchases)
            .tint(.readTimePurple)
            .preferredColorScheme(appearance.colorScheme)
            .task {
                ReadTimeAppDelegate.shared.store = store
                await purchases.load()
            }
    }
}

/// Android activity lifecycle callbacks, forwarded from `Main.kt`.
public final class ReadTimeAppDelegate {
    public static let shared = ReadTimeAppDelegate()
    var store: ReadingStore?

    private init() {
    }

    public func onInit() {}
    public func onLaunch() {}
    public func onResume() {}
    public func onPause() {}

    public func onStop() {
        guard let store else { return }
        store.save()
        if UserDefaults.standard.bool(forKey: CloudBackup.syncEnabledKey) {
            try? CloudBackup.backUp(store)
        }
    }

    public func onDestroy() {}
    public func onLowMemory() {}
}
#endif
