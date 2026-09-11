import SwiftUI

/// Client state for the social feed: session, posts, likes, comments.
@MainActor
final class SocialStore: ObservableObject {
    @Published var session: SocialAPI.Session? {
        didSet { persistSession() }
    }
    /// Called right after a successful sign-in/sign-up, on the main actor. Wired in App.swift
    /// to drive navigation — deterministic, unlike a SwiftUI onChange on a computed property.
    var onSignedIn: ((_ isNewAccount: Bool) -> Void)?

    @Published var posts: [FeedPost] = []
    @Published var likedPostIDs: Set<String> = []
    @Published var loading = false
    @Published var busy = false
    @Published var errorMessage = ""

    /// Post whose comments sheet is open.
    @Published var commentsFor: FeedPost?
    @Published var comments: [FeedComment] = []

    /// Recipe pending a "share to feed" caption.
    @Published var sharing: Recipe?

    // MARK: Community (groups + composer)
    @Published var groups: [CommunityGroup] = []
    @Published var myGroupIDs: Set<String> = []
    /// nil = "For you" (everything); "mine" = posts in my groups; otherwise a group id.
    /// Who this user has blocked. The server already filters them out of every query;
    /// this is kept so the UI can show and undo the blocks.
    @Published var blockedIDs: Set<String> = []
    /// Post or comment currently being reported, driving the report sheet.
    @Published var reporting: ReportTarget?
    @Published var deletingAccount = false

    @Published var feedFilter: String? = nil
    @Published var composing = false
    @Published var composeGroupID: String? = nil
    @Published var composeAsQuestion = false
    /// Filter to apply once groups load (slug, or "mine").
    var pendingFilterSlug: String? = nil

    // MARK: Reels (the community tab)
    @Published var reels: [Reel] = []
    @Published var reelsLoading = false
    /// Local likes for YouTube reels, which have no server row. Persisted per device.
    @Published var likedYouTubeReelIDs: Set<String> = []
    /// True while a reel upload is in flight.
    @Published var reelUploading = false
    /// Drives the reel composer sheet.
    @Published var composingReel = false

    private static let reelLikesKey = "gs_liked_yt_reels"

    var visiblePosts: [FeedPost] {
        switch feedFilter {
        case nil: return posts
        case "mine": return posts.filter { $0.group_id.map(myGroupIDs.contains) ?? false }
        case let id?: return posts.filter { $0.group_id == id }
        }
    }

    func group(id: String?) -> CommunityGroup? {
        guard let id else { return nil }
        return groups.first { $0.id == id }
    }

