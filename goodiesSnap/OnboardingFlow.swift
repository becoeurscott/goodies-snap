import SwiftUI

/// The value-first onboarding flow.
///
/// The old first run asked seven taste-profile questions and demanded an account before the
/// app would show anything. This one inverts that: the first thing it does is turn a video
/// the user already wanted to cook into a recipe, a shopping list and a cost, and only asks
/// for an account once there is something worth saving. The two questions that survived
/// (how many people, where you shop) are asked at the moment they change a number on screen,
/// which is what makes them feel like part of the product rather than a form.
///
/// AI during this flow runs on a guest session (see `GuestSession`), so "no account yet" and
/// "real extraction" are both true at once.
extension AppStore {

    enum OnboardStep: Int, CaseIterable, Comparable {
        /// 1 — "Let's make something delicious."
        case start
        /// 2 — video or photo.
        case source
        /// 3 — paste the link (or take the photo).
        case paste
        /// 4 — the extraction, narrated.
        case extracting
        /// 5 — the recipe. The first thing the app gives before it asks for anything.
        case recipe
        /// 6 — how many people (asked because it changes the list).
        case servings
        /// 7 — where you shop (asked because it changes the prices).
        case store
        /// 8 — the shopping list, priced, with "already have it?".
        case list
        /// 9 — cost per serving and where it could be cheaper.
        case cost
        /// 10 — "plan the rest of your week?"
        case planPrompt
        /// 11 — which meals, what budget.
        case planSetup
        /// 12 — the week being built, narrated.
        case planBuilding
        /// 13 — the week, with its total.
        case week
        /// 14 — what the app just did, counted up.
        case valueSummary
        /// 15 — the community, introduced only now that there's a reason to care.
        case community
        /// 16 — the whole system on one screen.
        case foodSystem
        /// 17 — "next time, just take a picture."
        case snapTeaser

        static func < (a: OnboardStep, b: OnboardStep) -> Bool { a.rawValue < b.rawValue }

        /// Steps that shouldn't be interrupted by a back gesture or a skip button.
        var isWorking: Bool { self == .extracting || self == .planBuilding }

        /// Steps that run on the brand gradient rather than on white. The root view draws
        /// it so it sits behind the progress bar too — otherwise the bar leaves a white
        /// seam across the top of an otherwise full-bleed screen.
        var usesGradient: Bool {
            switch self {
            case .extracting, .planBuilding, .planPrompt, .valueSummary: return true
            default: return false
            }
        }
    }

    enum OnboardSource: String { case video, photo, surprise }

    // MARK: - Entry

    /// Starts the flow and, in the background, opens the guest session the extraction will
    /// need. Kicked off early precisely so the network round trip overlaps the two taps it
    /// takes the user to reach the paste screen.
    func beginOnboarding(social: SocialStore) {
        onboard = OnboardState()
        withAnimation(.easeOut(duration: 0.4)) { phase = .onboard }
        Task { await social.startGuestSessionIfNeeded() }
    }

    /// "Already have an account?" on the first screen. Goes straight to sign-in without
    /// touching the taste profile or marking the flow as done.
    func signInFromOnboarding() {
        Haptics.tap(.light)
        askForAccount()
    }

    // MARK: - Navigation

    func onboardGo(to step: OnboardStep) {
        Haptics.tap(.light)
        withAnimation(Self.pushAnimation) {
            onboard.forward = step > onboard.step
            onboard.step = step
        }
    }

    /// Moves to the next step. Steps that need work done first (extraction, planning) start
    /// that work instead of advancing — they advance themselves when it lands.
    func onboardNextStep() {
        let all = OnboardStep.allCases
        guard let i = all.firstIndex(of: onboard.step), i + 1 < all.count else {
            finishOnboarding()
            return
        }
        onboardGo(to: all[i + 1])
    }

    func onboardBackStep() {
        let all = OnboardStep.allCases
        guard let i = all.firstIndex(of: onboard.step), i > 0 else { return }
        let previous = all[i - 1]
        // Never reverse into a screen whose only content was a progress animation.
        onboardGo(to: previous.isWorking ? all[max(0, i - 2)] : previous)
    }

