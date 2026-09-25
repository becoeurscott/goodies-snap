import SwiftUI
import PhotosUI

// Steps 1–5: from "I saw something I want to cook" to a recipe they can actually use.
// Nothing here asks the user for anything about themselves.

// MARK: - 1. Start

struct OBStartView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var social: SocialStore
    @State private var appear = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Artwork and scrim share one ignoresSafeArea container. Applying it to the
            // scrim separately left its bottom edge on the safe-area inset, so the model's
            // jacket showed in the strip underneath the buttons.
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    // The artwork carries the logo and the headline itself, so the screen
                    // adds nothing on top of them — only the way forward.
                    Image("OnboardHero")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)

                    // The artwork's own gradient continued downward, so the buttons sit on
                    // brand colour instead of on the model's hands.
                    LinearGradient(
                        colors: [.clear, Color.gsBrandBottom.opacity(0.9), Color.gsBrandDeep],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: geo.size.height * 0.42)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
            }
            .ignoresSafeArea()

            VStack(spacing: 10) {
                Text("Turn any food video or photo into a recipe,\na shopping list and a real cost.")
                    .font(nunito(14, .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Takes 2 minutes · No account needed")
                    .font(nunito(12, .extrabold))
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(.bottom, 6)

                OBLightPrimary(title: "Try it with a recipe") { store.onboardNextStep() }

                Button {
                    store.signInFromOnboarding()
                } label: {
                    (Text("Already have an account?  ")
                        .foregroundStyle(.white.opacity(0.75))
                     + Text("Sign in").foregroundStyle(.white))
                        .font(nunito(13.5, .bold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 18)
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 16)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.15)) { appear = true }
            // The guest session the extraction needs is opened now, so the round trip is
            // already done by the time the user has pasted a link.
            Task { await social.startGuestSessionIfNeeded() }
        }
    }
}

// MARK: - 2. Source

struct OBSourceView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        OBPage(
            title: "What do you want to cook?",
            subtitle: "Start with something you've already seen."
        ) {
            VStack(spacing: 12) {
                OBChoice(icon: "play.rectangle",
                         title: "A video",
                         detail: "Paste a recipe video from TikTok, Instagram, YouTube or Pinterest.",
                         selected: store.onboard.source == .video) {
                    store.onboard.source = .video
                    store.onboardNextStep()
                }

                OBChoice(icon: "camera",
                         title: "A photo of a dish",
                         detail: "Snap a plate and we'll work out what's in it.",
                         selected: store.onboard.source == .photo) {
                    store.onboard.source = .photo
                    store.onboardNextStep()
                }

                OBChoice(icon: "wand.and.stars.inverse",
                         title: "Surprise me",
                         detail: "We'll pick something good to start with.",
                         selected: store.onboard.source == .surprise) {
                    store.onboard.source = .surprise
                    store.onboardNextStep()
                }
            }
        } action: {
            EmptyView()
        }
    }
}

// MARK: - 3. Paste / pick

