import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var store: AppStore

    enum Tab: String, CaseIterable { case discover = "Discover", saved = "Saved" }
    @State private var tab: Tab = .discover
    @State private var page = 0
    @State private var showFilter = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let grid = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
    /// Drives the carousel auto-advance.
    private let autoScroll = Timer.publish(every: 3.5, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                titleRow
                searchBar.padding(.top, 14)
                segmented.padding(.top, 14)

                if tab == .discover {
                    discoverContent
                } else {
                    savedContent
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 116)
        }
        .background(Color.gsBg)
        .scrollDismissesKeyboard(.interactively)
        .task {
            // Fill the catalog the first time the Recipes tab is shown.
            if store.catalog.isEmpty { await store.loadCatalog(reset: true) }
            if store.catalogCuisines.isEmpty {
                store.catalogCuisines = (try? await CatalogService.cuisines()) ?? []
            }
            if store.catalogCategories.isEmpty {
                store.catalogCategories = (try? await CatalogService.categories()) ?? []
            }
            await store.loadPopular()
        }
    }

    // MARK: Shared chrome

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Recipes").font(nunito(29, .black))
            Spacer()
            IconButton(system: "bell", badge: store.undoneCount > 0) { store.openProfile() }
                .frame(width: 46, height: 46)
        }
    }

    /// One search field, wired to whichever tab is showing.
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.gsFg)
            if tab == .discover {
                TextField("", text: $store.catalogSearch,
                          prompt: Text("Search thousands of recipes").foregroundStyle(Color.gsMuted))
                    .font(nunito(15, .semibold))
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { store.searchCatalog() }
                if !store.catalogSearch.isEmpty {
                    clearButton { store.catalogSearch = ""; store.searchCatalog() }
                }
            } else {
                TextField("", text: $store.search,
                          prompt: Text("Search your recipes").foregroundStyle(Color.gsMuted))
                    .font(nunito(15, .semibold))
                    .autocorrectionDisabled()
                if !store.search.isEmpty { clearButton { store.search = "" } }
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
        .softCard(radius: 18)
    }

    private func clearButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill").foregroundStyle(Color.gsMuted)
        }
        .buttonStyle(.plain)
    }

    private var segmented: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { t in
                Button {
                    Haptics.tap(.light)
                    withAnimation(AppStore.stepAnimation) { tab = t }
                } label: {
                    HStack(spacing: 6) {
                        Text(t.rawValue)
                        if t == .saved, !store.recipes.isEmpty {
                            Text("\(store.recipes.count)")
                                .font(nunito(10, .black))
                                .foregroundStyle(tab == t ? Color.gsDock : Color.gsMuted)
                        }
                    }
                    .font(nunito(13.5, .extrabold))
                    .foregroundStyle(tab == t ? Color.white : Color.gsMuted)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(tab == t ? Color.gsDock : Color.clear)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.gsFill)
        .clipShape(Capsule())
    }

    // MARK: Discover (catalog API)

    @ViewBuilder
    private var discoverContent: some View {
        cuisineChips.padding(.top, 16)

        if store.catalog.isEmpty && store.catalogLoading {
            loading
        } else if store.catalog.isEmpty {
            emptyMessage("Nothing here yet — try another cuisine or search.")
        } else {
            // Popular carousel: only on the unfiltered default view, above the grid.
            if store.catalogSearch.isEmpty, store.catalogCuisine == nil, !popularItems.isEmpty {
                popularCarousel.padding(.top, 20)
            }

            LazyVGrid(columns: grid, spacing: 14) {
                ForEach(gridItems) { recipe in
                    CatalogCard(recipe: recipe)
                        .onAppear {
                            if recipe.id == store.catalog.last?.id {
                                Task { await store.loadCatalog(reset: false) }
                            }
                        }
                }
            }
            .padding(.top, 16)

            if store.catalogLoading {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
            }

            Text("Recipes via TheMealDB")
                .font(nunito(10.5, .semibold))
                .foregroundStyle(Color.gsMuted)
                .frame(maxWidth: .infinity)
                .padding(.top, 22)
        }
    }

    /// The grid shows the full catalog; the carousel is a separate spotlight above it.
    private var gridItems: [Recipe] { store.catalog }

    /// What the carousel shows: the community's most-cooked recipes when we have them,
    /// otherwise a handful of featured catalog dishes so it's never empty (cold-start).
    private var popularItems: [Recipe] {
        store.popular.isEmpty ? Array(store.catalog.prefix(10)) : store.popular
    }

    /// True once real community popularity data is driving the carousel.
    private var popularIsReal: Bool { !store.popular.isEmpty }

    /// A short rotation for the single-card carousel.
    private var carouselItems: [Recipe] { Array(popularItems.prefix(6)) }

    /// One square card that auto-scrolls through the popular/featured recipes.
    private var popularCarousel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.gsPeach)
                Text(popularIsReal ? "Popular right now" : "Featured recipes")
                    .font(nunito(18, .black))
                Spacer()
            }

            TabView(selection: $page) {
                ForEach(Array(carouselItems.enumerated()), id: \.element.id) { i, recipe in
                    PopularBanner(recipe: recipe, rank: popularIsReal ? i + 1 : nil)
                        .padding(.horizontal, 2)
                        .tag(i)
                }
            }
            .frame(height: 200)
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onReceive(autoScroll) { _ in
                guard carouselItems.count > 1, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.6)) {
                    page = (page + 1) % carouselItems.count
                }
            }
            .onChange(of: carouselItems.count) { _, n in
                if page >= n { page = 0 }   // keep the selection valid if the list changes
            }

            // Page dots.
            if carouselItems.count > 1 {
                HStack(spacing: 6) {
                    ForEach(carouselItems.indices, id: \.self) { i in
                        Capsule()
                            .fill(i == page ? Color.gsFg : Color.gsFg.opacity(0.18))
                            .frame(width: i == page ? 16 : 6, height: 6)
                            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: page)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var cuisineChips: some View {
        HStack(spacing: 8) {
            // Opens the full filter — search by name, country and food type together.
            Button { showFilter = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 13, weight: .bold))
                    if store.catalogFilterActive {
                        Circle().fill(Color.gsPeach).frame(width: 7, height: 7)
                    }
                }
                .foregroundStyle(Color.gsFg)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(Color.gsCard)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Color.gsFg.opacity(0.1), lineWidth: 1))
            }
            .buttonStyle(PressableStyle(scale: 0.95))
            .accessibilityLabel("Filter recipes")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    pill("All", active: !store.catalogFilterActive) { store.clearCatalogFilters() }
                    ForEach(Array(store.catalogCategory).sorted(), id: \.self) { food in
                        pill(food, active: true) { store.setCatalogCategory(food) }
                    }
                    ForEach(Array(store.catalogCuisine).sorted(), id: \.self) { sel in
                        pill(sel, active: true) { store.setCatalogCuisine(sel) }
                    }
                    ForEach(store.catalogCuisines.filter { !store.catalogCuisine.contains($0) }, id: \.self) { c in
                        pill(c, active: false) { store.setCatalogCuisine(c) }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .sheet(isPresented: $showFilter) {
            RecipeFilterSheet().environmentObject(store)
        }
    }

    private func pill(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap(.light)
            action()
        } label: {
            Text(label)
                .font(nunito(13, active ? .extrabold : .semibold))
                .foregroundStyle(active ? Color.white : Color.gsFg)
                .padding(.horizontal, 16)
                .frame(height: 38)
                .background(active ? Color.gsDock : Color.gsCard)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Color.gsFg.opacity(active ? 0 : 0.1), lineWidth: 1))
        }
        .buttonStyle(PressableStyle(scale: 0.95))
    }

    // MARK: Saved (my recipes)

    @ViewBuilder
    private var savedContent: some View {
        if store.recipes.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "bookmark")
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(Color.gsMuted)
                    .padding(.bottom, 4)
                Text("No saved recipes yet")
                    .font(nunito(19, .extrabold))
                Text("Tap a recipe in Discover to save it, or import one with AI.")
                    .font(nunito(13, .semibold))
                    .foregroundStyle(Color.gsMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button { withAnimation(AppStore.stepAnimation) { tab = .discover } } label: {
                    Text("Browse Discover")
                        .font(nunito(13.5, .extrabold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 20)
                        .frame(minHeight: 46)
                }
                .buttonStyle(DarkButtonStyle())
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 44)
            .padding(.horizontal, 24)
        } else {
            // Icon pills for the category filter — lighter than the old square tiles.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.chipNames, id: \.self) { name in
                        savedChip(name)
                    }
                }
                .padding(.horizontal, 2)
            }
            .padding(.horizontal, -2)
            .padding(.top, 16)

            HStack(spacing: 6) {
                Text(store.chip == "All" ? "All recipes" : store.chip)
                    .font(nunito(13, .extrabold))
                Text("· \(store.filtered.count)")
                    .font(nunito(13, .bold))
                    .foregroundStyle(Color.gsMuted)
                Spacer()
                filtersButton
            }
            .padding(.top, 16)

            if store.filtered.isEmpty {
                emptyMessage("Nothing matches — try another ingredient or title.")
            } else {
                VStack(spacing: 12) {
                    ForEach(store.filtered) { r in
                        SavedCard(recipe: r)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.top, 12)
                .animation(AppStore.lateralAnimation, value: store.filtered)
            }
        }
    }

    /// Opens the filter sheet (cooking time, difficulty, calories). Badges the active count.
    private var filtersButton: some View {
        Button {
            Haptics.tap(.light)
            store.showFilters = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .bold))
                Text("Filters").font(nunito(13, .extrabold))
                if store.activeFilterCount > 0 {
                    Text("\(store.activeFilterCount)")
                        .font(nunito(11, .black))
                        .foregroundStyle(Color.white)
                        .frame(width: 18, height: 18)
                        .background(Color.gsDock)
                        .clipShape(Circle())
                }
            }
            .foregroundStyle(Color.gsFg)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Color.gsCard)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.gsFg.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(PressableStyle(scale: 0.95))
        .sheet(isPresented: $store.showFilters) {
            FilterSheet().environmentObject(store)
        }
    }

    /// Compact category pill with a leading icon, used in the Saved filter row.
    private func savedChip(_ name: String) -> some View {
        let active = store.chip == name
        return Button {
            Haptics.tap(.light)
            withAnimation(AppStore.lateralAnimation) { store.chip = name }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: CategoryChip.symbol(for: name))
                    .font(.system(size: 12, weight: .bold))
                Text(name).font(nunito(13, active ? .extrabold : .semibold))
            }
            .foregroundStyle(active ? Color.white : Color.gsFg)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(active ? Color.gsDock : Color.gsCard)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.gsFg.opacity(active ? 0 : 0.1), lineWidth: 1))
        }
        .buttonStyle(PressableStyle(scale: 0.95))
    }

    // MARK: Bits

    private var loading: some View {
        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 60)
    }

    private func emptyMessage(_ text: String) -> some View {
        Text(text)
            .font(nunito(13, .semibold))
            .foregroundStyle(Color.gsMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)
            .padding(.horizontal, 20)
    }
}

