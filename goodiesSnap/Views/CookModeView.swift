import SwiftUI

struct CookModeView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        if let sel = store.selected {
            let steps = sel.steps

            ZStack {
                CoverImage(url: sel.imageURL)
                    .opacity(0.22)
                    .blur(radius: 6)
                    .ignoresSafeArea()

                LinearGradient(
                    stops: [
                        .init(color: Color.gsBg.opacity(0.75), location: 0),
                        .init(color: .gsBg, location: 0.7),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Kicker(text: "Cook mode", size: 11, tracking: 1.5, opacity: 1)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(Color.fg(0.09))
                            .clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(Color.fg(0.14), lineWidth: 1))
                        Spacer()
                        Button { store.goBack() } label: {
                            Text("Exit")
                                .font(nunito(14, .bold))
                                .foregroundStyle(Color.fg(0.55))
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                    }

                    Text(sel.title)
                        .font(nunito(19, .extrabold))
                        .padding(.top, 12)

                    HStack(spacing: 5) {
                        ForEach(0..<steps.count, id: \.self) { i in
                            Capsule()
                                .fill(i <= store.cookStep ? Color.gsFg : Color.fg(0.15))
                                .frame(height: 4)
                        }
                    }
                    .padding(.top, 16)

                    Spacer()

                    VStack(alignment: .leading, spacing: 0) {
                        Text(String(format: "%02d", store.cookStep + 1))
                            .font(nunito(64, .black))
                            .foregroundStyle(Color.fg(0.16))
                        Kicker(text: "Step \(store.cookStep + 1) of \(steps.count)", size: 11.5, tracking: 1.5, opacity: 0.5)
                            .padding(.top, 10)
                            .padding(.bottom, 14)
                        Text(steps.indices.contains(store.cookStep) ? steps[store.cookStep] : "")
                            .font(nunito(27, .extrabold))
                            .lineSpacing(6)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .id("cookStep\(store.cookStep)")
                    .transition(.move(edge: .bottom).combined(with: .opacity))

                    Spacer()

                    HStack(spacing: 12) {
                        Button { store.prevCookStep() } label: {
                            Text("Previous")
                                .font(nunito(15, .extrabold))
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .background(Color.fg(0.06))
                                .clipShape(Capsule())
                                .overlay(Capsule().strokeBorder(Color.fg(0.18), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(store.cookStep == 0)
                        .opacity(store.cookStep == 0 ? 0.4 : 1)

                        Button { store.nextCookStep() } label: {
                            Text(store.cookStep >= steps.count - 1 ? "Finish" : "Next step")
                                .font(nunito(15, .extrabold))
                                .foregroundStyle(Color.white)
                                .frame(maxWidth: .infinity, minHeight: 56)
                        }
                        .buttonStyle(CreamButtonStyle())
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .animation(.easeOut(duration: 0.3), value: store.cookStep)
            }
        }
    }
}
