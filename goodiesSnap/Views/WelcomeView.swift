import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var store: AppStore

    private let foods = [
        "🍔", "🍕", "🌮", "🍣", "🥗", "🍰",
        "🍝", "🥘", "🍜", "🧁", "🥑", "🍗"
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Text("goodiesSnap")
                .font(nunito(32, .black))
                .foregroundStyle(Color.gsFg)
                .padding(.bottom, 28)

            // Food illustration grid
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 12)], spacing: 12) {
                ForEach(foods, id: \.self) { emoji in
                    Text(emoji)
                        .font(.system(size: 40))
                        .frame(width: 56, height: 56)
                        .background(Color.gsFill)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(.horizontal, 48)
            .padding(.bottom, 32)

            Text("Welcome to goodiesSnap 🎉")
                .font(nunito(22, .extrabold))
                .foregroundStyle(Color.gsFg)
                .padding(.bottom, 8)

            Text("Your fastest way to save, cook and share\ndelicious recipes — anytime, anywhere.")
                .font(nunito(14, .regular))
                .foregroundStyle(Color.gsMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            Button {
                store.startFromWelcome()
            } label: {
                Text("Let's Start!")
                    .font(nunito(16, .extrabold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(DarkButtonStyle())
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
        .background(Color.white.ignoresSafeArea())
    }
}
