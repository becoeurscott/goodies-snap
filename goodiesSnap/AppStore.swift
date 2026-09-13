import SwiftUI
import Combine
import UIKit

@MainActor
final class AppStore: ObservableObject {
    enum Phase { case splash, welcome, onboard, preferences, createAccount, preparing, app }
    enum Screen { case home, importer, scanIdentify, scanResults, library, detail, cook, shopping, basket, plan, profile, feed, discover, reelProfile, paywall, auth }

    /// Which way the next screen change should animate.
    enum NavDirection { case forward, backward, lateral }

    /// Tab-root screens sit at depth 0; anything deeper pushes and can be popped or swiped back.
    static func depth(of screen: Screen) -> Int {
        switch screen {
        // Meal plan is a tab root now, so it sits at depth 0 with the other tabs.
        case .home, .importer, .library, .shopping, .plan: return 0
        case .scanIdentify, .scanResults, .detail, .profile, .feed, .discover, .basket: return 1
        case .reelProfile: return 2
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
    /// Recently opened recipe ids, most-recent first. Persisted; drives Home's "Jump back in"
    /// resume card and "Recently viewed" row (requested by users importing from many sources).
    @Published var recentIDs: [String] = []
    private static let recentLimit = 12

    // MARK: Discover (server recipe catalog)
    @Published var catalog: [Recipe] = []
    /// The community's most-liked recipes, for the "Popular right now" carousel. Stays empty
    /// until people share recipes; the view falls back to featured catalog dishes.
    @Published var popular: [Recipe] = []
    @Published var catalogCuisines: [String] = []
    /// Selected countries — multi-select, so several can be active at once.
    @Published var catalogCuisine: Set<String> = []
    @Published var catalogCategories: [String] = []
    /// Selected food types — multi-select.
    @Published var catalogCategory: Set<String> = []
    @Published var catalogSearch = ""
    @Published var catalogMaxTime: Int? = nil
    @Published var catalogMaxCal: Int? = nil

    var catalogFilterActive: Bool {
        !catalogCuisine.isEmpty || !catalogCategory.isEmpty
            || !catalogSearch.trimmingCharacters(in: .whitespaces).isEmpty
            || catalogMaxTime != nil || catalogMaxCal != nil
    }
    var catalogFilterCount: Int {
        catalogCuisine.count + catalogCategory.count
            + (catalogMaxTime != nil ? 1 : 0) + (catalogMaxCal != nil ? 1 : 0)
    }
    @Published var catalogLoading = false

    /// Recipes recommended from the catalog for the user's taste profile, shown on Home.
    @Published var recommended: [Recipe] = []
    @Published var recommendedLoading = false

    /// Ids already saved to the library, so Discover can show a "Saved ✓" state.
    var isInLibrary: (String) -> Bool { { [weak self] id in self?.recipes.contains { $0.id == id } ?? false } }
    @Published var search = ""
    @Published var chip = "All"

    // MARK: Library filters (cooking time / difficulty / calories, on the Saved tab)

    /// Cooking-time band a recipe's total time must fall in.
    enum TimeBand: String, CaseIterable, Identifiable {
        case any = "Any time", under15 = "≤ 15 min", under30 = "≤ 30 min", under45 = "≤ 45 min", over60 = "60 min +"
        var id: String { rawValue }
        func matches(_ minutes: Int) -> Bool {
            switch self {
            case .any: return true
            case .under15: return minutes <= 15
            case .under30: return minutes <= 30
            case .under45: return minutes <= 45
            case .over60: return minutes >= 60
            }
        }
    }

    /// Calories-per-serving band.
    enum CalBand: String, CaseIterable, Identifiable {
        case any = "Any", under300 = "≤ 300", under500 = "≤ 500", under700 = "≤ 700", over700 = "700 +"
        var id: String { rawValue }
        func matches(_ cal: Int) -> Bool {
            switch self {
            case .any: return true
            case .under300: return cal <= 300
            case .under500: return cal <= 500
            case .under700: return cal <= 700
            case .over700: return cal >= 700
            }
        }
    }

    static let difficultyOptions = ["Easy", "Medium", "Hard"]

    @Published var showFilters = false
    @Published var timeBand: TimeBand = .any
    @Published var calBand: CalBand = .any
    @Published var difficultyFilter: String? = nil

    /// How many of the extra (sheet) filters are active — drives the badge on the Filters button.
    var activeFilterCount: Int {
        (timeBand != .any ? 1 : 0) + (calBand != .any ? 1 : 0) + (difficultyFilter != nil ? 1 : 0)
    }

    func clearFilters() {
        withAnimation(Self.lateralAnimation) {
            timeBand = .any
            calBand = .any
            difficultyFilter = nil
        }
    }

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
    /// Author whose reel profile is open.
    @Published var reelProfileAuthor: String?
    /// A reel the feed should jump to, set when one is opened from a profile grid.
    @Published var reelFocusID: String?
    /// Artwork for AI-suggested matches, keyed by match id. Filled in from the catalog after
    /// the scan lands, so a suggestion shows the real dish instead of a placeholder tile.
    @Published var matchArtwork: [String: String] = [:]
    /// The snapped frame written to disk, so a generated recipe can keep the user's own photo.
    private var scanPhotoURL: String?
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
    /// The signed-in user's id, mirrored from SocialStore by RootView.
    @Published var currentUserID: String?

    /// True when AI work can run server-side, where the key lives and the quota is enforced.
    var usesServerAI: Bool { aiToken != nil }

    /// Renews an expired access token via SocialStore and returns the fresh one. Wired in
    /// App.swift. Lets a signed-in user whose access token lapsed keep working instead of
    /// being sent back to the sign-in screen mid-import.
    var refreshAIToken: (() async -> String?)?

    /// Runs a metered proxy call, and on a 401 (expired access token) refreshes the token
    /// once and retries — so an expired token silently renews instead of surfacing as
    /// "sign in again". Any other failure propagates to `handleAIError`.
    func proxyWithRetry<T>(_ op: (String) async throws -> RecipeExtractor.ProxyResult<T>) async throws -> RecipeExtractor.ProxyResult<T> {
        guard let token = aiToken else { throw RecipeExtractor.ProxyError.notSignedIn }
        do {
            return try await op(token)
        } catch RecipeExtractor.ProxyError.notSignedIn {
            guard let fresh = await refreshAIToken?() else { throw RecipeExtractor.ProxyError.notSignedIn }
            aiToken = fresh
            return try await op(fresh)
        }
    }
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
            #if DEBUG
            // A DEBUG-only local unlock (used when StoreKit products can't load, e.g. the
            // plain simulator) must not be reverted by the server, which still says "free"
            // because no real receipt was submitted. Compiled out of release entirely.
            if !debugPlanUnlocked { entitlement.plan = serverPlan }
            #else
            entitlement.plan = serverPlan
            #endif
        }
        entitlement.syncRemaining(remaining)
        persistEntitlement()
    }

