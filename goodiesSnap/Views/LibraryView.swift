import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.gsFg)
                        TextField(
                            "", text: $store.search,
                            prompt: Text("Search").foregroundStyle(Color.gsMuted)
                        )
                        .font(nunito(15, .semibold))
                        .autocorrectionDisabled()
                        if !store.search.isEmpty {
                            Button { store.search = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Color.gsMuted)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 54)
                    .softCard(radius: 18)

                    IconButton(system: "bell", badge: store.undoneCount > 0) { store.go(to: .profile) }
                        .frame(width: 54, height: 54)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(store.chipNames, id: \.self) { name in
                            CategoryChip(name: name, active: store.chip == name) {
                                Haptics.tap(.light)
                                withAnimation(AppStore.lateralAnimation) { store.chip = name }
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 4)
                }
                .padding(.horizontal, -2)
                .padding(.top, 18)

                HStack(alignment: .center, spacing: 8) {
                    Text(store.chip == "All" ? "My recipes" : store.chip)
                        .font(nunito(19, .extrabold))
                    Text("\(store.filtered.count)")
                        .font(nunito(10, .black))
                        .foregroundStyle(Color.gsFg)
                        .frame(width: 22, height: 22)
                        .background(Color.gsPeach)
                        .clipShape(Circle())
                    Spacer()
                    Text("\(store.favorites.count) favorites")
                        .font(nunito(13, .bold))
                        .foregroundStyle(Color.gsMuted)
                }
                .padding(.top, 22)

                if store.filtered.isEmpty {
                    Text("Nothing matches — try another ingredient or title.")
                        .font(nunito(13, .semibold))
                        .foregroundStyle(Color.gsMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 48)
                        .padding(.horizontal, 20)
                }

                VStack(spacing: 14) {
                    ForEach(store.filtered) { r in
                        LibraryCard(recipe: r)
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    }
                }
                .padding(.top, 14)
                .animation(AppStore.lateralAnimation, value: store.filtered)
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 116)
        }
        .background(Color.gsBg)
        .scrollDismissesKeyboard(.interactively)
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

    /// SF Symbols has no per-cuisine glyphs, so cuisines share the generic dish mark
    /// rather than reaching for a stereotyped stand-in.
    private var symbol: String {
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
