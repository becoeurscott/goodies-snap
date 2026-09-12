import SwiftUI
import PhotosUI

struct ImportView: View {
    @EnvironmentObject var store: AppStore
    @FocusState private var focused: Bool

    private var trimmed: String {
        store.importText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Save a recipe")
                    .font(nunito(29, .black))
                Text("Snap a dish, paste a link or a video — AI writes the recipe card.")
                    .font(nunito(13, .semibold))
                    .foregroundStyle(Color.gsMuted)
                    .padding(.top, 6)

                // Hero: photo scan is the headline capture method (the reference's scan tab).
                Button { store.startPhotoScan() } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color.gsDock)
                        VStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .strokeBorder(Color.gsPeach, style: StrokeStyle(lineWidth: 2.5, dash: [10, 8]))
                                    .frame(width: 92, height: 92)
                                Image(systemName: store.canUseCamera ? "camera.viewfinder" : "lock.fill")
                                    .font(.system(size: store.canUseCamera ? 34 : 28, weight: .semibold))
                                    .foregroundStyle(Color.gsPeach)
                            }
                            HStack(spacing: 8) {
                                Text("Scan a dish")
                                    .font(nunito(17, .extrabold))
                                    .foregroundStyle(Color.white)
                                if !store.canUseCamera {
                                    Text("PRO")
                                        .font(nunito(9.5, .black))
                                        .tracking(1)
                                        .foregroundStyle(Color.gsDock)
                                        .padding(.horizontal, 8)
                                        .frame(height: 20)
                                        .background(Color.gsPeach)
                                        .clipShape(Capsule())
                                }
                            }
                            Text(store.canUseCamera
                                 ? "AI identifies it and writes the recipe"
                                 : "Upgrade to Pro to scan with your camera")
                                .font(nunito(12, .semibold))
                                .foregroundStyle(Color.white.opacity(0.65))
                        }
                        .padding(.vertical, 26)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PressableStyle(scale: 0.98))
                .padding(.top, 18)

                HStack(spacing: 10) {
                    Rectangle().fill(Color.gsFill).frame(height: 1)
                    Text("or paste")
                        .font(nunito(11.5, .bold))
                        .foregroundStyle(Color.gsMuted)
                    Rectangle().fill(Color.gsFill).frame(height: 1)
                }
                .padding(.top, 18)

                inputCard
                    .padding(.top, 14)

                quotaBar
                    .padding(.top, 14)

                Text("How it works")
                    .font(nunito(18, .extrabold))
                    .padding(.top, 28)

                let rows = [
                    "Scan a photo, or paste a link, video, or text — the source is detected automatically.",
                    "AI extracts the title, ingredients by aisle, steps, and timings.",
                    "Review the clean card, then save it — cook it, plan it, shop it, share it.",
                ]
                ForEach(Array(rows.enumerated()), id: \.offset) { i, text in
                    NumberedRow(num: i + 1, text: text)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 16)
            .padding(.bottom, 116)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// Standing reminder of what's left, and the way in to upgrade before hitting the wall.
    @ViewBuilder
    private var quotaBar: some View {
        Button { store.showPaywall(.upgrade) } label: {
                HStack(spacing: 10) {
                    Image(systemName: store.quotaRemaining > 0 ? "sparkles" : "lock.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.gsAccentInk)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(store.quotaRemaining > 0
                             ? "\(store.quotaRemaining) AI save\(store.quotaRemaining == 1 ? "" : "s") left this month"
                             : "No AI saves left this month")
                            .font(nunito(13, .extrabold))
                        Text("on \(store.entitlement.plan.title)")
                            .font(nunito(11, .semibold))
                            .foregroundStyle(Color.gsMuted)
                    }
                    Spacer()
                    Text("Upgrade")
                        .font(nunito(12.5, .extrabold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(Color.gsDock)
                        .clipShape(Capsule())
                }
                .padding(12)
                .fillSurface(radius: 16)
        }
        .buttonStyle(PressableStyle(scale: 0.98))
    }

    private var inputCard: some View {
        VStack(spacing: 12) {
            TextField(
                "", text: $store.importText,
                prompt: Text("https://…  or paste the recipe here").foregroundStyle(Color.fg(0.35)),
                axis: .vertical
            )
            .font(nunito(13.5, .semibold))
            .focused($focused)
            .lineLimit(4...4)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.78))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.fg(0.12), lineWidth: 1))

            HStack {
                if !trimmed.isEmpty {
                    Kicker(text: "Detected · \(store.detect(store.importText))", size: 11, tracking: 0.9, opacity: 0.6)
                }
                Spacer()
                Button {
                    focused = false
                    store.analyze()
                } label: {
                    Text("Extract with AI")
                        .font(nunito(14, .extrabold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 26)
                        .frame(minHeight: 48)
                }
                .buttonStyle(DarkButtonStyle())
                .disabled(trimmed.isEmpty || store.importing)
                .opacity(trimmed.isEmpty ? 0.5 : 1)
            }
        }
        .padding(16)
        .softCard(radius: 22)
    }

}

