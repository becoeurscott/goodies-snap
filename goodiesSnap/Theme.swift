import SwiftUI
import UIKit
import AudioToolbox

enum Haptics {
    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}

enum PreferenceSound {
    static func tick() {
        AudioServicesPlaySystemSound(1104)
    }

    static func success() {
        AudioServicesPlaySystemSound(1025)
    }
}

// MARK: - Palette (from the reference design)

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// Screen background — clean white with a faint warm whisper.
    static let gsBg = Color(hex: 0xFBFAF3)
    /// Primary text — near-black with a warm undertone.
    static let gsFg = Color(hex: 0x1E1A10)
    /// Cards / sheets — pure white, popping off the tinted background.
    static let gsCard = Color(hex: 0xFFFFFF)
    /// Sheet surface (same family as cards).
    static let gsSheet = Color(hex: 0xFFFFFF)
    /// Recessed fills: inputs, inactive arc segments, subtle chips.
    static let gsFill = Color(hex: 0xF5EEDA)
    /// Secondary text.
    static let gsMuted = Color(hex: 0x8A8172)
    /// Accent — vibrant yellow. Use for FILLS and on dark surfaces only: at 2.3:1 against
    /// white it is unreadable as text. For accent text on light surfaces use `gsAccentInk`.
    static let gsPeach = Color(hex: 0xFFC400)
    static let gsPeachSoft = Color(hex: 0xFFF0C2)
    /// Accent text/icons on light surfaces — deep amber, 5.2:1 on white (passes AA).
    static let gsAccentInk = Color(hex: 0x8F6300)
    /// Bottom dock and primary CTAs — black.
    static let gsDock = Color(hex: 0x000000)
    static let gsFgHover = Color(hex: 0x2A2A2A)

    /// Foreground at an opacity — used for hairlines and secondary text.
    static func fg(_ opacity: Double) -> Color { Color.gsFg.opacity(opacity) }
}

// MARK: - Type

enum GSWeight {
    case regular, semibold, bold, extrabold, black

    // PostScript names of the bundled Fontsource static instances
    var psName: String {
        switch self {
        case .regular: return "NunitoSans12ptExtraLight12pt-Regular"
        case .semibold: return "NunitoSans12ptExtraLight12pt-SemiBold"
        case .bold: return "NunitoSans12ptExtraLight12pt-Bold"
        case .extrabold: return "NunitoSans12ptExtraLight12pt-ExtraBold"
        case .black: return "NunitoSans12ptExtraLight12pt-Black"
        }
    }
}

func nunito(_ size: CGFloat, _ weight: GSWeight = .regular) -> Font {
    .custom(weight.psName, fixedSize: size)
}

// MARK: - Surfaces

/// Elevated white card with a soft drop shadow (the reference's default surface).
struct SoftCard: ViewModifier {
    var radius: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .background(Color.gsCard)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: Color.black.opacity(0.06), radius: 18, x: 0, y: 10)
    }
}

/// Kept for source compatibility: former dark "glass" cards now render as soft white cards.
struct GlassCard: ViewModifier {
    var radius: CGFloat = 22
    var fill: Double = 0.06
    var stroke: Double = 0.14

    func body(content: Content) -> some View {
        content.modifier(SoftCard(radius: radius))
    }
}

/// Recessed input / chip surface (no shadow).
struct FillSurface: ViewModifier {
    var radius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .background(Color.gsFill)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func softCard(radius: CGFloat = 24) -> some View { modifier(SoftCard(radius: radius)) }
    func glassCard(radius: CGFloat = 22, fill: Double = 0.06, stroke: Double = 0.14) -> some View {
        modifier(GlassCard(radius: radius, fill: fill, stroke: stroke))
    }
    func fillSurface(radius: CGFloat = 16) -> some View { modifier(FillSurface(radius: radius)) }
}

// MARK: - Buttons

/// Primary CTA — charcoal pill with white text (reference "Get Started").
struct DarkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.gsFgHover : Color.gsDock)
            .clipShape(Capsule())
    }
}

/// Alias kept for source compatibility — the old cream CTA is now the dark primary.
typealias CreamButtonStyle = DarkButtonStyle

/// Accent action — peach pill.
struct PeachButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.gsPeach.opacity(0.78) : Color.gsPeach)
            .clipShape(Capsule())
    }
}

/// Secondary pill — recessed fill, dark text.
struct FillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.gsFill.opacity(0.7) : Color.gsFill)
            .clipShape(Capsule())
    }
}