/// The full-width banner shown one-at-a-time in the auto-scrolling popular carousel.
struct PopularBanner: View {
    @EnvironmentObject var store: AppStore
    let recipe: Recipe
    /// 1-based rank when driven by real community data; nil for the featured fallback.
    var rank: Int?

    private var saved: Bool { store.isInLibrary(recipe.id) }

    var body: some View {
        Button { store.openCatalogRecipe(recipe) } label: {
            ZStack(alignment: .bottomLeading) {
                CoverImage(url: recipe.imageURL)
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipped()

                LinearGradient(colors: [.clear, .black.opacity(0.78)],
                               startPoint: .center, endPoint: .bottom)

                VStack {
                    HStack {
                        if let rank {
                            Text("#\(rank) this week")
                                .font(nunito(11, .black))
                                .foregroundStyle(Color.gsDock)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Color.gsPeach)
                                .clipShape(Capsule())
                        }
                        Spacer()
                        if saved {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white, Color.gsPeach)
                        }
                    }
                    Spacer()
                }
                .padding(14)

                VStack(alignment: .leading, spacing: 3) {
                    Text(recipe.title)
                        .font(nunito(20, .black))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(recipe.cuisine)
                        .font(nunito(12.5, .bold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.1), radius: 14, y: 7)
        }
        .buttonStyle(PressableStyle(scale: 0.98))
    }
}