struct NumberedRow: View {
    let num: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(num)")
                .font(nunito(13, .extrabold))
                .frame(width: 32, height: 32)
                .background(Color.fg(0.09))
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.fg(0.14), lineWidth: 1))
            Text(text)
                .font(nunito(13, .semibold))
                .foregroundStyle(Color.fg(0.65))
                .padding(.top, 5)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.fg(0.08)).frame(height: 1)
        }
    }
}

// MARK: - Food scan flow

/// Live camera scanner. Shows the real rear-camera feed, freezes on the snapped frame,
/// then runs the scanning animation while the AI identifies the plate.
struct ScanIdentifyView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var camera = CameraController()
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var sweep = false
    @State private var shutterFlash = false

    private var reticle: CGFloat { 300 }

    /// True once there's a photo to scan — either the frozen camera capture or a photo
    /// picked from the library. In that state we show the whole picture, not a reticle:
    /// the AI reads the entire image, so cropping it to a square is misleading.
    private var hasShot: Bool { store.scanImage != nil }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            backdrop
            scrim

            // Scanning an imported/captured photo: sweep the scan line across the whole
            // picture rather than a small square, so it reads as "the whole photo is scanned".
            if hasShot && store.identifyingFood {
                fullSweep
            }

            content

            if shutterFlash {
                Color.white.ignoresSafeArea().transition(.opacity)
            }
        }
        .task { await camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task {
                defer { pickedPhoto = nil }
                // Loading an iCloud-optimized photo can throw or return nil. Surface that
                // instead of silently doing nothing — the old code swallowed both with
                // `try?`, so a photo that failed to load looked like the scan was ignored.
                do {
                    guard let data = try await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else {
                        store.showToast("Couldn't load that photo — try another")
                        return
                    }
                    store.scan(image: image)
                } catch {
                    store.showToast("Couldn't load that photo — try another")
                }
            }
        }
    }

    // MARK: Layers

    /// The frozen capture once snapped, otherwise the live feed (or a fallback when there's no camera).
    @ViewBuilder
    private var backdrop: some View {
        if let shot = store.scanImage {
            // Fit, not fill: show the whole imported/captured photo so nothing is cropped
            // out of view. The black background fills any letterboxing.
            Image(uiImage: shot)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .transition(.opacity)
        } else if camera.status == .running {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()
        } else {
            LinearGradient(
                colors: [Color.gsDock, Color(hex: 0x2A2214)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }

    /// Darkens everything outside the reticle so the plate reads as the subject. Once a
    /// photo is captured or imported, the whole image is the subject, so we dim it
    /// uniformly (lightly) instead of punching a square hole — the photo stays fully visible.
    @ViewBuilder
    private var scrim: some View {
        if hasShot {
            Color.black.opacity(store.identifyingFood ? 0.28 : 0.12)
                .ignoresSafeArea()
                .animation(.easeOut(duration: 0.3), value: store.identifyingFood)
        } else {
            Color.black.opacity(store.identifyingFood ? 0.55 : 0.38)
                .ignoresSafeArea()
                .mask {
                    ZStack {
                        Rectangle().ignoresSafeArea()
                        RoundedRectangle(cornerRadius: 34, style: .continuous)
                            .frame(width: reticle, height: reticle)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                }
                .animation(.easeOut(duration: 0.3), value: store.identifyingFood)
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: 8)
            // The camera reticle is only for aiming the live camera. Once there's a photo,
            // the full-screen sweep takes over, so drop the square.
            if !hasShot { reticleStack }
            statusBlock
            Spacer()
            if !store.identifyingFood { controls }
        }
    }

    /// A scan line that travels the full height of the screen, over the whole photo.
    private var fullSweep: some View {
        GeometryReader { geo in
            let h = geo.size.height
            ZStack(alignment: .top) {
                LinearGradient(
                    colors: [Color.gsPeach.opacity(0), Color.gsPeach.opacity(0.35), Color.gsPeach.opacity(0)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 120)
                .offset(y: sweep ? h - 120 : 0)

                Rectangle()
                    .fill(Color.gsPeach)
                    .frame(height: 3)
                    .shadow(color: Color.gsPeach.opacity(0.9), radius: 8)
                    .offset(y: sweep ? h : 0)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            sweep = false
            withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true)) { sweep = true }
        }
    }

    private var header: some View {
        HStack {
            Button { store.goBack() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.35))
                    .clipShape(Circle())
            }
            .buttonStyle(PressableStyle(scale: 0.94))

            Spacer()
            Text(store.identifyingFood ? "Scanning" : "Scan a dish")
                .font(nunito(15, .extrabold))
                .foregroundStyle(Color.white)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
    }

    private var reticleStack: some View {
        ZStack {
            // Sweep stays inside the reticle; the corner brackets sit outside the clip.
            ZStack {
                if store.identifyingFood {
                    LinearGradient(
                        colors: [Color.gsPeach.opacity(0), Color.gsPeach.opacity(0.45), Color.gsPeach.opacity(0)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 90)
                    .offset(y: sweep ? reticle / 2 - 45 : -reticle / 2 + 45)

                    Rectangle()
                        .fill(Color.gsPeach)
                        .frame(height: 3)
                        .shadow(color: Color.gsPeach.opacity(0.9), radius: 8)
                        .offset(y: sweep ? reticle / 2 : -reticle / 2)
                }
            }
            .frame(width: reticle, height: reticle)
            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))

            ScanCorners()
                .stroke(Color.gsPeach, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .frame(width: reticle + 22, height: reticle + 22)
                .opacity(store.identifyingFood ? 1 : 0.85)
        }
        .frame(width: reticle + 22, height: reticle + 22)
        .onChange(of: store.identifyingFood) { _, on in
            sweep = false
            guard on else { return }
            withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true)) { sweep = true }
        }
    }

    @ViewBuilder
    private var statusBlock: some View {
        if store.identifyingFood {
            VStack(spacing: 8) {
                HStack(spacing: 9) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(Color.gsPeach)
                        .scaleEffect(0.85)
                    Text(store.scanStatus)
                        .font(nunito(16, .extrabold))
                        .foregroundStyle(Color.white)
                        .contentTransition(.opacity)
                }
                Text("Hold on — the AI is looking at your plate")
                    .font(nunito(12, .semibold))
                    .foregroundStyle(Color.white.opacity(0.7))
            }
            .padding(.top, 26)
            .transition(.opacity)
        } else {
            VStack(spacing: 6) {
                Text("Point at the dish")
                    .font(nunito(21, .black))
                    .foregroundStyle(Color.white)
                Text(hint)
                    .font(nunito(12.5, .semibold))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 26)
            .padding(.horizontal, 34)
        }
    }

    private var hint: String {
        switch camera.status {
        case .running: return "Fill the frame with the plate, then tap the shutter."
        case .denied: return "Camera access is off — enable it in Settings, or pick a photo."
        case .unavailable: return "No camera on this device — pick a photo from your library."
        case .idle: return "Starting the camera…"
        }
    }

    private var controls: some View {
        HStack(spacing: 20) {
            PhotosPicker(selection: $pickedPhoto, matching: .images) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 58, height: 58)
                    .background(Color.white.opacity(0.16))
                    .clipShape(Circle())
            }
            .buttonStyle(PressableStyle())

            Button(action: snap) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.28)).frame(width: 82, height: 82)
                    Circle().fill(Color.white).frame(width: 68, height: 68)
                    if camera.status != .running {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Color.gsFg.opacity(0.35))
                    }
                }
            }
            .buttonStyle(PressableStyle(scale: 0.92))
            .disabled(camera.status != .running || camera.capturing)
        }
        .padding(.bottom, 40)
        .transition(.opacity)
    }

    private func snap() {
        withAnimation(.easeOut(duration: 0.08)) { shutterFlash = true }
        camera.capturePhoto { image in
            withAnimation(.easeIn(duration: 0.18)) { shutterFlash = false }
            guard let image else {
                store.showToast("Couldn't take that photo")
                return
            }
            store.scan(image: image)
        }
    }
}

