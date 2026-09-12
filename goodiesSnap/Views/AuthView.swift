import SwiftUI

/// Sign in / create account.
///
/// Layout follows a clean illustrated-auth reference — a food hero up top, a big
/// left-aligned title, underline fields with a leading icon and floating label, a
/// full-width primary action, social options, and a footer link to switch modes — but in
/// goodiesSnap's own palette rather than the reference's blue. One screen for both modes,
/// so switching never discards what's already typed.
struct AuthView: View {
    @EnvironmentObject var social: SocialStore
    @EnvironmentObject var store: AppStore

    enum Mode: String, CaseIterable {
        case signIn = "Sign in"
        case signUp = "Create account"
    }

    @State private var mode: Mode = .signIn
    @State private var didPreselect = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var acceptedTerms = false
    /// Only show validation once a field has been visited, so it never scolds you up front.
    @State private var touchedEmail = false
    @State private var touchedPassword = false
    @FocusState private var focus: Field?

    private enum Field { case name, email, password }

    private var isSignUp: Bool { mode == .signUp }

    // MARK: Validation

    private var emailValid: Bool {
        let t = email.trimmingCharacters(in: .whitespaces)
        return t.contains("@") && t.contains(".") && !t.hasPrefix("@") && t.count >= 6
    }
    private var passwordValid: Bool { password.count >= 8 }
    private var nameValid: Bool { !isSignUp || name.trimmingCharacters(in: .whitespaces).count >= 2 }
    private var termsAccepted: Bool { !isSignUp || acceptedTerms }
    private var canSubmit: Bool { emailValid && passwordValid && nameValid && termsAccepted && !social.busy }

    private var emailError: String? {
        guard touchedEmail, !email.isEmpty, !emailValid else { return nil }
        return "That doesn't look like an email address"
    }
    private var passwordError: String? {
        guard touchedPassword, !password.isEmpty, !passwordValid else { return nil }
        return "Use at least 8 characters"
    }

