import SwiftUI

/// Discover: browse the server-side recipe catalog and save recipes into the library.
///
/// Content comes from `catalog_recipes` via `CatalogService`; tapping a card saves it to
/// the library and opens the normal detail screen, so cook mode and the shopping list all
/// work on catalog recipes with no special-casing downstream.
struct DiscoverView: View {
    @EnvironmentObject var store: AppStore

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                searchBar
                    .padding(.top, 16)

                cuisineChips
                    .padding(.top, 14)

                if store.catalog.isEmpty && store.catalogLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                } else if store.catalog.isEmpty {
                    Text("Nothing here yet — try another cuisine or search.")
                        .font(nunito(13, .semibold))
                        .foregroundStyle(Color.gsMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                } else {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(store.catalog) { recipe in
                            CatalogCard(recipe: recipe)
                                .onAppear {
                                    // Infinite scroll: load the next page as the last card appears.
                                    if recipe.id == store.catalog.last?.id {
                                        Task { await store.loadCatalog(reset: false) }
                                    }
                                }
                        }
                    }
                    .padding(.top, 18)

                    if store.catalogLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    }
                }

                // TheMealDB requires attribution; keep it visible on the source screen.
                Text("Recipes via TheMealDB")
                    .font(nunito(10.5, .semibold))
                    .foregroundStyle(Color.gsMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 116)
        }
        .background(Color.gsBg)
        .scrollDismissesKeyboard(.interactively)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { store.goBack() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(Color.gsFg)
                    .frame(width: 44, height: 44)
                    .background(Color.gsCard)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.gsFg.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(PressableStyle(scale: 0.94))

            VStack(alignment: .leading, spacing: 1) {
                Text("Discover")
                    .font(nunito(24, .black))
                Text("Proven recipes to add to your library")
                    .font(nunito(12, .semibold))
                    .foregroundStyle(Color.gsMuted)
            }
            Spacer()
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.gsFg)
            TextField("", text: $store.catalogSearch,
                      prompt: Text("Search recipes").foregroundStyle(Color.gsMuted))
                .font(nunito(15, .semibold))
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { store.searchCatalog() }
            if !store.catalogSearch.isEmpty {
                Button { store.catalogSearch = ""; store.searchCatalog() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.gsMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
        .softCard(radius: 18)
    }

    private var cuisineChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", active: store.catalogCuisine == nil) { store.setCatalogCuisine(nil) }
                ForEach(store.catalogCuisines, id: \.self) { c in
                    chip(c, active: store.catalogCuisine == c) { store.setCatalogCuisine(c) }
                }
            }
            .padding(.horizontal, 2)
        }
        .padding(.horizontal, -2)
    }

    private func chip(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
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
}

/// A compact catalog card: cover image, title, cuisine, and a saved indicator.
/// Shared by Discover and the redesigned Library tab.
struct CatalogCard: View {
    @EnvironmentObject var store: AppStore
    let recipe: Recipe

    private var saved: Bool { store.isInLibrary(recipe.id) }

    var body: some View {
        Button { store.openCatalogRecipe(recipe) } label: {
            VStack(alignment: .leading, spacing: 0) {
                CoverImage(url: recipe.imageURL)
                    .frame(height: 130)
                    .clipped()
                    .overlay(alignment: .topTrailing) {
                        if saved {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(Color.white, Color.gsPeach)
                                .padding(8)
                        }
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(recipe.title)
                        .font(nunito(14, .extrabold))
                        .foregroundStyle(Color.gsFg)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(recipe.cuisine)
                        .font(nunito(11.5, .semibold))
                        .foregroundStyle(Color.gsMuted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(Color.gsCard)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.gsFg.opacity(0.06), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(PressableStyle(scale: 0.97))
    }
}