struct ScanResultsView: View {
    @EnvironmentObject var store: AppStore
    /// Drives the staggered reveal of the plate composition.
    @State private var revealed = false

    private var ingredients: [IngredientConfidence] { store.scanIngredients }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack {
                    IconButton(system: "chevron.left") { store.goBack() }
                    Spacer()
                    IconButton(system: "arrow.triangle.2.circlepath") { store.startPhotoScan() }
                }
                .padding(.horizontal, 22)
                .padding(.top, 16)

                Kicker(text: "Identified", size: 11, tracking: 2)
                    .padding(.top, 10)

                // Real dish names run long ("Tofu Buddha Bowl with Edamame, Corn, and Quail
                // Eggs") — cap at two lines and shrink rather than pushing the plate off-screen.
                Text(store.scanDishName)
                    .font(nunito(30, .black))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
                Text("\(store.scanWeight) g on the plate")
                    .font(nunito(14, .bold))
                    .foregroundStyle(Color.gsMuted)
                    .padding(.top, 3)

                compositionHeader
                    .padding(.top, 26)

                IngredientFlower(ingredients: ingredients, center: store.scanImage, revealed: revealed)
                    .frame(height: 330)
                    .padding(.top, 2)

                Text("Tap any ingredient to see what you need")
                    .font(nunito(12, .semibold))
                    .foregroundStyle(Color.gsMuted)

