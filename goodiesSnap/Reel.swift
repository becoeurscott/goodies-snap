import Foundation

/// One card in the community reel feed. A reel is either a user-uploaded clip (backed by a
/// `posts` row, so likes/comments/reports reuse the existing feed plumbing) or a YouTube
/// recipe video synthesised from the catalog. The view treats both uniformly; the store
/// routes actions by `source`.
struct Reel: Identifiable, Equatable {
    enum Source: Equatable {
        case upload(URL)
        case youtube(String)
    }

    let id: String
    let source: Source
    let authorID: String
    let authorName: String
    let caption: String
    /// The recipe a viewer can open from the reel, when there is one.
    let recipe: Recipe?
    /// Poster frame shown before the video plays.
    let thumbURL: URL?
    var likeCount: Int
    var commentCount: Int
    let createdAt: String
    /// The backing feed post for uploaded reels — nil for YouTube reels.
    let post: FeedPost?

    var isUpload: Bool { if case .upload = source { return true } else { return false } }

    /// Uploaded reel from a feed post. Fails when the row has no playable video.
    init?(upload post: FeedPost) {
        guard let url = post.videoURL else { return nil }
        self.id = post.id
        self.source = .upload(url)
        self.authorID = post.author_id
        self.authorName = post.author_name
        self.caption = post.caption
        self.recipe = post.recipe
        self.thumbURL = post.thumbURL
        self.likeCount = post.like_count
        self.commentCount = post.comment_count
        self.createdAt = post.created_at
        self.post = post
    }

    /// YouTube recipe reel drawn from the catalog.
    init(youtube reel: CatalogService.ReelRecipe) {
        self.id = "yt_" + reel.youtubeID
        self.source = .youtube(reel.youtubeID)
        self.authorID = "catalog"
        self.authorName = "goodiesSnap"
        self.caption = reel.recipe.title
        self.recipe = reel.recipe
        // The video's own 16:9 thumbnail, so the poster matches the letterboxed player frame.
        self.thumbURL = URL(string: "https://img.youtube.com/vi/\(reel.youtubeID)/hqdefault.jpg")
        self.likeCount = 0
        self.commentCount = 0
        self.createdAt = ""
        self.post = nil
    }

    /// Thumbnail for the profile grid. YouTube's `hqdefault` is 4:3 with black bars baked in,
    /// which read as gaps in a tight grid; `mqdefault` is a clean 16:9 crop.
    var gridThumbURL: URL? {
        if case .youtube(let id) = source {
            return URL(string: "https://img.youtube.com/vi/\(id)/mqdefault.jpg")
        }
        return thumbURL
    }

    /// Short cuisine/label line under the author for YouTube reels.
    var subtitle: String {
        if case .youtube = source, let cuisine = recipe?.cuisine, !cuisine.isEmpty {
            return "Recipe reel · \(cuisine)"
        }
        return post?.relativeTime ?? ""
    }
}
