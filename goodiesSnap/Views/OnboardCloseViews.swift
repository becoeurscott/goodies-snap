import SwiftUI

// Steps 14–17: count up what just happened, introduce the community now that there's a
// reason to care about it, show the whole system on one screen, and tease the camera.

// MARK: - 14. What we just did

struct OBValueSummaryView: View {
    @EnvironmentObject var store: AppStore

    private var dinners: Int { max(1, store.onboard.plannedWeek.count) }
    private var listCount: Int { store.shopping.filter { !$0.alreadyHave }.count }

    private var headline: String {
        switch store.onboard.source {
        case .video: return "From one video\nto a week of food"
        case .photo: return "From one photo\nto a week of food"
        case .surprise: return "From one recipe\nto a week of food"
        }
    }

    var body: some View {
        OBHeroPage(
            kicker: "Here's what we just did",
            title: headline
        ) {
            VStack(alignment: .leading, spacing: 0) {
                OBBigStat(value: "\(dinners)",
                          label: dinners == 1 ? "dinner planned and saved" : "dinners planned and saved",
                          onGradient: true)
                OBBigStat(value: "\(listCount)",
                          label: "items on one shopping list", onGradient: true)
                if store.onboard.weekSharedCount > 0 {
                    OBBigStat(value: "\(store.onboard.weekSharedCount)",
                              label: "ingredients reused across meals", onGradient: true)
                }
                if let week = store.onboardWeekCost {
                    OBBigStat(value: store.formatPrice(week.cents),
                              label: "estimated for the week", onGradient: true)
                }

                Text("Less food waste. Less planning.\nFewer random trips to the shop.")
                    .font(nunito(18, .extrabold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 26)

                Text("All of it is already saved on this device.")
                    .font(nunito(13, .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.top, 8)
            }
        } action: {
            OBLightPrimary(title: "Continue") { store.onboardNextStep() }
        }
    }
}

// MARK: - 15. Community

struct OBCommunityView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var social: SocialStore

    /// Real recipes other people have shared. Empty early in the app's life, which is fine —
    /// the screen falls back to the catalog rather than inventing save counts. Fabricated
    /// social proof is the one thing that would make everything else on screen suspect.
    @State private var popular: [Recipe] = []
    @State private var loading = true

    private var showcase: [Recipe] {
        popular.isEmpty ? Array(store.catalog.prefix(4)) : Array(popular.prefix(4))
    }

    var body: some View {
        OBPage(
            kicker: "You're not the only one cooking",
            title: popular.isEmpty ? "There's a community\ninside the app" : "Cooking right now",
            subtitle: popular.isEmpty
                ? "People share the recipes they've imported, what they cost and how they went."
                : "Recipes people here have shared this week."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if loading && showcase.isEmpty {
                    ProgressView().tint(Color.gsAccentInk)
                        .frame(maxWidth: .infinity).padding(.vertical, 40)
                } else {
                    ForEach(showcase, id: \.id) { recipe in
                        OBRecipeCard(recipe: recipe)
                    }
                }

                Text("Share a recipe, post what you cooked, or just watch. It's all in the Community tab.")
                    .font(nunito(13.5, .semibold))
                    .foregroundStyle(Color.gsMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
        } action: {
            OBPrimary(title: "Continue") { store.onboardNextStep() }
        }
        .task {
            defer { loading = false }
            if let token = store.aiToken,
               let rows = try? await SocialAPI.popularRecipes(token: token, limit: 6) {
                popular = rows
            }
            if store.catalog.count < 4, let rows = try? await CatalogService.fetch(limit: 24) {
                store.catalog = rows.map(\.recipe)
            }
        }
    }
}

// MARK: - 16. The whole system

struct OBFoodSystemView: View {
    @EnvironmentObject var store: AppStore

    private var listCount: Int { store.shopping.filter { !$0.alreadyHave }.count }

    var body: some View {
        OBPage(
            kicker: "You came for one recipe",
            title: "You built a\nfood system"
        ) {
            VStack(alignment: .leading, spacing: 0) {
                OBBigStat(value: "\(store.recipes.count)", label: "recipes saved")
                OBBigStat(value: store.plannedCount == 0 ? "—" : "\(store.plannedCount)",
                          label: store.plannedCount == 1 ? "day planned" : "days planned")
                OBBigStat(value: "\(listCount)", label: "items on your shopping list")
                OBBigStat(value: store.cartTotal.map { store.formatPrice($0.cents) } ?? "—",
                          label: "estimated to buy it all")

                OBEstimateNote(store: store.onboard.store)
                    .padding(.top, 20)
            }
        } action: {
            OBPrimary(title: "Continue") { store.onboardNextStep() }
        }
    }
}

// MARK: - 17. Snap teaser

struct OBSnapTeaserView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        OBPage(
            kicker: "One more thing",
            title: "Next time, you don't\neven need a link",
            subtitle: "Point the camera at a plate — anywhere — and we'll work out what it is and what's in it."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(LinearGradient(colors: [.gsBrandTop, .gsBrandBottom],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(height: 185)
                    Text("See food.\nSnap.\nShop.")
                        .font(nunito(30, .black))
                        .tracking(-0.9)
                        .foregroundStyle(.white)
                        .padding(24)
                }

                VStack(alignment: .leading, spacing: 10) {
                    step("1", "Snap the dish")
                    step("2", "We name it and list what's in it")
                    step("3", "It goes straight onto your shopping list, priced")
                }
            }
        } action: {
            OBPrimary(title: "Save my food system  →") { store.finishOnboarding() }
        }
    }

    private func step(_ number: String, _ text: String) -> some View {
        HStack(spacing: 11) {
            Text(number)
                .font(nunito(13, .black))
                .foregroundStyle(Color.gsBrandBottom)
                .frame(width: 22, alignment: .leading)
            Text(text)
                .font(nunito(13.5, .semibold))
                .foregroundStyle(Color.gsFg)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
