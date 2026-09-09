import SwiftUI

/// Launch screen. Uses the same logo art as the app icon, so the icon appears to open into
/// the app on cold start.
///
/// The animation is timed to `AppStore.splashDuration` — the loading arc completes exactly as
/// the screen hands off, so the wait reads as progress rather than as a stall. Everything is
/// decorative: tapping still skips ahead, and Reduce Motion collapses it to a plain fade.
struct SplashView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var logoIn = false
    @State private var haloOut = false
    @State private var orbit = false
    @State private var progress: CGFloat = 0
    @State private var wordmarkIn = false

    private let logo: CGFloat = 148
    private let ring: CGFloat = 196

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            // A warm bloom behind the mark so the white ground isn't flat.
            RadialGradient(
                colors: [Color.gsPeach.opacity(0.16), Color.gsPeach.opacity(0)],
                center: .center, startRadius: 8, endRadius: 260
            )
            .frame(width: 520, height: 520)
            .blur(radius: 8)
            .opacity(logoIn ? 1 : 0)
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                mark
                wordmark
                    .padding(.top, 34)
                Spacer()
                loadingBar
                    .padding(.bottom, 54)
            }
            .padding(.horizontal, 44)
        }
        .contentShape(Rectangle())
        .onTapGesture { store.endSplash() }   // tapping still skips ahead
        .onAppear(perform: run)
    }

    // MARK: - Mark

    private var mark: some View {
        ZStack {
            // Two halos breathing outward, like heat rising off a plate.
            if !reduceMotion {
                ForEach(0..<2, id: \.self) { i in
                    Circle()
                        .strokeBorder(Color.gsPeach.opacity(0.35), lineWidth: 1.5)
                        .frame(width: ring, height: ring)
                        .scaleEffect(haloOut ? 1.28 : 0.9)
                        .opacity(haloOut ? 0 : 0.9)
                        .animation(
                            .easeOut(duration: 2.0)
                                .repeatForever(autoreverses: false)
                                .delay(Double(i) * 1.0),
                            value: haloOut
                        )
                }
            }

            // The track, then the arc that fills as the app loads.
            Circle()
                .stroke(Color.gsFill, lineWidth: 4)
                .frame(width: ring, height: ring)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: [.gsPeach, Color(hex: 0xFFA800), .gsPeach],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .frame(width: ring, height: ring)
                .rotationEffect(.degrees(-90))

            // A dot riding the head of the arc.
            if !reduceMotion {
                Circle()
                    .fill(Color.gsPeach)
                    .frame(width: 10, height: 10)
                    .offset(y: -ring / 2)
                    .rotationEffect(.degrees(Double(progress) * 360))
                    .shadow(color: Color.gsPeach.opacity(0.6), radius: 6)
            }

            Image("SplashLogo")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: logo, height: logo)
                .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                .shadow(color: Color.gsFg.opacity(0.10), radius: 22, y: 10)
                .scaleEffect(logoIn ? (orbit ? 1.03 : 1) : 0.78)
                .opacity(logoIn ? 1 : 0)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 1.6).repeatForever(autoreverses: true),
                    value: orbit
                )
        }
    }

    private var wordmark: some View {
        VStack(spacing: 6) {
            Text("goodiesSnap")
                .font(nunito(27, .black))
                .foregroundStyle(Color.gsFg)
            Text("Every recipe, beautifully kept.")
                .font(nunito(13, .semibold))
                .foregroundStyle(Color.gsMuted)
        }
        .opacity(wordmarkIn ? 1 : 0)
        .offset(y: wordmarkIn ? 0 : 10)
    }

    // MARK: - Loading bar

    private var loadingBar: some View {
        VStack(spacing: 12) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gsFill)
                    Capsule()
                        .fill(Color.gsPeach)
                        .frame(width: max(6, geo.size.width * progress))
                }
            }
            .frame(height: 5)
            .frame(maxWidth: 180)

            Text("Warming up the kitchen…")
                .font(nunito(11.5, .bold))
                .foregroundStyle(Color.gsMuted)
        }
        .opacity(wordmarkIn ? 1 : 0)
        .accessibilityElement()
        .accessibilityLabel("Loading goodiesSnap")
    }

    // MARK: - Timing

    private func run() {
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.35)) {
                logoIn = true
                wordmarkIn = true
                progress = 1
            }
        } else {
            withAnimation(.spring(response: 0.62, dampingFraction: 0.68)) { logoIn = true }
            withAnimation(.easeOut(duration: 0.5).delay(0.28)) { wordmarkIn = true }
            // The arc is the honest part: it lands on full exactly when the splash hands off.
            withAnimation(.easeInOut(duration: AppStore.splashDuration - 0.15)) { progress = 1 }
            haloOut = true
            orbit = true
        }
        store.startSplashTimer()
    }
}