    private static let sessionKey = "gs_social_session"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.sessionKey),
           let saved = try? JSONDecoder().decode(SocialAPI.Session.self, from: data) {
            session = saved
        }
        if let ids = UserDefaults.standard.stringArray(forKey: Self.reelLikesKey) {
            likedYouTubeReelIDs = Set(ids)
        }
    }

    private func persistSession() {
        if let session, let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: Self.sessionKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.sessionKey)
        }
    }

    var signedIn: Bool { session != nil }

    // MARK: - Auth

    func signUp(email: String, password: String, name: String) async {
        await authFlow(isSignUp: true) { try await SocialAPI.signUp(email: email, password: password, name: name) }
    }

    func signIn(email: String, password: String) async {
        await authFlow(isSignUp: false) { try await SocialAPI.signIn(email: email, password: password) }
    }

    private func authFlow(isSignUp: Bool, _ work: () async throws -> SocialAPI.Session) async {
        busy = true
        errorMessage = ""
        do {
            let s = try await work()
            withAnimation(AppStore.sheetAnimation) { session = s }
            Haptics.notify(.success)
            // Fire the redirect immediately and deterministically, before the (slower)
            // feed refresh — the user shouldn't wait on posts loading to leave this screen.
            onSignedIn?(isSignUp)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.notify(.error)
        }
        busy = false
    }

    /// Called at launch: confirm a persisted session still belongs to a real, current
    /// account and sign out if not, so a deleted or expired login never appears active.
    /// A transient network error is ignored — we only sign out on a definite invalid session.
    func validateSession() async {
        guard let current = session else { return }
        do {
            let exists = try await SocialAPI.accountExists(session: current)
            if !exists { signOut() }               // account was deleted
        } catch SocialAPI.SocialError.sessionExpired {
            // Try one refresh; keep the renewed session so the fresh access token is what
            // the app actually uses. If even the refresh fails, the session is dead.
            if let renewed = try? await SocialAPI.refresh(session: current) {
                session = renewed
            } else {
                signOut()
            }
        } catch {
            // Network/transient error — keep the session, don't sign the user out.
        }
    }

    /// Exchanges the refresh token for a fresh access token and adopts the renewed session,
    /// returning the new access token. Used by the AI proxy path: an expired access token
    /// should silently renew, not bounce the signed-in user to the sign-in screen.
    /// Returns nil (and signs out) only when the refresh token itself is dead.
    func refreshedToken() async -> String? {
        guard let current = session else { return nil }
        guard let renewed = try? await SocialAPI.refresh(session: current) else {
            signOut()
            return nil
        }
        session = renewed
        return renewed.accessToken
    }

    func signOut() {
        withAnimation(AppStore.lateralAnimation) {
            session = nil
            posts = []
            likedPostIDs = []
        }
    }

    /// Runs an authenticated call; on 401 refreshes the session once and retries.
    /// Signs out only when the refresh itself fails.
    private func authed<T>(_ work: (SocialAPI.Session) async throws -> T) async throws -> T {
        guard let current = session else { throw SocialAPI.SocialError.sessionExpired }
        do {
            return try await work(current)
        } catch SocialAPI.SocialError.sessionExpired {
            let renewed: SocialAPI.Session
            do { renewed = try await SocialAPI.refresh(session: current) }
            catch { signOut(); throw SocialAPI.SocialError.sessionExpired }
            session = renewed
            return try await work(renewed)
        }
    }

    private func handle(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    // MARK: - Feed

    func refresh() async {
        guard session != nil else { return }
        loading = posts.isEmpty
        do {
            let (p, l, g, m) = try await authed { s in
                async let posts = SocialAPI.fetchPosts(token: s.accessToken)
                async let likes = SocialAPI.fetchMyLikes(token: s.accessToken, userID: s.userID)
                async let groups = SocialAPI.fetchGroups(token: s.accessToken)
                async let mine = SocialAPI.fetchMyGroupIDs(token: s.accessToken, userID: s.userID)
                return try await (posts, likes, groups, mine)
            }
            withAnimation(AppStore.lateralAnimation) {
                self.posts = p
                self.likedPostIDs = l
                self.groups = g
                self.myGroupIDs = m
                if let slug = pendingFilterSlug {
                    feedFilter = slug == "mine" ? "mine" : g.first { $0.slug == slug }?.id
                    pendingFilterSlug = nil
                }
            }
        } catch {
            handle(error)
        }
        loading = false
    }

    func toggleLike(_ post: FeedPost) {
        guard session != nil else { return }
        let wasLiked = likedPostIDs.contains(post.id)
        Haptics.tap(.light)
        // Optimistic update; reconciled by the next refresh.
        withAnimation(AppStore.stepAnimation) {
            if wasLiked { likedPostIDs.remove(post.id) } else { likedPostIDs.insert(post.id) }
            if let i = posts.firstIndex(where: { $0.id == post.id }) {
                posts[i].like_count = max(0, posts[i].like_count + (wasLiked ? -1 : 1))
            }
        }
        Task {
            do {
                try await authed { s in
                    if wasLiked {
                        try await SocialAPI.unlike(postID: post.id, token: s.accessToken, userID: s.userID)
                    } else {
                        try await SocialAPI.like(postID: post.id, token: s.accessToken, userID: s.userID)
                    }
                }
            } catch {
                handle(error)
                await refresh()
            }
        }
    }

    func share(recipe: Recipe, caption: String) async -> Bool {
        guard session != nil else { return false }
        busy = true
        defer { busy = false }
        var shared = recipe
        shared.favorite = false
        do {
            let post = try await authed { s in
                try await SocialAPI.createPost(
                    recipe: shared, caption: caption,
                    token: s.accessToken, userID: s.userID
                )
            }
            withAnimation(AppStore.sheetAnimation) {
                posts.insert(post, at: 0)
                sharing = nil
            }
            Haptics.notify(.success)
            return true
        } catch {
            handle(error)
            return false
        }
    }

    // MARK: - Reels

    /// Loads the community reel feed: uploaded reels (when signed in) on top, then YouTube
    /// recipe reels from the catalog so the feed is never empty. Refreshes like state too.
    func loadReels(force: Bool = false) async {
        guard reels.isEmpty || force else { return }
        reelsLoading = reels.isEmpty
        var uploaded: [FeedPost] = []
        if session != nil {
            do {
                (uploaded, likedPostIDs) = try await authed { s in
                    async let r = SocialAPI.fetchReels(token: s.accessToken)
                    async let l = SocialAPI.fetchMyLikes(token: s.accessToken, userID: s.userID)
                    return try await (r, l)
                }
            } catch { handle(error) }
        }
        let youtube = (try? await CatalogService.reelRecipes(limit: 30)) ?? []
        var items = uploaded.compactMap { Reel(upload: $0) }
        items += youtube.map { Reel(youtube: $0) }
        withAnimation(AppStore.lateralAnimation) { self.reels = items }
        reelsLoading = false
    }

    func isReelLiked(_ reel: Reel) -> Bool {
        reel.isUpload ? likedPostIDs.contains(reel.id) : likedYouTubeReelIDs.contains(reel.id)
    }

    /// Likes/unlikes a reel. Uploaded reels hit the server; YouTube reels toggle a local set.
    func toggleReelLike(_ reel: Reel) {
        guard let idx = reels.firstIndex(where: { $0.id == reel.id }) else { return }
        Haptics.tap(.light)
        let wasLiked = isReelLiked(reel)
        withAnimation(AppStore.stepAnimation) {
            reels[idx].likeCount = max(0, reels[idx].likeCount + (wasLiked ? -1 : 1))
        }
        if reel.isUpload {
            if wasLiked { likedPostIDs.remove(reel.id) } else { likedPostIDs.insert(reel.id) }
            guard session != nil else { return }
            Task {
                do {
                    try await authed { s in
                        if wasLiked {
                            try await SocialAPI.unlike(postID: reel.id, token: s.accessToken, userID: s.userID)
                        } else {
                            try await SocialAPI.like(postID: reel.id, token: s.accessToken, userID: s.userID)
                        }
                    }
                } catch { handle(error) }
            }
        } else {
            if wasLiked { likedYouTubeReelIDs.remove(reel.id) } else { likedYouTubeReelIDs.insert(reel.id) }
            UserDefaults.standard.set(Array(likedYouTubeReelIDs), forKey: Self.reelLikesKey)
        }
    }

    /// Opens comments for an uploaded reel (YouTube reels have none).
    func openReelComments(_ reel: Reel) {
        guard let post = reel.post else { return }
        openComments(post)
    }

    /// Uploads a clip and publishes it as a reel, prepended to the feed.
    func publishReel(videoData: Data, thumbnail: UIImage?, caption: String,
                     recipe: Recipe?, duration: Int?) async -> Bool {
        guard session != nil else { return false }
        reelUploading = true
        defer { reelUploading = false }
        do {
            let post = try await authed { s -> FeedPost in
                let url = try await SocialAPI.uploadReelVideo(videoData, token: s.accessToken, userID: s.userID)
                var thumbURL: String? = nil
                if let thumbnail, let data = thumbnail.jpegData(compressionQuality: 0.7) {
                    thumbURL = try? await SocialAPI.uploadImage(data, token: s.accessToken, userID: s.userID)
                }
                return try await SocialAPI.createReel(
                    videoURL: url, thumbURL: thumbURL, caption: caption, recipe: recipe,
                    durationSeconds: duration, token: s.accessToken, userID: s.userID)
            }
            if let reel = Reel(upload: post) {
                withAnimation(AppStore.sheetAnimation) {
                    reels.insert(reel, at: 0)
                    composingReel = false
                }
            }
            Haptics.notify(.success)
            return true
        } catch {
            handle(error)
            return false
        }
    }

    /// Deletes the current user's uploaded reel.
    func deleteReel(_ reel: Reel) {
        guard reel.isUpload, session != nil else { return }
        withAnimation(AppStore.sheetAnimation) { reels.removeAll { $0.id == reel.id } }
        Task {
            do { try await authed { s in try await SocialAPI.deletePost(id: reel.id, token: s.accessToken) } }
            catch { handle(error); await loadReels(force: true) }
        }
    }

    // MARK: - Moderation

    /// What the report sheet is aimed at. A comment carries its post so the report row
    /// can record both.
    enum ReportTarget: Identifiable, Equatable {
        case post(FeedPost)
        case comment(FeedComment, postID: String)

        var id: String {
            switch self {
            case .post(let p): return "post-\(p.id)"
            case .comment(let c, _): return "comment-\(c.id)"
            }
        }

        var authorName: String {
            switch self {
            case .post(let p): return p.author_name
            case .comment(let c, _): return c.author_name
            }
        }

        var authorID: String {
            switch self {
            case .post(let p): return p.author_id
            case .comment(let c, _): return c.author_id
            }
        }
    }

    func startReport(_ target: ReportTarget) {
        Haptics.tap(.medium)
        reporting = target
    }

    func cancelReport() { reporting = nil }

    /// Files the report. The content disappears locally straight away: someone who has
    /// just reported a post should not have to keep looking at it while we round-trip.
    func submitReport(reason: SocialAPI.ReportReason, note: String) async {
        guard let target = reporting, let session else { return }
        busy = true
        do {
            switch target {
            case .post(let post):
                try await authed { s in
                    try await SocialAPI.reportPost(id: post.id, reason: reason, note: note,
                                                   token: s.accessToken, userID: s.userID)
                }
                withAnimation(AppStore.pushAnimation) { posts.removeAll { $0.id == post.id } }
            case .comment(let comment, let postID):
                try await authed { s in
                    try await SocialAPI.reportComment(id: comment.id, postID: postID, reason: reason,
                                                      note: note, token: s.accessToken, userID: s.userID)
                }
                withAnimation(AppStore.pushAnimation) { comments.removeAll { $0.id == comment.id } }
            }
            _ = session
            Haptics.notify(.success)
            errorMessage = "Thanks — our team will review this within 24 hours."
        } catch {
            handle(error)
            Haptics.notify(.error)
        }
        reporting = nil
        busy = false
    }

    /// Blocks a user and drops their content from the current feed immediately.
    func block(userID blocked: String) {
        guard let session, blocked != session.userID else { return }
        Haptics.notify(.success)
        withAnimation(AppStore.pushAnimation) {
            blockedIDs.insert(blocked)
            posts.removeAll { $0.author_id == blocked }
            comments.removeAll { $0.author_id == blocked }
        }
        Task {
            do {
                try await authed { s in
                    try await SocialAPI.block(userID: blocked, token: s.accessToken, userID: s.userID)
                }
            } catch {
                // Put them back rather than leaving the UI claiming a block that never landed.
                blockedIDs.remove(blocked)
                handle(error)
                await refresh()
            }
        }
    }

    func unblock(userID blocked: String) {
        guard session != nil else { return }
        withAnimation(AppStore.pushAnimation) { _ = blockedIDs.remove(blocked) }
        Task {
            do {
                try await authed { s in
                    try await SocialAPI.unblock(userID: blocked, token: s.accessToken, userID: s.userID)
                }
                await refresh()
            } catch {
                blockedIDs.insert(blocked)
                handle(error)
            }
        }
    }

    func loadBlocked() async {
        guard session != nil else { return }
        do {
            let rows = try await authed { s in try await SocialAPI.fetchBlocked(token: s.accessToken) }
            blockedIDs = Set(rows.map(\.blocked_id))
        } catch {
            // Non-fatal: the server filters blocked content regardless of this list.
        }
    }

    // MARK: - Account deletion

    /// Deletes the account server-side, then clears every local trace of it.
    /// Returns true when the account is gone.
    func deleteAccount() async -> Bool {
        guard session != nil else { return false }
        deletingAccount = true
        defer { deletingAccount = false }
        do {
            try await authed { s in try await SocialAPI.deleteAccount(token: s.accessToken) }
            blockedIDs = []
            comments = []
            commentsFor = nil
            myGroupIDs = []
            signOut()
            Haptics.notify(.success)
            return true
        } catch {
            handle(error)
            Haptics.notify(.error)
            return false
        }
    }

    func deletePost(_ post: FeedPost) {
        guard let session, post.author_id == session.userID else { return }
        withAnimation(AppStore.pushAnimation) { posts.removeAll { $0.id == post.id } }
        Task {
            do { try await authed { s in try await SocialAPI.deletePost(id: post.id, token: s.accessToken) } }
            catch { handle(error); await refresh() }
        }
    }

    /// Publish a general post from the composer. Uploads the photo first if present.
    func publish(text: String, image: UIImage?, recipe: Recipe?, groupID: String?, asQuestion: Bool) async -> Bool {
        guard session != nil else { return false }
        let caption = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !caption.isEmpty || image != nil || recipe != nil else { return false }
        busy = true
        defer { busy = false }
        do {
            let post = try await authed { s in
                var imageURL: String? = nil
                if let image, let jpeg = image.downscaledJPEG(maxEdge: 1600) {
                    imageURL = try await SocialAPI.uploadImage(jpeg, token: s.accessToken, userID: s.userID)
                }
                let kind = recipe != nil ? "recipe" : (asQuestion ? "question" : (imageURL != nil ? "photo" : "text"))
                var shared = recipe
                shared?.favorite = false
                return try await SocialAPI.createPost(
                    kind: kind, caption: caption, imageURL: imageURL, recipe: shared, groupID: groupID,
                    token: s.accessToken, userID: s.userID
                )
            }
            withAnimation(AppStore.sheetAnimation) {
                posts.insert(post, at: 0)
                composing = false
                composeAsQuestion = false
                if let gid = post.group_id, let i = groups.firstIndex(where: { $0.id == gid }) {
                    groups[i].post_count += 1
                }
            }
            Haptics.notify(.success)
            return true
        } catch {
            handle(error)
            Haptics.notify(.error)
            return false
        }
    }

    func toggleMembership(_ group: CommunityGroup) {
        guard session != nil else { return }
        let joined = myGroupIDs.contains(group.id)
        Haptics.tap(.light)
        withAnimation(AppStore.stepAnimation) {
            if joined { myGroupIDs.remove(group.id) } else { myGroupIDs.insert(group.id) }
            if let i = groups.firstIndex(where: { $0.id == group.id }) {
                groups[i].member_count = max(0, groups[i].member_count + (joined ? -1 : 1))
            }
        }
        Task {
            do {
                try await authed { s in
                    if joined {
                        try await SocialAPI.leaveGroup(id: group.id, token: s.accessToken, userID: s.userID)
                    } else {
                        try await SocialAPI.joinGroup(id: group.id, token: s.accessToken, userID: s.userID)
                    }
                }
            } catch {
                handle(error)
                await refresh()
            }
        }
    }

    // MARK: - Comments

    func openComments(_ post: FeedPost) {
        comments = []
        withAnimation(AppStore.sheetAnimation) { commentsFor = post }
        Task {
            do { comments = try await authed { s in try await SocialAPI.fetchComments(postID: post.id, token: s.accessToken) } }
            catch { handle(error) }
        }
    }

    func closeComments() {
        withAnimation(AppStore.sheetAnimation) { commentsFor = nil }
    }

    func addComment(_ body: String) async {
        guard session != nil, let post = commentsFor else { return }
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        do {
            let comment = try await authed { s in
                try await SocialAPI.addComment(
                    postID: post.id, body: text,
                    token: s.accessToken, userID: s.userID
                )
            }
            Haptics.tap(.light)
            withAnimation(AppStore.stepAnimation) {
                comments.append(comment)
                if let i = posts.firstIndex(where: { $0.id == post.id }) {
                    posts[i].comment_count += 1
                }
            }
        } catch {
            handle(error)
        }
    }
}
