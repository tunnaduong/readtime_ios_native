import SwiftUI
#if !SKIP
import StoreKit
#endif

#if !SKIP
@MainActor
final class PurchaseManager: ObservableObject {
    // TODO: Replace with the product ID configured in App Store Connect.
    static let premiumProductID = "com.fatties.readtime.premium"

    @Published private(set) var premiumProduct: Product?
    @Published private(set) var isPremium = false {
        didSet { AdManager.shared.isAdFree = isPremium }
    }
    @Published private(set) var isWorking = false
    @Published var message: String?

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self?.refreshEntitlements()
                }
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func load() async {
        premiumProduct = try? await Product.products(for: [Self.premiumProductID]).first
        await refreshEntitlements()
    }

    /// Length of the free trial, when the product is a subscription with one.
    var freeTrialDescription: String? {
        guard let offer = premiumProduct?.subscription?.introductoryOffer, offer.paymentMode == .freeTrial else { return nil }
        return Self.describe(offer.period)
    }

    func isEligibleForFreeTrial() async -> Bool {
        guard freeTrialDescription != nil, let subscription = premiumProduct?.subscription else { return false }
        return await subscription.isEligibleForIntroOffer
    }

    /// "29,000 ₫/year" for subscriptions, or the plain price for a one-time purchase.
    var priceDescription: String? {
        guard let product = premiumProduct else { return nil }
        guard let period = product.subscription?.subscriptionPeriod else { return product.displayPrice }
        return "\(product.displayPrice)/\(Self.describe(period, unitOnly: period.value == 1))"
    }

    private static func describe(_ period: Product.SubscriptionPeriod, unitOnly: Bool = false) -> String {
        let components: DateComponents
        switch period.unit {
        case .day: components = DateComponents(day: period.value)
        case .week: components = DateComponents(day: period.value * 7)
        case .month: components = DateComponents(month: period.value)
        case .year: components = DateComponents(year: period.value)
        @unknown default: components = DateComponents(day: period.value)
        }
        if unitOnly {
            switch period.unit {
            case .week: return String(localized: "week")
            case .month: return String(localized: "month")
            case .year: return String(localized: "year")
            default: return String(localized: "day")
            }
        }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 1
        return formatter.string(from: components) ?? ""
    }

    func refreshEntitlements() async {
        var owned = false
        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.premiumProductID,
               transaction.revocationDate == nil {
                owned = true
            }
        }
        isPremium = owned
    }

    func buyPremium() async {
        if premiumProduct == nil { await load() }
        guard let premiumProduct else {
            message = String(localized: "Premium isn't available right now. Please try again later.")
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            switch try await premiumProduct.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                isPremium = true
                message = String(localized: "Welcome to ReadTime Premium!")
            case .success(.unverified):
                message = String(localized: "The purchase couldn't be verified.")
            case .pending:
                message = String(localized: "Your purchase is pending approval.")
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = error.localizedDescription
        }
    }

    func restorePurchases() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            message = isPremium
                ? String(localized: "Your purchases have been restored.")
                : String(localized: "No previous purchases were found.")
        } catch {
            message = error.localizedDescription
        }
    }
}
#else
// TODO(android): wire up real Google Play Billing (BillingClient) via Skip Kotlin
// interop. Stubbed as "no premium available" for now so the rest of the app
// (paywall, settings) can run on Android without a purchase backend.
/// Minimal stand-in for StoreKit's `Product`, exposing only what the paywall UI reads.
struct StubPremiumProduct {
    let displayPrice: String
}

@MainActor
final class PurchaseManager: ObservableObject {
    static let premiumProductID = "com.fatties.readtime.premium"

    @Published private(set) var premiumProduct: StubPremiumProduct? = nil
    @Published private(set) var isPremium = false {
        didSet { AdManager.shared.isAdFree = isPremium }
    }
    @Published private(set) var isWorking = false
    @Published var message: String?

    init() {}

    func load() async {}

    var freeTrialDescription: String? { nil }

    func isEligibleForFreeTrial() async -> Bool { false }

    var priceDescription: String? { nil }

    func refreshEntitlements() async {}

    func buyPremium() async {
        message = String(localized: "Premium isn't available yet on Android.")
    }

    func restorePurchases() async {
        message = String(localized: "Premium isn't available yet on Android.")
    }
}
#endif
