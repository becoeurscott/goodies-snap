import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var social: SocialStore
    /// Live translation of the interactive edge-swipe back gesture.
    @State private var backDrag: CGFloat = 0

    var body: some View {
        ZStack {
            Color.gsBg.ignoresSafeArea()

            if store.phase == .app {
                appContent
            }

            if store.phase == .onboard {
                OnboardingView()
                    .transition(.opacity)
                    .zIndex(70)
            }

            if store.phase == .createAccount {
                AuthView()
                    .transition(.opacity)
                    .zIndex(66)
            }

            if store.phase == .preparing {
                PreparingView()
                    .transition(.opacity)
                    .zIndex(65)
            }

            if store.phase == .preferences {
                PreferenceSetupView()
                    .transition(.opacity)
                    .zIndex(75)
            }

            if store.phase == .splash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(80)
            }
        }
        .foregroundStyle(Color.gsFg)
        .font(nunito(14, .semibold))
        // Sign-in state and the post-sign-in redirect are driven by SocialStore.onSignedIn
        // (wired in App.swift) — a deterministic callback, not a fragile view onChange.
        .onChange(of: social.signedIn) { _, yes in store.isAuthenticated = yes }
        // The token is what lets AI calls use the metered proxy instead of a local key.
        .onChange(of: social.session?.accessToken) { _, token in
            store.aiToken = token
            store.currentUserID = social.session?.userID
            // Whenever a token first arrives (sign-in or restore), bring the account's saved
            // state onto this device. Idempotent, so it's safe alongside the App.swift paths.
            if token != nil {
                Task { await store.pullAndMergeServerState() }
            }
        }
        .onOpenURL { url in
            guard url.scheme == "goodiessnap" else { return }
            jump(to: url.host ?? "")
        }
        .onAppear {
            store.isAuthenticated = social.signedIn
            store.aiToken = social.session?.accessToken
            store.currentUserID = social.session?.userID
            // Launch-argument navigation (`-gsScreen feed`), used by UI automation.
            if let target = UserDefaults.standard.string(forKey: "gsScreen") {
                jump(to: target)
            }
            // Onboarding automation (`-gsOnboard 1`) to screenshot a specific slide.
            if let idx = UserDefaults.standard.string(forKey: "gsOnboard"), let i = Int(idx) {
                withTransaction(Transaction(animation: nil)) {
                    store.phase = .onboard
                    store.obIndex = max(0, min(i, OnboardingView.pages.count - 1))
                }
            }
            // Account-step automation (`-gsCreateAccount 1`).
            if UserDefaults.standard.string(forKey: "gsCreateAccount") != nil {
                withTransaction(Transaction(animation: nil)) { store.phase = .createAccount }
            }
            // Preparing-screen automation (`-gsPreparing 1`).
            if UserDefaults.standard.string(forKey: "gsPreparing") != nil {
                withTransaction(Transaction(animation: nil)) { store.phase = .preparing }
            }
            // Taste-profile automation (`-gsPrefs 2`) to screenshot a specific question.
            if let idx = UserDefaults.standard.string(forKey: "gsPrefs"), let i = Int(idx) {
                withTransaction(Transaction(animation: nil)) {
                    store.phase = .preferences
                    store.preferenceIndex = max(0, i)
                }
            }
            // Debug-only sign-in for verification runs (`-gsSignIn email:password`).
            // Wrapped in DEBUG so no shipped build can authenticate from a launch argument.
            #if DEBUG
            if let creds = UserDefaults.standard.string(forKey: "gsSignIn") {
                let parts = creds.split(separator: ":", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    Task { @MainActor in
                        await social.signIn(email: parts[0], password: parts[1])
                        store.isAuthenticated = social.signedIn
                        store.aiToken = social.session?.accessToken
                    }
                }
            }
            #endif
            // Extraction automation (`-gsExtract <text>`): runs a real import end to end.
            if let text = UserDefaults.standard.string(forKey: "gsExtract") {
                jump(to: "import")
                store.importText = text
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(3.0))   // let a debug sign-in land first
                    store.analyze()
                }
            }
            // Report-sheet automation (`-gsReport 1`): opens a report on the first post
            // this user did not write.
            if UserDefaults.standard.string(forKey: "gsReport") != nil {
                jump(to: "feed")
                Task { @MainActor in
                    for _ in 0..<20 {
                        if let other = social.posts.first(where: { $0.author_id != social.session?.userID }) {
                            social.startReport(.post(other))
                            return
                        }
                        try? await Task.sleep(for: .milliseconds(300))
                    }
                }
            }
            // Scan-flow automation (`-gsScan results`), so each scan state is screenshottable.
            if let stage = UserDefaults.standard.string(forKey: "gsScan") {
                enterScan(stage)
            }
        }
    }

    private func jump(to name: String) {
        withTransaction(Transaction(animation: nil)) { store.phase = .app }
        switch name {
        case "feed": store.go(to: .feed)
        case "library": store.go(to: .library)
        case "shopping": store.go(to: .shopping)
        case "plan": store.go(to: .plan)
        case "import": store.go(to: .importer)
        case "profile": store.openProfile()
        case "discover": store.openDiscover()
        case "picker":
            store.go(to: .plan)
            store.openPicker(day: store.todayName)
        case "basket":
            if let first = store.shopByRecipe.first { store.openBasket(first.id) }
            else { store.go(to: .shopping) }
        case "scan": store.startPhotoScan()
        case "paywall": store.showPaywall(.upgrade)
        case "paywall-active":
            // Verification hook: pretend Pro yearly was bought. Applied after a beat because
            // `refreshEntitlements()` runs at launch and would otherwise reset us to free —
            // StoreKit is the real source of truth for the plan.
            store.showPaywall(.upgrade)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.5))
                store.entitlement.plan = .pro
                store.entitlement.annualBilling = true
                store.entitlement.used = 137
                store.isAuthenticated = true
            }
        case "paywall-empty":
            store.entitlement.used = store.entitlement.plan.allowance
            store.showPaywall(.outOfActions)
        default: store.go(to: .home)
        }
    }

    /// Drives the dish-scan flow from a launch argument for headless verification.
    private func enterScan(_ stage: String) {
        withTransaction(Transaction(animation: nil)) { store.phase = .app }
        store.startPhotoScan()
        switch stage {
        case "scanning":
            store.scanMock()
        case "live":
            // Real end-to-end scan against whatever provider the stored key routes to.
            Task {
                guard let url = URL(string: "https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=900&q=80"),
                      let (data, _) = try? await URLSession.shared.data(from: url),
                      let image = UIImage(data: data) else {
                    store.showToast("Couldn't load the test photo")
                    return
                }
                store.scan(image: image)
            }
        case "results", "food", "fetching":
            store.scanMock()
            // Give the mock a frame to work with, so the artwork path (scan photo behind a
            // suggestion, and on the recipe it writes) is exercised like a real scan.
            Task {
                if let url = URL(string: "https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=900&q=80"),
                   let (data, _) = try? await URLSession.shared.data(from: url),
                   let image = UIImage(data: data) {
                    store.scanImage = image
                }
            }
            Task {
                // Let the mock scan land on the results screen first.
                try? await Task.sleep(for: .seconds(3.2))
                if stage == "food", let first = store.scanIngredients.first {
                    store.openFoodDetail(first)
                } else if stage == "fetching", let suggestion = store.scanMatches.first(where: { !$0.isInLibrary }) {
                    store.openScanMatch(suggestion)
                }
            }
        default:
            break
        }
    }

    @ViewBuilder
    private var appContent: some View {
        ZStack {
            screenLayer

            if store.showTabs {
                VStack {
                    Spacer()
                    TabBarView()
                }
                // The floating bar now sits inside the safe area, above the home indicator,
                // rather than bleeding into the bottom edge.
                .zIndex(30)
            }

            if store.importing {
                AnalyzingOverlay()
                    .transition(.opacity)
                    .zIndex(40)
            }

            if store.fetchingDish != nil {
                RecipeFetchOverlay()
                    .transition(.opacity)
                    .zIndex(45)
            }

            if store.preview != nil {
                ImportPreviewSheet()
                    .zIndex(50)
            }

            if store.foodDetail != nil {
                FoodDetailSheet()
                    .zIndex(50)
            }

            if store.pickDay != nil {
                MealPickerSheet()
                    .zIndex(50)
            }

            if social.commentsFor != nil {
                CommentsSheet()
                    .zIndex(50)
            }

            if social.sharing != nil {
                ShareSheet()
                    .zIndex(50)
            }

            if social.composing {
                ComposerSheet()
                    .zIndex(50)
            }

            if social.composingReel {
                ReelComposeSheet()
                    .zIndex(52)
            }

            if social.reporting != nil {
                // Above the comments sheet: a comment is reported from on top of it.
                ReportSheet()
                    .zIndex(56)
            }

            if store.writingReview {
                WriteReviewSheet()
                    .zIndex(55)
            }

            if store.reportingReview != nil {
                ReviewReportSheet()
                    .zIndex(57)
            }

            if !store.toast.isEmpty {
                VStack {
                    Spacer()
                    Text(store.toast)
                        .font(nunito(12.5, .extrabold))
                        .foregroundStyle(Color.gsBg)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color.gsFg)
                        .clipShape(Capsule())
                        .padding(.bottom, 108)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(60)
            }
        }
        .animation(.easeOut(duration: 0.25), value: store.importing)
        .animation(.easeOut(duration: 0.25), value: store.toast)
    }

    /// The current screen, transitioning in the direction of travel and draggable back from the edge.
    private var screenLayer: some View {
        ZStack {
            Group {
                switch store.screen {
                case .home: HomeView()
                case .importer: ImportView()
                case .scanIdentify: ScanIdentifyView()
                case .scanResults: ScanResultsView()
                case .library: LibraryView()
                case .detail: RecipeDetailView()
                case .cook: CookModeView()
                case .shopping: ShoppingView()
                case .basket: BasketView()
                case .plan: MealPlanView()
                case .profile: ProfileView()
                case .feed: ReelsView()
                case .reelProfile: ReelProfileView()
                case .discover: DiscoverView()
                case .reviews: ReviewsView()
                case .paywall: PaywallView()
                case .auth: AuthView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.gsBg)
            // The swipe-back now dims and shrinks slightly instead of translating, so the
            // gesture matches the crossfade rather than fighting it.
            .scaleEffect(1 - min(backDrag / 2400, 0.03))
            .opacity(1 - min(backDrag / 900, 0.55))
            .id(store.screen)
            .transition(transition)
        }
        .overlay(alignment: .leading) { edgeBackGrabber }
        .onChange(of: store.screen) { _, _ in backDrag = 0 }
    }

    /// Every screen change crossfades. Depth is carried by a very small scale shift —
    /// pushing settles inward, popping eases outward — so direction still reads without
    /// anything sliding across the screen.
    private var transition: AnyTransition {
        switch store.navDirection {
        case .forward:
            return .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 1.015)),
                removal: .opacity.combined(with: .scale(scale: 0.99))
            )
        case .backward:
            return .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.99)),
                removal: .opacity.combined(with: .scale(scale: 1.015))
            )
        case .lateral:
            return .opacity
        }
    }

    /// A narrow leading strip that drives an interactive pop, like the system back swipe.
    @ViewBuilder
    private var edgeBackGrabber: some View {
        if store.canGoBack {
            Color.clear
                .frame(width: 32)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { value in
                            // Ignore drags that are mostly vertical: on a scrolling screen the
                            // strip would otherwise swallow the start of a normal scroll.
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            backDrag = max(0, value.translation.width)
                        }
                        .onEnded { value in
                            let far = value.translation.width > 90
                            let flick = value.predictedEndTranslation.width > 220
                            if far || flick {
                                store.goBack()
                            } else {
                                withAnimation(AppStore.navAnimation) { backDrag = 0 }
                            }
                        }
                )
                .ignoresSafeArea()
        }
    }
}

