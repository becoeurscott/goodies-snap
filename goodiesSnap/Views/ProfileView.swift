import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var social: SocialStore
    @FocusState private var nameFocused: Bool
    @State private var confirmReset = false
    @State private var confirmDisconnect = false
    @State private var confirmDelete = false
    @State private var deleteConfirmation = ""
    @State private var deleteFailed = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                identity
                    .padding(.top, 18)
                statsCard
                    .padding(.top, 22)
                planBanner
                    .padding(.top, 14)

                section("Kitchen") {
                    navRow(icon: "book.closed.fill", title: "My recipes",
                           badge: "\(store.recipes.count)") { store.go(to: .library) }
                    navRow(icon: "cart.fill", title: "Shopping list",
                           badge: store.undoneCount > 0 ? "\(store.undoneCount)" : nil) { store.go(to: .shopping) }
                    navRow(icon: "calendar", title: "Meal plan",
                           badge: store.plannedCount > 0 ? "\(store.plannedCount)" : nil) { store.go(to: .plan) }
                    navRow(icon: "plus", title: "Save a new recipe", isLast: true) { store.go(to: .importer) }
                }
                .padding(.top, 22)

                section("Account") {
                    toggleRow(icon: "sparkles", title: "Allow AI recipe processing", isOn: Binding(
                        get: { store.aiSharingAllowed },
                        set: { value in
                            if value { store.showAIConsent = true }
                            else { store.finishAIConsent(allow: false) }
                        }
                    ))
                    if social.signedIn && !social.blockedIDs.isEmpty {
                        actionRow(icon: "hand.raised.fill", title: "\(social.blockedIDs.count) blocked",
                                  trailing: "Unblock all") {
                            for id in social.blockedIDs { social.unblock(userID: id) }
                        }
                    }
                    navRow(icon: "bubble.left.and.text.bubble.right.fill", title: "Help & support",
                           isLast: true) { store.go(to: .support) }
                }
                .padding(.top, 16)

                section("Privacy & legal") {
                    linkRow(icon: "doc.text.fill", title: "Terms of Use", url: Legal.terms)
                    linkRow(icon: "lock.fill", title: "Privacy Policy", url: Legal.privacy,
                            isLast: !social.signedIn)
                    if social.signedIn {
                        navRow(icon: "trash.fill", title: "Delete my account", destructive: true, isLast: true) {
                            deleteConfirmation = ""
                            deleteFailed = ""
                            confirmDelete = true
                        }
                    }
                }
                .padding(.top, 16)

                section("Data") {
                    actionRow(icon: "cart.badge.minus", title: "Clear shopping list",
                              disabled: store.shopping.isEmpty) { store.clearShoppingAll() }
                    actionRow(icon: "arrow.counterclockwise", title: "Clear saved library",
                              destructive: true, isLast: true) { confirmReset = true }
                }
                .padding(.top, 16)

                if social.signedIn {
                    disconnectButton
                        .padding(.top, 24)
                }

                Text("goodiesSnap 1.0 — every recipe, beautifully kept.")
                    .font(nunito(11.5, .semibold))
                    .foregroundStyle(Color.fg(0.3))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 26)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 44)
        }
        .background(Color.gsBg.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .task { await social.loadBlocked() }
        .onAppear {
            if UserDefaults.standard.string(forKey: "gsDeleteAccount") != nil { confirmDelete = true }
        }
        .alert("Reset your library?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { store.resetLibrary() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes your saved recipes, shopping list, and meal plan. This cannot be undone.")
        }
        .alert("Disconnect?", isPresented: $confirmDisconnect) {
            Button("Disconnect", role: .destructive) { social.signOut() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll be signed out on this iPhone. Your account and everything in it stays exactly as it is — sign back in any time.")
        }
        .sheet(isPresented: $confirmDelete) { deleteAccountSheet }
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            Text("Profile")
                .font(nunito(17, .extrabold))
            HStack {
                Button { store.goBack() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.gsFg)
                        .frame(width: 42, height: 42)
                        .background(Color.gsCard, in: Circle())
                        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                Spacer()
            }
        }
    }

    // MARK: - Identity

    private var identity: some View {
        VStack(spacing: 0) {
            Button { nameFocused = true } label: {
                Text(store.initial)
                    .font(nunito(34, .black))
                    .foregroundStyle(Color.gsFg)
                    .frame(width: 96, height: 96)
                    .background(Color.gsPeach, in: Circle())
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Color.gsDock, in: Circle())
                            .overlay(Circle().strokeBorder(Color.gsBg, lineWidth: 3))
                            .offset(x: 2, y: 2)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit your name")

            TextField("", text: $store.userName,
                      prompt: Text("Your name").foregroundStyle(Color.fg(0.35)))
                .font(nunito(26, .black))
                .multilineTextAlignment(.center)
                .focused($nameFocused)
                .submitLabel(.done)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .onSubmit { store.persist() }
                .padding(.top, 14)

            Text(subtitle)
                .font(nunito(13, .semibold))
                .foregroundStyle(Color.gsMuted)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .onChange(of: nameFocused) { _, focused in
            if !focused { store.persist() }
        }
    }

    private var subtitle: String {
        let who = social.signedIn ? "Home cook" : "Guest"
        return "\(who) · \(store.entitlement.plan.title) plan"
    }

    // MARK: - Stats

    private var statsCard: some View {
        HStack(spacing: 0) {
            stat("\(store.recipes.count)", "Recipes")
            divider
            stat("\(store.favorites.count)", "Favorites")
            divider
            stat("\(store.plannedCount)", "Planned")
        }
        .padding(.vertical, 16)
        .background(Color.gsCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 12, y: 3)
    }

    private var divider: some View {
        Rectangle().fill(Color.fg(0.08)).frame(width: 1, height: 34)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(nunito(24, .black))
            Text(label).font(nunito(12.5, .semibold)).foregroundStyle(Color.gsMuted)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Plan banner

    private var planBanner: some View {
        let plan = store.entitlement.plan
        return Button { store.showPaywall(.upgrade) } label: {
            HStack(spacing: 14) {
                Image(systemName: plan.isPaid ? "crown.fill" : "sparkles")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.gsPeach)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.isPaid ? "\(plan.title) active" : "Upgrade to Pro")
                        .font(nunito(15.5, .extrabold))
                        .foregroundStyle(.white)
                    Text(plan.isPaid
                         ? "\(store.entitlement.remaining) AI actions left this month"
                         : "\(store.entitlement.remaining) free AI actions left this month")
                        .font(nunito(12, .semibold))
                        .foregroundStyle(Color.white.opacity(0.62))
                }
                Spacer(minLength: 6)
                Text(plan.isPaid ? "Manage" : "Upgrade")
                    .font(nunito(12.5, .extrabold))
                    .foregroundStyle(Color.gsFg)
                    .padding(.horizontal, 13)
                    .frame(height: 32)
                    .background(Color.gsPeach, in: Capsule())
            }
            .padding(16)
            .background(Color.gsDock, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.98))
    }

    // MARK: - Grouped rows

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(nunito(11.5, .extrabold))
                .tracking(1.2)
                .foregroundStyle(Color.gsMuted)
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
            VStack(spacing: 0) { content() }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .background(Color.gsCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 3)
        }
    }

    private func iconTile(_ icon: String, destructive: Bool = false) -> some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(destructive ? Color.red : Color.gsAccentInk)
            .frame(width: 36, height: 36)
            .background(destructive ? Color.red.opacity(0.08) : Color.gsPeachSoft,
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func rowChrome<Content: View>(isLast: Bool, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 12) { content() }
            .frame(minHeight: 58)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if !isLast { Rectangle().fill(Color.fg(0.06)).frame(height: 1).padding(.leading, 48) }
            }
    }

    private func navRow(icon: String, title: String, badge: String? = nil, destructive: Bool = false,
                        isLast: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            rowChrome(isLast: isLast) {
                iconTile(icon, destructive: destructive)
                Text(title)
                    .font(nunito(15, .bold))
                    .foregroundStyle(destructive ? Color.red : Color.gsFg)
                Spacer(minLength: 8)
                if let badge {
                    Text(badge)
                        .font(nunito(12.5, .extrabold))
                        .foregroundStyle(Color.gsMuted)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Color.gsFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.fg(0.35))
            }
        }
        .buttonStyle(.plain)
    }

    private func linkRow(icon: String, title: String, url: URL, isLast: Bool = false) -> some View {
        Link(destination: url) {
            rowChrome(isLast: isLast) {
                iconTile(icon)
                Text(title).font(nunito(15, .bold)).foregroundStyle(Color.gsFg)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.fg(0.35))
            }
        }
    }

    private func toggleRow(icon: String, title: String, isOn: Binding<Bool>, isLast: Bool = false) -> some View {
        rowChrome(isLast: isLast) {
            iconTile(icon)
            Toggle(title, isOn: isOn)
                .font(nunito(15, .bold))
                .tint(Color.gsPeach)
        }
    }

    private func actionRow(icon: String, title: String, trailing: String? = nil, destructive: Bool = false,
                           disabled: Bool = false, isLast: Bool = false,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            rowChrome(isLast: isLast) {
                iconTile(icon, destructive: destructive)
                Text(title)
                    .font(nunito(15, .bold))
                    .foregroundStyle(destructive ? Color.red : Color.gsFg)
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing).font(nunito(13, .extrabold)).foregroundStyle(Color.gsAccentInk)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }

    // MARK: - Disconnect (last item on screen)

    private var disconnectButton: some View {
        Button { confirmDisconnect = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 14, weight: .bold))
                Text("Disconnect")
                    .font(nunito(14, .extrabold))
            }
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.red.opacity(0.06))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.red.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Delete account sheet

    private var deleteAccountSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Delete your account")
                .font(nunito(23, .black))
                .padding(.top, 28)

            Text("This permanently deletes your account, your posts, comments, likes, group memberships and uploaded photos. It cannot be undone.")
                .font(nunito(14, .semibold))
                .foregroundStyle(Color.fg(0.6))
                .fixedSize(horizontal: false, vertical: true)

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
}
