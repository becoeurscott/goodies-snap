import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var social: SocialStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                HighlightStrip()
                    .padding(.top, 16)

                // Picks sit directly under the banner — the two most browsable things first.
                sectionHeader(
                    "Tonight's picks",
                    count: store.heroRecipes.count,
                    action: "See All"
                ) { store.go(to: .library) }
                .padding(.top, 20)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(store.heroRecipes) { r in
                            HeroCard(recipe: r)
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 12)
                }
                .padding(.horizontal, -2)
                .padding(.top, 2)

                WeekPlanCard(
                    planned: store.plannedCount,
                    total: AppStore.days.count,
                    dateLabel: store.todayLabel,
                    onCapture: { store.go(to: .importer) }
                )
                .padding(.top, 16)

                TonightCard(recipe: store.tonightsDinner)
                    .padding(.top, 12)

                ShoppingCard()
                    .padding(.top, 12)

                sectionHeader("Recently saved", count: nil, action: nil) {}
                    .padding(.top, 26)

                ForEach(store.recentlySaved) { r in
                    RecentRow(recipe: r)
                }

                if social.signedIn, social.posts.contains(where: { $0.recipe != nil }) {
                    sectionHeader("From the community", count: nil, action: "See All") { store.go(to: .feed) }
                        .padding(.top, 24)

                    ForEach(social.posts.filter { $0.recipe != nil }.prefix(2)) { post in
                        if let recipe = post.recipe {
                            RecentRow(recipe: recipe, subtitle: "by \(post.author_name) · ♥ \(post.like_count)")
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 116)
        }
        .background(Color.gsBg)
    }

    private var header: some View {
        HStack {
            IconButton(system: "calendar") { store.go(to: .plan) }
            Spacer()
            VStack(spacing: 1) {
                Text("goodiesSnap")
                    .font(nunito(15, .extrabold))
                Text(store.greeting)
                    .font(nunito(11, .semibold))
                    .foregroundStyle(Color.gsMuted)
            }
            Spacer()
            IconButton(system: "person", badge: false) { store.go(to: .profile) }
        }
    }

    private func sectionHeader(_ title: String, count: Int?, action: String?, onAction: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title)
                .font(nunito(19, .extrabold))
            if let count {
                Text("\(count)")
                    .font(nunito(10, .black))
                    .foregroundStyle(Color.gsFg)
                    .frame(width: 22, height: 22)
                    .background(Color.gsPeach)
                    .clipShape(Circle())
            }
            Spacer()
            if let action {
                Button(action: onAction) {
                    Text(action)
                        .font(nunito(13, .bold))
                        .foregroundStyle(Color.gsMuted)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Auto-scrolling highlights

/// One banner in the top-of-Home carousel.
struct Highlight: Identifiable {
    let id: String
    let kicker: String
    let title: String
    let subtitle: String
    let icon: String
    let cta: String
    /// Photo behind the banner. Recipe cards use their own image; the rest use a fixed shot.
    let image: URL?
    let action: (AppStore) -> Void

    /// Stock imagery for the banners that aren't backed by a saved recipe.
    static func stock(_ name: String) -> URL? {
        let map: [String: String] = [
            "plan": "https://images.unsplash.com/photo-1547592180-85f173990554?w=1000&q=80",
            "pro": "https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=1000&q=80",
            "shop": "https://images.unsplash.com/photo-1542838132-92c53300491e?w=1000&q=80",
            "save": "https://images.unsplash.com/photo-1466637574441-749b8f19452f?w=1000&q=80",
            "welcome": "https://images.unsplash.com/photo-1495521821757-a1efb6729352?w=1000&q=80",
        ]
        return map[name].flatMap(URL.init(string:))
    }
}

/// Highlight strip that advances on its own every few seconds, and stops as soon as the
/// user takes over by swiping — auto-advance that fights the reader is worse than none.
struct HighlightStrip: View {
    @EnvironmentObject var store: AppStore
    @State private var index = 0
    @State private var userTookOver = false

    private var items: [Highlight] {
        var out: [Highlight] = []

        // Time-limited offers lead — they're the only card with a deadline.
        if store.entitlement.welcomeOfferActive {
            out.append(Highlight(
                id: "welcome", kicker: "Welcome offer",
                title: "Plus for \(Promo.introPrice(for: .plus) ?? "")",
                subtitle: "Then \(Entitlement.Plan.plus.priceLabel)/mo · \(store.entitlement.welcomeCountdown)",
                icon: "gift.fill", cta: "Claim it",
                image: Highlight.stock("welcome"), action: { $0.showPaywall(.upgrade) }
            ))
        } else if store.entitlement.onProTrial {
            out.append(Highlight(
                id: "trial", kicker: "Pro trial", title: "Camera unlocked",
                subtitle: store.entitlement.trialCountdown,
                icon: "sparkles", cta: "Scan a dish",
                image: Highlight.stock("pro"), action: { $0.startPhotoScan() }
            ))
        }

        if let recipe = store.tonightsDinner {
            out.append(Highlight(
                id: "tonight", kicker: "Tonight's dinner", title: recipe.title,
                subtitle: "\(recipe.totalMinutes) min · serves \(recipe.servings)",
                icon: "moon.stars.fill", cta: "Open recipe",
                image: recipe.imageURL, action: { $0.open(recipe) }
            ))
        } else {
            out.append(Highlight(
                id: "plan", kicker: "Tonight", title: "Nothing planned yet",
                subtitle: "Pick a dinner for today", icon: "calendar", cta: "Choose one",
                image: Highlight.stock("plan"), action: { $0.openPicker(day: $0.todayName) }
            ))
        }

        if !store.canUseCamera {
            out.append(Highlight(
                id: "pro", kicker: "Go Pro", title: "Scan a dish with your camera",
                subtitle: "AI reads the plate",
                icon: "camera.viewfinder", cta: "See Pro",
                image: Highlight.stock("pro"), action: { $0.showPaywall(.cameraIsPro) }
            ))
        }

        if store.undoneCount > 0 {
            out.append(Highlight(
                id: "shop", kicker: "Shopping", title: "\(store.undoneCount) still to buy",
                subtitle: "\(store.shoppingDone) already ticked off",
                icon: "cart.fill", cta: "Open list",
                image: Highlight.stock("shop"), action: { $0.go(to: .shopping) }
            ))
        }

        out.append(Highlight(
            id: "save", kicker: "Save a recipe", title: "Paste a link or a video",
            subtitle: "\(store.quotaRemaining) AI save\(store.quotaRemaining == 1 ? "" : "s") left this month",
            icon: "wand.and.stars", cta: "Save one",
            image: Highlight.stock("save"), action: { $0.go(to: .importer) }
        ))

        return out
    }

    var body: some View {
        let cards = items
        VStack(spacing: 10) {
            TabView(selection: $index) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { i, item in
                    HighlightCard(item: item) { item.action(store) }
                        .padding(.horizontal, 2)
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 210)
            // A swipe is the user taking control — stop advancing under them.
            .simultaneousGesture(DragGesture().onChanged { _ in userTookOver = true })

            if cards.count > 1 {
                HStack(spacing: 6) {
                    ForEach(cards.indices, id: \.self) { i in
                        Capsule()
                            .fill(i == index ? Color.gsPeach : Color.gsFill)
                            .frame(width: i == index ? 18 : 6, height: 6)
                    }
                }
                .animation(AppStore.stepAnimation, value: index)
            }
        }
        .onAppear { index = min(index, max(0, cards.count - 1)) }
        .task {
            // Advance every 4s until the user swipes.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled, !userTookOver else { return }
                let count = items.count
                guard count > 1 else { continue }
                withAnimation(.easeInOut(duration: 0.5)) { index = (index + 1) % count }
            }
        }
    }
}

/// Full-bleed photo banner. Text sits on a bottom scrim so it stays legible over any image.
struct HighlightCard: View {
    let item: Highlight
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                CoverImage(url: item.image)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.05),
                        Color.black.opacity(0.45),
                        Color.black.opacity(0.82),
                    ],
                    startPoint: .top, endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 7) {
                        Image(systemName: item.icon)
                            .font(.system(size: 11, weight: .bold))
                        Text(item.kicker.uppercased())
                            .font(nunito(10, .black))
                            .tracking(1.4)
                    }
                    .foregroundStyle(Color.gsDock)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Color.gsPeach)
                    .clipShape(Capsule())

                    Text(item.title)
                        .font(nunito(23, .black))
                        .foregroundStyle(Color.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Text(item.subtitle)
                            .font(nunito(12.5, .semibold))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        HStack(spacing: 5) {
                            Text(item.cta).font(nunito(12.5, .extrabold))
                            Image(systemName: "arrow.right").font(.system(size: 10, weight: .black))
                        }
                        .foregroundStyle(Color.gsFg)
                        .padding(.horizontal, 13)
                        .frame(height: 32)
                        .background(Color.white)
                        .clipShape(Capsule())
                    }
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 8)
        }
        .buttonStyle(PressableStyle(scale: 0.985))
    }
}