// MARK: - Tab bar

/// The dock: Home · Library · [Scan] · Community · Shopping.
///
/// A floating Liquid Glass capsule. Screens keep 116pt of bottom padding but their
/// scroll content passes *under* the bar, which is what gives the glass something to
/// refract — an opaque bar pinned to the edge would have nothing to bend.
/// The peach scan button is a separate glass element inside the same container, so on
/// iOS 26 the two shapes blend as they near each other instead of overlapping flatly.
struct TabBarView: View {
    @EnvironmentObject var store: AppStore
    /// Namespace for the union between the bar and the scan button.
    @Namespace private var glass

    private static let barShape = Capsule(style: .continuous)
    private static let scanShape = RoundedRectangle(cornerRadius: 17, style: .continuous)

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 20) {
                    dockRow
                }
            } else {
                dockRow
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
    }

    private var dockRow: some View {
        HStack(spacing: 0) {
            tab(.home, active: store.activeTabRoot == .home, system: "house.fill")
            tab(.library, active: store.activeTabRoot == .library, system: "book.closed.fill")

            scanButton
                .padding(.horizontal, 4)

            tab(.plan, active: store.activeTabRoot == .plan, system: "calendar", badge: store.plannedCount)
            tab(.shopping, active: store.activeTabRoot == .shopping, system: "cart.fill", badge: store.undoneCount)
        }
        .padding(.horizontal, 7)
        .frame(height: 64)
        .modifier(BarGlass(shape: Self.barShape, id: "bar", ns: glass))
    }

    /// Deliberately NOT a glass element: two overlapping glass shapes fuse into one blob,
    /// and the accent has to stay a hard, readable target. Solid peach on glass is the
    /// same split Apple uses for a prominent action in a Liquid Glass bar.
    private var scanButton: some View {
        Button { store.go(to: store.screen == .importer ? .home : .importer) } label: {
            Image(systemName: store.screen == .importer ? "xmark" : "viewfinder")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.gsDock)
                .frame(width: 54, height: 50)
                .background(Color.gsPeach, in: Self.scanShape)
                .shadow(color: Color.gsPeach.opacity(0.42), radius: 12, x: 0, y: 5)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(PressableStyle(scale: 0.92))
    }

    private func tab(_ screen: AppStore.Screen, active: Bool, system: String, badge: Int = 0) -> some View {
        Button { store.go(to: screen) } label: {
            Image(systemName: system)
                .font(.system(size: 20, weight: .semibold))
                // On translucent glass the inactive weight has to carry more contrast than
                // it did on the solid black dock, or it dissolves into whatever scrolls past.
                .foregroundStyle(active ? Color.gsPeach : Color.white.opacity(0.92))
                .scaleEffect(active ? 1.08 : 1)
                .frame(maxWidth: .infinity, minHeight: 46)
                .contentShape(Rectangle())
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text("\(badge)")
                            .font(nunito(9.5, .black))
                            .foregroundStyle(Color.gsDock)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Color.gsPeach)
                            .clipShape(Capsule())
                            .offset(x: -8, y: 2)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(AppStore.stepAnimation, value: badge)
        }
        .buttonStyle(.plain)
        .animation(AppStore.pushAnimation, value: active)
    }
}

/// Liquid Glass for the bar, tinted toward the dock's charcoal so the app keeps its
/// identity instead of turning into a generic clear pill. Pre-iOS 26 falls back to a
/// blurred material, which is the closest the older stack gets.
private struct BarGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    let id: String
    let ns: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.tint(Color.gsDock.opacity(0.92)), in: shape)
                .glassEffectID(id, in: ns)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background(Color.gsDock.opacity(0.72), in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.22), radius: 22, x: 0, y: 10)
        }
    }
}