    var body: some View {
        // Fits one screen with no scroll when idle; the content is pinned to at least the
        // available height, so a scroll only appears when the keyboard shrinks that height
        // — the lower fields then stay reachable instead of hiding behind the keyboard.
        GeometryReader { geo in
            ScrollView {
                content
                    .frame(minHeight: geo.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color.gsBg)
        .onAppear {
            // Arriving from a feature wall means they almost certainly need an account.
            if !didPreselect {
                didPreselect = true
                if store.isSettingUpAccount
                    || (store.authReason != .general && store.authReason != .community) {
                    mode = .signUp
                }
            }
        }
        // Redirect after sign-in is driven from RootView (always mounted), so it fires
        // reliably even as this screen is torn down.
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            hero

            Text(title)
                .font(nunito(27, .black))
                .foregroundStyle(Color.gsFg)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 12)
            Text(subtitle)
                .font(nunito(12.5, .semibold))
                .foregroundStyle(Color.gsMuted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)

            fields
                .padding(.top, 16)

            submitButton
                .padding(.top, 16)

            orDivider
                .padding(.top, 14)

            socialRow
                .padding(.top, 12)

            if isSignUp {
                termsRow
                    .padding(.top, 12)
            }

            Spacer(minLength: 8)

            switchModeRow
        }
        .padding(.horizontal, 26)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var title: String {
        isSignUp ? "Create account" : "Welcome back"
    }

    private var subtitle: String {
        if isSignUp {
            return store.isSettingUpAccount
                ? "So your recipes, plan and answers follow you to any device."
                : store.authReason.blurb
        }
        return "Sign in to your recipes, plan and the community feed."
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            if !store.isSettingUpAccount {
                Button { store.goBack() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(Color.gsFg)
                        .frame(width: 42, height: 42)
                        .background(Color.gsCard)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Color.gsFg.opacity(0.08), lineWidth: 1))
                }
                .buttonStyle(PressableStyle(scale: 0.94))
            }
            Spacer()
        }
        .frame(height: 42)
        .padding(.top, 8)
    }

    // MARK: Hero (app logo)

    /// The app's own logo, on a white tile matching the icon and splash — so the auth
    /// screen opens with the same brand mark the user tapped to get here.
    private var hero: some View {
        Image("SplashLogo")
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: 104, height: 104)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 6)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }

    // MARK: Fields

    private var fields: some View {
        VStack(spacing: 20) {
            if isSignUp {
                UnderlineField(icon: "person", label: "Full name", text: $name,
                               focused: focus == .name)
                    .focused($focus, equals: .name)
                    .textInputAutocapitalization(.words)
                    .textContentType(.name)
                    .submitLabel(.next)
                    .onSubmit { focus = .email }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            UnderlineField(icon: "envelope", label: "Email address", text: $email,
                           focused: focus == .email, error: emailError, keyboard: .emailAddress)
                .focused($focus, equals: .email)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.emailAddress)
                .submitLabel(.next)
                .onSubmit { focus = .password }
                .onChange(of: focus) { _, cur in
                    if cur != .email, !email.isEmpty { touchedEmail = true }
                }

            passwordField

            if isSignUp == false {
                // A place for forgot-password to live; wired once the reset flow exists.
                HStack {
                    Spacer()
                    Button("Forgot password?") {
                        store.showToast("Password reset is coming soon", seconds: 2.4)
                    }
                    .font(nunito(12, .extrabold))
                    .foregroundStyle(Color.gsAccentInk)
                    .buttonStyle(.plain)
                }
            }

            if !social.errorMessage.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text(social.errorMessage)
                        .font(nunito(12, .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Color.gsAccentInk)
                .padding(12)
                .background(Color.gsPeachSoft)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .animation(AppStore.stepAnimation, value: isSignUp)
        .animation(AppStore.stepAnimation, value: social.errorMessage)
    }

    /// Password reuses the underline style but keeps its own show/hide control.
    private var passwordField: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 12) {
                Image(systemName: "lock")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(focus == .password ? Color.gsFg : Color.gsMuted)
                    .frame(width: 20)

                ZStack(alignment: .leading) {
                    if password.isEmpty {
                        Text("Password")
                            .font(nunito(14.5, .semibold))
                            .foregroundStyle(Color.gsMuted)
                    }
                    Group {
                        if showPassword {
                            TextField("", text: $password)
                        } else {
                            SecureField("", text: $password)
                        }
                    }
                    .font(nunito(14.5, .semibold))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { if canSubmit { submit() } }
                }

                Button { showPassword.toggle() } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.gsMuted)
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 34)

            Rectangle()
                .fill(underlineColor(active: focus == .password, error: passwordError != nil))
                .frame(height: focus == .password ? 2 : 1.2)

            if let passwordError {
                Text(passwordError)
                    .font(nunito(11.5, .bold))
                    .foregroundStyle(Color.gsAccentInk)
            }
        }
        .onChange(of: focus) { _, f in if f != .password && !password.isEmpty { touchedPassword = true } }
    }

    private func underlineColor(active: Bool, error: Bool) -> Color {
        if error { return Color.gsAccentInk.opacity(0.7) }
        return active ? Color.gsFg : Color.gsFg.opacity(0.18)
    }

    // MARK: Actions

    private var submitButton: some View {
        Button(action: submit) {
            Group {
                if social.busy {
                    ProgressView().tint(Color.white)
                } else {
                    Text(isSignUp ? "Create account" : "Sign in")
                        .font(nunito(15.5, .extrabold))
                }
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 54)
        }
        .buttonStyle(DarkButtonStyle())
        .disabled(!canSubmit)
        .opacity(canSubmit ? 1 : 0.45)
    }

    private var orDivider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Color.gsFg.opacity(0.12)).frame(height: 1)
            Text("or continue with")
                .font(nunito(11, .bold))
                .foregroundStyle(Color.gsMuted)
                .fixedSize()
            Rectangle().fill(Color.gsFg.opacity(0.12)).frame(height: 1)
        }
    }

    /// Full-width Apple and Google buttons, matching the reference's social row.
    ///
    /// Presentation only for now: Sign in with Apple needs the entitlement plus server-side
    /// token verification, and Google needs its SDK and an OAuth client id. Rather than fake
    /// a sign-in, each says so when tapped.
    private var socialRow: some View {
        HStack(spacing: 12) {
            socialButton {
                Image(systemName: "apple.logo")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.gsFg)
                Text("Apple").font(nunito(13.5, .extrabold)).foregroundStyle(Color.gsFg)
            } action: {
                store.showToast("Apple sign-in isn't set up yet", seconds: 2.4)
            }

            socialButton {
                GoogleGlyph().frame(width: 18, height: 18)
                Text("Google").font(nunito(13.5, .extrabold)).foregroundStyle(Color.gsFg)
            } action: {
                store.showToast("Google sign-in isn't set up yet", seconds: 2.4)
            }
        }
    }

    private func socialButton<L: View>(@ViewBuilder label: () -> L,
                                       action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) { label() }
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Color.gsCard)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.gsFg.opacity(0.12), lineWidth: 1.5)
                )
        }
        .buttonStyle(PressableStyle(scale: 0.96))
    }

    /// Footer link that flips modes, like the reference's "Joined us before? Login".
    private var switchModeRow: some View {
        HStack(spacing: 5) {
            Spacer()
            Text(isSignUp ? "Already have an account?" : "New to goodiesSnap?")
                .font(nunito(12.5, .semibold))
                .foregroundStyle(Color.gsMuted)
            Button(isSignUp ? "Sign in" : "Create one") {
                withAnimation(AppStore.stepAnimation) {
                    mode = isSignUp ? .signIn : .signUp
                }
                social.errorMessage = ""
            }
            .font(nunito(12.5, .extrabold))
            .foregroundStyle(Color.gsAccentInk)
            .buttonStyle(.plain)
            Spacer()
        }
    }

    /// Guideline 1.2 requires people to actively agree to the community rules before they
    /// can post, so this is a real checkbox that gates the button — not a footnote.
    private var termsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Haptics.tap(.light)
                acceptedTerms.toggle()
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: acceptedTerms ? "checkmark.square.fill" : "square")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(acceptedTerms ? Color.gsAccentInk : Color.gsMuted)
                    // Compact wording keeps the required agreement to two lines; the full
                    // rules live in the linked documents below.
                    (Text("I agree to the ")
                        .foregroundStyle(Color.gsMuted)
                     + Text("Terms").foregroundStyle(Color.gsAccentInk)
                     + Text(" and ").foregroundStyle(Color.gsMuted)
                     + Text("Privacy Policy").foregroundStyle(Color.gsAccentInk)
                     + Text(", and the community rules.").foregroundStyle(Color.gsMuted))
                        .font(nunito(11.5, .semibold))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Agree to the Terms of Use, Privacy Policy and community rules")
            .accessibilityAddTraits(acceptedTerms ? [.isSelected] : [])

            HStack(spacing: 16) {
                Link("Terms of Use", destination: Legal.terms)
                Link("Privacy Policy", destination: Legal.privacy)
            }
            .font(nunito(10.5, .extrabold))
            .foregroundStyle(Color.gsAccentInk)
            .padding(.leading, 29)
        }
    }

    private func submit() {
        focus = nil
        touchedEmail = true
        touchedPassword = true
        guard canSubmit else { return }
        let mail = email.trimmingCharacters(in: .whitespaces)
        Task {
            if isSignUp {
                await social.signUp(email: mail, password: password,
                                    name: name.trimmingCharacters(in: .whitespaces))
            } else {
                await social.signIn(email: mail, password: password)
            }
        }
    }
}

