import SwiftUI
import Combine
import UIKit

@MainActor
final class AppStore: ObservableObject {
    enum Phase { case splash, onboard, preferences, createAccount, preparing, app }
    enum Screen { case home, importer, scanIdentify, scanResults, library, detail, cook, shopping, basket, plan, profile, feed, discover, paywall, auth }

    /// Which way the next screen change should animate.
    enum NavDirection { case forward, backward, lateral }

    /// Tab-root screens sit at depth 0; anything deeper pushes and can be popped or swiped back.
    static func depth(of screen: Screen) -> Int {
        switch screen {
        // Meal plan is a tab root now, so it sits at depth 0 with the other tabs.
        case .home, .importer, .library, .shopping, .plan: return 0
        case .scanIdentify, .scanResults, .detail, .profile, .feed, .discover, .basket: return 1
        case .cook, .paywall, .auth: return 2
        }
    }

    // Launch flow
    @Published var phase: Phase = .splash
    @Published var obIndex = 0
    @Published var preferenceIndex = 0
    /// Which way the question flow is travelling, so the slide matches the direction.
    @Published var preferenceForward = true

    // Navigation + UI state
    @Published var screen: Screen = .home
    @Published var navDirection: NavDirection = .lateral
    /// Screen a pushed recipe detail returns to, so back lands where the tap came from.
    @Published private(set) var detailReturn: Screen = .library
    @Published var selId: String?

    // MARK: Discover (server recipe catalog)
    @Published var catalog: [Recipe] = []
    @Published var catalogCuisines: [String] = []
    @Published var catalogCuisine: String? = nil
    @Published var catalogSearch = ""
    @Published var catalogLoading = false
    /// Ids already saved to the library, so Discover can show a "Saved ✓" state.
    var isInLibrary: (String) -> Bool { { [weak self] id in self?.recipes.contains { $0.id == id } ?? false } }
    @Published var search = ""
    @Published var chip = "All"
    @Published var importText = ""
    @Published var importing = false
    @Published var preview: Recipe?
    @Published var scanMatches: [FoodScanMatch] = []
    @Published var scanDishName = ""
    @Published var scanWeight = 0
    @Published var identifyingFood = false
    /// The frame the user actually snapped — shown while scanning and on the results header.
    @Published var scanImage: UIImage?
    /// What the plate is made of, published as the scan resolves.
    @Published var scanIngredients: [IngredientConfidence] = []
    /// Rolling status line under the scanner ("Reading the plate…" → detected names).
    @Published var scanStatus = ""
    /// Non-nil while Claude writes a full recipe for a tapped match; drives the fetch loader.
    @Published var fetchingDish: String?
    /// A detected food the user tapped, shown in the ingredient sheet.
    @Published var foodDetail: IngredientConfidence?
    /// Plan + remaining AI actions.
    @Published var entitlement = Entitlement()
    /// Why the paywall is on screen, and where to return when it's dismissed.
    @Published var paywallReason: PaywallReason = .upgrade
    @Published private(set) var paywallReturn: Screen = .importer
    /// Mirrored from SocialStore by RootView — AppStore owns no networking of its own.
    @Published var isAuthenticated = false
    /// Access token for the signed-in InsForge user, mirrored from `SocialStore` by `RootView`.
    /// Its presence is what lets AI calls use the metered server proxy.
    @Published var aiToken: String?

    /// True when AI work can run server-side, where the key lives and the quota is enforced.
    var usesServerAI: Bool { aiToken != nil }
    /// Why the sign-up wall appeared, so the screen can say what it unlocks.
    @Published var authReason: AuthReason = .general
    @Published private(set) var authReturn: Screen = .home
    @Published var cookStep = 0
    @Published var pickDay: String?
    @Published var newItem = ""
    /// Which recipe's shopping basket is open. "__manual__" is the hand-added bucket.
    @Published var basketID: String?
    @Published var toast = ""

    // Persisted data
    @Published var recipes: [Recipe]
    @Published var shopping: [ShoppingItem]
    @Published var plan: [String: String]
    @Published var userName: String
    @Published var preferences: UserPreferences
    /// Developer-only provider key, for exercising AI without an account. Debug builds
    /// keep it in UserDefaults; release builds have no such path at all, so the shipped
    /// binary can only reach the metered proxy and there is no plaintext key on device.
    #if DEBUG
    @Published var apiKey: String = UserDefaults.standard.string(forKey: "gs_api_key") ?? "" {
        didSet { UserDefaults.standard.set(apiKey, forKey: "gs_api_key") }
    }
    #else
    let apiKey: String = ""
    #endif

    /// Only ever true in a debug build with a key entered by hand. In release this is
    /// constant false, so `analyze()` and friends fall through to the proxy or the mock.
    var liveAI: Bool {
        #if DEBUG
        !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
        #else
        false
        #endif
    }

    /// Which backend the key routes to. Internal only — the provider and model are never
    /// shown to users, so there is deliberately no label exposed here.
    var aiProvider: RecipeExtractor.Provider { RecipeExtractor.Provider.forKey(apiKey) }

    // MARK: - Entitlement

    var quotaRemaining: Int { entitlement.remaining }
    var quotaLabel: String { entitlement.usageLabel }
    /// Scanning a dish is Pro-only; links, video and text are on every plan.
    /// An active Pro trial counts.
    var canUseCamera: Bool { entitlement.effectivePlan.allowsCamera }

    /// Checks the quota and spends one action. Returns false and opens the paywall when empty.
    /// Every AI entry point goes through here — there is no bypass.
    @discardableResult
    func useAIAction() -> Bool {
        // An account comes first: the quota belongs to a person, not a handset.
        guard isAuthenticated else {
            showAuth(.aiFeature)
            return false
        }
        entitlement.rollOverIfNeeded()
        guard entitlement.hasActionsLeft else {
            showPaywall(.outOfActions)
            return false
        }
        // When the proxy runs the call, Postgres is the one that spends the action and
        // returns the new balance — decrementing here too would double-count.
        if !usesServerAI {
            entitlement.consume()
            persistEntitlement()
        }
        return true
    }

    /// Adopts the balance the server reported after a metered call.
    func applyServerQuota(remaining: Int, plan: String) {
        if let serverPlan = Entitlement.Plan(rawValue: plan), serverPlan != entitlement.plan {
            entitlement.plan = serverPlan
        }
        entitlement.syncRemaining(remaining)
        persistEntitlement()
    }