    /// Pulls the entitlement the server actually enforces and mirrors it locally, so the
    /// client's gating (camera, quota) can't disagree with what the AI proxy will allow.
    /// The server is authoritative: a plan bought on another device, or granted server-side,
    /// shows up here even when this device's StoreKit has no record of it. Runs at launch and
    /// after sign-in — a no-op (leaves local state untouched) if it can't reach the server.
    func refreshServerEntitlement(token: String) async {
        guard let server = try? await SocialAPI.fetchEntitlement(token: token) else { return }
        if let plan = Entitlement.Plan(rawValue: server.plan) {
            #if DEBUG
            if !debugPlanUnlocked { entitlement.plan = plan }
            #else
            entitlement.plan = plan
            #endif
        }
        entitlement.period = server.period
        entitlement.used = max(0, server.used)
        entitlement.topUp = max(0, server.top_up)
        entitlement.trialUntil = Self.isoDate(server.trial_until)
        entitlement.rollOverIfNeeded()
        persistEntitlement()
    }

    /// Parses the server's ISO-8601 timestamps (with or without fractional seconds).
    private static func isoDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) { return date }
        return ISO8601DateFormatter().date(from: raw)
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

    /// A creator's reel page, opened from the author line on a reel.
    func openReelProfile(authorID: String) {
        Haptics.tap(.light)
        reelProfileAuthor = authorID
        go(to: .reelProfile)
    }

    /// Opens a specific reel in the feed — used by the profile grid.
    func openReel(_ reel: Reel) {
        reelFocusID = reel.id
        go(to: .feed)
    }

    /// Profile is an account screen — signed out there is nothing in it but blanks, so
    /// ask for an account instead of showing an empty shell.
    func openProfile() {
        guard isAuthenticated else {
            showAuth(.general)
            return
        }
        go(to: .profile)
    }

    /// Sends the user to create an account (or sign in) before a gated feature.
    func showAuth(_ reason: AuthReason = .general) {
        guard screen != .auth else { return }
        Haptics.tap(.medium)
        authReason = reason
        go(to: .auth)
    }

    /// Called when a session appears, so the user lands back where they were headed.
    /// Drives the welcome screen's copy: a new account gets "Welcome, [name]!" with the
    /// setup steps; a returning sign-in gets a shorter "Welcome back, [name]!". nil when no
    /// welcome is playing (e.g. a silent session restore at launch).
    enum WelcomeMode { case newAccount, returning }
    @Published var welcome: WelcomeMode?

    /// Called after an explicit sign-in/sign-up succeeds (never on silent session restore).
    /// Both paths play the welcome animation, then land on Home.
    func authenticationSucceeded(newAccount: Bool = false) {
        isAuthenticated = true
        welcome = newAccount ? .newAccount : .returning
        screen = .home
        withAnimation(.easeOut(duration: 0.4)) {
            if newAccount && !preferences.isComplete {
                phase = .preferences
            } else {
                phase = .preparing
            }
        }
    }

    /// Called when the user disconnects. Drops their token, cancels any pending sync, wipes
    /// this device's personal data (it lives on their account and would otherwise leak to the
    /// next person to sign in here), and returns to onboarding so the app is genuinely logged out.
    func signedOut() {
        isAuthenticated = false
        aiToken = nil
        currentUserID = nil
        syncPushTask?.cancel()
        welcome = nil
        // Clear per-user state so a second account on this device starts clean.
        recipes = []
        shopping = []
        plan = [:]
        userName = ""
        preferences = UserPreferences()
        entitlement = Entitlement()
        selId = nil
        openedRecipe = nil
        persistEntitlement()
        persistLocalOnly()
        screen = .home
        authReason = .general
        withAnimation(.easeOut(duration: 0.4)) { phase = .createAccount }
    }

    /// Saves the local snapshot to UserDefaults WITHOUT pushing to the server — used on
    /// sign-out, where there's no longer a session to sync to.
    private func persistLocalOnly() {
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: Self.storeKey)
        }
    }

    #if DEBUG
    /// Jumps straight into the app, bypassing onboarding/preferences/sign-in. Launch-arg only
    /// (`-gsEnterApp`), for verifying in-app screens without walking the whole first-run flow.
    func debugEnterApp() {
        phase = .app
        screen = .home
    }

    /// Seeds a spread of local recipes (varied time / calories / cuisine / difficulty) so the
    /// Library filters and the recently-viewed row can be exercised without a server account.
    /// Launch-arg only (`-gsSeed`). Compiled out of release.
    func debugSeedSampleRecipes() {
        let specs: [(String, String, Int, Int, Int, Bool)] = [
            // title, cuisine, prep, cook, cal, favorite
            ("Avocado Toast",        "Breakfast",     5,  5,  280, true),
            ("Green Smoothie Bowl",  "Breakfast",     8,  0,  240, false),
            ("Chicken Stir-Fry",     "Thai",         12, 12,  520, true),
            ("Beef Tacos",           "Mexican",      15, 15,  640, false),
            ("Margherita Pizza",     "Italian",      25, 18,  780, false),
            ("Slow Braised Short Ribs", "Italian",   20, 60,  860, false),
        ]
        recipes = specs.enumerated().map { i, s in
            var r = Self.mockRecipe(source: "Sample")
            r.id = "seed_\(i)"
            r.title = s.0; r.cuisine = s.1; r.prep = s.2; r.cook = s.3; r.cal = s.4; r.favorite = s.5
            return r
        }
        persistLocalOnly()
    }
    #endif

    func showPaywall(_ reason: PaywallReason = .upgrade) {
        Haptics.tap(.medium)
        paywallReason = reason
        go(to: .paywall)
    }

    /// Applies a purchased plan. Real receipts arrive via StoreKit; this is the state change
    /// both the sandbox flow and a restored purchase land on.
    /// Applies a plan that Apple (and, when signed in, our server) has confirmed.
    /// This is the only path that may raise the plan — nothing in the UI sets it directly.
    #if DEBUG
    /// Set once a DEBUG-only local unlock has been used, so the server sync stops reverting
    /// the plan to "free". Never compiled into release builds.
    var debugPlanUnlocked = false

    /// Testing shortcut for when StoreKit products can't load (e.g. the plain simulator, where
    /// `simctl launch` doesn't apply the StoreKit config). Flips the plan locally and pins it so
    /// the profile/paywall reflect Pro without a real purchase. NOT a code path in release.
    func debugUnlock(_ plan: Entitlement.Plan, annual: Bool) {
        debugPlanUnlocked = true
        activate(plan, annual: annual)
    }
    #endif

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

    func activate(_ plan: Entitlement.Plan, annual: Bool = false) {
        Haptics.notify(.success)
        let tookWelcome = entitlement.welcomeOfferActive
        entitlement.plan = plan
        entitlement.annualBilling = annual
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

    /// The real Date for each entry in `days` — Monday of the current calendar week onward,
    /// so the meal plan always shows today's actual dates rather than fixed numbers.
    var weekDayDates: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // Calendar weekday is 1=Sun … 7=Sat; shift so Monday is day 0 of our week.
        let daysSinceMonday = (cal.component(.weekday, from: today) + 5) % 7
        guard let monday = cal.date(byAdding: .day, value: -daysSinceMonday, to: today) else { return [] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: monday) }
    }

    /// The day-of-month number for each day this week, aligned to `days`.
    var weekDates: [Int] {
        weekDayDates.map { Calendar.current.component(.day, from: $0) }
    }

    /// Index into `days` for today, so the plan can highlight the current day.
    var todayIndexInWeek: Int? { Self.days.firstIndex(of: todayName) }

    /// The meal-plan's seven rows, a rolling window that STARTS with today and runs six days
    /// forward. Each entry carries the weekday key (matching `plan`), the real date number,
    /// and whether it's today.
    var planDays: [(day: String, date: Int, isToday: Bool)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEEE"
        return (0..<7).compactMap { offset in
            guard let d = cal.date(byAdding: .day, value: offset, to: today) else { return nil }
            return (f.string(from: d), cal.component(.day, from: d), offset == 0)
        }
    }

    /// e.g. "Sep 11 – 17", for the plan header, spanning the today-anchored window.
    var planRangeLabel: String {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let last = cal.date(byAdding: .day, value: 6, to: today) else { return "" }
        let mon = DateFormatter(); mon.dateFormat = "MMM"
        let startMonth = mon.string(from: today), endMonth = mon.string(from: last)
        let d1 = cal.component(.day, from: today), d2 = cal.component(.day, from: last)
        return startMonth == endMonth ? "\(startMonth) \(d1) – \(d2)" : "\(startMonth) \(d1) – \(endMonth) \(d2)"
    }

    /// e.g. "Sep 8 – 14" or "Aug 31 – Sep 6" for the current week's header.
    var weekRangeLabel: String {
        guard let first = weekDayDates.first, let last = weekDayDates.last else { return "" }
        let cal = Calendar.current
        let mon = DateFormatter(); mon.dateFormat = "MMM"
        let startMonth = mon.string(from: first)
        let endMonth = mon.string(from: last)
        let d1 = cal.component(.day, from: first), d2 = cal.component(.day, from: last)
        return startMonth == endMonth ? "\(startMonth) \(d1) – \(d2)" : "\(startMonth) \(d1) – \(endMonth) \(d2)"
    }

    /// The whole local snapshot — persisted to UserDefaults and, for a signed-in user, synced
    /// to their account so it follows them to any device. Not private: the sync layer encodes it.
    struct Persisted: Codable {
        var recipes: [Recipe]
        var shopping: [ShoppingItem]
        var plan: [String: String]
        var name: String?
        var preferences: UserPreferences?
        /// Recently opened recipe ids, most-recent first — powers the "Recently viewed" row
        /// and the "Jump back in" resume card. Optional with a default keeps older saves decodable.
        var recentIDs: [String]? = nil
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
            recentIDs = saved.recentIDs ?? []
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
        let saved = snapshot
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: Self.storeKey)
        }
        pushStateToServer()
    }

    /// The current local state as one snapshot.
    var snapshot: Persisted {
        Persisted(recipes: recipes, shopping: shopping, plan: plan, name: userName, preferences: preferences,
                  recentIDs: recentIDs)
    }

    // MARK: - Account sync

    private var syncPushTask: Task<Void, Never>?

    /// Debounced upload of the whole app state to the user's account, so it follows them to
    /// any device. No-op when signed out; failures are silent (the local copy is still saved).
    private func pushStateToServer() {
        guard let token = aiToken, let uid = currentUserID else { return }
        let state = snapshot
        syncPushTask?.cancel()
        syncPushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))   // coalesce rapid edits into one write
            guard !Task.isCancelled else { return }
            try? await SocialAPI.saveUserState(state, token: token, userID: uid)
            _ = self
        }
    }

    /// Pulls the account's synced state and merges it with what's on this device, then saves
    /// the union back up so every device converges. Called after sign-in and at launch.
    private var pullInFlight = false

    func pullAndMergeServerState() async {
        guard let token = aiToken, let uid = currentUserID else { return }
        guard !pullInFlight else { return }
        pullInFlight = true
        defer { pullInFlight = false }

        // Distinguish "no row yet" (a fresh account) from a transient error: only the former
        // should seed the account from this device.
        let remoteOrNil: AppStore.Persisted?
        do { remoteOrNil = try await SocialAPI.fetchUserState(token: token, userID: uid) }
        catch { return }   // network/transient — keep local, try again next launch

        guard let remote = remoteOrNil else {
            // The account has never synced — push this device's local state up as the seed.
            persist()
            return
        }

        // Union recipes and shopping by id (local wins on a shared id — this device may have
        // just edited it); remote adds anything this device has never seen.
        var mergedRecipes = recipes
        let localRecipeIDs = Set(recipes.map(\.id))
        mergedRecipes.append(contentsOf: remote.recipes.filter { !localRecipeIDs.contains($0.id) })

        var mergedShopping = shopping
        let localItemIDs = Set(shopping.map(\.id))
        mergedShopping.append(contentsOf: remote.shopping.filter { !localItemIDs.contains($0.id) })

        // Meal plan: keep local assignments, fill any empty day from remote.
        var mergedPlan = plan
        for (day, id) in remote.plan where mergedPlan[day] == nil { mergedPlan[day] = id }

        withAnimation(Self.lateralAnimation) {
            recipes = mergedRecipes
            shopping = mergedShopping
            plan = mergedPlan
            if userName.isEmpty, let name = remote.name, !name.isEmpty { userName = name }
            if !preferences.isComplete, let prefs = remote.preferences, prefs.isComplete {
                preferences = prefs
            }
        }
        persist()   // writes locally and pushes the merged union back up
    }

    // MARK: - Launch flow

    /// How long the splash holds. Shared with SplashView so the loading arc finishes exactly
    /// as the screen hands off — a bar that stops at 70% reads as a hang.
    static let splashDuration: Double = 2.4

    func startSplashTimer() {
        splashTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.splashDuration))
            guard let self, !Task.isCancelled, self.phase == .splash else { return }
            self.advanceFromSplash()
        }
    }

    func endSplash() {
        splashTask?.cancel()
        advanceFromSplash()
    }

    /// After the splash, a returning user (saved session) goes straight to the app; only a
    /// first launch with no session sees onboarding.
    private var hasOnboarded: Bool {
        get { UserDefaults.standard.bool(forKey: "hasOnboarded") }
        set { UserDefaults.standard.set(newValue, forKey: "hasOnboarded") }
    }

    private func advanceFromSplash() {
        guard phase == .splash else { return }
        withAnimation(.easeOut(duration: 0.4)) {
            if isAuthenticated {
                phase = .app
            } else if hasOnboarded {
                authReason = .general
                phase = .createAccount
            } else {
                phase = .welcome
            }
        }
    }

    func startFromWelcome() {
        withAnimation(.easeOut(duration: 0.4)) { phase = .onboard }
    }

    func onboardNext() {
        if obIndex >= 2 {
            advanceFromOnboarding()
        } else {
            withAnimation(.easeOut(duration: 0.35)) { obIndex += 1 }
        }
    }

    /// After onboarding (or skipping it): answer the taste profile if it isn't done, then —
    /// crucially — require an account before the app itself. There is no guest dashboard.
    private func advanceFromOnboarding() {
        hasOnboarded = true
        withAnimation(.easeOut(duration: 0.4)) {
            if isAuthenticated {
                phase = preferences.isComplete ? .app : .preferences
            } else {
                authReason = .general
                phase = .createAccount
            }
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
        welcome = nil
    }

    func skipOnboard() {
        advanceFromOnboarding()
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
            Task { await loadRecommendations(force: true) }
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
        case .reelProfile: return .home
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
        case .reelProfile: return .feed
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
        rememberTabState()
    }

    // MARK: - Per-tab navigation memory

    /// The deepest screen (and the recipe it was showing) last active under each tab root, so
    /// switching tabs and coming back restores where you were — e.g. a recipe you were reading —
    /// instead of dumping you at the tab's root.
    private struct TabState { var screen: Screen; var recipe: Recipe?; var selId: String? }
    private var tabMemory: [Screen: TabState] = [:]

    private func rememberTabState() {
        let root = activeTabRoot
        if Self.depth(of: screen) > 0 {
            tabMemory[root] = TabState(screen: screen, recipe: openedRecipe, selId: selId)
        } else {
            tabMemory[root] = nil   // at the root there's nothing deeper to restore
        }
    }

    /// Tab-bar tap: go back to where you last were under this tab (e.g. a recipe you were
    /// reading), not always its root. Falls back to the root when there's nothing deeper to
    /// restore. Use the back button/gesture to leave a detail — that's what clears the memory.
    func selectTab(_ root: Screen) {
        if let saved = tabMemory[root], saved.screen != root, Self.depth(of: saved.screen) > 0 {
            // Rebind the restored detail to this tab so its highlight and back target are right.
            detailReturn = root
            openedRecipe = saved.recipe
            selId = saved.selId
            go(to: saved.screen)
        } else {
            go(to: root)
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

    /// The recipe last opened, even when it isn't in the library (a feed post, a catalog
    /// preview). Prefer the saved copy so edits/favourites stay live; fall back to this so a
    /// non-saved recipe still shows its own details instead of another recipe's.
    @Published var openedRecipe: Recipe?

    var selected: Recipe? { recipes.first { $0.id == selId } ?? openedRecipe }

    var showTabs: Bool {
        // Profile is account settings, not a tab destination — the dock is hidden there and
        // you leave by the back chevron or the edge swipe, like cook mode and the paywall.
        phase == .app && screen != .cook && screen != .scanIdentify && screen != .paywall
            && screen != .auth && screen != .profile && screen != .feed && screen != .reelProfile
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

        // Extra filters from the Filters sheet.
        if timeBand != .any { out = out.filter { timeBand.matches($0.totalMinutes) } }
        if calBand != .any { out = out.filter { calBand.matches($0.cal) } }
        if let d = difficultyFilter { out = out.filter { $0.difficultyLabel == d } }
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

    /// Removes a single item from the list (swipe-to-delete).
    func removeItem(_ id: String) {
        Haptics.tap(.medium)
        withAnimation(Self.pushAnimation) {
            shopping.removeAll { $0.id == id }
        }
        persist()
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

    /// Grand total across the whole list, in cents. nil until at least one item is priced.
    var cartTotalCents: Int? { priceTotalCents(shopping) }

    /// How many items on the list have a known price, for "12 of 15 priced".
    var pricedItemCount: Int { shopping.filter { $0.priceCents != nil }.count }

    // MARK: - Discover

    /// Loads taste-profile recommendations for the dashboard. Silent on failure — the Home
    /// section just stays hidden rather than showing an error.
    @MainActor
    func loadRecommendations(force: Bool = false) async {
        guard preferences.isComplete else { recommended = []; return }
        guard force || recommended.isEmpty, !recommendedLoading else { return }
        recommendedLoading = true
        defer { recommendedLoading = false }
        if let rows = try? await CatalogService.recommended(for: preferences) {
            recommended = rows.map(\.recipe)
        }
    }

    /// Discover now lives inside the Library ("Recipes") tab, which opens on its Discover
    /// segment. Routing here keeps a single home for the catalog instead of a separate screen.
    func openDiscover() {
        go(to: .library)
        if catalog.isEmpty { Task { await loadCatalog(reset: true) } }
        if catalogCuisines.isEmpty {
            Task { catalogCuisines = (try? await CatalogService.cuisines()) ?? [] }
        }
        if catalogCategories.isEmpty {
            Task { catalogCategories = (try? await CatalogService.categories()) ?? [] }
        }
    }

    /// Loads the community's most-cooked recipes. Best-effort: needs a signed-in token, and
    /// silently leaves `popular` empty (view falls back to the catalog) when unavailable.
    @MainActor
    func loadPopular() async {
        guard let token = aiToken else { return }
        if let recipes = try? await SocialAPI.popularRecipes(token: token), !recipes.isEmpty {
            popular = recipes
        }
    }

    /// Adds or removes a country from the multi-select country facet. Passing nil clears them all.
    func setCatalogCuisine(_ cuisine: String?) {
        if let cuisine { catalogCuisine.formSymmetricDifference([cuisine]) }
        else { catalogCuisine.removeAll() }
        Task { await loadCatalog(reset: true) }
    }

    /// Adds or removes a food type from the multi-select food-type facet. nil clears them all.
    func setCatalogCategory(_ category: String?) {
        if let category { catalogCategory.formSymmetricDifference([category]) }
        else { catalogCategory.removeAll() }
        Task { await loadCatalog(reset: true) }
    }

    /// Resets every Discover filter facet at once (the sheet's "Clear all").
    func setCatalogMaxTime(_ t: Int?) {
        catalogMaxTime = catalogMaxTime == t ? nil : t
        Task { await loadCatalog(reset: true) }
    }

    func setCatalogMaxCal(_ c: Int?) {
        catalogMaxCal = catalogMaxCal == c ? nil : c
        Task { await loadCatalog(reset: true) }
    }

    func clearCatalogFilters() {
        catalogCuisine.removeAll()
        catalogCategory.removeAll()
        catalogSearch = ""
        catalogMaxTime = nil
        catalogMaxCal = nil
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
                cuisines: catalogCuisine, categories: catalogCategory,
                search: catalogSearch, maxTime: catalogMaxTime, maxCal: catalogMaxCal,
                limit: 60, offset: offset)
            let recipes = rows.map(\.recipe)
            if reset { catalog = recipes } else { catalog.append(contentsOf: recipes) }
        } catch {
            if reset { catalog = [] }
            showToast("Couldn't load Discover. Check your connection.")
        }
    }

    /// Opens a catalog recipe in the normal detail screen. It is added to the library on
    /// first view so cook mode, favouriting and the shopping list all work on it.
    /// Opens a catalog/discover recipe for browsing. It is NOT added to the library — saving is
    /// a deliberate action on the detail screen (or the reel's Save button). The detail resolves
    /// it from `openedRecipe`, so viewing, cook mode and shopping all work unsaved.
    func openCatalogRecipe(_ recipe: Recipe) {
        open(recipe)
    }

    /// Saves a recipe into the library without navigating — for the reel feed's Save button,
    /// where the point is to keep scrolling. Returns true only when it was newly added.
    @discardableResult
    func saveToLibrary(_ recipe: Recipe) -> Bool {
        guard !recipes.contains(where: { $0.id == recipe.id }) else { return false }
        recipes.insert(recipe, at: 0)
        persist()
        return true
    }

    /// Adds or removes a recipe from the library — the detail screen's Save button. Removing
    /// also clears it from the meal plan (a plan can't point at a recipe you no longer keep).
    /// Returns true when the recipe is saved after the toggle.
    @discardableResult
    func toggleSaved(_ recipe: Recipe) -> Bool {
        Haptics.tap(.light)
        if recipes.contains(where: { $0.id == recipe.id }) {
            for (day, id) in plan where id == recipe.id { plan[day] = nil }
            recipes.removeAll { $0.id == recipe.id }
            persist()
            return false
        }
        recipes.insert(recipe, at: 0)
        persist()
        return true
    }

    // MARK: - Recipes

    func open(_ recipe: Recipe) {
        if Self.depth(of: screen) == 0 { detailReturn = screen }
        openedRecipe = recipe
        selId = recipe.id
        cookStep = 0
        noteRecentlyViewed(recipe.id)
        go(to: .detail)
    }

    /// Moves a recipe to the front of the recently-viewed list and persists it, so the
    /// "Jump back in" card and "Recently viewed" row survive leaving the app.
    private func noteRecentlyViewed(_ id: String) {
        recentIDs.removeAll { $0 == id }
        recentIDs.insert(id, at: 0)
        if recentIDs.count > Self.recentLimit { recentIDs = Array(recentIDs.prefix(Self.recentLimit)) }
        persist()
    }

    /// Recently opened recipes that still exist in the library, most-recent first. Ids that no
    /// longer resolve (e.g. an unsaved preview, or a deleted recipe) are skipped.
    var recentRecipes: [Recipe] {
        recentIDs.compactMap { id in recipes.first { $0.id == id } }
    }

    /// The single most recent recipe, for the "Jump back in" resume card.
    var resumeRecipe: Recipe? { recentRecipes.first }

    /// Reopens the last-viewed recipe from the resume card.
    func resumeLast() {
        guard let recipe = resumeRecipe else { return }
        open(recipe)
    }

    func toggleFav(_ id: String) {
        if let i = recipes.firstIndex(where: { $0.id == id }) {
            Haptics.tap(.light)
            withAnimation(Self.stepAnimation) { recipes[i].favorite.toggle() }
            persist()
        } else if let opened = openedRecipe, opened.id == id {
            // Favouriting a recipe you're only browsing keeps it: save it, favourited.
            Haptics.tap(.light)
            var r = opened
            r.favorite = true
            withAnimation(Self.stepAnimation) { recipes.insert(r, at: 0) }
            persist()
        }
    }

    func deleteSelected() {
        guard let sel = selected else { return }
        for (day, id) in plan where id == sel.id { plan[day] = nil }
        recipes.removeAll { $0.id == sel.id }
        recentIDs.removeAll { $0 == sel.id }
        selId = nil
        go(to: .library)
        persist()
    }

    /// Removes a saved recipe by id (swipe-to-delete in the library), also clearing it from
    /// any meal-plan day it was assigned to.
    func deleteRecipe(_ id: String) {
        Haptics.tap(.medium)
        for (day, planned) in plan where planned == id { plan[day] = nil }
        recentIDs.removeAll { $0 == id }
        withAnimation(Self.pushAnimation) {
            recipes.removeAll { $0.id == id }
        }
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

    /// Adds the typed item to the list. Returns whether anything was actually added, so the
    /// UI can play its "added" confirmation only on a real add (not on an empty submit).
    @discardableResult
    func addItem() -> Bool {
        let n = newItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return false }
        Haptics.tap(.light)
        withAnimation(Self.pushAnimation) {
            shopping.append(ShoppingItem(id: "s" + String(UUID().uuidString.prefix(6)), name: n, qty: "", category: "Other", done: false))
        }
        newItem = ""
        persist()
        return true
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
        if let platform = RecipeExtractor.socialPlatform(for: t) { return platform }
        if t.range(of: #"^https?://"#, options: [.regularExpression, .caseInsensitive]) != nil { return "Website" }
        return "Pasted text"
    }

    func analyze() {
        let t = importText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        guard useAIAction() else { return }
        let source = detect(t)
        if aiToken != nil {
            runLiveExtraction { [weak self] in
                guard let self else { throw RecipeExtractor.ProxyError.notSignedIn }
                let result = try await self.proxyWithRetry { token in
                    try await RecipeExtractor.proxyExtract(from: t, token: token, sourceLabel: source)
                }
                self.applyServerQuota(remaining: result.remaining, plan: result.plan)
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
                guard let self else { return }
                let result = try await self.proxyWithRetry { token in
                    try await RecipeExtractor.proxyAnalyzeFoodPhoto(image, token: token)
                }
                guard self.identifyingFood else { return }
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
            matchArtwork = [:]
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
        scanPhotoURL = ScanPhotoStore.save(scanImage)
        loadMatchArtwork()
        withAnimation(Self.pushAnimation) {
            identifyingFood = false
            scanStatus = ""
            go(to: .scanResults)
        }
    }

    /// Looks each AI suggestion up in the server catalog by title and keeps the first photo
    /// it finds. Best-effort and per-match, so one miss never blocks the others.
    private func loadMatchArtwork() {
        let wanted = scanMatches.filter { !$0.isInLibrary }
        guard !wanted.isEmpty else { return }

        // The catalog is free and already ours, so ask it about every suggestion.
        for match in wanted {
            Task { [weak self] in
                guard let rows = try? await CatalogService.fetch(search: match.dishName, limit: 1),
                      let img = rows.first?.recipe.img, !img.isEmpty else { return }
                await MainActor.run { self?.matchArtwork[match.id] = img }
            }
        }

        // Google is billed per query, so only the closest match earns one on the scan itself.
        // The rest keep the user's own photo until they're actually tapped.
        if let top = wanted.first {
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(600))   // give the catalog a chance first
                await self?.searchArtwork(for: top)
            }
        }
    }

    /// Buys one image-search query for `match`, unless something already answered for it.
    /// Server-side this hits a shared cache first, so a repeated dish costs nothing.
    private func searchArtwork(for match: FoodScanMatch) async {
        guard matchArtwork[match.id] == nil, let token = aiToken else { return }
        guard let found = await RecipeExtractor.proxyDishImage(dish: match.dishName, token: token)
        else { return }
        matchArtwork[match.id] = found
    }

    /// The picture to show for a match: the catalog's photo of that dish, else the frame the
    /// user actually snapped — every suggestion is a name for that same plate.
    func artwork(for match: FoodScanMatch) -> URL? {
        if let recipe = recipe(for: match) { return recipe.imageURL }
        if let found = matchArtwork[match.id] { return URL(string: found) }
        if let photo = scanPhotoURL { return URL(string: photo) }
        return nil
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

        // Now that this dish is genuinely being used, it's worth buying its photo — the
        // recipe we're about to save will keep it. Runs alongside the write, not before it.
        Task { [weak self] in await self?.searchArtwork(for: match) }

        let detected = scanIngredients
        if aiToken != nil {
            withAnimation(Self.lateralAnimation) { fetchingDish = match.dishName }
            Task { [weak self] in
                do {
                    guard let self else { return }
                    let result = try await self.proxyWithRetry { token in
                        try await RecipeExtractor.proxyGenerateRecipe(
                            forDish: match.dishName, detected: detected, token: token)
                    }
                    guard self.fetchingDish != nil else { return }
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
    private func presentFetched(_ fetched: Recipe, for match: FoodScanMatch) {
        Haptics.notify(.success)
        var recipe = fetched
        // The extractor can only fall back to a generic stock photo by cuisine. We have better:
        // the catalog's photo of this dish, or failing that the frame the user just snapped.
        if let real = matchArtwork[match.id] ?? scanPhotoURL {
            recipe.img = real
        }
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