/// A large spotlight card for the top catalog recipe — full-width photo with a gradient
/// scrim and the title/cuisine over it. (Kept for reuse; the tab now uses PopularCard.)
struct FeaturedCard: View {
    @EnvironmentObject var store: AppStore
    let recipe: Recipe

    var body: some View {
        Button { store.openCatalogRecipe(recipe) } label: {
            ZStack(alignment: .bottomLeading) {
                CoverImage(url: recipe.imageURL)
                    .frame(height: 210)
                    .frame(maxWidth: .infinity)
                    .clipped()

                LinearGradient(colors: [.clear, .black.opacity(0.72)],
                               startPoint: .center, endPoint: .bottom)

                VStack(alignment: .leading, spacing: 4) {
                    Text("FEATURED")
                        .font(nunito(10, .black))
                        .tracking(1.5)
                        .foregroundStyle(Color.gsDock)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.gsPeach)
                        .clipShape(Capsule())
                    Text(recipe.title)
                        .font(nunito(20, .black))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(recipe.cuisine)
                        .font(nunito(12.5, .bold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.1), radius: 16, y: 8)
        }
        .buttonStyle(PressableStyle(scale: 0.98))
    }
}

/// Category tile ("All / Favorites / each cuisine").
///
/// Uses SF Symbols rather than emoji: emoji are a font the system owns, so they ignore
/// the app's palette, redraw differently per iOS version, and carry no accessibility
/// label a screen reader can use. Symbols inherit tint, weight and Dynamic Type.
struct CategoryChip: View {
    let name: String
    let active: Bool
    let action: () -> Void

