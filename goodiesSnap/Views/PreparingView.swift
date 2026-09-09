import SwiftUI

/// Shown once, between finishing setup and landing on Home.
///
/// The steps are tied to real work — the taste profile is written to disk and the home picks
/// are ranked against it — so the wait states what it's actually doing rather than stalling.
struct PreparingView: View {
    @EnvironmentObject var store: AppStore

    @State private var step = 0
    @State private var markIn = false
    @State private var spin = false
    @State private var burst = false

    private let steps = [
        "Saving your taste profile",
        "Ranking recipes you'll like",
        "Building your shopping list",
        "Setting the table",
    ]

    /// First name for a warm greeting, falling back gracefully.
    private var firstName: String {
        let n = store.userName.trimmingCharacters(in: .whitespaces)
        return n.split(separator: " ").first.map(String.init) ?? (n.isEmpty ? "" : n)
    }

    private var headline: String {
        switch store.welcome {
        case .newAccount:
            return firstName.isEmpty ? "Welcome to goodiesSnap!" : "Welcome, \(firstName)!"
        case .returning:
            return firstName.isEmpty ? "Welcome back!" : "Welcome back, \(firstName)!"
        case nil:
            return "Getting your kitchen ready"
        }
    }

    private var subhead: String {
        switch store.welcome {
        case .newAccount: return "Setting up your kitchen…"
        case .returning: return "Loading your kitchen…"
        case nil: return "Just a moment"
        }
    }

    /// A returning user doesn't need the first-run setup checklist — just a quick greeting.
    private var showsSteps: Bool { store.welcome != .returning }
    private var isWelcome: Bool { store.welcome != nil }

    var body: some View {
        ZStack {
            Color.gsBg.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                ZStack {
                    // A celebratory burst behind the logo, just for the welcome.
                    if isWelcome {
                        ForEach(0..<8, id: \.self) { i in
                            Circle()
                                .fill(i.isMultiple(of: 2) ? Color.gsPeach : Color.gsAccentInk.opacity(0.5))
                                .frame(width: 10, height: 10)
                                .offset(y: burst ? -96 : -20)
                                .rotationEffect(.degrees(Double(i) / 8 * 360))
                                .opacity(burst ? 0 : 1)
                                .scaleEffect(burst ? 0.4 : 1)
                        }
                    }

                    Circle()
                        .stroke(Color.gsFill, lineWidth: 5)
                        .frame(width: 128, height: 128)
                    Circle()
                        .trim(from: 0, to: 0.22)
                        .stroke(Color.gsPeach, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .frame(width: 128, height: 128)
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .animation(.linear(duration: 1.1).repeatForever(autoreverses: false), value: spin)

                    Image("SplashLogo")
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .scaleEffect(markIn ? 1 : 0.8)
                        .opacity(markIn ? 1 : 0)
                }

                Text(headline)
                    .font(nunito(24, .black))
                    .multilineTextAlignment(.center)
                    .padding(.top, 30)
                    .padding(.horizontal, 30)
                    .transition(.opacity)

                Text(subhead)
                    .font(nunito(13, .semibold))
                    .foregroundStyle(Color.gsMuted)
                    .padding(.top, 4)

                // One line per step, ticking off as it completes (skipped for returning users).
                if showsSteps {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, label in
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(i <= step ? Color.gsPeach : Color.gsFill)
                                    .frame(width: 20, height: 20)
                                if i < step {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .black))
                                        .foregroundStyle(Color.gsDock)
                                }
                            }
                            Text(label)
                                .font(nunito(13.5, .bold))
                                .foregroundStyle(i <= step ? Color.gsFg : Color.gsMuted)
                            Spacer(minLength: 0)
                        }
                        .opacity(i <= step ? 1 : 0.45)
                    }
                }
                .frame(maxWidth: 260)
                .padding(.top, 26)
                }

                Spacer()
            }
            .padding(.horizontal, 28)
        }
        .onAppear {
            spin = true
            withAnimation(.spring(response: 0.55, dampingFraction: 0.74)) { markIn = true }
            if isWelcome {
                Haptics.notify(.success)
                withAnimation(.easeOut(duration: 0.8)) { burst = true }
            }
            advance()
        }
    }

    private func advance() {
        Task {
            if showsSteps {
                for i in 0..<steps.count {
                    try? await Task.sleep(for: .seconds(i == 0 ? 0.45 : 0.5))
                    withAnimation(AppStore.stepAnimation) { step = i }
                }
                try? await Task.sleep(for: .seconds(0.45))
            } else {
                // Returning user: a brief, warm beat, then straight to Home.
                try? await Task.sleep(for: .seconds(1.3))
            }
            store.finishPreparing()
        }
    }
}
