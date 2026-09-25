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
    @State private var manageTab = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                identityCard
                    .padding(.top, 22)
                statsGrid
                    .padding(.top, 16)
                subscriptionCard
                    .padding(.top, 16)
                manageSection
                    .padding(.top, 28)
                legalSection
                    .padding(.top, 28)

                if social.signedIn {
                    disconnectButton
                        .padding(.top, 28)
                }

                Text("goodiesSnap 1.0 — every recipe, beautifully kept.")
                    .font(nunito(11.5, .semibold))
                    .foregroundStyle(Color.fg(0.3))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)
            }
            .padding(.horizontal, 22)
            .padding(.top, 16)
            .padding(.bottom, 44)
        }
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

    // MARK: - Identity card

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

    // MARK: - Subscription

    @ViewBuilder
    private var subscriptionCard: some View {
        let plan = store.entitlement.plan
        if plan.isPaid {
            HStack(spacing: 12) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.gsAccentInk)
                    .frame(width: 42, height: 42)
                    .background(Color.gsPeachSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(plan.title) active")
                        .font(nunito(15, .extrabold))
                    Text("\(store.entitlement.remaining) AI actions left this month")
                        .font(nunito(11.5, .semibold))
                        .foregroundStyle(Color.gsMuted)
                }
                Spacer()
                Button("Manage") { store.showPaywall(.upgrade) }
                    .font(nunito(12.5, .extrabold))
                    .foregroundStyle(Color.gsAccentInk)
                    .buttonStyle(.plain)
            }
            .padding(14)
            .glassCard(radius: 20, fill: 0.05, stroke: 0.1)
        } else {
            Button { store.showPaywall(.upgrade) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.gsPeach)
                        .frame(width: 42, height: 42)
                        .background(Color.gsDock)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Upgrade to Pro")
                            .font(nunito(15, .extrabold))
                        Text("\(store.entitlement.remaining) free AI actions left this month")
                            .font(nunito(11.5, .semibold))
                            .foregroundStyle(Color.fg(0.5))
                    }
                    Spacer(minLength: 8)
                    Text("Upgrade")
                        .font(nunito(12.5, .extrabold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(Color.gsDock)
                        .clipShape(Capsule())
                }
                .padding(14)
                .background(Color.gsPeachSoft)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.gsPeach.opacity(0.5), lineWidth: 1.5))
            }
            .buttonStyle(PressableStyle(scale: 0.98))
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

    // MARK: - Manage (tabbed: Profile / Kitchen / Actions)

    private var manageSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Manage")
                .font(nunito(19, .extrabold))

            HStack(spacing: 0) {
                manageTabButton("Profile", index: 0)
                manageTabButton("Kitchen", index: 1)
                manageTabButton("Actions", index: 2)
            }
            .padding(4)
            .background(Color.fg(0.06))
            .clipShape(Capsule())

            switch manageTab {
            case 0: profileTab
            case 1: kitchenTab
            default: actionsTab
            }
        }
    }

    private func manageTabButton(_ title: String, index: Int) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { manageTab = index }
        } label: {
            Text(title)
                .font(nunito(13, .extrabold))
                .foregroundStyle(manageTab == index ? Color.gsFg : Color.fg(0.45))
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(manageTab == index ? Color.gsBg : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var profileTab: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "person.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.fg(0.55))
                    .frame(width: 20)
                Text("Name")
                    .font(nunito(13.5, .bold))
                Spacer()
                Text(store.userName.isEmpty ? "Not set" : store.userName)
                    .font(nunito(13.5, .bold))
                    .foregroundStyle(Color.fg(0.5))
            }
            .frame(minHeight: 48)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.fg(0.07)).frame(height: 1)
            }

            if social.signedIn && !social.blockedIDs.isEmpty {
                HStack(spacing: 14) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.fg(0.55))
                        .frame(width: 20)
                    Text("\(social.blockedIDs.count) blocked")
                        .font(nunito(13.5, .bold))
                    Spacer()
                    Button("Unblock all") {
                        for id in social.blockedIDs { social.unblock(userID: id) }
                    }
                    .font(nunito(12, .extrabold))
                    .foregroundStyle(Color.gsAccentInk)
                    .buttonStyle(.plain)
                }
                .frame(minHeight: 48)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .glassCard(radius: 20, fill: 0.05, stroke: 0.1)
    }

    private var kitchenTab: some View {
        VStack(spacing: 0) {
            infoRow(icon: "globe", title: "Cooks the most", value: store.topCuisine ?? "—")
            infoRow(icon: "clock", title: "Average cook time",
                    value: store.recipes.isEmpty ? "—" : "\(store.avgCookTime) min")
            infoRow(icon: "cart", title: "On the shopping list",
                    value: "\(store.undoneCount) to buy", isLast: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .glassCard(radius: 20, fill: 0.05, stroke: 0.1)
    }

    private var actionsTab: some View {
        VStack(spacing: 10) {
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
                Text("Clear saved library")
                    .font(nunito(12.5, .bold))
                    .foregroundStyle(Color.fg(0.4))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Privacy & legal

    private var legalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Privacy & legal")
                .font(nunito(19, .extrabold))

            Toggle("Allow AI recipe processing", isOn: Binding(
                get: { store.aiSharingAllowed },
                set: { value in
                    if value { store.showAIConsent = true }
                    else { store.finishAIConsent(allow: false) }
                }
            ))
            .padding(.vertical, 8)

            Button { store.go(to: .support) } label: {
                HStack(spacing: 14) {
                    Image(systemName: "bubble.left.and.text.bubble.right.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 42, height: 42)
                        .background(Color.gsPeach)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Help & support")
                            .font(nunito(15, .extrabold))
                        Text("FAQs & email support")
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

            VStack(spacing: 0) {
                legalRow(icon: "doc.text", title: "Terms of Use", url: Legal.terms)
                legalRow(icon: "hand.raised", title: "Privacy Policy", url: Legal.privacy, isLast: !social.signedIn)
                if social.signedIn {
                    Button {
                        deleteConfirmation = ""
                        deleteFailed = ""
                        confirmDelete = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "trash")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.red.opacity(0.7))
                                .frame(width: 20)
                            Text("Delete my account")
                                .font(nunito(13.5, .bold))
                                .foregroundStyle(.red)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.fg(0.4))
                        }
                        .frame(minHeight: 48)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .glassCard(radius: 20, fill: 0.05, stroke: 0.1)
        }
    }

    private func legalRow(icon: String, title: String, url: URL, isLast: Bool = false) -> some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.fg(0.55))
                    .frame(width: 20)
                Text(title)
                    .font(nunito(13.5, .bold))
                    .foregroundStyle(Color.gsFg)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.fg(0.4))
            }
            .frame(minHeight: 48)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if !isLast {
                    Rectangle().fill(Color.fg(0.07)).frame(height: 1)
                }
            }
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
