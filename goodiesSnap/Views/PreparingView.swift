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

    private let steps = [
        "Saving your taste profile",
        "Ranking recipes you'll like",
        "Building your shopping list",
        "Setting the table",
    ]

    var body: some View {
        ZStack {
            Color.gsBg.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                ZStack {
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

                Text("Getting your kitchen ready")
                    .font(nunito(23, .black))
                    .multilineTextAlignment(.center)
                    .padding(.top, 30)
                    .padding(.horizontal, 30)

                // One line per step, ticking off as it completes.
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

                Spacer()
            }
            .padding(.horizontal, 28)
        }
        .onAppear {
            spin = true
            withAnimation(.spring(response: 0.55, dampingFraction: 0.74)) { markIn = true }
            advance()
        }
    }

    private func advance() {
        Task {
            for i in 0..<steps.count {
                try? await Task.sleep(for: .seconds(i == 0 ? 0.45 : 0.5))
                withAnimation(AppStore.stepAnimation) { step = i }
            }
            try? await Task.sleep(for: .seconds(0.45))
            store.finishPreparing()
        }
    }
}
