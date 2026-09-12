import SwiftUI

/// Shared chrome for the reel screens: near-black ground, glassy dark chips, small tight type.
///
/// Adapted from the TikTok reference the user supplied. Its coral accent was deliberately
/// swapped for the app's yellow — the rest of goodiesSnap is yellow/black, and a second accent
/// colour would read as a different product. Everything else (the dark glass circles, the count
/// pills, the stat row, the two-column grid) follows the reference.
enum ReelStyle {
    static let ground = Color(hex: 0x0C0C0E)
    static let chip = Color.white.opacity(0.14)
    static let chipStroke = Color.white.opacity(0.16)
    static let dim = Color.white.opacity(0.55)
    static let accent = Color.gsPeach

    /// The dark translucent circle every floating control sits in.
    static func glassCircle(_ size: CGFloat) -> some View {
        Circle()
            .fill(.black.opacity(0.34))
            .overlay(Circle().fill(chip))
            .overlay(Circle().strokeBorder(chipStroke, lineWidth: 0.8))
            .frame(width: size, height: size)
    }
}

/// The Community tab: a full-screen, vertical TikTok-style video feed. Each page is one reel —
/// either a user-uploaded clip or a YouTube recipe video — that autoplays while it's on screen
/// and pauses when swiped away. Overlays float over the video; the app's own tab bar is hidden
/// here for an immersive, edge-to-edge feed.
struct ReelsView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var social: SocialStore

    /// The reference's "Following / For You" pair. We have no follow graph, so inventing one
    /// would be a fake control; these are the two kinds of reel the feed genuinely holds.
    enum Lane: String, CaseIterable {
        case community = "Community"
        case recipes = "Recipes"
    }

    @State private var lane: Lane = .community
    @State private var activeID: String?
    @State private var muted = false

    private var reels: [Reel] {
        switch lane {
        case .community: return social.reels.filter { $0.isUpload }
        case .recipes:   return social.reels.filter { !$0.isUpload }
        }
    }

    var body: some View {
        ZStack {
            ReelStyle.ground.ignoresSafeArea()

            if reels.isEmpty {
                if social.reelsLoading {
                    ProgressView().tint(.white)
                } else {
                    emptyState
                }
            } else {
                feed
            }

            topBar
        }
        .task {
            await social.loadReels()
            // Don't open on an empty lane: with nobody posting yet, Community is blank and the
            // feed looks broken. Land on whichever lane actually has something to play.
            if social.reels.contains(where: { $0.isUpload }) == false { lane = .recipes }
            if activeID == nil { activeID = reels.first?.id }
        }
        .onChange(of: lane) { _, _ in
            // Each lane keeps its own top-of-feed rather than inheriting a stale offset.
            activeID = reels.first?.id
        }
        // Opening a creator's reel from their profile grid jumps the feed to it.
        .onChange(of: store.reelFocusID) { _, id in
            guard let id else { return }
            if social.reels.first(where: { $0.id == id })?.isUpload == false { lane = .recipes }
            else { lane = .community }
            withAnimation { activeID = id }
            store.reelFocusID = nil
        }
    }

    // MARK: - Feed

    /// Index of the reel currently snapped into view, for the preload window.
    private var activeIndex: Int? {
        guard let activeID else { return nil }
        return reels.firstIndex { $0.id == activeID }
    }

    private var feed: some View {
        // The page height is measured from a geometry that already ignores the safe area.
        // `containerRelativeFrame` measures the scroll view's container *before* the
        // ignoresSafeArea, so pages came out slightly short and the neighbouring reel's
        // overlay peeked in at the top edge after every snap.
        GeometryReader { geo in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(reels.enumerated()), id: \.element.id) { index, reel in
                        ReelCell(reel: reel,
                                 isActive: reel.id == activeID,
                                 // Keep the current reel and its neighbours mounted so the next
                                 // video is already buffered before it snaps into view.
                                 shouldLoad: shouldLoad(index),
                                 muted: muted,
                                 onToggleMute: { muted.toggle() })
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .id(reel.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $activeID)
            .scrollIndicators(.hidden)
        }
        .ignoresSafeArea()
    }

    private func shouldLoad(_ index: Int) -> Bool {
        guard let activeIndex else { return index == 0 }   // first frame before any scroll
        return abs(index - activeIndex) <= 1
    }

    // MARK: - Chrome

    /// Lane switcher on the left, compose on the right — the reference's header, with a back
    /// chevron added because this screen is pushed rather than a root tab.
    private var topBar: some View {
        VStack {
            HStack(spacing: 14) {
                Button { store.goBack() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(ReelStyle.glassCircle(36))
                }
                .buttonStyle(PressableStyle(scale: 0.92))

                ForEach(Lane.allCases, id: \.self) { item in
                    Button {
                        Haptics.tap(.light)
                        withAnimation(.easeOut(duration: 0.2)) { lane = item }
                    } label: {
                        VStack(spacing: 5) {
                            Text(item.rawValue)
                                .font(nunito(15, lane == item ? .black : .semibold))
                                .foregroundStyle(lane == item ? .white : ReelStyle.dim)
                            Capsule()
                                .fill(lane == item ? ReelStyle.accent : .clear)
                                .frame(width: 18, height: 3)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button { startCompose() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(ReelStyle.glassCircle(36))
                }
                .buttonStyle(PressableStyle(scale: 0.92))
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .shadow(color: .black.opacity(0.5), radius: 10, y: 2)

            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: lane == .recipes ? "fork.knife" : "play.rectangle.on.rectangle.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
            Text(lane == .recipes ? "No recipe reels" : "No reels yet")
                .font(nunito(19, .black)).foregroundStyle(.white)
            Text(lane == .recipes
                 ? "Recipe videos from Discover show up here."
                 : "Be the first to share a cooking clip.")
                .font(nunito(13, .semibold))
                .foregroundStyle(ReelStyle.dim)
                .multilineTextAlignment(.center)
            if lane == .community {
                Button { startCompose() } label: {
                    Text("Post a reel")
                        .font(nunito(14, .extrabold)).foregroundStyle(.black)
                        .padding(.horizontal, 22).padding(.vertical, 12)
                        .background(ReelStyle.accent, in: Capsule())
                }
                .buttonStyle(PressableStyle(scale: 0.95))
                .padding(.top, 4)
            }
        }
        .padding(40)
    }

    private func startCompose() {
        guard social.session != nil else { store.showAuth(.community); return }
        Haptics.tap(.medium)
        social.composingReel = true
    }
}

// MARK: - One reel page

private struct ReelCell: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var social: SocialStore

    let reel: Reel
    let isActive: Bool
    let shouldLoad: Bool
    let muted: Bool
    let onToggleMute: () -> Void

    /// Flips true once the player has a real frame on screen, lifting the poster.
    @State private var videoReady = false

    private var liked: Bool { social.isReelLiked(reel) }
    private var isMine: Bool { reel.authorID == social.session?.userID }

    var body: some View {
        ZStack {
            ReelStyle.ground.ignoresSafeArea()

            // Uploaded clips preload with their neighbours (AVPlayer buffers ahead cleanly).
            // YouTube players mount only when active: a preloaded-then-resumed embed can stall
            // in a paused state that keeps showing YouTube's chrome, whereas a fresh mount
            // starts playing cleanly under the poster.
            if reel.isUpload ? shouldLoad : isActive {
                player.ignoresSafeArea()
            }

            // Poster frame over the player, hiding the YouTube chrome / black loading frame
            // until there's real video to show. Fades out the moment the player is ready.
            poster
                .opacity(videoReady ? 0 : 1)
                .animation(.easeOut(duration: 0.35), value: videoReady)
                .allowsHitTesting(false)
                .ignoresSafeArea()

            // Scrims top and bottom so the chrome stays legible over any frame.
            LinearGradient(
                colors: [.black.opacity(0.45), .clear, .clear, .black.opacity(0.65)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            HStack(alignment: .bottom, spacing: 12) {
                info
                Spacer(minLength: 0)
                actionRail
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 34)
            .frame(maxHeight: .infinity, alignment: .bottom)

            if muted {
                // The whole page toggles sound, so say which state you're in.
                Image(systemName: "speaker.slash.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(ReelStyle.glassCircle(42))
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onToggleMute() }
        .onChange(of: shouldLoad) { _, loading in
            // When the cell scrolls out of the preload window its player is torn down, so the
            // next time it mounts it must re-earn "ready" rather than lift the poster instantly.
            if !loading { videoReady = false }
        }
        // YouTube shows its own start-of-play chrome (title, logo, controls) whenever a reel
        // begins playing — including when a preloaded reel resumes as you scroll to it. A
        // one-shot ready flag can't cover that, so for YouTube the poster re-covers on every
        // activation and lifts only after the chrome has auto-hidden.
        .onChange(of: isActive) { _, active in armYouTubePoster(active) }
        .onAppear { armYouTubePoster(isActive) }
    }

    /// Re-covers the poster over a YouTube reel each time it becomes active, so the black load
    /// frame is hidden until playback starts; the player's PLAYING signal lifts it. A fallback
    /// lifts it anyway if that signal never arrives, so a reel can't get stuck on its poster.
    /// No-op for uploaded clips (which lift on their first frame via the player's onReady).
    private func armYouTubePoster(_ active: Bool) {
        guard case .youtube = reel.source else { return }
        guard active else { videoReady = false; return }
        videoReady = false
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4.0))
            guard isActive, !videoReady else { return }
            withAnimation(.easeOut(duration: 0.4)) { videoReady = true }
        }
    }

    @ViewBuilder
    private var player: some View {
        switch reel.source {
        case .upload(let url):
            ReelVideoPlayer(url: url, isActive: isActive, isMuted: muted,
                            onReady: { videoReady = true })
        case .youtube(let id):
            // Lift the poster the moment playback starts; armYouTubePoster re-covers on activation.
            ReelYouTubePlayer(videoID: id, isActive: isActive, isMuted: muted,
                              onReady: { if isActive { videoReady = true } })
        }
    }

    /// The still shown before (and behind) the video. Fit for YouTube reels so it matches the
    /// letterboxed 16:9 player; fill for uploaded clips (which are already vertical). Falls back
    /// to a flat dark ground so nothing YouTube-branded is ever visible first.
    @ViewBuilder
    private var poster: some View {
        switch reel.source {
        case .youtube:
            if let thumb = reel.thumbURL {
                AsyncImage(url: thumb) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: { ReelStyle.ground }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ReelStyle.ground
            }
        case .upload:
            if let thumb = reel.thumbURL {
                CoverImage(url: thumb)
            } else {
                ReelStyle.ground
            }
        }
    }

    // MARK: Left column — author, caption, recipe row

    private var info: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                Button { store.openReelProfile(authorID: reel.authorID) } label: {
                    HStack(spacing: 9) {
                        avatar
                        Text("@" + handle)
                            .font(nunito(14.5, .black))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(PressableStyle(scale: 0.96))

                // YouTube's own view count, when the proxy has fetched it.
                if let views = social.views(for: reel) {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 8.5, weight: .black))
                        Text(views.compactCount)
                            .font(nunito(11, .black))
                    }
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.42), in: Capsule())
                    .overlay(Capsule().strokeBorder(ReelStyle.chipStroke, lineWidth: 0.8))
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.25), value: social.views(for: reel) ?? -1)

            if !reel.caption.isEmpty, reel.caption != reel.recipe?.title {
                Text(reel.caption)
                    .font(nunito(13, .semibold)).foregroundStyle(.white.opacity(0.92))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // The reference's music row. Ours carries the recipe instead — same shape, same
            // position, and tapping it opens the dish.
            if let recipe = reel.recipe {
                Button { store.openCatalogRecipe(recipe) } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "fork.knife")
                            .font(.system(size: 10, weight: .black))
                        Text(recipe.title)
                            .font(nunito(12, .extrabold))
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.38), in: Capsule())
                    .overlay(Capsule().strokeBorder(ReelStyle.chipStroke, lineWidth: 0.8))
                }
                .buttonStyle(PressableStyle(scale: 0.96))
            }
        }
        .frame(maxWidth: 250, alignment: .leading)
        .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
    }

    private var avatar: some View {
        Circle()
            .fill(ReelStyle.accent)
            .frame(width: 32, height: 32)
            .overlay(Text(initials).font(nunito(12, .black)).foregroundStyle(.black))
            .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.5))
    }

    /// `@handle` form of the author name, the way the reference labels a creator.
    private var handle: String {
        let squashed = reel.authorName
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
        return squashed.isEmpty ? "cook" : squashed
    }

    private var initials: String {
        let parts = reel.authorName.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    // MARK: Right column — like / comment / save / more

    private var actionRail: some View {
        VStack(spacing: 18) {
            railButton(system: liked ? "heart.fill" : "heart",
                       tint: liked ? ReelStyle.accent : .white,
                       count: reel.likeCount) {
                social.toggleReelLike(reel)
            }

            if reel.isUpload {
                railButton(system: "bubble.right.fill", tint: .white,
                           count: reel.commentCount) {
                    guard social.session != nil else { store.showAuth(.community); return }
                    social.openReelComments(reel)
                }
            }

            if let recipe = reel.recipe {
                let saved = store.isInLibrary(recipe.id)
                railButton(system: saved ? "bookmark.fill" : "bookmark",
                           tint: saved ? ReelStyle.accent : .white,
                           label: saved ? "Saved" : "Save") {
                    // Save in place and keep scrolling — the recipe row is how you open it.
                    if store.saveToLibrary(recipe) {
                        Haptics.notify(.success)
                        store.showToast("Saved to your library")
                    } else {
                        store.showToast("Already in your library")
                    }
                }
            }

            railButton(system: "ellipsis", tint: .white) {
                if isMine {
                    social.deleteReel(reel)
                    store.showToast("Reel deleted")
                } else if let post = reel.post {
                    social.startReport(.post(post))
                } else {
                    store.showToast("Recipe reels can't be reported")
                }
            }
        }
        .padding(.bottom, 2)
    }

    /// Reference rail button: the icon in a dark glass circle with its count in a small pill
    /// tucked under it.
    private func railButton(system: String, tint: Color, count: Int? = nil,
                            label: String? = nil,
                            action: @escaping () -> Void) -> some View {
        let text: String? = {
            if let label { return label }
            if let count, count > 0 { return count.compactCount }
            return nil
        }()

        return Button(action: action) {
            VStack(spacing: -7) {
                Image(systemName: system)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 46, height: 46)
                    .background(ReelStyle.glassCircle(46))

                if let text {
                    Text(text)
                        .font(nunito(10.5, .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.72), in: Capsule())
                        .overlay(Capsule().strokeBorder(ReelStyle.chipStroke, lineWidth: 0.8))
                }
            }
            .frame(width: 52)
        }
        .buttonStyle(PressableStyle(scale: 0.9))
    }
}

extension Int {
    /// 8_600 → "8.6K", 2_400_000 → "2.4M", the way the reference labels counts.
    var compactCount: String {
        switch self {
        case 1_000_000...:
            return String(format: "%.1fM", Double(self) / 1_000_000).replacingOccurrences(of: ".0", with: "")
        case 1_000...:
            return String(format: "%.1fK", Double(self) / 1_000).replacingOccurrences(of: ".0", with: "")
        default:
            return "\(self)"
        }
    }
}