                Button { store.addAllDetectedFoods() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "cart.badge.plus").font(.system(size: 14, weight: .bold))
                        Text("Add all to shopping list").font(nunito(14, .extrabold))
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 22)
                    .frame(minHeight: 48)
                }
                .buttonStyle(DarkButtonStyle())
                .padding(.top, 16)

                matchesSection
                    .padding(.horizontal, 22)
                    .padding(.top, 32)
                    .padding(.bottom, 116)
            }
        }
        .background(Color.gsBg)
        .onAppear {
            revealed = false
            withAnimation(.spring(response: 0.55, dampingFraction: 0.72).delay(0.12)) { revealed = true }
        }
    }

    private var compositionHeader: some View {
        VStack(spacing: 3) {
            Text("Plate composition")
                .font(nunito(20, .extrabold))
            Text("\(ingredients.count) ingredients detected")
                .font(nunito(12, .semibold))
                .foregroundStyle(Color.gsMuted)
        }
    }

    private var matchesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recipe matches")
                    .font(nunito(20, .extrabold))
                Spacer()
                Text("Closest first")
                    .font(nunito(12, .bold))
                    .foregroundStyle(Color.gsMuted)
            }
            .padding(.horizontal, 2)

            ForEach(store.scanMatches) { match in
                ScanRecipeMatchCard(match: match, recipe: store.recipe(for: match))
            }
        }
    }
}

/// A candidate dish. Library matches show their real card; AI suggestions show a
/// "write it with AI" affordance and generate on tap.
struct ScanRecipeMatchCard: View {
    @EnvironmentObject var store: AppStore
    let match: FoodScanMatch
    let recipe: Recipe?