    /// Maps a failed AI call to the right destination: paywall when the server refused on
    /// entitlement, a toast when it was a genuine failure.
    func handleAIError(_ error: Error) {
        if let proxyError = error as? RecipeExtractor.ProxyError {
            switch proxyError {
            case .notEntitled(let reason, let remaining, let plan):
                applyServerQuota(remaining: remaining, plan: plan)
                Haptics.notify(.error)
                showPaywall(reason == "camera_is_pro" ? .cameraIsPro : .outOfActions)
                return
            case .notSignedIn:
                showAuth(.aiFeature)
                return
            case .failed:
                break
            }
        }
        reportAIFailure(error)
    }

    /// Sends the user to create an account (or sign in) before a gated feature.
    func showAuth(_ reason: AuthReason = .general) {
        guard screen != .auth else { return }
        Haptics.tap(.medium)
        authReason = reason
        go(to: .auth)
    }

    /// Called when a session appears, so the user lands back where they were headed.
    func authenticationSucceeded() {
        NSLog("[gs-auth] authenticationSucceeded phase=%@ screen=%@", "\(phase)", "\(screen)")
        isAuthenticated = true
        if phase == .createAccount {
            enterApp()
        } else if screen == .auth {
            goBack()
        }
    }

    func showPaywall(_ reason: PaywallReason = .upgrade) {
        Haptics.tap(.medium)
        paywallReason = reason
        go(to: .paywall)
    }

    /// Applies a purchased plan. Real receipts arrive via StoreKit; this is the state change
    /// both the sandbox flow and a restored purchase land on.
    /// Applies a plan that Apple (and, when signed in, our server) has confirmed.
    /// This is the only path that may raise the plan — nothing in the UI sets it directly.
    func applyPurchasedPlan(_ plan: Entitlement.Plan) {
        guard plan != entitlement.plan else { return }
        let upgrade = plan != .free
        entitlement.plan = plan
        entitlement.period = Entitlement.currentPeriod
        if upgrade {
            // A new subscription starts with a clean allowance; a lapse keeps the count,
            // so cancelling mid-month doesn't hand out a fresh free tier.
            entitlement.used = 0
            entitlement.trialUntil = nil
        }
        persistEntitlement()
        if upgrade {
            Haptics.notify(.success)
            showToast("\(plan.title) is active — \(plan.allowance) AI actions")
        }
    }

    func activate(_ plan: Entitlement.Plan) {
        Haptics.notify(.success)
        let tookWelcome = entitlement.welcomeOfferActive
        entitlement.plan = plan
        entitlement.period = Entitlement.currentPeriod
        entitlement.used = 0
        entitlement.trialUntil = nil
        if tookWelcome { entitlement.introUsed = true }
        persistEntitlement()
        goBack()
        showToast(tookWelcome
                  ? "\(plan.title) active at \(Promo.introPrice(for: plan) ?? "") for your first month"
                  : "\(plan.title) is active — \(plan.allowance) AI actions")
    }

    // MARK: - Promotions

    /// Starts the capped Pro trial. One per install.
    func startProTrial() {
        guard entitlement.canStartTrial else { return }
        Haptics.notify(.success)
        entitlement.trialUntil = Calendar.current.date(byAdding: .day, value: Promo.trialDays, to: Date())
        entitlement.used = 0
        persistEntitlement()
        goBack()
        showToast("Pro unlocked for \(Promo.trialDays) days · \(Promo.trialActions) actions")
    }

    /// Redeems a promo code for bonus actions. Returns a message for the sheet to show.
    func redeem(code raw: String) -> (ok: Bool, message: String) {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else { return (false, "Enter a code first") }
        guard !entitlement.redeemed.contains(code) else {
            return (false, "You've already used that code")
        }
        guard let bonus = Promo.bonus(forCode: code) else {
            Haptics.notify(.error)
            return (false, "That code isn't valid")
        }
        Haptics.notify(.success)
        entitlement.redeemed.append(code)
        entitlement.topUp += bonus
        persistEntitlement()
        return (true, "\(bonus) AI actions added")
    }

    func addTopUp(_ count: Int = 50) {
        Haptics.notify(.success)
        entitlement.topUp += count
        persistEntitlement()
        goBack()
        showToast("\(count) extra AI actions added")
    }

    private func persistEntitlement() {
        if let data = try? JSONEncoder().encode(entitlement) {
            UserDefaults.standard.set(data, forKey: Self.entitlementKey)
        }
    }

    private var splashTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?

    static let days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    static let weekDates = [17, 18, 19, 20, 21, 22, 23]

    private struct Persisted: Codable {
        var recipes: [Recipe]
        var shopping: [ShoppingItem]
        var plan: [String: String]
        var name: String?
        var preferences: UserPreferences?
    }
    private static let storeKey = "gs_state_v4"
    fileprivate static let entitlementKey = "gs_entitlement_v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storeKey),
           let saved = try? JSONDecoder().decode(Persisted.self, from: data) {
            recipes = saved.recipes
            shopping = saved.shopping
            plan = saved.plan
            userName = saved.name ?? "Anny"
            preferences = saved.preferences ?? UserPreferences()
        } else {
            // A new install starts genuinely empty — no sample recipes.
            recipes = []
            shopping = []
            plan = [:]
            userName = ""
            preferences = UserPreferences()
        }

