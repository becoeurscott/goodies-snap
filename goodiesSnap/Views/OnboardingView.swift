import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var store: AppStore

    struct Page {
        let kicker: String
        /// Headline split into runs so weight can shift mid-sentence, like the reference.
        let title: [TitleRun]
        let body: String
        let img: String
        /// Lightweight labels that float over the photo (position is normalized 0…1).
        let tags: [FloatingTag]
    }

    struct TitleRun: Hashable {
        let text: String
        let strong: Bool
    }

    struct FloatingTag: Hashable {
        let text: String
        let x: CGFloat
        let y: CGFloat
    }

    static let pages: [Page] = [
        Page(kicker: "SNAP & SAVE",
             title: [TitleRun(text: "Any recipe, ", strong: false),
                     TitleRun(text: "decoded by AI", strong: true)],
             body: "Snap a dish, paste a link or a video — the AI reads it and writes you a clean recipe card.",
             img: "https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=1200&h=1500&fit=crop&q=80",
             tags: [FloatingTag(text: "Grilled tofu", x: 0.28, y: 0.52),
                    FloatingTag(text: "Romaine", x: 0.7, y: 0.66)]),
        Page(kicker: "COOK HANDS-FREE",
             title: [TitleRun(text: "Step by step, ", strong: false),
                     TitleRun(text: "no mess", strong: true)],
             body: "One generous step at a time, timers built in — no scrolling back with sticky fingers.",
             img: "https://images.unsplash.com/photo-1556910103-1c02745aae4d?w=1200&h=1500&fit=crop&q=80",
             tags: [FloatingTag(text: "Step 3 of 7", x: 0.32, y: 0.5),
                    FloatingTag(text: "6:00 timer", x: 0.72, y: 0.62)]),
        Page(kicker: "PLAN THE WEEK",
             title: [TitleRun(text: "Shop ", strong: false),
                     TitleRun(text: "once", strong: true)],
             body: "Drop dinners onto your week and the shopping list writes itself, sorted by aisle.",
             img: "https://images.unsplash.com/photo-1540420773420-3366772f4999?w=1200&h=1500&fit=crop&q=80",
             tags: [FloatingTag(text: "4 dinners", x: 0.3, y: 0.54),
                    FloatingTag(text: "12 items", x: 0.71, y: 0.64)]),
    ]

    private var isLast: Bool { store.obIndex == Self.pages.count - 1 }

    /// Drives the paged TabView. The swipe sets it directly (the page style animates the
    /// drag itself); the Continue button routes through `onboardNext` for the last-page exit.
    private var selection: Binding<Int> {
        // No `withAnimation` here: a paged TabView already animates the page under the finger,
        // and wrapping the write layers a second animation on top of it, which reads as a hitch.
        Binding(get: { store.obIndex }, set: { store.obIndex = $0 })
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.gsBg.ignoresSafeArea()

            GeometryReader { geo in
                let imgHeight = geo.size.height * 0.60
                TabView(selection: selection) {
                    ForEach(Array(Self.pages.enumerated()), id: \.offset) { i, page in
                        pageContent(page, width: geo.size.width, imgHeight: imgHeight)
                            .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                // On the last slide the paged TabView has nowhere left to go, so a swipe there
                // does nothing and the flow feels stuck. Carry that swipe out of onboarding,
                // which is what "keep swiping forward" is asking for.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 24)
                        .onEnded { value in
                            guard isLast else { return }
                            let horizontal = abs(value.translation.width) > abs(value.translation.height)
                            let leftward = value.translation.width < -60
                                || value.predictedEndTranslation.width < -140
                            if horizontal && leftward { store.onboardNext() }
                        }
                )
            }
            .ignoresSafeArea()

            // Fixed chrome that does not slide with the pages.
            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomBar
            }
        }
    }

    // MARK: - A single page (image + copy), slides horizontally

    private func pageContent(_ page: Page, width: CGFloat, imgHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CoverImage(url: URL(string: page.img))
                .frame(width: width, height: imgHeight)
                .clipped()
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [.clear, .clear, Color.gsBg.opacity(0.85), Color.gsBg],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: imgHeight * 0.5)
                }
                .overlay {
                    ForEach(page.tags, id: \.self) { tag in
                        tagChip(tag.text)
                            .position(x: width * tag.x, y: imgHeight * tag.y)
                    }
                }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 0) {
                Text(page.kicker)
                    .font(nunito(11, .black))
                    .tracking(2.4)
                    .foregroundStyle(Color.gsAccentInk)

                titleText(page.title)
                    .padding(.top, 10)

                Text(page.body)
                    .font(nunito(14.5, .semibold))
                    .foregroundStyle(Color.gsMuted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                    .frame(maxWidth: 340, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            // Clear the fixed bottom bar (dots + Continue) plus the home indicator.
            .padding(.bottom, 150)
        }
    }

    // MARK: - Pieces

    private func titleText(_ runs: [TitleRun]) -> some View {
        runs.reduce(Text("")) { acc, run in
            acc + Text(run.text)
                .font(nunito(34, run.strong ? .black : .regular))
                .foregroundColor(Color.gsFg)
        }
        .tracking(-0.5)
        .lineSpacing(2)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// A translucent label that floats over the photo, echoing the scan overlay.
    private func tagChip(_ text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(Color.gsPeach).frame(width: 6, height: 6)
            Text(text)
                .font(nunito(12, .extrabold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
        .environment(\.colorScheme, .dark)
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
    }

    private var topBar: some View {
        HStack {
            Spacer()
            Button { store.skipOnboard() } label: {
                Text("Skip")
                    .font(nunito(13, .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 34)
                    .background(.ultraThinMaterial, in: Capsule())
                    .environment(\.colorScheme, .dark)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
        .padding(.horizontal, 20)
    }

    private var bottomBar: some View {
        HStack(alignment: .center) {
            progressDots
            Spacer()
            Button {
                Haptics.tap(.light)
                store.onboardNext()
            } label: {
                HStack(spacing: 10) {
                    Text(isLast ? "Get started" : "Continue")
                        .font(nunito(15, .extrabold))
                    Image(systemName: isLast ? "arrow.right" : "chevron.right")
                        .font(.system(size: 12, weight: .black))
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 26)
                .frame(minHeight: 56)
            }
            .buttonStyle(DarkButtonStyle())
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 28)
    }

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<Self.pages.count, id: \.self) { i in
                Capsule()
                    .fill(i == store.obIndex ? Color.gsFg : Color.gsFg.opacity(0.15))
                    .frame(width: i == store.obIndex ? 22 : 7, height: 7)
            }
        }
        .animation(AppStore.stepAnimation, value: store.obIndex)
    }
}
