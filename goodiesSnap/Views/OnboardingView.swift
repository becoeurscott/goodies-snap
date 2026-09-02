import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var store: AppStore

    struct Page {
        let kicker: String
        let title: String
        let body: String
        let img: String
        /// Each page gets an overlay that demonstrates *that* page's promise.
        let overlay: HeroOverlay
    }

    /// What floats on top of a page's photo.
    enum HeroOverlay {
        case scanResult       // the real dish-scan output card
        case cookStep         // one step at a time, with a timer
        case weekPlan         // the week filling in, list writing itself
    }

    static let pages: [Page] = [
        Page(kicker: "Save",
             title: "Any recipe,\ndecoded by AI",
             body: "Snap a dish, paste a link or a video. The AI reads it and writes you a clean recipe card.",
             img: "https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=900&q=80",
             overlay: .scanResult),
        Page(kicker: "Cook",
             title: "Cook hands-free,\nstep by step",
             body: "One generous step at a time, timers built in — no scrolling back with sticky fingers.",
             img: "https://images.unsplash.com/photo-1556910103-1c02745aae4d?w=900&q=80",
             overlay: .cookStep),
        Page(kicker: "Plan",
             title: "Plan the week,\nshop once",
             body: "Drop dinners onto your week and the shopping list writes itself, sorted by aisle.",
             img: "https://images.unsplash.com/photo-1540420773420-3366772f4999?w=900&q=80",
             overlay: .weekPlan),
    ]

    private var isLast: Bool { store.obIndex == Self.pages.count - 1 }

    var body: some View {
        let page = Self.pages[store.obIndex]

        ZStack {
            Color.gsSheet.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                OnboardingHero(image: page.img, overlay: page.overlay)
                    .frame(height: 460)
                    .padding(.top, 4)
                    .id("obImg\(store.obIndex)")
                    .transition(.opacity)

                Spacer(minLength: 0)

                VStack(spacing: 0) {
                    Text(page.kicker.uppercased())
                        .font(nunito(11, .black))
                        .tracking(2.2)
                        .foregroundStyle(Color.gsAccentInk)

                    Text(page.title)
                        .font(nunito(33, .black))
                        .lineSpacing(1)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)

                    Text(page.body)
                        .font(nunito(14, .semibold))
                        .foregroundStyle(Color.gsMuted)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                        .frame(maxWidth: 330)
                }
                .id("obText\(store.obIndex)")
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .opacity
                ))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 28)

                progressDots
                    .padding(.top, 26)

                Button { store.onboardNext() } label: {
                    HStack(spacing: 8) {
                        Text(isLast ? "Get started" : "Next")
                            .font(nunito(15, .extrabold))
                        Image(systemName: isLast ? "arrow.right" : "chevron.right")
                            .font(.system(size: 12, weight: .black))
                    }
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(DarkButtonStyle())
                .padding(.horizontal, 28)
                .padding(.top, 20)
                .padding(.bottom, 28)
            }
        }
        .background(Color.gsSheet)
        .animation(.easeOut(duration: 0.35), value: store.obIndex)
        // Swiping is what people try first on a carousel.
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    if value.translation.width < -40 {
                        store.onboardNext()
                    } else if value.translation.width > 40, store.obIndex > 0 {
                        withAnimation(.easeOut(duration: 0.35)) { store.obIndex -= 1 }
                    }
                }
        )
    }

    private var topBar: some View {
        HStack {
            Text("goodiesSnap")
                .font(nunito(14, .black))
                .foregroundStyle(Color.gsFg.opacity(0.7))
            Spacer()
            Button { store.skipOnboard() } label: {
                Text("Skip")
                    .font(nunito(13, .bold))
                    .foregroundStyle(Color.gsFg.opacity(0.65))
                    .padding(.horizontal, 18)
                    .frame(minHeight: 38)
                    .background(Color.gsFill)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 12)
        .padding(.horizontal, 24)
    }

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<Self.pages.count, id: \.self) { i in
                Capsule()
                    .fill(i == store.obIndex ? Color.gsPeach : Color.gsFg.opacity(0.15))
                    .frame(width: i == store.obIndex ? 22 : 7, height: 7)
            }
        }
        .animation(AppStore.stepAnimation, value: store.obIndex)
    }
}

// MARK: - Hero

struct OnboardingHero: View {
    let image: String
    var overlay: OnboardingView.HeroOverlay = .scanResult

    var body: some View {
        ZStack {
            CoverImage(url: URL(string: image))
                .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))