// MARK: - Week plan card (the reference's arc card, repurposed)

/// Segmented arc = dinners planned this week. The bar beneath is the app's main action: capture a recipe with AI.
struct WeekPlanCard: View {
    @EnvironmentObject var store: AppStore
    let planned: Int
    let total: Int
    let dateLabel: String
    let onCapture: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                CalorieArc(progress: total > 0 ? Double(planned) / Double(total) : 0, segments: total)
                    .frame(height: 178)
                VStack(spacing: 3) {
                    Image(systemName: "fork.knife")
                        .foregroundStyle(Color.gsAccentInk)
                        .font(.system(size: 15, weight: .bold))
                    Text(dateLabel)
                        .font(nunito(13, .bold))
                        .foregroundStyle(Color.gsMuted)
                    Text(verbatim: "\(planned) of \(total)")
                        .font(nunito(32, .black))
                    Text(planned >= total ? "week fully planned" : "dinners planned")
                        .font(nunito(13, .extrabold))
                        .foregroundStyle(Color.gsAccentInk)
                }
                .padding(.top, 40)
            }
            .contentShape(Rectangle())
            .onTapGesture { store.go(to: .plan) }

            Button(action: onCapture) {
                HStack(spacing: 12) {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 18, weight: .bold))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Save a recipe with AI")
                            .font(nunito(15, .extrabold))
                        Text("Photo · Link · Video · Text")
                            .font(nunito(11, .semibold))
                            .foregroundStyle(Color.gsMuted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.gsMuted)
                }
                .foregroundStyle(Color.gsFg)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(Color.gsFill)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(PressableStyle(scale: 0.98))
            .padding(.top, 8)
        }
        .padding(18)
        .softCard(radius: 28)
    }
}