        if let data = UserDefaults.standard.data(forKey: Self.entitlementKey),
           let saved = try? JSONDecoder().decode(Entitlement.self, from: data) {
            entitlement = saved
        }
        entitlement.rollOverIfNeeded()
    }

    func persist() {
        let saved = Persisted(recipes: recipes, shopping: shopping, plan: plan, name: userName, preferences: preferences)
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: Self.storeKey)
        }
    }

    // MARK: - Launch flow

    func startSplashTimer() {
        splashTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            guard let self, !Task.isCancelled, self.phase == .splash else { return }
            withAnimation(.easeOut(duration: 0.4)) { self.phase = .onboard }
        }
    }

    func endSplash() {
        splashTask?.cancel()
        withAnimation(.easeOut(duration: 0.4)) { phase = .onboard }
    }

    func onboardNext() {
        if obIndex >= 2 {
            withAnimation(.easeOut(duration: 0.4)) {
                phase = preferences.isComplete ? .app : .preferences
            }
        } else {
            withAnimation(.easeOut(duration: 0.35)) { obIndex += 1 }
        }
    }

    /// Setup asks for an account once the taste profile is answered, so the profile has
    /// somewhere to live. Skipping is still allowed — the wall reappears at the first
    /// gated feature.
    func askForAccount() {
        guard phase != .createAccount else { return }
        if isAuthenticated {
            enterApp()
            return
        }
        authReason = .general
        withAnimation(.easeOut(duration: 0.35)) { phase = .createAccount }
    }

    /// True while the sign-up step of first-run setup is on screen.
    var isSettingUpAccount: Bool { phase == .createAccount }

    /// The single way into the app from setup — always via the preparing screen, so Home is
    /// never revealed half-built.
    func enterApp() {
        guard phase != .preparing, phase != .app else { return }
        withAnimation(.easeOut(duration: 0.35)) { phase = .preparing }
    }

    func finishPreparing() {
        Haptics.notify(.success)
        withAnimation(.easeOut(duration: 0.45)) { phase = .app }
    }

    func skipOnboard() {
        withAnimation(.easeOut(duration: 0.4)) {
            phase = preferences.isComplete ? .app : .preferences
        }
    }

    func answerPreference(sound: Bool = true, _ apply: (inout UserPreferences) -> Void) {
        if sound {
            PreferenceSound.tick()
            Haptics.tap(.light)
        }
        apply(&preferences)
        persist()
    }

    func preferenceNext(maxIndex: Int) {
        if preferenceIndex >= maxIndex {
            PreferenceSound.success()
            Haptics.notify(.success)
            persist()
            askForAccount()
        } else {
            preferenceForward = true
            withAnimation(Self.questionAnimation) { preferenceIndex += 1 }
        }
    }

    func preferenceBack() {
        guard preferenceIndex > 0 else { return }
        preferenceForward = false
        withAnimation(Self.questionAnimation) { preferenceIndex -= 1 }
    }

    // MARK: - Navigation

    static let pushAnimation = Animation.spring(response: 0.42, dampingFraction: 0.86)
    /// Screen-to-screen changes. An ease reads cleaner than a spring for a crossfade —
    /// a spring overshoots the scale and makes the fade look like a wobble.
    static let navAnimation = Animation.easeInOut(duration: 0.26)
    static let lateralAnimation = Animation.easeOut(duration: 0.24)
    static let sheetAnimation = Animation.spring(response: 0.38, dampingFraction: 0.9)
    static let stepAnimation = Animation.spring(response: 0.34, dampingFraction: 0.88)
    /// Question-to-question travel in the taste-profile flow.
    static let questionAnimation = Animation.spring(response: 0.72, dampingFraction: 0.88)

    var canGoBack: Bool { Self.depth(of: screen) > 0 }

    /// The tab root the current screen belongs to, so a pushed screen keeps its origin tab lit.
    var activeTabRoot: Screen {
        switch screen {
        case .detail: return detailReturn
        case .cook: return detailReturn
        case .scanIdentify, .scanResults: return .importer
        case .profile, .feed: return .home
        case .basket: return .shopping
        case .discover: return .library
        case .paywall: return Self.depth(of: paywallReturn) == 0 ? paywallReturn : .importer
        case .auth: return Self.depth(of: authReturn) == 0 ? authReturn : .home
        default: return screen
        }
    }

    /// Where the back gesture / back button lands from the current screen.
    var backTarget: Screen? {
        switch screen {
        case .detail: return detailReturn
        case .cook: return .detail
        case .scanResults: return .scanIdentify
        case .scanIdentify: return .importer
        case .basket: return .shopping
        case .profile, .feed: return .home
        case .paywall: return paywallReturn
        case .auth: return authReturn
        default: return nil
        }
    }

    func go(to target: Screen) {
        guard target != screen else { return }
        // Remember where the paywall was raised from so dismissing lands back there.
        if target == .paywall { paywallReturn = screen }
        if target == .auth { authReturn = screen }
        let from = Self.depth(of: screen)
        let to = Self.depth(of: target)
        navDirection = to > from ? .forward : (to < from ? .backward : .lateral)
        Haptics.tap(navDirection == .lateral ? .light : .medium)
        withAnimation(Self.navAnimation) {
            screen = target
        }
    }

    func goBack() {
        guard let target = backTarget else { return }
        go(to: target)
    }

    // MARK: - Toast

    /// Shows a safe message to the user and keeps the real cause in the console only.
    func reportAIFailure(_ error: Error) {
        if let e = error as? RecipeExtractor.ExtractionError {
            print("[goodiesSnap] AI failure — \(e.debugDetail)")
            showToast(e.errorDescription ?? "Something went wrong. Please try again.", seconds: 3.0)
        } else {
            print("[goodiesSnap] AI failure — \(error)")
            showToast("Something went wrong. Please try again.", seconds: 3.0)
        }
    }

    func showToast(_ msg: String, seconds: Double = 1.8) {
        toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.25)) { toast = msg }
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { self.toast = "" }
        }
    }

    // MARK: - Selection / derived

    var selected: Recipe? { recipes.first { $0.id == selId } ?? recipes.first }

    var showTabs: Bool {
        phase == .app && screen != .cook && screen != .scanIdentify && screen != .paywall && screen != .auth
    }

    var undoneCount: Int { shopping.filter { !$0.done }.count }

    var favorites: [Recipe] { recipes.filter(\.favorite) }

    var heroRecipes: [Recipe] {
        let base = favorites.count >= 2 ? favorites : recipes
        guard preferences.isComplete else { return Array(base.prefix(4)) }
        return Array(base
            .filter { !preferences.matchesAvoidance($0) }
            .sorted { a, b in
                let left = preferences.score(a)
                let right = preferences.score(b)
                return left == right ? a.totalMinutes < b.totalMinutes : left > right
            }
            .prefix(4))
    }

    var initial: String {
        String(userName.trimmingCharacters(in: .whitespaces).first.map(String.init) ?? "A").uppercased()
    }

    var plannedCount: Int { Self.days.compactMap { plan[$0] }.count }

    // MARK: - Dashboard (today)

    /// Weekday name matching the meal-plan keys ("Monday" …).
    var todayName: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEEE"
        return f.string(from: Date())
    }

    var todayLabel: String {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f.string(from: Date())
    }

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "morning" : (hour < 18 ? "afternoon" : "evening")
        guard preferences.isComplete else {
            // A brand-new account has no name yet, so don't leave a dangling comma.
            let name = userName.trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? "Good \(part)" : "Good \(part), \(name)"
        }
        return "Good \(part) · \(preferences.summary)"
    }

    /// Tonight's planned dinner, if any.
    var tonightsDinner: Recipe? {
        plan[todayName].flatMap { id in recipes.first { $0.id == id } }
    }

    /// The upcoming planned dinners after today, in week order.
    var upcomingDinners: [(day: String, recipe: Recipe)] {
        guard let todayIndex = Self.days.firstIndex(of: todayName) else { return [] }
        return Self.days.enumerated().compactMap { i, day in
            guard i > todayIndex, let id = plan[day], let r = recipes.first(where: { $0.id == id }) else { return nil }
            return (day, r)
        }
    }

    /// Shopping progress for the dashboard ring.
    var shoppingDone: Int { shopping.filter(\.done).count }

    /// Recipes saved this week (rough: the newest three).
    var recentlySaved: [Recipe] { Array(recipes.prefix(3)) }

    /// Cuisine with the most saved recipes, for the profile's "you cook the most" stat.
    var topCuisine: String? {
        var counts: [String: Int] = [:]
        for r in recipes { counts[r.cuisine, default: 0] += 1 }
        return counts.max { a, b in a.value == b.value ? a.key > b.key : a.value < b.value }?.key
    }

    var avgCookTime: Int {
        guard !recipes.isEmpty else { return 0 }
        return recipes.map(\.totalMinutes).reduce(0, +) / recipes.count
    }

    /// Clears everything the user has saved. There is no sample content to fall back to.
    func resetLibrary() {
        recipes = []
        shopping = []
        plan = [:]
        selId = nil
        chip = "All"
        search = ""
        persist()
        showToast("Everything cleared")
    }

    func clearShoppingAll() {
        shopping = []
        persist()
        showToast("Shopping list cleared")
    }

    var chipNames: [String] {
        var cuisines: [String] = []
        for r in recipes where !cuisines.contains(r.cuisine) { cuisines.append(r.cuisine) }
        return ["All", "Favorites"] + cuisines
    }

    var filtered: [Recipe] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var out = recipes.filter { r in
            q.isEmpty
                || r.title.lowercased().contains(q)
                || r.cuisine.lowercased().contains(q)
                || r.ingredients.contains { $0.name.lowercased().contains(q) }
        }
        if chip == "Favorites" { out = out.filter(\.favorite) }
        else if chip != "All" { out = out.filter { $0.cuisine == chip } }
        return out
    }

    var shopGroups: [(name: String, items: [ShoppingItem])] {
        Aisle.order
            .map { name in (name, shopping.filter { ($0.category.isEmpty ? "Other" : $0.category) == name }) }
            .filter { !$0.1.isEmpty }
    }

    enum ShopGroupMode: String { case recipe, aisle }
    @Published var shopGroupMode: ShopGroupMode = .recipe

    // MARK: Store pricing (Kroger)
    /// The chosen store, persisted so the user picks it once. nil = no store set.
    @Published var krogerLocationId: String? = UserDefaults.standard.string(forKey: "gs_kroger_loc") {
        didSet { UserDefaults.standard.set(krogerLocationId, forKey: "gs_kroger_loc") }
    }
    @Published var krogerStoreName: String? = UserDefaults.standard.string(forKey: "gs_kroger_name") {
        didSet { UserDefaults.standard.set(krogerStoreName, forKey: "gs_kroger_name") }
    }
    @Published var storePickerOpen = false
    @Published var storeCandidates: [PriceService.Store] = []
    @Published var storeZip = ""
    @Published var pricesLoading = false

    /// Formats integer cents as a local currency string.
    func formatPrice(_ cents: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = .current
        return f.string(from: NSNumber(value: Double(cents) / 100)) ?? "$\(cents / 100).\(cents % 100)"
    }

    func openStorePicker() {
        storeCandidates = []
        storeZip = ""
        storePickerOpen = true
    }

    func findStores() {
        guard let token = aiToken else { showAuth(.aiFeature); return }
        let zip = storeZip.trimmingCharacters(in: .whitespaces)
        guard zip.count == 5 else { return }
        Task { @MainActor in
            do { storeCandidates = try await PriceService.stores(zip: zip, token: token) }
            catch { handlePriceError(error) }
        }
    }

    func chooseStore(_ store: PriceService.Store) {
        krogerLocationId = store.location_id
        krogerStoreName = store.name
        storePickerOpen = false
        refreshPrices()
    }

    /// Looks up a price for every item on the list at the chosen store and caches it on the
    /// items. Requires a store and a signed-in user; otherwise it routes to the right prompt.
    func refreshPrices() {
        guard let token = aiToken else { showAuth(.aiFeature); return }
        guard let loc = krogerLocationId else { openStorePicker(); return }
        guard !shopping.isEmpty, !pricesLoading else { return }
        pricesLoading = true
        let names = Array(Set(shopping.map(\.name)))
        Task { @MainActor in
            defer { pricesLoading = false }
            do {
                let priced = try await PriceService.prices(items: names, locationID: loc, token: token)
                for i in shopping.indices {
                    if let match = priced[shopping[i].name] {
                        shopping[i].priceCents = match.cents
                        shopping[i].priceImage = match.image
                        shopping[i].priceStore = krogerStoreName
                    }
                }
                persist()
                let matched = shopping.filter { $0.priceCents != nil }.count
                showToast(matched == 0 ? "No prices found at this store" : "Prices updated for \(matched) items")
            } catch {
                handlePriceError(error)
            }
        }
    }

    private func handlePriceError(_ error: Error) {
        if let e = error as? PriceService.PriceError {
            switch e {
            case .notSignedIn: showAuth(.aiFeature)
            case .notConfigured: showToast("Store prices aren't available yet")
            case .failed(let m): showToast(m)
            }
        } else {
            showToast("Couldn't load prices")
        }
    }

    /// Shopping items grouped by their source recipe, in the order recipes were added, with
    /// hand-added items last under "Added by you".
    /// Opens one recipe's basket.
    func openBasket(_ id: String) {
        basketID = id
        go(to: .basket)
    }

    /// The basket currently on screen.
    var openBasketGroup: (id: String, title: String, items: [ShoppingItem])? {
        guard let basketID else { return nil }
        return shopByRecipe.first { $0.id == basketID }
    }

    /// Aisle-ordered sections within one basket — walking the shop in order still helps
    /// even when the list is grouped by recipe.
    func aisleSections(of items: [ShoppingItem]) -> [(name: String, items: [ShoppingItem])] {
        Aisle.order
            .map { name in (name, items.filter { ($0.category.isEmpty ? "Other" : $0.category) == name }) }
            .filter { !$0.1.isEmpty }
    }

    /// Removes a whole basket from the list.
    func removeBasket(_ id: String) {
        Haptics.tap(.medium)
        withAnimation(Self.pushAnimation) {
            shopping.removeAll { ($0.recipeID ?? "__manual__") == id }
        }
        persist()
        if basketID == id { goBack() }
    }

    var shopByRecipe: [(id: String, title: String, items: [ShoppingItem])] {
        var order: [String] = []
        var buckets: [String: [ShoppingItem]] = [:]
        var titles: [String: String] = [:]
        for item in shopping {
            let key = item.recipeID ?? "__manual__"
            if buckets[key] == nil { order.append(key); buckets[key] = [] }
            buckets[key]?.append(item)
            titles[key] = item.recipeTitle ?? "Added by you"
        }
        // Keep "Added by you" at the bottom.
        order.sort { a, b in (a == "__manual__" ? 1 : 0) < (b == "__manual__" ? 1 : 0) }
        return order.map { (id: $0, title: titles[$0] ?? "Added by you", items: buckets[$0] ?? []) }
    }

    /// Total of known prices in a set of items, in cents (items without a price are skipped).
    func priceTotalCents(_ items: [ShoppingItem]) -> Int? {
        let known = items.compactMap(\.priceCents)
        return known.isEmpty ? nil : known.reduce(0, +)
    }

    // MARK: - Discover

    func openDiscover() {
        go(to: .discover)
        if catalog.isEmpty { Task { await loadCatalog(reset: true) } }
        if catalogCuisines.isEmpty {
            Task { catalogCuisines = (try? await CatalogService.cuisines()) ?? [] }
        }
    }

    func setCatalogCuisine(_ cuisine: String?) {
        catalogCuisine = cuisine
        Task { await loadCatalog(reset: true) }
    }

    func searchCatalog() {
        Task { await loadCatalog(reset: true) }
    }

    @MainActor
    func loadCatalog(reset: Bool) async {
        guard !catalogLoading else { return }
        catalogLoading = true
        defer { catalogLoading = false }
        let offset = reset ? 0 : catalog.count
        do {
            let rows = try await CatalogService.fetch(
                cuisine: catalogCuisine, search: catalogSearch, limit: 60, offset: offset)
            let recipes = rows.map(\.recipe)
            if reset { catalog = recipes } else { catalog.append(contentsOf: recipes) }
        } catch {
            if reset { catalog = [] }
            showToast("Couldn't load Discover. Check your connection.")
        }
    }

    /// Opens a catalog recipe in the normal detail screen. It is added to the library on
    /// first view so cook mode, favouriting and the shopping list all work on it.
    func openCatalogRecipe(_ recipe: Recipe) {
        if !recipes.contains(where: { $0.id == recipe.id }) {
            recipes.insert(recipe, at: 0)
            persist()
        }
        open(recipe)
    }

    // MARK: - Recipes

    func open(_ recipe: Recipe) {
        if Self.depth(of: screen) == 0 { detailReturn = screen }
        selId = recipe.id
        cookStep = 0
        go(to: .detail)
    }

    func toggleFav(_ id: String) {
        if let i = recipes.firstIndex(where: { $0.id == id }) {
            Haptics.tap(.light)
            withAnimation(Self.stepAnimation) { recipes[i].favorite.toggle() }
            persist()
        }
    }

    func deleteSelected() {
        guard let sel = selected else { return }
        for (day, id) in plan where id == sel.id { plan[day] = nil }
        recipes.removeAll { $0.id == sel.id }
        selId = nil
        go(to: .library)
        persist()
    }

    // MARK: - Shopping

    /// Adds a recipe's ingredients, skipping any already on the list (unchecked). Returns the count added.
    @discardableResult
    func addIngredients(of recipe: Recipe) -> Int {
        var added = 0
        withAnimation(Self.pushAnimation) {
            for i in recipe.ingredients where !shopping.contains(where: { $0.name.lowercased() == i.name.lowercased() && !$0.done }) {
                shopping.append(ShoppingItem(id: "s" + String(UUID().uuidString.prefix(6)), name: i.name, qty: i.qty, category: i.category, done: false, recipeID: recipe.id, recipeTitle: recipe.title))
                added += 1
            }
        }
        persist()
        return added
    }

    func allOnList(_ recipe: Recipe) -> Bool {
        !recipe.ingredients.isEmpty && recipe.ingredients.allSatisfy { i in
            shopping.contains { $0.name.lowercased() == i.name.lowercased() && !$0.done }
        }
    }

    func toggleItem(_ id: String) {
        if let i = shopping.firstIndex(where: { $0.id == id }) {
            Haptics.tap(.light)
            withAnimation(Self.stepAnimation) { shopping[i].done.toggle() }
            persist()
        }
    }

    func clearDone() {
        Haptics.tap(.medium)
        withAnimation(Self.pushAnimation) { shopping.removeAll { $0.done } }
        persist()
    }

    func addItem() {
        let n = newItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        Haptics.tap(.light)
        withAnimation(Self.pushAnimation) {
            shopping.append(ShoppingItem(id: "s" + String(UUID().uuidString.prefix(6)), name: n, qty: "", category: "Other", done: false))
        }
        newItem = ""
        persist()
    }

    // MARK: - Meal plan

    func assign(_ recipe: Recipe, to day: String) {
        Haptics.tap(.light)
        withAnimation(Self.pushAnimation) {
            plan[day] = recipe.id
            pickDay = nil
        }
        persist()
    }

    func openPicker(day: String) {
        Haptics.tap(.light)
        withAnimation(Self.sheetAnimation) { pickDay = day }
    }

    func closePicker() {
        withAnimation(Self.sheetAnimation) { pickDay = nil }
    }

    func removePlan(day: String) {
        Haptics.tap(.light)
        withAnimation(Self.pushAnimation) { plan[day] = nil }
        persist()
    }

    func planToShopping() {
        let ids = Self.days.compactMap { plan[$0] }
        guard !ids.isEmpty else {
            showToast("Plan some dinners first")
            return
        }
        var count = 0
        for id in ids {
            if let r = recipes.first(where: { $0.id == id }) {
                count += addIngredients(of: r)
            }
        }
        showToast("\(count) items added from your plan")
    }

    // MARK: - Import

    func detect(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.range(of: #"youtu\.?be"#, options: [.regularExpression, .caseInsensitive]) != nil { return "YouTube video" }
        if t.range(of: #"^https?://"#, options: [.regularExpression, .caseInsensitive]) != nil { return "Website" }
        return "Pasted text"
    }

    func analyze() {
        let t = importText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        guard useAIAction() else { return }
        let source = detect(t)
        if let token = aiToken {
            runLiveExtraction { [weak self] in
                let result = try await RecipeExtractor.proxyExtract(from: t, token: token, sourceLabel: source)
                self?.applyServerQuota(remaining: result.remaining, plan: result.plan)
                return result.value
            }
            return
        }
        // Developer fallback only: a locally-entered key, used for testing without an account.
        guard liveAI else {
            runMockExtraction(source: source)
            return
        }
        let key = apiKey
        runLiveExtraction {
            try await RecipeExtractor.extract(from: t, apiKey: key, sourceLabel: source)
        }
    }

    /// Entry point from the shutter (or the photo picker): freeze the frame, then identify it.
    func scan(image: UIImage?) {
        guard let image else { return }
        guard canUseCamera else {
            showPaywall(.cameraIsPro)
            return
        }
        guard useAIAction() else { return }
        scanImage = image
        if let token = aiToken {
            runLiveFoodScan(image: image, token: token)
            return
        }
        guard liveAI else {
            runMockFoodScan()
            return
        }
        runLiveFoodScan(image: image, apiKey: apiKey)
    }

    func scanMock() {
        guard useAIAction() else { return }
        runMockFoodScan()
    }

    /// Entry to the camera scanner. Needs an account first, then Pro.
    func startPhotoScan() {
        guard isAuthenticated else {
            showAuth(.scan)
            return
        }
        guard canUseCamera else {
            showPaywall(.cameraIsPro)
            return
        }
        scanDishName = ""
        scanWeight = 0
        scanMatches = []
        scanIngredients = []
        scanImage = nil
        scanStatus = ""
        identifyingFood = false
        go(to: .scanIdentify)
    }

    /// Demo path (no API key): same staged reveal as the live scan so the flow is walkable.
    private func runMockFoodScan() {
        beginIdentifying()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard let self, self.identifyingFood else { return }
            let analysis = FoodScanAnalysis(
                dishName: "Salmon Poke Bowl",
                weightGrams: 350,
                ingredients: Self.salmonBowlIngredients,
                suggestions: [
                    FoodScanSuggestion(name: "Salmon Poke Bowl", confidence: 92,
                                       blurb: "Cubed raw salmon over seasoned rice with crisp veg."),
                    FoodScanSuggestion(name: "Teriyaki Salmon Rice Bowl", confidence: 74,
                                       blurb: "Same build, glazed and seared instead of raw."),
                    FoodScanSuggestion(name: "Salmon Sushi Salad", confidence: 58,
                                       blurb: "Deconstructed sushi with a rice-vinegar dressing."),
                ]
            )
            self.finishIdentifying(with: analysis)
        }
    }

    /// Metered scan: the server holds the key, spends the action, and returns the balance.
    private func runLiveFoodScan(image: UIImage, token: String) {
        beginIdentifying()
        Task { [weak self] in
            do {
                let result = try await RecipeExtractor.proxyAnalyzeFoodPhoto(image, token: token)
                guard let self, self.identifyingFood else { return }
                self.applyServerQuota(remaining: result.remaining, plan: result.plan)
                self.finishIdentifying(with: result.value)
            } catch {
                guard let self else { return }
                withAnimation(Self.lateralAnimation) {
                    self.identifyingFood = false
                    self.scanStatus = ""
                }
                self.handleAIError(error)
            }
        }
    }

    private func runLiveFoodScan(image: UIImage, apiKey: String) {
        beginIdentifying()
        Task { [weak self] in
            do {
                let analysis = try await RecipeExtractor.analyzeFoodPhoto(image, apiKey: apiKey)
                guard let self, self.identifyingFood else { return }
                self.finishIdentifying(with: analysis)
            } catch {
                guard let self else { return }
                Haptics.notify(.error)
                withAnimation(Self.lateralAnimation) {
                    self.identifyingFood = false
                    self.scanStatus = ""
                }
                self.reportAIFailure(error)
            }
        }
    }

    /// Starts the scanning animation and cycles the status line while the model works.
    private func beginIdentifying() {
        Haptics.tap(.medium)
        withAnimation(Self.lateralAnimation) {
            identifyingFood = true
            scanIngredients = []
            scanMatches = []
            scanStatus = "Reading the plate…"
        }
        Task { [weak self] in
            let lines = ["Reading the plate…", "Finding ingredients…", "Estimating portions…", "Matching recipes…"]
            var i = 1
            while true {
                try? await Task.sleep(for: .seconds(1.1))
                guard let self, self.identifyingFood else { return }
                // Short crossfade: a spring here leaves both strings visible at once.
                withAnimation(.easeInOut(duration: 0.22)) { self.scanStatus = lines[i % lines.count] }
                i += 1
            }
        }
    }

    /// Publishes the analysis and pushes to the results screen.
    private func finishIdentifying(with analysis: FoodScanAnalysis) {
        Haptics.notify(.success)
        scanDishName = analysis.dishName
        scanWeight = analysis.weightGrams
        scanIngredients = analysis.ingredients
        scanMatches = matches(for: analysis)
        withAnimation(Self.pushAnimation) {
            identifyingFood = false
            scanStatus = ""
            go(to: .scanResults)
        }
    }

    func recipe(for match: FoodScanMatch) -> Recipe? {
        guard let id = match.recipeID else { return nil }
        return recipes.first { $0.id == id }
    }

    /// Tapping a match: library recipes open straight away; AI suggestions are generated
    /// first, which can take a while — hence `fetchingDish` and its loader.
    func openScanMatch(_ match: FoodScanMatch) {
        if let recipe = recipe(for: match) {
            detailReturn = .scanResults
            selId = recipe.id
            cookStep = 0
            go(to: .detail)
            return
        }

        guard fetchingDish == nil else { return }
        // Writing a recipe is a second billable action on top of the scan.
        guard useAIAction() else { return }
        Haptics.tap(.medium)

        let detected = scanIngredients
        if let token = aiToken {
            withAnimation(Self.lateralAnimation) { fetchingDish = match.dishName }
            Task { [weak self] in
                do {
                    let result = try await RecipeExtractor.proxyGenerateRecipe(
                        forDish: match.dishName, detected: detected, token: token)
                    guard let self, self.fetchingDish != nil else { return }
                    self.applyServerQuota(remaining: result.remaining, plan: result.plan)
                    self.presentFetched(result.value, for: match)
                } catch {
                    guard let self else { return }
                    withAnimation(Self.lateralAnimation) { self.fetchingDish = nil }
                    self.handleAIError(error)
                }
            }
            return
        }
        guard liveAI else {
            fetchMockRecipe(for: match)
            return
        }
        let key = apiKey
        withAnimation(Self.lateralAnimation) { fetchingDish = match.dishName }
        Task { [weak self] in
            do {
                let recipe = try await RecipeExtractor.generateRecipe(forDish: match.dishName, detected: detected, apiKey: key)
                guard let self, self.fetchingDish != nil else { return }
                self.presentFetched(recipe, for: match)
            } catch {
                guard let self else { return }
                Haptics.notify(.error)
                withAnimation(Self.lateralAnimation) { self.fetchingDish = nil }
                self.reportAIFailure(error)
            }
        }
    }

    private func fetchMockRecipe(for match: FoodScanMatch) {
        withAnimation(Self.lateralAnimation) { fetchingDish = match.dishName }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.8))
            guard let self, self.fetchingDish != nil else { return }
            var recipe = Self.mockRecipe(source: "Dish scan")
            recipe.title = match.dishName
            self.presentFetched(recipe, for: match)
        }
    }

    /// Saves a freshly generated recipe into the library and opens it.
    private func presentFetched(_ recipe: Recipe, for match: FoodScanMatch) {
        Haptics.notify(.success)
        recipes.insert(recipe, at: 0)
        persist()
        // Point the match at the now-real recipe so a second tap is instant.
        if let i = scanMatches.firstIndex(where: { $0.id == match.id }) {
            scanMatches[i].recipeID = recipe.id
        }
        detailReturn = .scanResults
        selId = recipe.id
        cookStep = 0
        withAnimation(Self.pushAnimation) {
            fetchingDish = nil
            go(to: .detail)
        }
        showToast("Recipe written and saved")
    }

    func cancelRecipeFetch() {
        withAnimation(Self.lateralAnimation) { fetchingDish = nil }
    }

    // MARK: - Detected foods

    func openFoodDetail(_ item: IngredientConfidence) {
        Haptics.tap(.light)
        withAnimation(Self.sheetAnimation) { foodDetail = item }
    }

    func closeFoodDetail() {
        withAnimation(Self.sheetAnimation) { foodDetail = nil }
    }

    /// True once a scanned food is on the list and still unchecked.
    func onShoppingList(_ item: IngredientConfidence) -> Bool {
        shopping.contains { $0.name.lowercased() == item.name.lowercased() && !$0.done }
    }

    /// Adds one detected food to the shopping list, with a quantity from its estimated weight.
    func addDetectedFood(_ item: IngredientConfidence) {
        guard !onShoppingList(item) else {
            showToast("\(item.name) is already on your list")
            return
        }
        Haptics.notify(.success)
        withAnimation(Self.pushAnimation) {
            shopping.append(
                ShoppingItem(
                    id: "s" + String(UUID().uuidString.prefix(6)),
                    name: item.name,
                    qty: item.shoppingQty,
                    category: Aisle.guess(for: item.name),
                    done: false
                )
            )
        }
        persist()
        showToast("\(item.name) added to your list")
    }

    /// Adds every detected food that isn't already on the list.
    func addAllDetectedFoods() {
        let missing = scanIngredients.filter { !onShoppingList($0) }
        guard !missing.isEmpty else {
            showToast("Everything is already on your list")
            return
        }
        Haptics.notify(.success)
        withAnimation(Self.pushAnimation) {
            for item in missing {
                shopping.append(
                    ShoppingItem(
                        id: "s" + String(UUID().uuidString.prefix(6)),
                        name: item.name,
                        qty: item.shoppingQty,
                        category: Aisle.guess(for: item.name),
                        done: false
                    )
                )
            }
        }
        persist()
        showToast("\(missing.count) items added to your list")
    }

    /// Saved recipes that use a detected food — the "what you need it for" list in the sheet.
    func recipesUsing(_ item: IngredientConfidence) -> [Recipe] {
        let needle = normalized(item.name)
        guard !needle.isEmpty else { return [] }
        return recipes.filter { recipe in
            recipe.ingredients.contains { normalized($0.name).contains(needle) }
        }
    }

    /// What the user needs to buy for a detected food, taken from the recipes that use it
    /// (falls back to the scan's own weight estimate when the library has no match).
    func requirements(for item: IngredientConfidence) -> [(recipe: String, qty: String)] {
        let needle = normalized(item.name)
        return recipesUsing(item).compactMap { recipe in
            guard let match = recipe.ingredients.first(where: { normalized($0.name).contains(needle) }) else { return nil }
            return (recipe.title, match.qty)
        }
    }

    private func matches(for analysis: FoodScanAnalysis) -> [FoodScanMatch] {
        let detected = analysis.ingredients.map { normalized($0.name) }
        let dishWords = normalizedWords(analysis.dishName)
        let scored = recipes.map { recipe -> (Recipe, Int) in
            let ingredientWords = recipe.ingredients.flatMap { normalizedWords($0.name) }
            let titleWords = normalizedWords(recipe.title)
            let ingredientScore = detected.reduce(0) { total, item in
                let words = normalizedWords(item)
                let hit = words.contains { word in ingredientWords.contains(word) || titleWords.contains(word) }
                return total + (hit ? 18 : 0)
            }
            let titleScore = dishWords.reduce(0) { total, word in
                total + (titleWords.contains(word) ? 16 : 0)
            }
            let cuisineScore = dishWords.contains(normalized(recipe.cuisine)) ? 8 : 0
            return (recipe, min(98, ingredientScore + titleScore + cuisineScore))
        }

        // Library hits first — cooking something you already saved beats generating a new card.
        let library = scored
            .filter { $0.1 >= 18 }
            .sorted { a, b in a.1 == b.1 ? a.0.totalMinutes < b.0.totalMinutes : a.1 > b.1 }
            .prefix(3)
            .map { recipe, score in
                FoodScanMatch(
                    recipeID: recipe.id,
                    dishName: recipe.title,
                    confidence: max(35, score),
                    detectedIngredients: analysis.ingredients,
                    blurb: "Already in your library · \(recipe.totalMinutes) min"
                )
            }

        // Then the model's own guesses, which get written on demand.
        let libraryTitles = Set(library.map { normalized($0.dishName) })
        let suggested = analysis.suggestions
            .filter { !libraryTitles.contains(normalized($0.name)) }
            .map { suggestion in
                FoodScanMatch(
                    recipeID: nil,
                    dishName: suggestion.name,
                    confidence: suggestion.confidence,
                    detectedIngredients: analysis.ingredients,
                    blurb: suggestion.blurb
                )
            }

        let all = (library + suggested).sorted { $0.confidence > $1.confidence }
        guard all.isEmpty else { return all }

        // Nothing matched and the model offered nothing: fall back to the dish it named.
        return [
            FoodScanMatch(
                recipeID: nil,
                dishName: analysis.dishName,
                confidence: 70,
                detectedIngredients: analysis.ingredients,
                blurb: "Write this recipe with AI"
            )
        ]
    }

    private func normalized(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: #"[^a-z0-9 ]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedWords(_ value: String) -> [String] {
        normalized(value)
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 2 && !["with", "and", "the", "bowl"].contains($0) }
    }

    private func runLiveExtraction(_ work: @escaping () async throws -> Recipe) {
        withAnimation(Self.lateralAnimation) { importing = true }
        Task { [weak self] in
            do {
                let recipe = try await work()
                guard let self else { return }
                Haptics.notify(.success)
                withAnimation(Self.sheetAnimation) {
                    self.importing = false
                    self.preview = recipe
                }
            } catch {
                guard let self else { return }
                withAnimation(Self.lateralAnimation) { self.importing = false }
                // Routes an out-of-quota / Pro-only refusal to the paywall, anything else to a toast.
                self.handleAIError(error)
            }
        }
    }

    func fillSample() {
        importText = "https://www.youtube.com/watch?v=tacos-al-pastor"
    }

    private func runMockExtraction(source: String) {
        withAnimation(Self.lateralAnimation) { importing = true }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let self else { return }
            Haptics.notify(.success)
            withAnimation(Self.sheetAnimation) {
                self.importing = false
                self.preview = Self.mockRecipe(source: source)
            }
        }
    }

    func saveImport() {
        guard let r = preview else { return }
        recipes.insert(r, at: 0)
        withAnimation(Self.sheetAnimation) { preview = nil }
        importText = ""
        selId = r.id
        cookStep = 0
        detailReturn = .library
        go(to: .detail)
        persist()
        showToast("Saved to your library")
    }

    func discardImport() {
        withAnimation(Self.sheetAnimation) { preview = nil }
    }

    static func mockRecipe(source: String) -> Recipe {
        Recipe(
            id: "r\(Int(Date().timeIntervalSince1970 * 1000))",
            title: "Zesty Chipotle Chicken Tacos",
            cuisine: "Mexican",
            img: "https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=800&q=80",
            source: source, prep: 15, cook: 14, servings: 4, cal: 470,
            macros: Macros(protein: 31, carbs: 44, fat: 18),
            tags: ["Weeknight", "Family"], favorite: false,
            ingredients: [
                Ingredient(name: "Chicken breast", qty: "500 g", category: "Meat"),
                Ingredient(name: "Chipotle in adobo", qty: "2 tbsp", category: "Pantry"),
                Ingredient(name: "Corn tortillas", qty: "8", category: "Pantry"),
                Ingredient(name: "Lime", qty: "2", category: "Produce"),
                Ingredient(name: "Red cabbage", qty: "150 g", category: "Produce"),
                Ingredient(name: "Crema", qty: "100 ml", category: "Dairy"),
            ],
            steps: [
                "Blend chipotle, lime juice, and oil into a marinade.",
                "Coat chicken and rest 10 minutes.",
                "Sear chicken 6–7 minutes per side, then slice.",
                "Warm tortillas in a dry pan.",
                "Assemble with cabbage and a drizzle of crema.",
            ],
            notes: ""
        )
    }

    static let salmonBowlIngredients: [IngredientConfidence] = [
        IngredientConfidence(name: "Rice", percent: 42.9, grams: 150, image: "https://images.unsplash.com/photo-1586201375761-83865001e31c?w=300&q=80"),
        IngredientConfidence(name: "Salmon", percent: 28.6, grams: 100, image: "https://images.unsplash.com/photo-1599084993091-1cb5c0721cc6?w=300&q=80"),
        IngredientConfidence(name: "Cucumber", percent: 14.3, grams: 50, image: "https://images.unsplash.com/photo-1449300079323-02e209d9d3a6?w=300&q=80"),
        IngredientConfidence(name: "Sesame", percent: 5.7, grams: 20, image: "https://images.unsplash.com/photo-1515543904379-3d757afe72e4?w=300&q=80"),
        IngredientConfidence(name: "Spinach", percent: 4.4, grams: 15, image: "https://images.unsplash.com/photo-1576045057995-568f588f82fb?w=300&q=80"),
        IngredientConfidence(name: "Lettuce", percent: 4.2, grams: 15, image: "https://images.unsplash.com/photo-1622206151226-18ca2c9ab4a1?w=300&q=80"),
    ]

    // MARK: - Cook mode

    func nextCookStep() {
        guard let sel = selected else { return }
        if cookStep >= sel.steps.count - 1 {
            Haptics.notify(.success)
            go(to: .detail)
            showToast("Nice cooking!")
        } else {
            Haptics.tap(.light)
            withAnimation(Self.stepAnimation) { cookStep += 1 }
        }
    }

    func prevCookStep() {
        guard cookStep > 0 else { return }
        Haptics.tap(.light)
        withAnimation(Self.stepAnimation) { cookStep = max(0, cookStep - 1) }
    }
}