    private var symbol: String { CategoryChip.symbol(for: name) }

    /// SF Symbols has no per-cuisine glyphs, so cuisines share the generic dish mark
    /// rather than reaching for a stereotyped stand-in.
    static func symbol(for name: String) -> String {
        switch name.lowercased() {
        case "all": return "square.grid.2x2.fill"
        case "favorites": return "star.fill"
        case "breakfast": return "cup.and.saucer.fill"
        case "dessert": return "birthday.cake.fill"
        case "vegan", "vegetarian": return "leaf.fill"
        default: return "fork.knife"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(active ? Color.gsFg : Color.gsMuted)
                    .frame(width: 84, height: 74)
                    .background(active ? Color.gsPeachSoft : Color.gsCard)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(active ? Color.gsPeach : Color.clear, lineWidth: 2)
                    )
                    .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 6)
                Text(name)
                    .font(nunito(13, active ? .extrabold : .semibold))
                    .foregroundStyle(active ? Color.gsFg : Color.gsMuted)
                    .lineLimit(1)
            }
            .frame(width: 84)
        }
        .buttonStyle(PressableStyle(scale: 0.95))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(name)
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
    }
}

/// Reference-style card: title, time, star, round photo, difficulty, time & servings.
struct LibraryCard: View {
    @EnvironmentObject var store: AppStore
    let recipe: Recipe