            LinearGradient(
                colors: [.clear, Color.gsSheet.opacity(0.88), Color.gsSheet],
                startPoint: .center,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))

            switch overlay {
            case .scanResult: scanCard
            case .cookStep: cookCard
            case .weekPlan: weekCard
            }
        }
        .padding(.horizontal, 22)
    }

    // Page 1 — the dish-scan result, mirroring ScanResultsView. These are the real
    // figures the model returned for this exact photo during live testing.
    private var scanCard: some View {
        let parts: [(String, Double)] = [
            ("Grilled tofu", 18), ("Romaine lettuce", 14), ("Corn kernels", 10),
        ]
        return VStack(spacing: 11) {
            HStack(spacing: 8) {
                Text("IDENTIFIED")
                    .font(nunito(10, .black))
                    .tracking(1.6)
                    .foregroundStyle(Color.gsDock)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Color.gsPeach)
                    .clipShape(Capsule())
                Spacer()
                Text("420 g")
                    .font(nunito(12, .black))
                    .foregroundStyle(Color.gsMuted)
            }

            Text("Tofu Buddha Bowl")
                .font(nunito(17, .black))
                .foregroundStyle(Color.gsFg)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 7) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    HStack(spacing: 10) {
                        Text(part.0)
                            .font(nunito(12.5, .bold))
                            .foregroundStyle(Color.gsFg)
                            .frame(width: 110, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.gsFill)
                                Capsule().fill(Color.gsPeach)
                                    .frame(width: geo.size.width * (part.1 / 20))
                            }
                        }
                        .frame(height: 6)
                        Text(String(format: "%.0f%%", part.1))
                            .font(nunito(11.5, .black))
                            .foregroundStyle(Color.gsMuted)
                            .frame(width: 34, alignment: .trailing)
                    }
                }
            }

            HStack(spacing: 7) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.gsAccentInk)
                Text("5 recipe matches ready to cook")
                    .font(nunito(12, .bold))
                    .foregroundStyle(Color.gsFg)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Color.gsFill)
            .clipShape(Capsule())
        }
        .padding(16)
        .background(Color.gsCard)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        .padding(.horizontal, 18)
        .offset(y: 82)
    }

    // Page 2 — the cook-mode step card, with its timer.
    private var cookCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Text("STEP 3 OF 7")
                    .font(nunito(10, .black))
                    .tracking(1.6)
                    .foregroundStyle(Color.gsDock)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Color.gsPeach)
                    .clipShape(Capsule())
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "timer").font(.system(size: 11, weight: .bold))
                    Text("6:00").font(nunito(13, .black))
                }
                .foregroundStyle(Color.gsFg)
            }
            Text("Sear the chicken 6–7 minutes a side, then rest it before slicing.")
                .font(nunito(15, .extrabold))
                .foregroundStyle(Color.gsFg)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 5) {
                ForEach(0..<7, id: \.self) { i in
                    Capsule()
                        .fill(i <= 2 ? Color.gsPeach : Color.gsFill)
                        .frame(height: 5)
                }
            }
        }
        .padding(16)
        .background(Color.gsCard)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        .padding(.horizontal, 18)
        .offset(y: 96)
    }

    // Page 3 — the week filling up, and the list that falls out of it.
    private var weekCard: some View {
        let days = ["M", "T", "W", "T", "F", "S", "S"]
        let planned = [true, true, false, true, true, false, false]
        return VStack(spacing: 12) {
            HStack {
                Text("This week")
                    .font(nunito(14, .extrabold))
                    .foregroundStyle(Color.gsFg)
                Spacer()
                Text("4 dinners")
                    .font(nunito(12, .bold))
                    .foregroundStyle(Color.gsMuted)
            }
            HStack(spacing: 6) {
                ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                    VStack(spacing: 5) {
                        Text(d)
                            .font(nunito(10.5, .black))
                            .foregroundStyle(planned[i] ? Color.gsDock : Color.gsMuted)
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(planned[i] ? Color.gsPeach : Color.gsFill)
                            .frame(height: 34)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "cart.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.gsAccentInk)
                Text("Shopping list · 12 items, sorted by aisle")
                    .font(nunito(12, .bold))
                    .foregroundStyle(Color.gsFg)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(Color.gsFill)
            .clipShape(Capsule())
        }
        .padding(16)
        .background(Color.gsCard)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        .padding(.horizontal, 18)
        .offset(y: 88)
    }
}
