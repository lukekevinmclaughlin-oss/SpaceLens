import Foundation
import StoreKit

@MainActor
final class PurchaseManager: ObservableObject {
    static let shared = PurchaseManager()
    static let monthlyID = "com.lukemclaughlin.spacelens.pro.monthly"
    static let yearlyID = "com.lukemclaughlin.spacelens.pro.annual"
    static let productIDs: Set<String> = [monthlyID, yearlyID]

    // Freemium: the core app (scanning, visualization, cleanup, export) is
    // free forever. `hasAccess` is the Pro entitlement for the advanced layer
    // (menu-bar watcher, trends). Nothing is deleted if a subscription lapses.
    @Published private(set) var hasAccess = false
    /// Contextual paywall trigger — set once after the first completed scan.
    @Published var showPaywall = false
    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoading = true
    @Published private(set) var isPurchasing = false
    @Published var lastError: String?
    private var updatesTask: Task<Void, Never>?

    private init() {
        #if DEBUG
        hasAccess = UserDefaults.standard.bool(forKey: "debug.forcePurchased") || ProcessInfo.processInfo.environment["SPACELENS_DEMO"] == "1"
        #endif
        #if DIRECT_DISTRIBUTION
        hasAccess = true
        #endif
        if ProcessInfo.processInfo.environment["SPACELENS_PRO"] == "1" { hasAccess = true }
        updatesTask = listenForTransactions()
        Task { await refresh() }
    }

    var monthlyProduct: Product? { products.first { $0.id == Self.monthlyID } }
    var yearlyProduct: Product? { products.first { $0.id == Self.yearlyID } }
    var monthlyPrice: String { monthlyProduct?.displayPrice ?? "Monthly price unavailable" }
    var yearlyPrice: String { yearlyProduct?.displayPrice ?? "Annual price unavailable" }

    var yearlyCallToAction: String {
        guard let product = yearlyProduct else { return "Try Premium" }
        return product.subscription?.introductoryOffer == nil ? "Subscribe Annually" : "Start Free Trial"
    }

    var monthlyCallToAction: String {
        guard let product = monthlyProduct else { return "Monthly plan" }
        return product.subscription?.introductoryOffer == nil ? "Monthly — \(product.displayPrice)" : "Monthly free trial — then \(product.displayPrice)"
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            products = try await Product.products(for: Self.productIDs)
                .sorted { $0.price < $1.price }
            if products.count != Self.productIDs.count {
                lastError = "One or more subscription options are temporarily unavailable."
            }
        } catch {
            products = []
            lastError = "Subscriptions couldn’t be loaded. Please check your connection and try again."
        }
        await updateEntitlement()
    }

    func purchaseYearly() async { await purchase(yearlyProduct) }
    func purchaseMonthly() async { await purchase(monthlyProduct) }

    private func purchase(_ product: Product?) async {
        guard let product else {
            lastError = "Subscriptions aren’t available right now. Please try again later."
            return
        }
        isPurchasing = true
        lastError = nil
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(.verified(let transaction)):
                await transaction.finish()
                await updateEntitlement()
            case .success(.unverified):
                lastError = "The App Store could not verify this purchase. No Premium access was granted."
            case .pending:
                lastError = "This purchase is pending approval. Premium will unlock automatically when it completes."
            case .userCancelled:
                break
            @unknown default:
                lastError = "The purchase did not complete. Please try again."
            }
        } catch { lastError = error.localizedDescription }
    }

    /// Shows the contextual Pro paywall exactly once, after the user's first
    /// completed scan (their first meaningful result). Never for Pro users.
    func recordMeaningfulResult() {
        guard !hasAccess else { return }
        let key = "spacelens.contextualPaywallShown"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        showPaywall = true
    }

    func restore() async {
        lastError = nil
        do { try await AppStore.sync() }
        catch { lastError = error.localizedDescription }
        await updateEntitlement()
        if !hasAccess && lastError == nil {
            lastError = "No active Storage Atlas Pro subscription was found for this Apple Account."
        }
    }

    private func updateEntitlement() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               Self.productIDs.contains(transaction.productID),
               transaction.revocationDate == nil,
               (transaction.expirationDate ?? .distantFuture) > Date() { active = true }
        }
        #if DEBUG
        active = active || UserDefaults.standard.bool(forKey: "debug.forcePurchased") || ProcessInfo.processInfo.environment["SPACELENS_DEMO"] == "1"
        #endif
        #if DIRECT_DISTRIBUTION
        active = true
        #endif
        hasAccess = active
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task(priority: .background) {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await updateEntitlement()
                }
            }
        }
    }
}
