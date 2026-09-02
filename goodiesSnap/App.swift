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
                    purchases.onPlanChange = { [weak store] plan in store?.applyPurchasedPlan(plan) }
                    await purchases.loadProducts()
                    await purchases.refreshEntitlements()
                }
        }
    }
}