/// Segmented half-ring of rounded blocks, filled peach up to `progress`.
struct CalorieArc: View {
    let progress: Double
    var segments: Int = 11

    var body: some View {
        let count = max(segments, 2)
        let filled = Int((min(max(progress, 0), 1) * Double(count)).rounded(.up))
        let step = 180.0 / Double(count)
        let width: CGFloat = count <= 7 ? 54 : 44
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(i < filled ? Color.gsPeach : Color.gsFill)
                    .frame(width: width, height: 58)
                    .offset(y: -106)
                    .rotationEffect(.degrees(-90 + step / 2 + Double(i) * step))
            }
        }
        .frame(height: 178)
        .offset(y: 78)
        .animation(AppStore.pushAnimation, value: filled)
    }
}

// MARK: - Tonight's dinner card

struct TonightCard: View {
    @EnvironmentObject var store: AppStore
    let recipe: Recipe?

    var body: some View {
        if let recipe {
            Button { store.open(recipe) } label: {
                VStack(spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        CoverImage(url: recipe.imageURL)
                            .frame(width: 58, height: 58)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tonight's dinner")
                                .font(nunito(15, .extrabold))
                            Text(recipe.title)
                                .font(nunito(12.5, .semibold))
                                .foregroundStyle(Color.gsMuted)
                                .lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(recipe.totalMinutes) min")
                                .font(nunito(20, .extrabold))
                            Text(recipe.cuisine)
                                .font(nunito(12, .bold))
                                .foregroundStyle(Color.gsAccentInk)
                        }
                    }
                    HStack(alignment: .bottom, spacing: 22) {
                        stat("Serves", "\(recipe.servings)")
                        stat("Steps", "\(recipe.steps.count)")
                        stat("Ingredients", "\(recipe.ingredients.count)")
                        Spacer()
                        Button {
                            store.selId = recipe.id
                            store.cookStep = 0
                            store.go(to: .cook)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "play.fill").font(.system(size: 11, weight: .bold))
                                Text("Cook").font(nunito(13, .extrabold))
                            }
                            .foregroundStyle(Color.gsDock)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 36)
                        }
                        .buttonStyle(PeachButtonStyle())
                    }
                }
                .padding(16)
                .softCard(radius: 22)
            }
            .buttonStyle(PressableStyle())
        } else {
            Button { store.openPicker(day: store.todayName) } label: {
                HStack(spacing: 14) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.gsAccentInk)
                        .frame(width: 58, height: 58)
                        .background(Color.gsPeachSoft)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nothing planned for tonight")
                            .font(nunito(15, .extrabold))
                        Text("Pick a dinner from your recipes")
                            .font(nunito(12.5, .semibold))
                            .foregroundStyle(Color.gsMuted)
                    }
                    Spacer()
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.gsDock)
                        .frame(width: 40, height: 40)
                        .background(Color.gsPeach)
                        .clipShape(Circle())
                }
                .padding(16)
                .softCard(radius: 22)
            }
            .buttonStyle(PressableStyle())
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(nunito(12, .semibold))
                .foregroundStyle(Color.gsMuted)
            Text(value)
                .font(nunito(14, .extrabold))
        }
    }
}