// MARK: - Underline field

/// Leading icon + floating label + underline, the reference's input treatment. The label
/// lifts to a caption once the field has content; the underline thickens and darkens on
/// focus. Field modifiers (`.focused`, `.keyboardType`, …) are applied by the caller.
private struct UnderlineField: View {
    let icon: String
    let label: String
    @Binding var text: String
    var focused: Bool
    var error: String? = nil
    var keyboard: UIKeyboardType = .default

    private var lifted: Bool { focused || !text.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(focused ? Color.gsFg : Color.gsMuted)
                    .frame(width: 20)

                ZStack(alignment: .leading) {
                    if !lifted {
                        Text(label)
                            .font(nunito(14.5, .semibold))
                            .foregroundStyle(Color.gsMuted)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        if lifted {
                            Text(label)
                                .font(nunito(9.5, .extrabold))
                                .foregroundStyle(Color.gsMuted)
                                .transition(.opacity)
                        }
                        TextField("", text: $text)
                            .font(nunito(14.5, .semibold))
                            .keyboardType(keyboard)
                    }
                }
            }
            .frame(minHeight: 40)
            .animation(AppStore.stepAnimation, value: lifted)

            Rectangle()
                .fill(underlineColor)
                .frame(height: focused ? 2 : 1.2)

            if let error {
                Text(error)
                    .font(nunito(11.5, .bold))
                    .foregroundStyle(Color.gsAccentInk)
            }
        }
    }

    private var underlineColor: Color {
        if error != nil { return Color.gsAccentInk.opacity(0.7) }
        return focused ? Color.gsFg : Color.gsFg.opacity(0.18)
    }
}

/// Google's "G", approximated with arcs.
///
/// NOTE: Google's brand guidelines require their **official** asset, unmodified. Replace
/// this with the supplied artwork from the Google Identity brand pages before shipping.
struct GoogleGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let lw = s * 0.22
            ZStack {
                arc(from: -30, to: 60, color: Color(hex: 0x4285F4), size: s, lw: lw)   // blue
                arc(from: 60, to: 150, color: Color(hex: 0x34A853), size: s, lw: lw)   // green
                arc(from: 150, to: 220, color: Color(hex: 0xFBBC05), size: s, lw: lw)  // yellow
                arc(from: 220, to: 330, color: Color(hex: 0xEA4335), size: s, lw: lw)  // red
                Rectangle()
                    .fill(Color(hex: 0x4285F4))
                    .frame(width: s * 0.30, height: lw)
                    .offset(x: s * 0.16, y: 0)
            }
            .frame(width: s, height: s)
        }
    }

    private func arc(from: Double, to: Double, color: Color, size: CGFloat, lw: CGFloat) -> some View {
        Circle()
            .trim(from: from / 360, to: to / 360)
            .stroke(color, style: StrokeStyle(lineWidth: lw, lineCap: .butt))
            .frame(width: size - lw, height: size - lw)
    }
}