    var body: some View {
        Button { store.openScanMatch(match) } label: {
            HStack(spacing: 14) {
                thumbnail

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text("\(match.confidence)% match")
                            .font(nunito(11, .black))
                            .foregroundStyle(Color.gsFg)
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(Color.gsPeachSoft)
                            .clipShape(Capsule())
                        if match.id == store.scanMatches.first?.id {
                            Text("Closest")
                                .font(nunito(11, .black))
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 10)
                                .frame(height: 26)
                                .background(Color.gsDock)
                                .clipShape(Capsule())
                        }
                    }
                    Text(recipe?.title ?? match.dishName)
                        .font(nunito(17, .extrabold))
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    Text(subtitle)
                        .font(nunito(12, .semibold))
                        .foregroundStyle(Color.gsMuted)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                Image(systemName: recipe == nil ? "sparkles" : "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(recipe == nil ? Color.gsPeach : Color.gsMuted)
            }
            .padding(12)
            .softCard(radius: 26)
        }
        .buttonStyle(PressableStyle())
    }

    private var subtitle: String {
        if let recipe {
            return "\(recipe.totalMinutes) min · \(recipe.cal) kcal · \(recipe.ingredients.count) ingredients"
        }
        return match.blurb.isEmpty ? "Tap to write this recipe with AI" : match.blurb
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let art = store.artwork(for: match) {
            CoverImage(url: art)
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                // A suggestion still has to read as "not written yet", so it keeps a small
                // sparkle over the photo rather than looking like a saved recipe.
                .overlay(alignment: .bottomTrailing) {
                    if recipe == nil {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.gsAccentInk)
                            .padding(5)
                            .background(Color.gsBg.opacity(0.92), in: Circle())
                            .padding(5)
                    }
                }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.gsPeachSoft)
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.gsAccentInk)
            }
            .frame(width: 76, height: 76)
        }
    }
}

struct ScanMetric: View {
    let icon: String
    let color: Color
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(value)
                .font(nunito(18, .black))
            Text(label)
                .font(nunito(13, .bold))
                .foregroundStyle(Color.gsMuted)
        }
        .frame(maxWidth: .infinity, minHeight: 114)
        .background(Color.gsCard)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 8)
    }
}

/// The detected ingredients arranged around the snapped plate. Petals bloom outward
/// with a stagger so the composition reads as something the app just worked out.
struct IngredientFlower: View {
    @EnvironmentObject var store: AppStore
    let ingredients: [IngredientConfidence]
    var center: UIImage?
    var revealed: Bool

    private var shown: [IngredientConfidence] { Array(ingredients.prefix(6)) }

    var body: some View {
        ZStack {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                Button { store.openFoodDetail(item) } label: {
                    IngredientPetal(item: item, onList: store.onShoppingList(item))
                }
                .buttonStyle(PressableStyle(scale: 0.93))
                .offset(revealed ? offset(for: index) : .zero)
                .scaleEffect(revealed ? 1 : 0.35)
                .opacity(revealed ? 1 : 0)
                .animation(
                    .spring(response: 0.5, dampingFraction: 0.7).delay(Double(index) * 0.07),
                    value: revealed
                )
            }

            centerPlate
                .scaleEffect(revealed ? 1 : 0.7)
                .animation(.spring(response: 0.45, dampingFraction: 0.72), value: revealed)
        }
    }

    @ViewBuilder
    private var centerPlate: some View {
        Group {
            if let center {
                Image(uiImage: center)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.gsFill
                    Image(systemName: "fork.knife")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Color.gsAccentInk)
                }
            }
        }
        .frame(width: 92, height: 92)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.gsCard, lineWidth: 5))
        .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 8)
    }

    private func offset(for index: Int) -> CGSize {
        let count = max(shown.count, 1)
        let angle = (Double(index) / Double(count)) * 2 * Double.pi - Double.pi / 2
        return CGSize(width: cos(angle) * 108, height: sin(angle) * 98)
    }
}

struct IngredientPetal: View {
    let item: IngredientConfidence
    var onList: Bool = false

    var body: some View {
        VStack(spacing: 2) {
            Text(String(format: "%.1f%%", item.percent))
                .font(nunito(16, .black))
                .foregroundStyle(Color.gsFg)
            Text(item.name)
                .font(nunito(13, .bold))
                .foregroundStyle(Color.gsMuted)
                .lineLimit(1)
            if onList {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.gsAccentInk)
            }
        }
        .frame(width: 128, height: 96)
        .background(
            RadialGradient(
                colors: [Color.gsPeach.opacity(0.34), Color.gsCard],
                center: .center,
                startRadius: 8,
                endRadius: 72
            )
        )
        .clipShape(Ellipse())
        .overlay(Ellipse().strokeBorder(onList ? Color.gsPeach.opacity(0.7) : Color.clear, lineWidth: 2))
        .shadow(color: Color.black.opacity(0.06), radius: 15, x: 0, y: 8)
    }
}

// MARK: - Recipe fetch loader

/// Shown while Claude writes a recipe for a tapped suggestion. The call has no
/// predictable duration, so this is an indeterminate, reassuring loader.
struct RecipeFetchOverlay: View {
    @EnvironmentObject var store: AppStore
    @State private var spin = false
    @State private var phase = 0

