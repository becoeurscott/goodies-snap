import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var social: SocialStore
    @FocusState private var nameFocused: Bool
    @State private var confirmReset = false
    @State private var confirmDelete = false
    @State private var deleteConfirmation = ""
    @State private var deleteFailed = ""


    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                identityCard
                    .padding(.top, 22)
                statsGrid
                    .padding(.top, 16)
                tasteSection
                    .padding(.top, 28)
                actionsSection
                    .padding(.top, 28)
                accountSection
                    .padding(.top, 28)

                Text("goodiesSnap 1.0 — every recipe, beautifully kept.")
                    .font(nunito(11.5, .semibold))
                    .foregroundStyle(Color.fg(0.3))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)
            }
            .padding(.horizontal, 22)
            .padding(.top, 16)
            .padding(.bottom, 116)
        }
        .scrollDismissesKeyboard(.interactively)
        .task { await social.loadBlocked() }
        .onAppear {
            // Delete-sheet automation (`-gsDeleteAccount 1`), matching the other
            // launch-argument hooks used for headless verification.
            if UserDefaults.standard.string(forKey: "gsDeleteAccount") != nil { confirmDelete = true }
        }
        .alert("Reset your library?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { store.resetLibrary() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your saved recipes, shopping list, and meal plan go back to the starter samples.")
        }
        .sheet(isPresented: $confirmDelete) { deleteAccountSheet }
    }

    // MARK: - Account

    /// App Store guideline 5.1.1(v): an account created in the app must be deletable
    /// from inside the app, not only by writing to support.
    @ViewBuilder
    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Account")
                .font(nunito(19, .extrabold))

            if social.signedIn {
                if !social.blockedIDs.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.gsAccentInk)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(social.blockedIDs.count) blocked \(social.blockedIDs.count == 1 ? "account" : "accounts")")
                                .font(nunito(14, .extrabold))
                            Text("You won't see each other's posts or comments.")
                                .font(nunito(11.5, .semibold))
                                .foregroundStyle(Color.fg(0.5))
                        }
                        Spacer()
                        Button("Unblock all") {
                            for id in social.blockedIDs { social.unblock(userID: id) }
                        }
                        .font(nunito(12, .extrabold))
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.gsAccentInk)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .glassCard(radius: 20, fill: 0.05, stroke: 0.1)
                }

                Button {
                    deleteConfirmation = ""
                    deleteFailed = ""
                    confirmDelete = true
                } label: {
                    Text("Delete my account")
                        .font(nunito(14, .extrabold))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color.red.opacity(0.08))
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(Color.red.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
            } else {
                Text("Sign in from the Community tab to manage your account.")
                    .font(nunito(12.5, .semibold))
                    .foregroundStyle(Color.fg(0.45))
            }
        }
    }

    private var deleteAccountSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Delete your account")
                .font(nunito(23, .black))
                .padding(.top, 28)

            Text("This permanently deletes your account, your posts, comments, likes, group memberships and uploaded photos. It cannot be undone.")
                .font(nunito(14, .semibold))
                .foregroundStyle(Color.fg(0.6))
                .fixedSize(horizontal: false, vertical: true)

            // Recipes live on the device, so say so plainly rather than letting people
            // assume deleting the account wipes their library too.
            Text("Recipes saved on this iPhone stay on this iPhone.")
                .font(nunito(12.5, .bold))
                .foregroundStyle(Color.gsAccentInk)

            Text("Type DELETE to confirm")
                .font(nunito(12.5, .extrabold))
                .padding(.top, 4)

            TextField("", text: $deleteConfirmation, prompt: Text("DELETE").foregroundStyle(Color.gsMuted))
                .font(nunito(15, .extrabold))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(Color.gsFill)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if !deleteFailed.isEmpty {
                Text(deleteFailed)
                    .font(nunito(12.5, .semibold))
                    .foregroundStyle(.red)
            }

            Button {
                Task {
                    deleteFailed = ""
                    if await social.deleteAccount() {
                        confirmDelete = false
                        store.showToast("Your account has been deleted")
                    } else {
                        deleteFailed = social.errorMessage.isEmpty
                            ? "Couldn't delete your account. Please try again."
                            : social.errorMessage
                    }
                }
            } label: {
                Text(social.deletingAccount ? "Deleting…" : "Permanently delete")
                    .font(nunito(15, .extrabold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(Color.red.opacity(canDelete ? 1 : 0.35))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canDelete || social.deletingAccount)

            Button("Keep my account") { confirmDelete = false }
                .font(nunito(14, .extrabold))
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, minHeight: 46)

            Spacer()
        }
        .padding(.horizontal, 24)
        .background(Color.gsBg.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }

    private var canDelete: Bool {
        deleteConfirmation.trimmingCharacters(in: .whitespaces).uppercased() == "DELETE"
    }

    private var header: some View {
        HStack {
            Button { store.goBack() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.gsFg)
                    .frame(width: 44, height: 44)
                    .background(Color.fg(0.06))
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.fg(0.14), lineWidth: 1))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.leading, -4)
    }

    private var identityCard: some View {
        VStack(spacing: 0) {
            Text(store.initial)
                .font(nunito(30, .black))
                .frame(width: 84, height: 84)
                .background(Color.fg(0.1))
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.fg(0.18), lineWidth: 1))

            TextField(
                "", text: $store.userName,
                prompt: Text("Your name").foregroundStyle(Color.fg(0.35))
            )
            .font(nunito(26, .black))
            .multilineTextAlignment(.center)
            .focused($nameFocused)
            .submitLabel(.done)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.words)
            .onSubmit { store.persist() }
            .padding(.top, 14)

            HStack(spacing: 6) {
                Image(systemName: "pencil")
                    .font(.system(size: 10, weight: .bold))
                Text("Tap your name to change it")
                    .font(nunito(11.5, .semibold))
            }
            .foregroundStyle(Color.fg(0.4))
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .glassCard(radius: 26)
        .onChange(of: nameFocused) { _, focused in
            if !focused { store.persist() }
        }
    }

    private var statsGrid: some View {
        HStack(spacing: 12) {
            statTile(value: "\(store.recipes.count)", label: "Recipes")
            statTile(value: "\(store.favorites.count)", label: "Favorites")
            statTile(value: "\(store.plannedCount)", label: "Planned")
        }
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(nunito(26, .black))
            Kicker(text: label, size: 10, tracking: 1.4, opacity: 0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .glassCard(radius: 20, fill: 0.05, stroke: 0.1)
    }

    private var tasteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your kitchen")
                .font(nunito(19, .extrabold))

            VStack(spacing: 0) {
                infoRow(
                    icon: "globe",
                    title: "Cooks the most",
                    value: store.topCuisine ?? "—"
                )
                infoRow(
                    icon: "clock",
                    title: "Average cook time",
                    value: store.recipes.isEmpty ? "—" : "\(store.avgCookTime) min"
                )
                infoRow(
                    icon: "cart",
                    title: "On the shopping list",
                    value: "\(store.undoneCount) to buy",
                    isLast: true
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .glassCard(radius: 20, fill: 0.05, stroke: 0.1)
        }
    }

    private func infoRow(icon: String, title: String, value: String, isLast: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.fg(0.55))
                .frame(width: 20)
            Text(title)
                .font(nunito(13.5, .bold))
            Spacer()
            Text(value)
                .font(nunito(13.5, .bold))
                .foregroundStyle(Color.fg(0.5))
        }
        .frame(minHeight: 48)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(Color.fg(0.07)).frame(height: 1)
            }
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Manage")
                .font(nunito(19, .extrabold))

            Button { store.go(to: .importer) } label: {
                HStack(spacing: 14) {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 42, height: 42)
                        .background(Color.gsFg)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Save a new recipe")
                            .font(nunito(15, .extrabold))
                        Text("Link · YouTube · photo · text")
                            .font(nunito(11.5, .semibold))
                            .foregroundStyle(Color.fg(0.5))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.fg(0.4))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .glassCard(radius: 20, fill: 0.05, stroke: 0.1)
            }
            .buttonStyle(.plain)

            Button { store.clearShoppingAll() } label: {
                Text("Clear shopping list")
                    .font(nunito(14, .extrabold))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color.fg(0.06))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Color.fg(0.16), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(store.shopping.isEmpty)
            .opacity(store.shopping.isEmpty ? 0.45 : 1)

            Button { confirmReset = true } label: {
                Text("Reset library to samples")
                    .font(nunito(12.5, .bold))
                    .foregroundStyle(Color.fg(0.4))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
        }
    }
}