    var body: some View {
        Button { store.open(recipe) } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(recipe.title)
                            .font(nunito(17, .extrabold))
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.gsAccentInk)
                            Text("\(recipe.totalMinutes) min")
                                .font(nunito(13, .semibold))
                                .foregroundStyle(Color.gsMuted)
                            Text("· \(recipe.cuisine) · \(recipe.ingredients.count) ingredients")
                                .font(nunito(13, .semibold))
                                .foregroundStyle(Color.gsMuted)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Button { store.toggleFav(recipe.id) } label: {
                        Image(systemName: recipe.favorite ? "star.fill" : "star")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(recipe.favorite ? Color.gsPeach : Color.gsFg)
                            // Stays 44pt: the tap target must not shrink with the card.
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)

                CoverImage(url: recipe.imageURL)
                    .frame(width: 152, height: 152)
                    .clipShape(Circle())
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)

                HStack(alignment: .center, spacing: 10) {
                    Text(recipe.difficultyLabel)
                        .font(nunito(13.5, .semibold))
                        .foregroundStyle(Color.gsMuted)
                    DifficultyBars(filled: recipe.difficultyBars)
                    Rectangle().fill(Color.gsFill).frame(width: 1, height: 26)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(recipe.totalMinutes) min")
                            .font(nunito(19, .black))
                        Text("Serves \(recipe.servings) · \(recipe.steps.count) steps")
                            .font(nunito(11.5, .semibold))
                            .foregroundStyle(Color.gsMuted)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 14)
            }
            .softCard(radius: 26)
        }
        .buttonStyle(PressableStyle())
    }
}

/// Small round favorite toggle used on image overlays.
struct FavButton: View {
    let filled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: filled ? "star.fill" : "star")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(filled ? Color.gsPeach : Color.gsFg)
                .frame(width: 40, height: 40)
                .background(Color.gsCard.opacity(0.92))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// Full list of cuisines/countries to filter Discover by — every country in the catalog,
/// searchable, since the horizontal pills only surface a handful.
/// The Discover filter: search by name, country and food type in one place. Selections apply
/// live to the catalog; "Clear all" resets every facet.
struct RecipeFilterSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    /// Local mirror of the name query so typing feels instant; committed on submit / Show.
    @State private var name = ""

    private let cols = [GridItem(.adaptive(minimum: 110), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Filters").font(nunito(22, .black))
                Spacer()
                if store.catalogFilterActive {
                    Button("Clear all") {
                        name = ""
                        store.clearCatalogFilters()
                    }
                    .font(nunito(13, .extrabold))
                    .foregroundStyle(Color.gsAccentInk)
                }
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24)).foregroundStyle(Color.gsMuted)
                }
                .buttonStyle(.plain)
                .padding(.leading, 10)
            }
            .padding(.top, 22)
            .padding(.bottom, 14)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.gsMuted)
                TextField("", text: $name,
                          prompt: Text("Search by name").foregroundStyle(Color.gsMuted))
                    .font(nunito(15, .semibold))
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { commitName() }
                if !name.isEmpty {
                    Button { name = ""; commitName() } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Color.gsMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).frame(height: 48)
            .background(Color.gsFill)
            .clipShape(Capsule())

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    multiSection("Food type", options: store.catalogCategories,
                               selected: store.catalogCategory) { store.setCatalogCategory($0) }
                    multiSection("Country", options: store.catalogCuisines,
                                selected: store.catalogCuisine) { store.setCatalogCuisine($0) }

                    rangeSection("Cooking time", choices: [
                        ("Any", nil), ("≤ 15 min", 15), ("≤ 30 min", 30), ("≤ 60 min", 60)
                    ], selected: store.catalogMaxTime) { store.setCatalogMaxTime($0) }

                    rangeSection("Calories per serving", choices: [
                        ("Any", nil), ("≤ 300", 300), ("≤ 500", 500), ("≤ 700", 700)
                    ], selected: store.catalogMaxCal) { store.setCatalogMaxCal($0) }
                }
                .padding(.top, 18)
                .padding(.bottom, 8)
            }

            Button {
                commitName()
                dismiss()
            } label: {
                Text(store.catalogLoading ? "Filtering…" : "Show recipes")
                    .font(nunito(15, .extrabold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 54)
            }
            .buttonStyle(DarkButtonStyle())
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 22)
        .background(Color.gsBg.ignoresSafeArea())
        .presentationDetents([.large])
        .onAppear { name = store.catalogSearch }
    }

    private func commitName() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard trimmed != store.catalogSearch else { return }
        store.catalogSearch = trimmed
        store.searchCatalog()
    }

    /// A titled facet: an "Any" chip plus one chip per option. Tapping toggles the facet.
    @ViewBuilder
    private func multiSection(_ title: String, options: [String], selected: Set<String>,
                              toggle: @escaping (String?) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(nunito(15, .extrabold)).foregroundStyle(Color.gsFg)
            LazyVGrid(columns: cols, spacing: 10) {
                chip("Any", isSelected: selected.isEmpty) { toggle(nil) }
                ForEach(options, id: \.self) { opt in
                    chip(opt, isSelected: selected.contains(opt)) { toggle(opt) }
                }
            }
        }
    }

    @ViewBuilder
    private func rangeSection(_ title: String, choices: [(String, Int?)],
                              selected: Int?, set: @escaping (Int?) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(nunito(15, .extrabold)).foregroundStyle(Color.gsFg)
            LazyVGrid(columns: cols, spacing: 10) {
                ForEach(Array(choices.enumerated()), id: \.offset) { _, pair in
                    chip(pair.0, isSelected: selected == pair.1) { set(pair.1) }
                }
            }
        }
    }

    private func chip(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap(.light)
            action()
        } label: {
            Text(label)
                .font(nunito(13, isSelected ? .extrabold : .semibold))
                .foregroundStyle(isSelected ? Color.white : Color.gsFg)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10).frame(height: 40)
                .background(isSelected ? Color.gsDock : Color.gsCard)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Color.gsFg.opacity(isSelected ? 0 : 0.1), lineWidth: 1))
        }
        .buttonStyle(PressableStyle(scale: 0.96))
    }
}

