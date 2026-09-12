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
                    // Lets a lapsed access token silently renew during an AI call instead of
                    // bouncing the signed-in user back to the sign-in screen.
                    store.refreshAIToken = { [weak social] in await social?.refreshedToken() }
                    // Deterministic post-sign-in redirect + token propagation.
                    social.onSignedIn = { [weak store, weak social] isNewAccount in
                        store?.aiToken = social?.session?.accessToken
                        // Use the account's display name for the greeting (sign-in recovers
                        // it from the profile), keeping any onboarding-entered name otherwise.
                        if let name = social?.session?.displayName, !name.isEmpty {
                            store?.userName = name
                        }
                        store?.authenticationSucceeded(newAccount: isNewAccount)
                        // The server owns the plan; mirror it so gating matches enforcement.
                        if let token = social?.session?.accessToken {
                            store?.aiToken = token
                            store?.currentUserID = social?.session?.userID
                            Task {
                                await store?.refreshServerEntitlement(token: token)
                                // Bring this account's saved recipes/plan/answers onto the device.
                                await store?.pullAndMergeServerState()
                            }
                        }
                    }
                    // Disconnect: reset the app to a logged-out state and return to onboarding.
                    social.onSignedOut = { [weak store] in store?.signedOut() }
                    purchases.onPlanChange = { [weak store] plan in store?.applyPurchasedPlan(plan) }
                    // Drop a stale/deleted persisted login before the UI trusts it.
                    await social.validateSession()
                    await purchases.loadProducts()
                    await purchases.refreshEntitlements()
                    // Server is authoritative — run last so it corrects any StoreKit-derived
                    // plan on a silently restored session (StoreKit may not know about a sub
                    // this device never bought).
                    if let token = social.session?.accessToken {
                        store.aiToken = token
                        store.currentUserID = social.session?.userID
                        await store.refreshServerEntitlement(token: token)
                        // A silently restored session (returning user, maybe a new device):
                        // pull their account state and merge it onto whatever is local.
                        await store.pullAndMergeServerState()
                    }

                    #if DEBUG
                    // Test-only launch hooks (via `simctl launch … -gsSignIn a:b -gsSeed -gsEnterApp`).
                    // None of these compile into release builds.
                    let args = ProcessInfo.processInfo.arguments
                    if args.contains("-gsSeed") { store.debugSeedSampleRecipes() }
                    if args.contains("-gsEnterApp") { store.debugEnterApp() }
                    if let i = args.firstIndex(of: "-gsSignIn"), i + 1 < args.count {
                        let creds = args[i + 1].split(separator: ":", maxSplits: 1).map(String.init)
                        if creds.count == 2 { await social.signIn(email: creds[0], password: creds[1]) }
                    }
                    #endif
                }
        }
    }
}