    /// Leaves onboarding for the account step. Everything the flow produced is already in
    /// the app's normal state (recipes, list, plan), so nothing is lost by skipping.
    ///
    /// "Completed" means the flow actually produced something. Someone who tapped "Sign in"
    /// on the first screen has built nothing, and must not be greeted later by a paywall
    /// congratulating them on the food system they didn't make.
    func finishOnboarding() {
        hasCompletedOnboarding = onboard.recipe != nil
        // The taste profile was never asked as a questionnaire; assemble what the flow
        // actually learned so Home has something to rank recommendations with.
        preferences.servings = onboard.servings
        preferences.householdSize = Self.householdLabel(for: onboard.servings)
        if !onboard.store.isEmpty { preferences.preferredStore = onboard.store }
        if let seed = onboard.recipe, !seed.cuisine.isEmpty, preferences.cuisines.isEmpty {
            preferences.cuisines = [seed.cuisine]
        }
        if preferences.motivations.isEmpty {
            preferences.motivations = onboard.plannedWeek.isEmpty
                ? ["Find recipes to cook"]
                : ["Plan my meals for the week", "Plan my grocery shopping"]
        }
        if preferences.cookFrequency.isEmpty { preferences.cookFrequency = "A few times a week" }
        persist()
        askForAccount()
    }

    static func householdLabel(for servings: Int) -> String {
        switch servings {
        case ...1: return "Just me"
        case 2: return "2 people"
        case 3...4: return "3-4 people"
        default: return "5+ people"
        }
    }

    // MARK: - Step 3/4: extraction