/// A sleek horizontal card for a saved recipe: left thumbnail, title, meta and a favourite
/// toggle. Replaces the older centered-round-photo card for a tighter, more scannable list.
struct SavedCard: View {
    @EnvironmentObject var store: AppStore
    let recipe: Recipe

    /// How far the card is dragged left, revealing the delete action behind it.
    @State private var offset: CGFloat = 0
    private let deleteThreshold: CGFloat = 220
    private let revealWidth: CGFloat = 88

    var body: some View {
        ZStack(alignment: .trailing) {
            // Delete action sits behind the card, revealed as it slides left.
            Button { delete() } label: {
                VStack(spacing: 4) {
                    Image(systemName: "trash.fill").font(.system(size: 17, weight: .bold))
                    Text("Delete").font(nunito(11, .extrabold))
                }
                .foregroundStyle(.white)
                .frame(width: revealWidth, height: 96)
                .background(Color.red)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)
            .opacity(offset < -8 ? 1 : 0)

            card
                .offset(x: offset)
                .gesture(
                    DragGesture(minimumDistance: 14)
                        .onChanged { value in
                            if value.translation.width < 0 {
                                offset = max(value.translation.width, -deleteThreshold - 40)
                            }
                        }
                        .onEnded { value in
                            if value.translation.width < -deleteThreshold {
                                delete()
                            } else if value.translation.width < -revealWidth / 2 {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { offset = -revealWidth }
                            } else {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { offset = 0 }
                            }
                        }
                )
        }
    }

    private func delete() {
        withAnimation(.easeIn(duration: 0.2)) { offset = -600 }
        store.deleteRecipe(recipe.id)
    }

