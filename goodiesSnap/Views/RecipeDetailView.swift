import SwiftUI

struct RecipeDetailView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var social: SocialStore
    @State private var confirmDelete = false
    /// Briefly true right after ingredients are added, driving the button's success flash.
    @State private var justAdded = false
    /// Latest request to jump the embedded video to a step's moment.
    @State private var seek: SeekCommand?
    @State private var seekNonce = 0

    var body: some View {
        if let sel = store.selected {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero(sel)

                    VStack(alignment: .leading, spacing: 0) {
                        Kicker(text: "\(sel.cuisine) · from \(sel.source)", size: 11, tracking: 2)
                        Text(sel.title)
                            .font(nunito(32, .black))
                            .tracking(-0.6)
                            .lineSpacing(1)
                            .padding(.top, 6)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 8) {
                            statChip("⏱ \(sel.totalMinutes) min")
                            statChip("Serves \(sel.servings)")
                            statChip("\(sel.steps.count) steps")
                            statChip("\(sel.difficultyLabel)")
                        }
                        .padding(.top, 14)

                        Text("Approx. \(sel.cal) kcal per serving · protein \(sel.macros.protein) g · carbs \(sel.macros.carbs) g · fat \(sel.macros.fat) g")
                            .font(nunito(12, .semibold))
                            .foregroundStyle(Color.gsMuted)
                            .padding(.top, 12)

                        HStack(alignment: .firstTextBaseline) {
                            Text("Ingredients")
                                .font(nunito(19, .extrabold))
                            Spacer()
                            Text("\(sel.ingredients.count)")
                                .font(nunito(13, .black))
                                .foregroundStyle(Color.gsMuted)
                        }
                        .padding(.top, 26)

                        VStack(spacing: 0) {
                            ForEach(sel.ingredients) { i in
                                HStack(spacing: 12) {
                                    Text(i.name)
                                    Spacer()
                                    Text(i.qty).foregroundStyle(Color.fg(0.5))
                                }
                                .font(nunito(13.5, .bold))
                                .padding(.vertical, 11)
                                .overlay(alignment: .bottom) {
                                    if i.id != sel.ingredients.last?.id {
                                        Rectangle().fill(Color.fg(0.07)).frame(height: 1)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                        .softCard(radius: 20)
                        .padding(.top, 10)

                        addToListButton(sel)
                            .padding(.top, 12)

                        Text("Method")
                            .font(nunito(19, .extrabold))
                            .padding(.top, 26)

                        ForEach(Array(sel.steps.enumerated()), id: \.offset) { i, step in
                            VStack(alignment: .leading, spacing: 0) {
                                NumberedRow(num: i + 1, text: step)
                                if let start = sel.stepStart(at: i) {
                                    Button {
                                        seekNonce += 1
                                        seek = SeekCommand(seconds: start, nonce: seekNonce)
                                        Haptics.tap(.light)
                                    } label: {
                                        Text("▶ Watch this step · \(timeLabel(start))")
                                            .font(nunito(12, .extrabold))
                                            .foregroundStyle(Color.gsAccentInk)
                                            .padding(.vertical, 7)
                                            .padding(.horizontal, 12)
                                            .background(Color.gsAccentInk.opacity(0.12))
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.leading, 46)
                                    .padding(.bottom, 12)
                                }
                            }
                        }

                        if sel.hasVideo, let vid = sel.videoID {
                            Text("Watch")
                                .font(nunito(19, .extrabold))
                                .padding(.top, 26)

                            YouTubePlayerView(videoID: vid, seek: seek)
                                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .padding(.top, 10)

                            Text(sel.stepSeconds?.contains(where: { $0 >= 0 }) == true
                                 ? "Tap ▶ on a step to jump the video there · from YouTube"
                                 : "Plays here in the app · from YouTube")
                                .font(nunito(11.5, .semibold))
                                .foregroundStyle(Color.gsMuted)
                                .padding(.top, 8)
                        }

                        if !sel.notes.isEmpty {
                            Text("Note — \(sel.notes)")
                                .font(nunito(13, .semibold))
                                .italic()
                                .foregroundStyle(Color.fg(0.55))
                                .padding(.top, 16)
                        }

                        Button {
                            store.cookStep = 0
                            store.go(to: .cook)
                        } label: {
                            Text("▶ Start cooking")
                                .font(nunito(16, .extrabold))
                                .foregroundStyle(Color.white)
                                .frame(maxWidth: .infinity, minHeight: 56)
                        }
                        .buttonStyle(CreamButtonStyle())
                        .padding(.top, 24)

                        Button {
                            if social.signedIn {
                                withAnimation(AppStore.sheetAnimation) { social.sharing = sel }
                            } else {
                                store.go(to: .feed)
                                store.showToast("Sign in to share recipes")
                            }
                        } label: {
                            Text("Share to feed")
                                .font(nunito(14, .extrabold))
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(Color.fg(0.06))
                                .clipShape(Capsule())
                                .overlay(Capsule().strokeBorder(Color.fg(0.16), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)

                        Button { confirmDelete = true } label: {
                            Text("Delete recipe")
                                .font(nunito(12.5, .bold))
                                .foregroundStyle(Color.fg(0.4))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 6)
                    }
                    .padding(.horizontal, 22)
                    .offset(y: -72)
                    .padding(.bottom, -72)
                }
                .padding(.bottom, 116)
            }
            .ignoresSafeArea(edges: .top)
            .alert("Delete \"\(sel.title)\"?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) { store.deleteSelected() }
                Button("Cancel", role: .cancel) {}
            }
        } else {
            // Reachable when the recipe is deleted while this screen is open. Without an
            // else this rendered as a blank screen — and cook mode hides the tab bar, so
            // there was no visible way out.
            VStack(spacing: 12) {
                Text("That recipe is no longer here")
                    .font(nunito(18, .extrabold))
                Text("It may have been deleted.")
                    .font(nunito(13, .semibold))
                    .foregroundStyle(Color.gsMuted)
                Button { store.goBack() } label: {
                    Text("Go back")
                        .font(nunito(14, .extrabold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 24)
                        .frame(minHeight: 48)
                }
                .buttonStyle(DarkButtonStyle())
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.gsBg)
        }
    }

    /// Prominent "add all ingredients to the shopping list" button, with a green success
    /// flash — the same confirmation pattern as the manual add on the Shopping tab.
    @ViewBuilder
    private func addToListButton(_ sel: Recipe) -> some View {
        let alreadyOn = store.allOnList(sel)
        Button { add(sel) } label: {
            HStack(spacing: 10) {
                Image(systemName: justAdded ? "checkmark" : (alreadyOn ? "checkmark.circle.fill" : "cart.badge.plus"))
                    .font(.system(size: 17, weight: .heavy))
                    .scaleEffect(justAdded ? 1.18 : 1)
                    .contentTransition(.symbolEffect(.replace))
                Text(justAdded ? "Added to your list"
                     : (alreadyOn ? "All ingredients on your list" : "Add all to shopping list"))
                    .font(nunito(15, .extrabold))
            }
            .foregroundStyle(Color.gsDock)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(justAdded ? Color.gsMint : (alreadyOn ? Color.gsPeachSoft : Color.gsPeach))
            .clipShape(Capsule())
            .shadow(color: (justAdded ? Color.gsMint : Color.gsPeach).opacity(alreadyOn ? 0 : 0.4),
                    radius: justAdded ? 14 : 8, y: 5)
        }
        .buttonStyle(PressableStyle(scale: 0.97))
        .animation(.spring(response: 0.32, dampingFraction: 0.6), value: justAdded)
    }

    private func add(_ sel: Recipe) {
        let count = store.addIngredients(of: sel)
        // Nothing new to add (all already on the list) — confirm quietly, no green flash.
        guard count > 0 else {
            Haptics.tap(.light)
            store.showToast("Already on your shopping list")
            return
        }
        Haptics.notify(.success)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) { justAdded = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.easeOut(duration: 0.3)) { justAdded = false }
        }
    }

    private func hero(_ sel: Recipe) -> some View {
        ZStack {
            CoverImage(url: sel.imageURL)
            LinearGradient(
                stops: [
                    .init(color: Color.gsBg.opacity(0.35), location: 0),
                    .init(color: .clear, location: 0.28),
                    .init(color: .clear, location: 0.55),
                    .init(color: .gsBg, location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
        .frame(height: 380)
        .overlay(alignment: .top) {
            HStack(spacing: 10) {
                circleButton(system: "chevron.left") { store.goBack() }
                Spacer()
                // Saving is deliberate: browsing a catalog recipe no longer adds it silently.
                circleButton(
                    system: store.isInLibrary(sel.id) ? "bookmark.fill" : "bookmark"
                ) {
                    let saved = store.toggleSaved(sel)
                    store.showToast(saved ? "Saved to your library" : "Removed from your library")
                }
                circleButton(
                    system: sel.favorite ? "heart.fill" : "heart"
                ) { store.toggleFav(sel.id) }
            }
            .padding(.horizontal, 18)
            .padding(.top, 60)
        }
    }

    private func statChip(_ text: String) -> some View {
        Text(text)
            .font(nunito(12, .extrabold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.fg(0.08))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.fg(0.14), lineWidth: 1))
            .lineLimit(1)
    }

    private func circleButton(system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.gsFg)
                .frame(width: 44, height: 44)
                .background(Color.gsCard.opacity(0.94))
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.fg(0.16), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