    private let lines = [
        "Reading the dish…",
        "Working out ingredients…",
        "Writing the steps…",
        "Balancing quantities…",
        "Almost there…",
    ]

    var body: some View {
        ZStack {
            Color.gsBg.opacity(0.94).ignoresSafeArea()
                .background(.ultraThinMaterial)

            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .stroke(Color.gsFill, lineWidth: 6)
                        .frame(width: 84, height: 84)
                    Circle()
                        .trim(from: 0, to: 0.28)
                        .stroke(Color.gsPeach, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 84, height: 84)
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spin)
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Color.gsAccentInk)
                }

                Text(store.fetchingDish ?? "")
                    .font(nunito(21, .black))
                    .multilineTextAlignment(.center)
                    .padding(.top, 22)
                    .padding(.horizontal, 40)

                Text(lines[phase % lines.count])
                    .font(nunito(13, .semibold))
                    .foregroundStyle(Color.gsMuted)
                    .padding(.top, 8)
                    .contentTransition(.opacity)

                Text("This can take a moment — the AI writes the whole card.")
                    .font(nunito(11.5, .semibold))
                    .foregroundStyle(Color.gsMuted.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.top, 18)
                    .padding(.horizontal, 46)

                Button { store.cancelRecipeFetch() } label: {
                    Text("Cancel")
                        .font(nunito(13.5, .extrabold))
                        .foregroundStyle(Color.gsFg)
                        .padding(.horizontal, 26)
                        .frame(minHeight: 44)
                }
                .buttonStyle(FillButtonStyle())
                .padding(.top, 26)
            }
        }
        .onAppear {
            spin = true
            Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2.2))
                    withAnimation(.easeInOut(duration: 0.35)) { phase += 1 }
                }
            }
        }
    }
}

// MARK: - Detected food sheet

/// What the user needs for one detected ingredient, plus the add-to-list action.
struct FoodDetailSheet: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        BottomSheet(onDismiss: { store.closeFoodDetail() }) {
            if let item = store.foodDetail {
                let onList = store.onShoppingList(item)
                let needs = store.requirements(for: item)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(Color.gsPeachSoft)
                            Text(String(format: "%.0f%%", item.percent))
                                .font(nunito(17, .black))
                                .foregroundStyle(Color.gsFg)
                        }
                        .frame(width: 62, height: 62)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(nunito(24, .black))
                            Text("\(item.grams) g on the plate · \(Aisle.guess(for: item.name))")
                                .font(nunito(12.5, .semibold))
                                .foregroundStyle(Color.gsMuted)
                        }
                        Spacer()
                    }

                    Text("What you need")
                        .font(nunito(15, .extrabold))
                        .padding(.top, 22)

                    if needs.isEmpty {
                        HStack {
                            Text("Buy about")
                                .font(nunito(13, .semibold))
                                .foregroundStyle(Color.gsMuted)
                            Spacer()
                            Text(item.shoppingQty.isEmpty ? "1 portion" : item.shoppingQty)
                                .font(nunito(13, .bold))
                        }
                        .padding(.vertical, 10)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Color.fg(0.07)).frame(height: 1)
                        }
                        Text("No saved recipe uses this yet — the estimate comes from the scan.")
                            .font(nunito(11.5, .semibold))
                            .foregroundStyle(Color.gsMuted)
                            .padding(.top, 8)
                    } else {
                        Text("Quantities from the recipes in your library that use it")
                            .font(nunito(11.5, .semibold))
                            .foregroundStyle(Color.gsMuted)
                            .padding(.top, 2)
                        ForEach(Array(needs.enumerated()), id: \.offset) { _, need in
                            HStack {
                                Text(need.recipe)
                                    .font(nunito(13, .semibold))
                                    .lineLimit(1)
                                Spacer()
                                Text(need.qty)
                                    .font(nunito(13, .bold))
                                    .foregroundStyle(Color.gsFg)
                            }
                            .padding(.vertical, 10)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(Color.fg(0.07)).frame(height: 1)
                            }
                        }
                    }

                    Button {
                        store.addDetectedFood(item)
                        store.closeFoodDetail()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: onList ? "checkmark" : "cart.badge.plus")
                                .font(.system(size: 14, weight: .bold))
                            Text(onList ? "Already on your list" : "Add to shopping list")
                                .font(nunito(14, .extrabold))
                        }
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(DarkButtonStyle())
                    .opacity(onList ? 0.55 : 1)
                    .disabled(onList)
                    .padding(.top, 20)

                    Button { store.closeFoodDetail() } label: {
                        Text("Close")
                            .font(nunito(13.5, .extrabold))
                            .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.gsMuted)
                    .padding(.top, 4)
                }
            }
        }
    }
}