    private var card: some View {
        Button { store.open(recipe) } label: {
            HStack(spacing: 14) {
                CoverImage(url: recipe.imageURL)
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(recipe.title)
                        .font(nunito(15.5, .extrabold))
                        .foregroundStyle(Color.gsFg)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        if recipe.totalMinutes > 0 {
                            metaChip(icon: "clock", text: "\(recipe.totalMinutes) min")
                        }
                        metaChip(icon: "fork.knife", text: recipe.cuisine)
                    }

                    HStack(spacing: 6) {
                        DifficultyBars(filled: recipe.difficultyBars)
                        Text(recipe.difficultyLabel)
                            .font(nunito(11, .bold))
                            .foregroundStyle(Color.gsMuted)
                    }
                }

                Spacer(minLength: 0)

                Button { store.toggleFav(recipe.id) } label: {
                    Image(systemName: recipe.favorite ? "star.fill" : "star")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(recipe.favorite ? Color.gsPeach : Color.gsMuted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(Color.gsCard)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.gsFg.opacity(0.06), lineWidth: 1))
            .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
        }
        .buttonStyle(PressableStyle(scale: 0.98))
    }

    private func metaChip(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold))
            Text(text).font(nunito(11.5, .bold)).lineLimit(1)
        }
        .foregroundStyle(Color.gsAccentInk)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.gsPeachSoft)
        .clipShape(Capsule())
    }
}

// MARK: - Filter sheet

/// Extra filters for the Saved tab: cooking time, difficulty, calories, and type of food.
/// Cuisine ("type of food") drives the same `store.chip` as the pill row, so the two stay
/// in sync. The time/difficulty/calorie bands live in their own AppStore state.
struct FilterSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    section("Cooking time") {
                        wrap(AppStore.TimeBand.allCases.map(\.rawValue),
                             isOn: { $0 == store.timeBand.rawValue }) { raw in
                            if let band = AppStore.TimeBand(rawValue: raw) {
                                withAnimation(AppStore.lateralAnimation) { store.timeBand = band }
                            }
                        }
                    }

                    section("Difficulty") {
                        wrap(["Any"] + AppStore.difficultyOptions,
                             isOn: { $0 == (store.difficultyFilter ?? "Any") }) { name in
                            withAnimation(AppStore.lateralAnimation) {
                                store.difficultyFilter = (name == "Any") ? nil : name
                            }
                        }
                    }

                    section("Calories per serving") {
                        wrap(AppStore.CalBand.allCases.map(\.rawValue),
                             isOn: { $0 == store.calBand.rawValue }) { raw in
                            if let band = AppStore.CalBand(rawValue: raw) {
                                withAnimation(AppStore.lateralAnimation) { store.calBand = band }
                            }
                        }
                    }

                    section("Type of food") {
                        wrap(store.chipNames, isOn: { $0 == store.chip }) { name in
                            withAnimation(AppStore.lateralAnimation) { store.chip = name }
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { store.clearFilters(); store.chip = "All" }
                        .font(nunito(14, .bold))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(nunito(14, .extrabold))
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(nunito(11, .black))
                .tracking(1.4)
                .foregroundStyle(Color.gsMuted)
            content()
        }
    }

    /// A wrapping run of selectable chips.
    private func wrap(_ options: [String], isOn: @escaping (String) -> Bool,
                      select: @escaping (String) -> Void) -> some View {
        FlexChips(options: options, isOn: isOn, select: select)
    }
}

/// Chips that wrap onto multiple lines (a lightweight flow layout).
private struct FlexChips: View {
    let options: [String]
    let isOn: (String) -> Bool
    let select: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(options, id: \.self) { name in
                let active = isOn(name)
                Button {
                    Haptics.tap(.light)
                    select(name)
                } label: {
                    Text(name)
                        .font(nunito(13, active ? .extrabold : .semibold))
                        .foregroundStyle(active ? Color.white : Color.gsFg)
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .background(active ? Color.gsDock : Color.gsCard)
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(Color.gsFg.opacity(active ? 0 : 0.12), lineWidth: 1))
                }
                .buttonStyle(PressableStyle(scale: 0.95))
            }
        }
    }
}

/// Minimal flow layout: lays children left-to-right, wrapping to the next line as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0; y += lineHeight + lineSpacing; lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += lineHeight + lineSpacing; lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
