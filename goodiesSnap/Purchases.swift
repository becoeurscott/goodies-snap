import Foundation
import StoreKit

/// StoreKit 2 subscriptions.
///
/// StoreKit verifies transactions on device, but the AI quota is enforced in Postgres, so
/// on-device verification alone is not enough: the server has to be told which plan the
/// user is on, and it must not take the client's word for it. Every purchase therefore
/// sends Apple's signed transaction (a JWS) to our `purchase` function, which verifies the
/// signature itself before writing `entitlements.plan`.
@MainActor
final class Purchases: ObservableObject {

    /// Product identifiers, matching App Store Connect and `Products.storekit`.
    enum ProductID {
        static let plusMonthly = "com.goodies.goodiesSnap.plus.monthly"
        static let plusYearly  = "com.goodies.goodiesSnap.plus.yearly"
        static let proMonthly  = "com.goodies.goodiesSnap.pro.monthly"
        static let proYearly   = "com.goodies.goodiesSnap.pro.yearly"

        static let all: [String] = [plusMonthly, plusYearly, proMonthly, proYearly]

        static func id(for plan: Entitlement.Plan, annual: Bool) -> String? {
            switch plan {
            case .free: return nil
            case .plus: return annual ? plusYearly : plusMonthly
            case .pro:  return annual ? proYearly : proMonthly
            }
        }

        static func plan(for id: String) -> Entitlement.Plan? {
            switch id {
            case plusMonthly, plusYearly: return .plus
            case proMonthly, proYearly: return .pro
            default: return nil
            }
        }
    }

    enum PurchaseOutcome: Equatable {
        case success(Entitlement.Plan)
        case cancelled
        /// Ask-to-buy and similar: the purchase may still complete later, via `Transaction.updates`.
        case pending
        case failed(String)
    }

    @Published private(set) var products: [Product] = []
    @Published private(set) var loading = false
    @Published private(set) var purchasing: String?
    /// The plan Apple says is currently active, independent of anything stored locally.
    @Published private(set) var activePlan: Entitlement.Plan = .free

    /// Called after the server has confirmed a plan, so AppStore can apply it.
    var onPlanChange: ((Entitlement.Plan) -> Void)?
    /// Supplies the current auth token. Without one, the receipt cannot be attributed to a
    /// user, so the purchase stays on device until they sign in.
    var authToken: (() -> String?)?

    private var updatesTask: Task<Void, Never>?

    init() {
        // Transactions can arrive at any time — Ask to Buy approvals, renewals, refunds,
        // or a purchase made on another device — so this listener runs for the whole
        // lifetime of the app, not just while the paywall is on screen.
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
    }

    deinit { updatesTask?.cancel() }

    // MARK: - Catalogue

    func loadProducts() async {
        guard products.isEmpty, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let loaded = try await Product.products(for: ProductID.all)
            // Cheapest first so the paywall's ordering is stable regardless of the order
            // StoreKit returns.
            products = loaded.sorted { $0.price < $1.price }
        } catch {
            // Non-fatal: the paywall falls back to its hard-coded price labels.
            products = []
        }
    }

    func product(for plan: Entitlement.Plan, annual: Bool) -> Product? {
        guard let id = ProductID.id(for: plan, annual: annual) else { return nil }
        return products.first { $0.id == id }
    }

    /// Localized price from StoreKit when available — never a hard-coded string, since the
    /// real price varies by storefront. Falls back to the static label only offline.
    func priceLabel(for plan: Entitlement.Plan, annual: Bool) -> String {
        if let product = product(for: plan, annual: annual) { return product.displayPrice }
        return annual ? plan.annualPriceLabel : plan.priceLabel
    }

    // MARK: - Buying

    func purchase(plan: Entitlement.Plan, annual: Bool) async -> PurchaseOutcome {
        guard let product = product(for: plan, annual: annual) else {
            return .failed("That plan isn't available right now.")
        }
        purchasing = product.id
        defer { purchasing = nil }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                return await redeem(verification)
            case .userCancelled:
                return .cancelled
            case .pending:
                return .pending
            @unknown default:
                return .failed("Purchase couldn't be completed.")
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Restores purchases. StoreKit 2 keeps entitlements in sync automatically, so this
    /// mostly matters after a reinstall or on a second device — and Apple requires the
    /// button regardless.
    func restore() async -> PurchaseOutcome {
        do {
            // Qualified: this app has its own type called AppStore.
            try await StoreKit.AppStore.sync()
        } catch {
            return .failed(error.localizedDescription)
        }
        await refreshEntitlements()
        return activePlan == .free
            ? .failed("No active subscription found for this Apple Account.")
            : .success(activePlan)
    }

    /// Reads Apple's current entitlements and tells the server about the active one.
    func refreshEntitlements() async {
        var best: Entitlement.Plan = .free
        var latest: VerificationResult<Transaction>?

        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement,
                  let plan = ProductID.plan(for: transaction.productID),
                  transaction.revocationDate == nil else { continue }
            // Pro outranks Plus if both somehow appear.
            if plan == .pro || best == .free {
                best = plan
                latest = entitlement
            }
        }

        activePlan = best
        if let latest { _ = await redeem(latest) } else { onPlanChange?(.free) }
    }

    // MARK: - Server hand-off

    /// Finishes a transaction and hands the signed payload to the backend.
    private func redeem(_ result: VerificationResult<Transaction>) async -> PurchaseOutcome {
        guard case .verified(let transaction) = result else {
            // An unverified transaction means the signature check failed. Nothing is
            // granted, and it is deliberately not finished.
            return .failed("That purchase couldn't be verified.")
        }
        guard let plan = ProductID.plan(for: transaction.productID) else {
            await transaction.finish()
            return .failed("Unknown product.")
        }

        // The server is the one that decides the plan; it re-verifies Apple's signature
        // rather than trusting this call.
        if let token = authToken?() {
            do {
                let granted = try await SocialAPI.submitPurchase(jws: result.jwsRepresentation, token: token)
                await transaction.finish()
                activePlan = granted
                onPlanChange?(granted)
                return .success(granted)
            } catch {
                // Do NOT finish: leaving it unfinished means StoreKit replays it through
                // `Transaction.updates`, so a network failure here can't lose a purchase.
                return .failed("Purchase went through, but we couldn't activate it yet. It'll retry automatically.")
            }
        }

        // Signed out: the purchase is real and Apple-verified, so unlock locally now and
        // let the next sign-in attach it to the account.
        await transaction.finish()
        activePlan = plan
        onPlanChange?(plan)
        return .success(plan)
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        _ = await redeem(result)
    }
}