struct OBPasteView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var social: SocialStore
    @FocusState private var focused: Bool
    @State private var loadingSurprise = false

    private let platforms = ["TikTok", "Instagram", "YouTube", "Pinterest"]

    var body: some View {
        switch store.onboard.source {
        case .video: videoBody
        case .photo: photoBody
        case .surprise: surpriseBody
        }
    }

    // ---- Video: the main path ----

    private var videoBody: some View {
        OBPage(
            kicker: "Step 1",
            title: "Paste your recipe video",
            subtitle: "Drop in a link and we'll read the whole thing — ingredients, steps, quantities."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                // Named, not badged: a hand-picked SF Symbol beside a real platform name
                // reads as a logo that failed to load.
                Text(platforms.joined(separator: "  ·  "))
                    .font(nunito(12, .extrabold))
                    .foregroundStyle(Color.gsMuted)
                    .tracking(0.3)

                HStack(spacing: 10) {
                    Image(systemName: "link")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.gsMuted)
                    TextField("https://…", text: $store.onboard.link)
                        .font(nunito(14.5, .semibold))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .submitLabel(.go)
                        .focused($focused)
                        .onSubmit { store.onboardExtract(social: social) }
                    if !store.onboard.link.isEmpty {
                        Button { store.onboard.link = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(Color.gsMuted.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Color.gsFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .strokeBorder(focused ? Color.gsAccentInk.opacity(0.4) : .clear, lineWidth: 1.5)
                        )
                )

                if !store.onboard.error.isEmpty {
                    Label(store.onboard.error, systemImage: "exclamationmark.triangle.fill")
                        .font(nunito(12.5, .bold))
                        .foregroundStyle(Color.gsAccentInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Haptics.tap(.light)
                    if let pasted = UIPasteboard.general.string { store.onboard.link = pasted }
                } label: {
                    Label("Paste from clipboard", systemImage: "doc.on.clipboard")
                        .font(nunito(13, .bold))
                        .foregroundStyle(Color.gsAccentInk)
                }
                .buttonStyle(.plain)
            }
        } action: {
            OBPrimary(title: "Extract recipe",
                      enabled: !store.onboard.link.trimmingCharacters(in: .whitespaces).isEmpty) {
                focused = false
                store.onboardExtract(social: social)
            }
            OBSecondary(title: "I don't have a link — pick one for me") {
                store.onboard.source = .surprise
            }
        }
        .onAppear { focused = true }
    }

    // ---- Photo: a real scan. Every account gets one before Pro, paid from the 5 free
    // actions (scan + writing the recipe = 2), so this is the actual camera feature. ----

    private var photoBody: some View { OBPhotoScanBody() }

    // ---- Surprise: a real catalog recipe, no AI action spent. ----

    private var surpriseBody: some View {
        OBPage(
            kicker: "Step 1",
            title: "We'll pick one to start",
            subtitle: "Something quick and well-liked, so you can see the whole flow. You can import your own straight after."
        ) {
            VStack(spacing: 12) {
                if loadingSurprise {
                    ProgressView().tint(Color.gsAccentInk).frame(maxWidth: .infinity).padding(.vertical, 30)
                } else {
                    ForEach(store.catalog.prefix(3), id: \.id) { recipe in
                        Button {
                            store.onboardUseCatalogRecipe(recipe)
                        } label: {
                            OBRecipeCard(recipe: recipe)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } action: {
            OBSecondary(title: "I'll paste a link instead") { store.onboard.source = .video }
        }
        .task {
            guard store.catalog.count < 3 else { return }
            loadingSurprise = true
            defer { loadingSurprise = false }
            // Dinner categories only: the first thing the app ever shows shouldn't be
            // three breakfasts, and the week gets built from this same seed.
            if let rows = try? await CatalogService.fetch(
                categories: WeekPlanner.dinnerCategories, maxTime: 45, limit: 40) {
                store.catalog = rows.map(\.recipe).filter(WeekPlanner.isDinner).shuffled()
            }
        }
    }
}

// MARK: - 4. Extracting

struct OBExtractingView: View {
    @EnvironmentObject var store: AppStore

    private var lines: [String] {
        switch store.onboard.source {
        case .photo: return ["Photo read", "Dish identified", "Ingredients detected",
                             "Quantities estimated", "Building your recipe"]
        default: return ["Video found", "Food detected", "Ingredients identified",
                         "Cooking steps read", "Building your recipe"]
        }
    }

    var body: some View {
        // The router paints the gradient; this screen is only its contents.
        VStack(spacing: 0) {
            Spacer()

            OBWorkingRing()

            Text("Reading your recipe")
                .font(nunito(28, .black))
                .tracking(-0.8)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.top, 26)

            OBChecklist(lines: lines, stage: store.onboard.extractStage, onGradient: true)
                .frame(maxWidth: 290)
                .padding(.top, 32)

            Spacer()

            Text(store.onboard.source == .photo
                 ? "This uses 2 of your 5 free actions."
                 : "This uses one of your free recipe extractions.")
                .font(nunito(12, .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.bottom, 28)
        }
        .padding(.horizontal, 26)
    }
}

// MARK: - 5. The recipe

struct OBRecipeRevealView: View {
    @EnvironmentObject var store: AppStore

    /// Named after where the recipe actually came from. Saying "we turned that video into a
    /// recipe" to someone who tapped "surprise me" is a small lie that costs trust for free.
    private var revealBlurb: String {
        switch store.onboard.source {
        case .video:
            return "We turned that video into a recipe you can actually cook from — and it's already saved."
        case .photo:
            return "We worked out what's on the plate and wrote it up — and it's already saved."
        case .surprise:
            return "Here's one to start with — it's already saved to your recipes."
        }
    }

    var body: some View {
        if let recipe = store.onboard.recipe {
            OBPage(
                title: "",
                header: {
                    OBPhotoHeader(
                        url: recipe.imageURL,
                        kicker: store.onboard.source == .surprise ? "Here's one to start" : "Found it",
                        title: recipe.title,
                        meta: "\(recipe.totalMinutes) min · serves \(recipe.servings) · \(recipe.ingredients.count) ingredients")
                }
            ) {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 11) {
                        Text("Ingredients")
                            .font(nunito(16, .extrabold))
                            .foregroundStyle(Color.gsFg)
                        ForEach(recipe.ingredients.prefix(9), id: \.id) { item in
                            HStack(alignment: .top, spacing: 9) {
                                Circle().fill(Color.gsBrandBottom).frame(width: 5, height: 5).padding(.top, 7)
                                Text(item.name)
                                    .font(nunito(14, .semibold))
                                    .foregroundStyle(Color.gsFg)
                                Spacer(minLength: 8)
                                Text(item.qty)
                                    .font(nunito(13, .bold))
                                    .foregroundStyle(Color.gsMuted)
                            }
                        }
                        if recipe.ingredients.count > 9 {
                            Text("+ \(recipe.ingredients.count - 9) more")
                                .font(nunito(12.5, .bold))
                                .foregroundStyle(Color.gsMuted)
                                .padding(.leading, 15)
                        }
                    }

                    if !recipe.steps.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "list.number").font(.system(size: 12, weight: .bold))
                            Text("\(recipe.steps.count) cooking steps, written out")
                                .font(nunito(13, .bold))
                        }
                        .foregroundStyle(Color.gsBrandBottom)
                    }

                    Text(revealBlurb)
                        .font(nunito(13.5, .semibold))
                        .foregroundStyle(Color.gsMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } action: {
                OBPrimary(title: "What will this cost me?  →") { store.onboardNextStep() }
            }
        } else {
            // Defensive: the reveal can only be reached with a recipe, but a restored state
            // should route somewhere sane rather than showing a blank screen.
            Color.clear.onAppear { store.onboardGo(to: .paste) }
        }
    }
}


// MARK: - 3b. Photo scan (real)

/// The photo path's paste step: a live viewfinder with a shutter, or a photo from the
/// library. Either one runs `onboardScan`, the same metered scan as the in-app camera.
struct OBPhotoScanBody: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var social: SocialStore
    @StateObject private var camera = CameraController()
    @State private var picked: PhotosPickerItem?

    var body: some View {
        OBPage(
            kicker: "Step 1",
            title: "Snap a dish",
            subtitle: "Point the camera at a plate. We'll name it, list what's in it and write the recipe."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                viewfinder
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                if !store.onboard.error.isEmpty {
                    Label(store.onboard.error, systemImage: "exclamationmark.triangle.fill")
                        .font(nunito(12.5, .bold))
                        .foregroundStyle(Color.gsAccentInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Label("Uses 2 of your 5 free actions: one to read the photo, one to write the recipe.",
                      systemImage: "sparkles")
                    .font(nunito(12, .semibold))
                    .foregroundStyle(Color.gsMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } action: {
            if camera.status == .running {
                OBPrimary(title: camera.capturing ? "Snapping…" : "Snap it") { snap() }
            }
            PhotosPicker(selection: $picked, matching: .images) {
                Text(camera.status == .running ? "Choose from photos" : "Choose a photo")
                    .font(nunito(15, .extrabold))
                    .foregroundStyle(camera.status == .running ? Color.gsAccentInk : .white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        Capsule().fill(camera.status == .running ? Color.clear : Color.gsFg)
                    )
            }
            .buttonStyle(.plain)
            OBSecondary(title: "Use a video link instead") {
                store.onboard.error = ""
                store.onboard.source = .video
            }
        }
        .task { await camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task {
                defer { picked = nil }
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    store.onboardScan(image: image, social: social)
                } else {
                    store.onboard.error = "Couldn't load that photo. Try another one."
                }
            }
        }
    }

    @ViewBuilder
    private var viewfinder: some View {
        ZStack {
            Color.black
            switch camera.status {
            case .running:
                CameraPreview(session: camera.session)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.85), style: StrokeStyle(lineWidth: 2, dash: [10, 8]))
                    .padding(34)
            case .denied:
                placeholder(icon: "camera.fill",
                            text: "Camera access is off. Choose a photo instead, or allow the camera in Settings.")
            case .unavailable:
                placeholder(icon: "photo.on.rectangle", text: "Choose a photo of a dish to scan.")
            case .idle:
                ProgressView().tint(.white)
            }
        }
    }

    private func placeholder(icon: String, text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 34, weight: .semibold))
            Text(text)
                .font(nunito(13.5, .semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .foregroundStyle(.white.opacity(0.85))
    }

    private func snap() {
        guard !camera.capturing else { return }
        Haptics.tap(.medium)
        camera.capturePhoto { image in
            guard let image else {
                store.onboard.error = "That shot didn't come through. Try again."
                return
            }
            store.onboardScan(image: image, social: social)
        }
    }
}
