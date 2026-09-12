import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var store: AppStore

    struct Page {
        let emoji: String
        let title: String
        let subtitle: String
        let bgColor: Color
    }

    static let pages: [Page] = [
        Page(emoji: "🍔🍟🥤🍕",
             title: "Save Your Favorite\nRecipes Instantly",
             subtitle: "Snap a dish, paste a link or a video —\nthe AI reads it and saves a clean recipe card.",
             bgColor: Color(hex: 0xFFF3E0)),
        Page(emoji: "👨‍🍳🍳📖✨",
             title: "Cook Step by Step\nHands-Free",
             subtitle: "One generous step at a time, timers built in —\nno scrolling back with sticky fingers.",
             bgColor: Color(hex: 0xFFF8E1)),
        Page(emoji: "📋🛒📅⭐",
             title: "Plan Your Week &\nShop Smart",
             subtitle: "Drop dinners onto your week and the\nshopping list writes itself, sorted by aisle.",
             bgColor: Color(hex: 0xFFF3E0)),
    ]

    private var isLast: Bool { store.obIndex == Self.pages.count - 1 }

    private var selection: Binding<Int> {
        Binding(get: { store.obIndex }, set: { store.obIndex = $0 })
    }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar: back + skip
                HStack {
                    if store.obIndex > 0 {
                        Button {
                            withAnimation(.easeOut(duration: 0.3)) { store.obIndex -= 1 }
                        } label: {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.black)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    Button { store.skipOnboard() } label: {
                        Text("Skip")
                            .font(nunito(14, .semibold))
                            .foregroundStyle(.black.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
                .frame(height: 44)
                .padding(.horizontal, 24)
                .padding(.top, 8)

                // Paged content
                TabView(selection: selection) {
                    ForEach(Array(Self.pages.enumerated()), id: \.offset) { i, page in
                        pageContent(page)
                            .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
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

                // Bottom: dots + next button
                HStack {
                    progressDots
                    Spacer()
                    Button {
                        Haptics.tap(.light)
                        store.onboardNext()
                    } label: {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 56, height: 56)
                            .background(Color(hex: 0xFDE604))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 32)
            }
        }
    }

    private func pageContent(_ page: Page) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)

            // Illustration circle
            ZStack {
                Circle()
                    .fill(page.bgColor)
                    .frame(width: 220, height: 220)
                Text(page.emoji)
                    .font(.system(size: 52))
            }
            .padding(.bottom, 40)

            // Title
            Text(page.title)
                .font(nunito(26, .black))
                .foregroundStyle(.black)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 32)
                .padding(.bottom, 14)

            // Subtitle
            Text(page.subtitle)
                .font(nunito(14, .regular))
                .foregroundStyle(.black.opacity(0.45))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 40)

            Spacer(minLength: 20)
        }
    }

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<Self.pages.count, id: \.self) { i in
                Capsule()
                    .fill(i == store.obIndex ? Color(hex: 0xFDE604) : Color.black.opacity(0.12))
                    .frame(width: i == store.obIndex ? 22 : 7, height: 7)
            }
        }
        .animation(AppStore.stepAnimation, value: store.obIndex)
    }
}
