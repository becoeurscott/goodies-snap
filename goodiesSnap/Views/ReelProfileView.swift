import SwiftUI

/// A creator's page, reached by tapping the author on a reel — the second screen of the
/// TikTok reference: glowing avatar, handle, a stat row, action buttons, then a two-column
/// grid of their reels.
///
/// The reference's Following/Followers counts are deliberately **not** reproduced: goodiesSnap
/// has no follow graph, and printing numbers we don't have would be inventing data. The stat
/// row carries three things that are genuinely true of a cook here — reels posted, likes
/// received, recipes shared.
struct ReelProfileView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var social: SocialStore

    /// Every reel this author has in the loaded feed.
    private var reels: [Reel] {
        social.reels.filter { $0.authorID == store.reelProfileAuthor }
    }

    private var name: String { reels.first?.authorName ?? "Cook" }
    private var isCatalog: Bool { store.reelProfileAuthor == "catalog" }
    private var isMe: Bool { store.reelProfileAuthor == social.session?.userID }

    private var totalLikes: Int { reels.reduce(0) { $0 + $1.likeCount } }
    private var recipeCount: Int { Set(reels.compactMap { $0.recipe?.id }).count }

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        ZStack {
            ReelStyle.ground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    header
                    identity
                        .padding(.top, 14)
                    stats
                        .padding(.top, 20)
                    actions
                        .padding(.top, 18)
                    grid
                        .padding(.top, 24)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    // MARK: - Chrome

    private var header: some View {
        HStack {
            Button { store.goBack() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(ReelStyle.glassCircle(36))
            }
            .buttonStyle(PressableStyle(scale: 0.92))

            Spacer()

            Menu {
                if let first = reels.first, !isMine(first), first.post != nil {
                    Button("Report this cook", role: .destructive) {
                        social.startReport(.post(first.post!))
                    }
                    Button("Block this cook", role: .destructive) {
                        social.block(userID: first.authorID)
                        store.goBack()
                    }
                }
                Button("Copy name") { UIPasteboard.general.string = name }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(ReelStyle.glassCircle(36))
            }
        }
        .padding(.top, 6)
    }

    private func isMine(_ reel: Reel) -> Bool { reel.authorID == social.session?.userID }

    // MARK: - Identity

    private var identity: some View {
        VStack(spacing: 10) {
            ZStack {
                // The reference's glow ring behind the avatar.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [ReelStyle.accent.opacity(0.45), .clear],
                            center: .center, startRadius: 30, endRadius: 76
                        )
                    )
                    .frame(width: 150, height: 150)
                    .blur(radius: 6)

                Circle()
                    .fill(ReelStyle.accent)
                    .frame(width: 96, height: 96)
                    .overlay(
                        Text(initials)
                            .font(nunito(34, .black))
                            .foregroundStyle(.black)
                    )
                    .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2))
            }

            Text("@" + handle)
                .font(nunito(19, .black))
                .foregroundStyle(.white)

            Text(subtitle)
                .font(nunito(12.5, .semibold))
                .foregroundStyle(ReelStyle.dim)
                .multilineTextAlignment(.center)
        }
    }

    private var subtitle: String {
        if isCatalog { return "✨ Recipe videos from Discover ✨" }
        if isMe { return "✨ This is you ✨" }
        return "✨ Cooking on goodiesSnap ✨"
    }

    private var initials: String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    private var handle: String {
        let squashed = name.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
        return squashed.isEmpty ? "cook" : squashed
    }

    // MARK: - Stats

    private var stats: some View {
        HStack(spacing: 0) {
            stat(reels.count, reels.count == 1 ? "Reel" : "Reels")
            divider
            stat(totalLikes, totalLikes == 1 ? "Like" : "Likes")
            divider
            stat(recipeCount, recipeCount == 1 ? "Recipe" : "Recipes")
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.14))
            .frame(width: 1, height: 30)
    }

    private func stat(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value.compactCount)
                .font(nunito(19, .black))
                .foregroundStyle(.white)
            Text(label)
                .font(nunito(11, .semibold))
                .foregroundStyle(ReelStyle.dim)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                // Their newest reel is the closest thing to "message" we can honestly offer.
                if let first = reels.first { store.openReel(first) }
            } label: {
                Text(isMe ? "View my reels" : "Watch reels")
                    .font(nunito(14, .extrabold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(ReelStyle.chip, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(ReelStyle.chipStroke, lineWidth: 0.8)
                    )
            }
            .buttonStyle(PressableStyle(scale: 0.97))
            .disabled(reels.isEmpty)
            .opacity(reels.isEmpty ? 0.4 : 1)

            squareButton(system: "book.fill") {
                store.go(to: .discover)
            }
        }
    }

    private func squareButton(system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(ReelStyle.chip, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(ReelStyle.chipStroke, lineWidth: 0.8)
                )
        }
        .buttonStyle(PressableStyle(scale: 0.94))
    }

    // MARK: - Grid

    @ViewBuilder
    private var grid: some View {
        if reels.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "play.slash.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                Text("No reels to show")
                    .font(nunito(13.5, .bold))
                    .foregroundStyle(ReelStyle.dim)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 50)
        } else {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(reels) { reel in
                    Button { store.openReel(reel) } label: {
                        tile(reel)
                    }
                    .buttonStyle(PressableStyle(scale: 0.97))
                }
            }
        }
    }

    private func tile(_ reel: Reel) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let thumb = reel.gridThumbURL {
                CoverImage(url: thumb)
            } else {
                ReelStyle.chip
            }

            LinearGradient(colors: [.clear, .black.opacity(0.7)],
                           startPoint: .center, endPoint: .bottom)

            HStack(spacing: 4) {
                Image(systemName: "play.fill")
                    .font(.system(size: 9, weight: .black))
                // Uploaded reels have no view counter of their own, so they show likes.
                Text((social.views(for: reel) ?? reel.likeCount).compactCount)
                    .font(nunito(11, .black))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
        }
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(ReelStyle.chipStroke, lineWidth: 0.8)
        )
    }
}