struct ScanCorners: Shape {
    /// Arm length as a fraction of the shorter side. Fixed lengths made the corners meet
    /// (reading as a closed box) whenever the mark was drawn small.
    var armRatio: CGFloat = 0.32

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let l = min(rect.width, rect.height) * armRatio
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + l))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + 18))
        p.addQuadCurve(to: CGPoint(x: rect.minX + 18, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + l, y: rect.minY))

        p.move(to: CGPoint(x: rect.maxX - l, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - 18, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + 18), control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + l))

        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - l))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 18))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - 18, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - l, y: rect.maxY))

        p.move(to: CGPoint(x: rect.minX + l, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + 18, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - 18), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - l))
        return p
    }
}

// MARK: - Analyzing overlay

/// Shown while the AI extracts a recipe. Rather than a static spinner, it stages a little
/// story: a stylized recipe card whose lines "fill in" as a glowing scan bar sweeps down
/// it, the brand mark pulsing in a ring above, and a caption that cycles through the real
/// phases of extraction. Honours Reduce Motion by falling back to a calm fade.
struct AnalyzingOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var scan = false          // scan-bar sweep position (0…1)
    @State private var filled = 0            // how many card lines have "read in"
    @State private var caption = 0           // index into `captions`
    @State private var ringSpin = false
    @State private var markPulse = false

    private let captions = [
        "Reading your recipe…",
        "Finding the ingredients…",
        "Extracting the steps…",
        "Estimating nutrition…",
    ]
    /// Relative widths of the skeleton lines, so the card reads like a real recipe.
    private let lineWidths: [CGFloat] = [1.0, 0.82, 0.66, 0.9, 0.55, 0.74]
    private let cardW: CGFloat = 230
    private let cardH: CGFloat = 264

    var body: some View {
        ZStack {
            Color.gsBg.opacity(0.92).ignoresSafeArea()
                .background(.ultraThinMaterial)

            VStack(spacing: 26) {
                mark
                card
                VStack(spacing: 6) {
                    Text(captions[caption])
                        .font(nunito(20, .black))
                        .contentTransition(.opacity)
                        .id(caption)
                        .transition(.opacity)
                    Text("This usually takes a few seconds")
                        .font(nunito(12, .semibold))
                        .foregroundStyle(Color.gsMuted)
                }
                .animation(.easeInOut(duration: 0.35), value: caption)
            }
        }
        .onAppear(perform: start)
    }

    // The brand mark inside a rotating gradient ring.
    private var mark: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(
                    AngularGradient(colors: [.gsPeach, .gsPeach.opacity(0.15), .gsPeach],
                                    center: .center),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 68, height: 68)
                .rotationEffect(.degrees(ringSpin ? 360 : 0))

            Image("SplashLogo")
                .resizable().interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .scaleEffect(markPulse ? 1.06 : 0.94)
        }
    }

    // The recipe card being "read": a header block, a photo placeholder, then text lines
    // that appear one by one, with a scan bar gliding over the whole thing.
    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.gsFg.opacity(0.14))
                .frame(width: cardW * 0.6, height: 15)
                .lineReveal(index: 0, filled: filled)

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.gsFill)
                .frame(height: 74)
                .overlay(
                    Image(systemName: "photo")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(Color.gsMuted.opacity(0.6))
                )
                .lineReveal(index: 1, filled: filled)

            ForEach(Array(lineWidths.enumerated()), id: \.offset) { i, w in
                Capsule()
                    .fill(Color.gsFg.opacity(0.11))
                    .frame(width: cardW * w, height: 9)
                    .lineReveal(index: i + 2, filled: filled)
            }
        }
        .padding(18)
        .frame(width: cardW + 36, alignment: .leading)
        .background(Color.gsCard)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(Color.gsFg.opacity(0.06), lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 22, y: 12)
        .overlay(scanBar)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // A soft peach glow bar sweeping top→bottom, the "reading" beam.
    private var scanBar: some View {
        GeometryReader { geo in
            let h = geo.size.height
            LinearGradient(
                colors: [.clear, .gsPeach.opacity(0.0), .gsPeach.opacity(0.35), .gsPeach.opacity(0.0), .clear],
                startPoint: .top, endPoint: .bottom)
                .frame(height: 90)
                .offset(y: scan ? h : -90)
                .allowsHitTesting(false)
                .opacity(reduceMotion ? 0 : 1)
        }
    }

    private func start() {
        guard !reduceMotion else {
            // Calm fallback: just reveal everything and cycle captions.
            filled = lineWidths.count + 2
            markPulse = true
            cycleCaptions()
            return
        }
        withAnimation(.linear(duration: 2.6).repeatForever(autoreverses: false)) { ringSpin = true }
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { markPulse = true }
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) { scan = true }

        // Reveal the card lines in sequence, looping so it keeps feeling alive on long calls.
        Task { @MainActor in
            let total = lineWidths.count + 2
            while !Task.isCancelled {
                for i in 1...total {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { filled = i }
                    try? await Task.sleep(for: .milliseconds(220))
                }
                try? await Task.sleep(for: .milliseconds(500))
                filled = 0
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        cycleCaptions()
    }

    private func cycleCaptions() {
        Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1600))
                withAnimation { caption = (caption + 1) % captions.count }
            }
        }
    }
}