    /// Runs the real extraction on the pasted link, narrating it as it goes.
    ///
    /// The narration is tied to the actual call: the lines advance on a timer because the
    /// model gives no progress, but the screen cannot finish until the recipe really lands,
    /// and a failure sends the user back to the paste screen with the reason.
    /// `social` is passed so a retry can reopen a guest session that failed to open at
    /// launch — otherwise the first network blip would leave the flow permanently unable to
    /// extract, with no way back short of restarting the app.
    func onboardExtract(social: SocialStore? = nil) {
        let text = onboard.link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        onboard.error = ""
        onboard.extractStage = 0
        onboardGo(to: .extracting)

        onboard.narrationTask?.cancel()
        onboard.narrationTask = Task { @MainActor [weak self] in
            for stage in 1...4 {
                try? await Task.sleep(for: .seconds(stage == 1 ? 0.7 : 0.9))
                guard let self, !Task.isCancelled, self.onboard.step == .extracting else { return }
                withAnimation(Self.stepAnimation) { self.onboard.extractStage = stage }
            }
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                if self.aiToken == nil, let social {
                    await social.startGuestSessionIfNeeded()
                    self.aiToken = social.session?.accessToken
                    self.currentUserID = social.session?.userID
                    self.isGuestSession = social.isGuest
                }
                guard self.aiToken != nil else { throw RecipeExtractor.ProxyError.notSignedIn }
                let source = self.detect(text)
                let result = try await self.proxyWithRetry { token in
                    try await RecipeExtractor.proxyExtract(from: text, token: token, sourceLabel: source)
                }
                self.applyServerQuota(remaining: result.remaining, plan: result.plan)
                await self.onboardFinishExtraction(with: result.value)
            } catch {
                self.onboardFailExtraction(error)
            }
        }
    }

    /// Runs a real photo scan for the "photo of a dish" path, then writes the recipe for the
    /// dish it found. Two AI actions from the free five: the server lets every account make
    /// one scan before Pro (see migration `onboarding-first-scan`), so this is the genuine
    /// camera feature, not a demo of it. Lands on the same reveal screen as a link.
    func onboardScan(image: UIImage, social: SocialStore? = nil) {
        onboard.error = ""
        onboard.photo = image
        onboard.extractStage = 0
        onboardGo(to: .extracting)

        onboard.narrationTask?.cancel()
        onboard.narrationTask = Task { @MainActor [weak self] in
            for stage in 1...4 {
                try? await Task.sleep(for: .seconds(stage == 1 ? 0.9 : 1.3))
                guard let self, !Task.isCancelled, self.onboard.step == .extracting else { return }
                withAnimation(Self.stepAnimation) { self.onboard.extractStage = stage }
            }
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                if self.aiToken == nil, let social {
                    await social.startGuestSessionIfNeeded()
                    self.aiToken = social.session?.accessToken
                    self.currentUserID = social.session?.userID
                    self.isGuestSession = social.isGuest
                }
                guard self.aiToken != nil else { throw RecipeExtractor.ProxyError.notSignedIn }

                let scan = try await self.proxyWithRetry { token in
                    try await RecipeExtractor.proxyAnalyzeFoodPhoto(image, token: token)
                }
                self.applyServerQuota(remaining: scan.remaining, plan: scan.plan)
                let analysis = scan.value
                let dish = analysis.suggestions.first?.name ?? analysis.dishName
                guard !dish.trimmingCharacters(in: .whitespaces).isEmpty else {
                    throw RecipeExtractor.ProxyError.failed("no dish")
                }

                let written = try await self.proxyWithRetry { token in
                    try await RecipeExtractor.proxyGenerateRecipe(
                        forDish: dish, detected: analysis.ingredients, token: token)
                }
                self.applyServerQuota(remaining: written.remaining, plan: written.plan)

                var recipe = written.value
                // The user's own plate is the right picture for a recipe named after it.
                if let photo = ScanPhotoStore.save(image) { recipe.img = photo }
                await self.onboardFinishExtraction(with: recipe)
            } catch {
                self.onboardFailScan(error)
            }
        }
    }

    private func onboardFailScan(_ error: Error) {
        onboard.narrationTask?.cancel()
        Haptics.notify(.error)
        if let proxy = error as? RecipeExtractor.ProxyError {
            switch proxy {
            case .notEntitled(let reason, _, _) where reason == "camera_is_pro":
                // This account already spent its one free scan (e.g. reinstalled the app).
                onboard.error = "Your free photo scan has been used. Paste a video link instead — it's just as quick."
                onboard.source = .video
                onboardGo(to: .paste)
                return
            case .notEntitled:
                handleAIError(error)
                return
            case .notSignedIn:
                onboard.error = "We couldn't reach the kitchen just now. Check your connection and try again."
                onboardGo(to: .paste)
                return
            case .failed:
                break
            }
        }
        onboard.error = "We couldn't make out a dish in that photo. Try a clearer shot of the plate."
        onboardGo(to: .paste)
    }

    private func onboardFinishExtraction(with recipe: Recipe) async {
        // Let the narration reach its last line rather than cutting it off mid-word — a
        // checklist that vanishes at step two reads as a glitch, not as speed.
        while onboard.extractStage < 4, onboard.step == .extracting {
            try? await Task.sleep(for: .milliseconds(120))
        }
        guard onboard.step == .extracting else { return }

        var saved = recipe
        saved.servings = max(1, recipe.servings)
        onboard.recipe = saved
        onboard.servings = saved.servings
        // Saved for real, not held in the flow: if the user quits here, the recipe is theirs.
        if !recipes.contains(where: { $0.id == saved.id }) {
            recipes.insert(saved, at: 0)
        }
        persist()
        Haptics.notify(.success)
        onboardGo(to: .recipe)
    }

    private func onboardFailExtraction(_ error: Error) {
        onboard.narrationTask?.cancel()
        Haptics.notify(.error)
        if let proxy = error as? RecipeExtractor.ProxyError {
            switch proxy {
            case .notEntitled:
                // Out of quota during onboarding: that's a paywall, not an error message.
                handleAIError(error)
                return
            case .notSignedIn:
                // No guest session — the network was down when the flow opened, or the
                // guest endpoint is unreachable. Blaming the user's link for that would
                // send them off hunting for a different video that also won't work.
                onboard.error = "We couldn't reach the kitchen just now. Check your connection and try again."
                onboardGo(to: .paste)
                return
            case .failed:
                break
            }
        }
        onboard.error = "That link didn't give us enough to work with. Try another one."
        onboardGo(to: .paste)
    }

    /// The "surprise me" path: a catalog recipe stands in for an extraction, so a user with
    /// no link to hand still sees the whole flow — and it costs them no AI action, because
    /// nothing was extracted.
    func onboardUseCatalogRecipe(_ recipe: Recipe) {
        var saved = recipe
        saved.servings = max(1, recipe.servings)
        onboard.recipe = saved
        onboard.servings = saved.servings
        if !recipes.contains(where: { $0.id == saved.id }) { recipes.insert(saved, at: 0) }
        persist()
        Haptics.notify(.success)
        onboardGo(to: .recipe)
    }

    // MARK: - Step 6/7: servings and store

    /// Rescales the extracted recipe to the household size the user just gave. Quantities are
    /// left as the source wrote them — rewriting "2 cups" into "3 cups" reliably needs a
    /// model, and guessing it wrong is worse than leaving it — but servings and the per-serving
    /// maths both follow the new number.
    func onboardSetServings(_ n: Int) {
        let clamped = max(1, min(12, n))
        onboard.servings = clamped
        guard var recipe = onboard.recipe else { return }
        recipe.servings = clamped
        onboard.recipe = recipe
        if let i = recipes.firstIndex(where: { $0.id == recipe.id }) { recipes[i] = recipe }
        persist()
    }

    func onboardSetStore(_ name: String) {
        Haptics.tap(.light)
        onboard.store = name
        preferences.preferredStore = name
        persist()
    }

    /// Builds the shopping list from the extracted recipe. Called on the way into step 8.
    func onboardBuildList() {
        guard let recipe = onboard.recipe else { return }
        if !allOnList(recipe) { addIngredients(of: recipe) }
    }

    // MARK: - Step 11/12: the week

    /// Builds the rest of the week around the extracted recipe, narrating the work.
    ///
    /// Unlike the extraction this is genuinely local (see `WeekPlanner`), so the narration
    /// is paced to be readable rather than to cover a slow call — but each line still names
    /// something the planner really does.
    func onboardBuildWeek() {
        onboard.weekStage = 0
        onboardGo(to: .planBuilding)

        onboard.narrationTask?.cancel()
        onboard.narrationTask = Task { @MainActor [weak self] in
            for stage in 1...5 {
                try? await Task.sleep(for: .seconds(0.62))
                guard let self, !Task.isCancelled, self.onboard.step == .planBuilding else { return }
                withAnimation(Self.stepAnimation) { self.onboard.weekStage = stage }
            }
        }

        Task { @MainActor [weak self] in
            guard let self, let seed = self.onboard.recipe else { return }
            // The catalog is the candidate pool. If it can't be reached the week is built
            // from whatever the user already has, which is honest — just shorter.
            // Fetched by dinner category rather than filtered afterwards, so a pool of 120
            // desserts doesn't come back and leave the planner with three usable candidates.
            var pool = self.catalog.filter(WeekPlanner.isDinner)
            if pool.count < 20,
               let rows = try? await CatalogService.fetch(
                   categories: WeekPlanner.dinnerCategories, limit: 150) {
                pool = rows.map(\.recipe)
            }
            if pool.isEmpty { pool = self.recipes }

            let plan = WeekPlanner.build(
                seed: seed, pool: pool, preferences: self.preferences,
                count: self.onboard.dinnersWanted)

            // Wait out the narration so the reveal doesn't beat the checklist.
            while self.onboard.weekStage < 5, self.onboard.step == .planBuilding {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard self.onboard.step == .planBuilding else { return }

            self.onboard.plannedWeek = plan.recipes
            self.onboard.weekIngredientCount = plan.ingredientCount
            self.onboard.weekSharedCount = plan.sharedCount

            // Commit it to the real meal plan and library, so the week survives onboarding.
            for recipe in plan.recipes where !self.recipes.contains(where: { $0.id == recipe.id }) {
                self.recipes.append(recipe)
            }
            for (day, recipe) in zip(Self.days, plan.recipes) {
                self.plan[day] = recipe.id
            }
            self.persist()
            Haptics.notify(.success)
            self.onboardGo(to: .week)
        }
    }

    /// Adds every planned dinner's ingredients to the shopping list — the "one list for the
    /// whole week" the summary claims.
    func onboardShopTheWeek() {
        for recipe in onboard.plannedWeek { addIngredients(of: recipe) }
    }

    // MARK: - Derived numbers for the flow's screens

    /// The recipe's cost, as shown on the cost step.
    var onboardRecipeCost: ItemPrice? {
        guard let recipe = onboard.recipe else { return nil }
        return priceTotal(shopping.filter { $0.recipeID == recipe.id })
            ?? recipeCost(recipe)
    }

    var onboardPerServing: ItemPrice? {
        guard let total = onboardRecipeCost else { return nil }
        return ItemPrice(cents: total.cents / max(1, onboard.servings), isEstimate: total.isEstimate)
    }

    /// The two or three best savings available on this recipe's list.
    var onboardSwaps: [IngredientPrices.Swap] {
        guard let recipe = onboard.recipe else { return [] }
        var seen = Set<String>()
        return recipe.ingredients
            .compactMap { IngredientPrices.swap(for: $0.name) }
            .filter { seen.insert($0.from).inserted }
            .sorted { $0.saving > $1.saving }
            .prefix(3)
            .map { $0 }
    }

    var onboardWeekCost: ItemPrice? { weekCost(for: onboard.plannedWeek) }

    /// Whether onboarding has already been completed on this device.
    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "gs_onboarding_v2_done") }
        set { UserDefaults.standard.set(newValue, forKey: "gs_onboarding_v2_done") }
    }
}

/// Everything the onboarding flow collects, in one place so it can be reset wholesale.
struct OnboardState {
    var step: AppStore.OnboardStep = .start
    var forward = true

    var source: AppStore.OnboardSource = .video
    var link = ""
    var error = ""
    /// The plate photographed on the photo path, shown while it's being read.
    var photo: UIImage?

    /// Which narration line the working screens are on.
    var extractStage = 0
    var weekStage = 0
    /// The timer driving those lines, cancelled when the screen is left.
    var narrationTask: Task<Void, Never>?

    var recipe: Recipe?
    var servings = 2
    var store = ""
    var zip = ""

    /// Which meals the user wants planned. Dinner is pre-selected because that is what the
    /// flow has just proved it can do.
    var meals: Set<String> = ["Dinner"]
    var budget = ""

    var plannedWeek: [Recipe] = []
    var weekIngredientCount = 0
    var weekSharedCount = 0

    /// How many dinners to plan — the seed plus the rest of the working week.
    var dinnersWanted = 5
}