// MARK: - Shopping card

struct ShoppingCard: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        Button { store.go(to: .shopping) } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(Color.gsFill, lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: store.shopping.isEmpty ? 0 : CGFloat(store.shoppingDone) / CGFloat(store.shopping.count))
                        .stroke(Color.gsPeach, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "cart.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.gsFg)
                }
                .frame(width: 58, height: 58)
                .animation(AppStore.stepAnimation, value: store.shoppingDone)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Shopping list")
                        .font(nunito(15, .extrabold))
                    Text(store.shopping.isEmpty
                         ? "Empty — add a recipe's ingredients"
                         : "\(store.undoneCount) to buy · \(store.shoppingDone) done")
                        .font(nunito(12.5, .semibold))
                        .foregroundStyle(Color.gsMuted)
                        .lineLimit(1)
                }
                Spacer()
                if !store.shopping.isEmpty {
                    Text("\(store.undoneCount)")
                        .font(nunito(20, .extrabold))
                        .foregroundStyle(Color.gsAccentInk)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.gsMuted)
            }
            .padding(16)
            .softCard(radius: 22)
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Recipe cards

struct HeroCard: View {
    @EnvironmentObject var store: AppStore
    let recipe: Recipe

    var body: some View {
        Button { store.open(recipe) } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recipe.title)
                            .font(nunito(15.5, .extrabold))
                            .lineLimit(1)
                        HStack(spacing: 5) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.gsAccentInk)
                            Text("\(recipe.totalMinutes) min · \(recipe.cuisine)")
                                .font(nunito(12, .semibold))
                                .foregroundStyle(Color.gsMuted)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Image(systemName: recipe.favorite ? "star.fill" : "star")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(recipe.favorite ? Color.gsPeach : Color.gsFg)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                CoverImage(url: recipe.imageURL)
                    .frame(width: 176, height: 176)
                    .clipShape(Circle())
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)

                HStack(alignment: .center, spacing: 8) {
                    Text(recipe.difficultyLabel)
                        .font(nunito(13, .semibold))
                        .foregroundStyle(Color.gsMuted)
                    DifficultyBars(filled: recipe.difficultyBars)
                    Rectangle().fill(Color.gsFill).frame(width: 1, height: 22)
                    Spacer()
                    Text("Serves \(recipe.servings)")
                        .font(nunito(15, .extrabold))
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 16)
            }
            .frame(width: 236)
            .softCard(radius: 26)
        }
        .buttonStyle(PressableStyle())
    }
}

struct TimeBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(nunito(11, .extrabold))
            .foregroundStyle(Color.gsFg)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.gsCard.opacity(0.92))
            .clipShape(Capsule())
    }
}

struct RecentRow: View {
    @EnvironmentObject var store: AppStore
    let recipe: Recipe
    var subtitle: String? = nil

    var body: some View {
        Button { store.open(recipe) } label: {
            HStack(spacing: 14) {
                CoverImage(url: recipe.imageURL)
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(recipe.title)
                        .font(nunito(15, .extrabold))
                        .lineLimit(1)
                    Text(subtitle ?? "\(recipe.totalMinutes) min · \(recipe.cuisine) · from \(recipe.source)")
                        .font(nunito(11.5, .semibold))
                        .foregroundStyle(Color.gsMuted)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.gsMuted)
            }
            .padding(12)
            .softCard(radius: 20)
        }
        .buttonStyle(PressableStyle())
        .padding(.top, 10)
    }
}
