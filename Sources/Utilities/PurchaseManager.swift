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
    var monthlyPrice: String { monthlyProduct?.displayPrice ?? "€2,99" }
    var yearlyPrice: String { yearlyProduct?.displayPrice ?? "€14,99" }

    func refresh() async {
        do { products = try await Product.products(for: Self.productIDs) }
        catch { products = [] }
        await updateEntitlement()
    }

    func purchaseYearly() async { await purchase(yearlyProduct) }
    func purchaseMonthly() async { await purchase(monthlyProduct) }

    private func purchase(_ product: Product?) async {
        guard let product else {
            lastError = "Subscriptions aren’t available right now. Please try again later."
            return
        }
        do {
            let result = try await product.purchase()
            if case .success(let verification) = result,
               case .verified(let transaction) = verification {
                await transaction.finish()
                await updateEntitlement()
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
        do { try await AppStore.sync() }
        catch { lastError = error.localizedDescription }
        await updateEntitlement()
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
        hasAccess = true  // free: always unlocked
        _ = active
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
