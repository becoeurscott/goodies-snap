import SwiftUI

/// Launch screen. Uses the same logo art as the app icon, so the icon appears to open into
/// the app on cold start.
struct SplashView: View {
    @EnvironmentObject var store: AppStore

    @State private var logoIn = false

    private let logo: CGFloat = 188

    var body: some View {
        ZStack {
            Color.white
            .ignoresSafeArea()

            Image("SplashLogo")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: logo, height: logo)
                .clipShape(RoundedRectangle(cornerRadius: 42, style: .continuous))
                .scaleEffect(logoIn ? 1 : 0.82)
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