/// Gives a tappable card a subtle press-in response, so touches feel immediate.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.975

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Small components

/// Kicker text: small uppercase letter-spaced label
struct Kicker: View {
    let text: String
    var size: CGFloat = 11
    var tracking: CGFloat = 2
    var opacity: Double = 0.55

    var body: some View {
        Text(text.uppercased())
            .font(nunito(size, .extrabold))
            .tracking(tracking)
            .foregroundStyle(Color.gsMuted.opacity(min(1, opacity + 0.35)))
    }
}

/// Small round icon button on a white card (reference header buttons).
struct IconButton: View {
    let system: String
    var badge: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.gsFg)
                .frame(width: 46, height: 46)
                .background(Color.gsCard)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 6)
                .overlay(alignment: .topTrailing) {
                    if badge {
                        Circle().fill(Color.gsPeach).frame(width: 9, height: 9)
                            .overlay(Circle().strokeBorder(Color.gsCard, lineWidth: 2))
                            .offset(x: -10, y: 10)
                    }
                }
        }
        .buttonStyle(PressableStyle(scale: 0.94))
    }
}

/// The reference's "Easy ▮▮▮▯▯" difficulty meter, derived from cook time.
struct DifficultyBars: View {
    var filled: Int = 3

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(i < filled ? Color.gsPeach : Color.gsFill)
                    .frame(width: 8, height: 20)
            }
        }
    }
}

extension Recipe {
    /// Rough difficulty from total time: ≤20 min easy … ≥60 min hard.
    var difficultyBars: Int { min(5, max(1, (totalMinutes + 9) / 12)) }
    var difficultyLabel: String {
        switch difficultyBars {
        case 0...2: return "Easy"
        case 3: return "Medium"
        default: return "Hard"
        }
    }
}

/// Remote image with cover-fit behavior, soft placeholder while loading.
struct CoverImage: View {
    let url: URL?

    var body: some View {
        GeometryReader { geo in
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure:
                    // A failed load used to sit as a blank block forever; say so quietly.
                    ZStack {
                        Color.gsFill
                        Image(systemName: "photo")
                            .font(.system(size: 20, weight: .light))
                            .foregroundStyle(Color.gsMuted)
                    }
                default:
                    SkeletonBlock()
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }
}

// MARK: - Loading

/// Sweeping highlight used for anything still loading. Honours Reduce Motion.
struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [.clear, Color.white.opacity(0.65), .clear],
                            startPoint: .leading, endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 0.55)
                        .offset(x: phase * geo.size.width * 1.8)
                    }
                }
            }
            .clipped()
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

extension View {
    func shimmering() -> some View { modifier(Shimmer()) }
}

/// Grey placeholder for content that hasn't arrived yet.
struct SkeletonBlock: View {
    var radius: CGFloat = 0

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.gsFill)
            .shimmering()
    }
}

/// The app's one inline loading indicator, so waiting looks the same everywhere.
struct GSLoader: View {
    var label: String? = nil
    var compact = false

    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(Color.gsAccentInk)
                .scaleEffect(compact ? 0.85 : 1)
            if let label {
                Text(label)
                    .font(nunito(12.5, .bold))
                    .foregroundStyle(Color.gsMuted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, compact ? 18 : 40)
    }
}

/// Placeholder card shown while the feed is being fetched.
struct SkeletonPostCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle().fill(Color.gsFill).frame(width: 34, height: 34).shimmering()
                VStack(alignment: .leading, spacing: 6) {
                    SkeletonBlock(radius: 4).frame(width: 120, height: 10)
                    SkeletonBlock(radius: 4).frame(width: 70, height: 9)
                }
                Spacer()
            }
            SkeletonBlock(radius: 6).frame(height: 11)
            SkeletonBlock(radius: 6).frame(width: 220, height: 11)
            SkeletonBlock(radius: 16).frame(height: 150)
        }
        .padding(14)
        .softCard(radius: 22)
    }
}


extension UIImage {
    /// JPEG data, downscaled so the long edge is at most `maxEdge` — keeps uploads small.
    func downscaledJPEG(maxEdge: CGFloat, quality: CGFloat = 0.82) -> Data? {
        let longest = max(size.width, size.height)
        let scaled: UIImage
        if longest > maxEdge {
            let k = maxEdge / longest
            let target = CGSize(width: size.width * k, height: size.height * k)
            scaled = UIGraphicsImageRenderer(size: target).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
        } else {
            scaled = self
        }
        return scaled.jpegData(compressionQuality: quality)
    }
}