/// Fades + rises each card line into place as the reveal index passes it.
private extension View {
    func lineReveal(index: Int, filled: Int) -> some View {
        let shown = index < filled
        return self
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 6)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: filled)
    }
}

// MARK: - Import preview sheet

struct ImportPreviewSheet: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        BottomSheet {
            if let p = store.preview {
                VStack(alignment: .leading, spacing: 0) {
                    Kicker(text: "AI extraction · \(p.source)", size: 11, tracking: 1.3, opacity: 0.7)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.fg(0.08))
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(Color.fg(0.14), lineWidth: 1))

                    Text(p.title)
                        .font(nunito(25, .black))
                        .padding(.top, 12)
                        .padding(.bottom, 6)
                    Text("\(p.totalMinutes) min · serves \(p.servings) · ~\(p.cal) cal/serving")
                        .font(nunito(12.5, .bold))
                        .foregroundStyle(Color.fg(0.55))
                        .padding(.bottom, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Color.fg(0.1)).frame(height: 1)
                        }

                    ForEach(p.ingredients) { i in
                        HStack {
                            Text(i.name).font(nunito(13, .bold))
                            Spacer()
                            Text(i.qty).font(nunito(13, .bold)).foregroundStyle(Color.fg(0.45))
                        }
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Color.fg(0.07)).frame(height: 1)
                        }
                    }

                    Text("+ \(p.steps.count) steps extracted")
                        .font(nunito(12, .semibold))
                        .italic()
                        .foregroundStyle(Color.fg(0.45))
                        .padding(.top, 10)

                    HStack(spacing: 12) {
                        Button { store.discardImport() } label: {
                            Text("Discard")
                                .font(nunito(14, .extrabold))
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(Color.fg(0.06))
                                .clipShape(Capsule())
                                .overlay(Capsule().strokeBorder(Color.fg(0.16), lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        Button { store.saveImport() } label: {
                            Text("Save to library")
                                .font(nunito(14, .extrabold))
                                .foregroundStyle(Color.white)
                                .frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .buttonStyle(DarkButtonStyle())
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.top, 18)
                }
            }
        }
    }
}

// MARK: - Shared bottom sheet chrome

struct BottomSheet<Content: View>: View {
    var onDismiss: (() -> Void)?
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { onDismiss?() }

            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.fg(0.18))
                    .frame(width: 44, height: 5)
                    .padding(.bottom, 16)
                ScrollView {
                    content
                }
                .frame(maxHeight: 560)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 34)
            .background(Color.gsSheet)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous))
            .overlay(
                UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                    .strokeBorder(Color.fg(0.1), lineWidth: 1)
            )
            .ignoresSafeArea(edges: .bottom)
            .transition(.move(edge: .bottom))
        }
        .transition(.opacity)
    }
}
