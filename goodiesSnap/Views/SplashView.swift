import SwiftUI

/// Launch screen. Uses the same logo art as the app icon, so the icon appears to open into
/// the app on cold start.
struct SplashView: View {
    @EnvironmentObject var store: AppStore

    @State private var logoIn = false

    private let logo: CGFloat = 240
    /// The icon art's own background yellow, so the wordmark sits flush on the screen.
    private let splashYellow = Color(hex: 0xFDE604)

    var body: some View {
        ZStack {
            splashYellow
                .ignoresSafeArea()

            Image("SplashLogo")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: logo, height: logo)
                .scaleEffect(logoIn ? 1 : 0.86)
                .opacity(logoIn ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { store.endSplash() }   // tapping still skips ahead
        .onAppear(perform: run)
    }

    private func run() {
        withAnimation(.spring(response: 0.55, dampingFraction: 0.74)) { logoIn = true }
        store.startSplashTimer()
    }
}
