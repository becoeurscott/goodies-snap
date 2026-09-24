import SwiftUI

// The onboarding flow's visual language, taken from the hero artwork: an amber-to-orange
// gradient, heavy white type set large, and photography where a lesser design would reach
// for an emoji. Everything below exists so the other sixteen screens read as the same piece
// of design as the first one.

extension Color {
    /// Top of the brand gradient, sampled from the hero artwork.
    static let gsBrandTop = Color(hex: 0xEBAA08)
    /// Bottom of the brand gradient.
    static let gsBrandBottom = Color(hex: 0xF59005)
    /// A deeper orange for scrims that have to sit under white text.
    static let gsBrandDeep = Color(hex: 0xE07C05)
}

/// The brand gradient. Used full-bleed on the moments that carry weight — the opening, the
/// two screens where work is happening, and the offer to plan a week.
struct OBGradient: View {
    var body: some View {
        LinearGradient(
            colors: [.gsBrandTop, .gsBrandBottom],
            startPoint: .top, endPoint: .bottom
        )
    }
}

/// A full-screen gradient page with white type. The counterpart to `OBPage`, for the steps
/// that are a statement rather than a form.
struct OBHeroPage<Content: View, Action: View>: View {
    var kicker: String = ""
    var title: String
    var subtitle: String = ""
    @ViewBuilder var content: () -> Content
    @ViewBuilder var action: () -> Action

    var body: some View {
        // No background here: the router paints the gradient for the whole screen, so it
        // runs behind the progress bar instead of starting under it.
        VStack(spacing: 0) {
            Group {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if !kicker.isEmpty {
                            Text(kicker.uppercased())
                                .font(nunito(11, .extrabold))
                                .tracking(1.6)
                                .foregroundStyle(.white.opacity(0.75))
                                .padding(.bottom, 12)
                        }
                        Text(title)
                            .font(nunito(32, .black))
                            .tracking(-1)
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(nunito(15, .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 10)
                        }
                        content()
                            .padding(.top, 26)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 26)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
                .scrollBounceBehavior(.basedOnSize)
            }

            VStack(spacing: 8) { action() }
                .padding(.horizontal, 26)
                .padding(.bottom, 14)
        }
    }
}

/// The light button used on top of the gradient — white on orange, the inverse of the
/// flow's normal dark button.
struct OBLightPrimary: View {
    var title: String
    var enabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap(.medium)
            action()
        } label: {
            Text(title)
                .font(nunito(16, .extrabold))
                .foregroundStyle(Color.gsFg)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Color.white)
                .clipShape(Capsule())
        }
        .buttonStyle(PressableStyle(scale: 0.97))
        .opacity(enabled ? 1 : 0.5)
        .disabled(!enabled)
    }
}

/// The quiet option on a gradient page.
struct OBLightSecondary: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap(.light)
            action()
        } label: {
            Text(title)
                .font(nunito(14.5, .bold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
    }
}

/// A stat set in the brand's own voice: the number carries the screen, the label steps back.
/// Replaces the icon-in-a-circle rows that made the summary screens look like a settings list.
struct OBBigStat: View {
    var value: String
    var label: String
    var onGradient: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(value)
                .font(nunito(30, .black))
                .tracking(-0.8)
                .foregroundStyle(onGradient ? .white : Color.gsFg)
                // Wide enough for a formatted price, so the labels line up in a column
                // instead of stepping right whenever the number gets longer.
                .frame(minWidth: 132, alignment: .leading)
            Text(label)
                .font(nunito(14, .bold))
                .foregroundStyle(onGradient ? .white.opacity(0.8) : Color.gsMuted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(onGradient ? Color.white.opacity(0.18) : Color.gsFg.opacity(0.07))
                .frame(height: 1)
        }
    }
}

/// The ring shown while real work happens. An animated arc rather than a sparkle emoji —
/// it reads as the app doing something, not as decoration.
struct OBWorkingRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinning = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.28), lineWidth: 3)
            Circle()
                .trim(from: 0, to: 0.24)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(reduceMotion ? nil : .linear(duration: 1).repeatForever(autoreverses: false),
                           value: spinning)
        }
        .frame(width: 54, height: 54)
        .onAppear { spinning = true }
    }
}

/// A photographic header: the dish itself, with a scrim so white type sits on it — the same
/// move the hero artwork makes with the model.
struct OBPhotoHeader: View {
    var url: URL?
    var kicker: String = ""
    var title: String
    var meta: String = ""

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CoverImage(url: url)
                .frame(height: 290)

            LinearGradient(
                colors: [.clear, .black.opacity(0.25), .black.opacity(0.78)],
                startPoint: .center, endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 7) {
                if !kicker.isEmpty {
                    Text(kicker.uppercased())
                        .font(nunito(10.5, .extrabold))
                        .tracking(1.6)
                        .foregroundStyle(Color.gsPeach)
                }
                Text(title)
                    .font(nunito(27, .black))
                    .tracking(-0.7)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                if !meta.isEmpty {
                    Text(meta)
                        .font(nunito(13, .bold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(20)
        }
        .frame(height: 290)
        .clipped()
    }
}
