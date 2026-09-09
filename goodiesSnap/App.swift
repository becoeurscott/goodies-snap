import SwiftUI

@main
struct GoodiesSnapApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var social = SocialStore()
    @StateObject private var purchases = Purchases()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(social)
                .environmentObject(purchases)
                .preferredColorScheme(.light)
                .task {
                    // Wire the purchase layer to the rest of the app once, at launch:
                    // transactions can arrive before the paywall is ever opened.
                    purchases.authToken = { [weak social] in social?.session?.accessToken }
                    // Deterministic post-sign-in redirect + token propagation.
                    social.onSignedIn = { [weak store, weak social] isNewAccount in
                        store?.aiToken = social?.session?.accessToken
                        // Use the account's display name for the greeting (sign-in recovers
                        // it from the profile), keeping any onboarding-entered name otherwise.
                        if let name = social?.session?.displayName, !name.isEmpty {
                            store?.userName = name
                        }
                        store?.authenticationSucceeded(newAccount: isNewAccount)
                    }
                    purchases.onPlanChange = { [weak store] plan in store?.applyPurchasedPlan(plan) }
                    // Drop a stale/deleted persisted login before the UI trusts it.
                    await social.validateSession()
                    await purchases.loadProducts()
                    await purchases.refreshEntitlements()
                }
        }
    }
}
