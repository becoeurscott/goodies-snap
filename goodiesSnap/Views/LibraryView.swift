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
            // Opens the full country/cuisine list — the horizontal pills only show a few.
            Button { showFilter = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 13, weight: .bold))
                    if store.catalogCuisine != nil {
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
            .accessibilityLabel("Filter by cuisine")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    pill("All", active: store.catalogCuisine == nil) { store.setCatalogCuisine(nil) }
                    // Selected cuisine floats to the front so it's always visible.
                    if let sel = store.catalogCuisine {
                        pill(sel, active: true) { store.setCatalogCuisine(nil) }
                    }
                    ForEach(store.catalogCuisines.filter { $0 != store.catalogCuisine }, id: \.self) { c in
                        pill(c, active: false) { store.setCatalogCuisine(c) }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .sheet(isPresented: $showFilter) {
            CuisineFilterSheet(
                cuisines: store.catalogCuisines,
                selected: store.catalogCuisine,
                onSelect: { store.setCatalogCuisine($0); showFilter = false })
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
struct CuisineFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    let cuisines: [String]
    let selected: String?
    let onSelect: (String?) -> Void

    @State private var query = ""

    private var filtered: [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? cuisines : cuisines.filter { $0.lowercased().contains(q) }
    }

    private let cols = [GridItem(.adaptive(minimum: 150), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Filter by cuisine").font(nunito(22, .black))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.gsMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 24)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.gsMuted)
                TextField("", text: $query,
                          prompt: Text("Search countries").foregroundStyle(Color.gsMuted))
                    .font(nunito(15, .semibold))
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 16).frame(height: 48)
            .background(Color.gsFill)
            .clipShape(Capsule())

            ScrollView {
                LazyVGrid(columns: cols, spacing: 10) {
                    row("All cuisines", isSelected: selected == nil) { onSelect(nil) }
                    ForEach(filtered, id: \.self) { c in
                        row(c, isSelected: selected == c) { onSelect(c) }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, 22)
        .background(Color.gsBg.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }

    private func row(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap(.light)
            action()
        } label: {
            HStack {
                Text(label)
                    .font(nunito(14, isSelected ? .extrabold : .semibold))
                    .foregroundStyle(isSelected ? Color.white : Color.gsFg)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if isSelected {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .black))
                        .foregroundStyle(Color.white)
                }
            }
            .padding(.horizontal, 14).frame(height: 46)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.gsDock : Color.gsCard)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.gsFg.opacity(isSelected ? 0 : 0.1), lineWidth: 1))
        }
        .buttonStyle(PressableStyle(scale: 0.97))
    }
}

/// A sleek horizontal card for a saved recipe: left thumbnail, title, meta and a favourite
/// toggle. Replaces the older centered-round-photo card for a tighter, more scannable list.
struct SavedCard: View {
    @EnvironmentObject var store: AppStore
    let recipe: Recipe

    var body: some View {
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
