import Foundation

/// REST client for the goodiesSnap InsForge backend (auth + feed data).
/// The anon key is the public client key; row access is enforced server-side by RLS.
enum SocialAPI {
    static let baseURL = URL(string: "https://j7pth4qn.us-east.insforge.app")!
    static let anonKey = "anon_b1cf2d2ec896c95b5cf5e890dec9fa3efd96b4951ee71fa50900adeba7146077"

    struct Session: Codable {
        var accessToken: String
        var refreshToken: String?
        var userID: String
        var displayName: String
    }

    enum SocialError: LocalizedError {
        case server(String)
        case sessionExpired

        var errorDescription: String? {
            switch self {
            case .server(let msg): return msg
            case .sessionExpired: return "Session expired — sign in again"
            }
        }
    }

    // MARK: - Auth

    static func signUp(email: String, password: String, name: String) async throws -> Session {
        var user = try await authRequest(
            path: "/api/auth/users",
            body: ["email": email, "password": password, "name": name]
        )
        user.displayName = name
        try await upsertProfile(session: user)
        return user
    }

    static func signIn(email: String, password: String) async throws -> Session {
        var user = try await authRequest(
            path: "/api/auth/sessions",
            body: ["method": "password", "email": email, "password": password]
        )
        // Recover the display name from the profile row.
        if let profile: [Profile] = try? await get("profiles", query: "id=eq.\(user.userID)&limit=1", token: user.accessToken),
           let name = profile.first?.display_name {
            user.displayName = name
        }
        try await upsertProfile(session: user)
        return user
    }

    private static func authRequest(path: String, body: [String: String]) async throws -> Session {
        var request = URLRequest(url: baseURL.appending(path: path).appending(queryItems: [URLQueryItem(name: "client_type", value: "mobile")]))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard (response as? HTTPURLResponse)?.statusCode ?? 0 < 300 else {
            throw SocialError.server(json["message"] as? String ?? "Sign-in failed")
        }
        guard let token = json["accessToken"] as? String,
              let user = json["user"] as? [String: Any],
              let id = user["id"] as? String else {
            throw SocialError.server("Sign-in failed — check email and password")
        }
        let name = (user["name"] as? String) ?? "Cook"
        return Session(accessToken: token, refreshToken: json["refreshToken"] as? String, userID: id, displayName: name)
    }

    /// Whether the signed-in account still exists. A deleted account's profile row is gone
    /// (cascade), so an empty result means the session is a ghost and should be dropped.
    /// Throws `.sessionExpired` on 401 so the caller can sign out on an expired token too.
    static func accountExists(session: Session) async throws -> Bool {
        let rows: [Profile] = try await get(
            "profiles", query: "id=eq.\(session.userID)&limit=1", token: session.accessToken)
        return !rows.isEmpty
    }

    /// Exchange the refresh token for a fresh session (tokens rotate — persist the result).
    static func refresh(session: Session) async throws -> Session {
        guard let refreshToken = session.refreshToken else { throw SocialError.sessionExpired }
        var request = URLRequest(url: baseURL.appending(path: "/api/auth/refresh").appending(queryItems: [URLQueryItem(name: "client_type", value: "mobile")]))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(["refreshToken": refreshToken])

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard (response as? HTTPURLResponse)?.statusCode ?? 0 < 300,
              let token = json["accessToken"] as? String else {
            throw SocialError.sessionExpired
        }
        var next = session
        next.accessToken = token
        next.refreshToken = (json["refreshToken"] as? String) ?? refreshToken
        return next
    }

    private static func upsertProfile(session: Session) async throws {
        struct Row: Encodable { let id: String; let display_name: String }
        // Insert; on conflict (already exists) fall back to update.
        do {
            try await send("POST", "profiles", body: [Row(id: session.userID, display_name: session.displayName)], token: session.accessToken)
        } catch {
            try? await send("PATCH", "profiles", query: "id=eq.\(session.userID)",
                            body: ["display_name": session.displayName], token: session.accessToken)
        }
    }

    // MARK: - Feed data

    static func fetchPosts(token: String) async throws -> [FeedPost] {
        try await get("posts", query: "order=created_at.desc&limit=100", token: token)
    }

    /// The community's most-cooked recipes: recipe-bearing posts ranked by likes. Powers the
    /// "Popular right now" carousel. Empty early on, which the caller handles by falling back
    /// to featured catalog dishes.
    static func popularRecipes(token: String, limit: Int = 12) async throws -> [Recipe] {
        let posts: [FeedPost] = try await get(
            "posts",
            query: "recipe=not.is.null&order=like_count.desc,comment_count.desc&limit=\(limit)",
            token: token)
        return posts.compactMap(\.recipe)
    }

    static func fetchMyLikes(token: String, userID: String) async throws -> Set<String> {
        struct Like: Decodable { let post_id: String }
        let likes: [Like] = try await get("likes", query: "user_id=eq.\(userID)&select=post_id", token: token)
        return Set(likes.map(\.post_id))
    }

    /// Create any kind of post: text / question / photo / recipe share, optionally inside a group.
    static func createPost(
        kind: String, caption: String, imageURL: String?, recipe: Recipe?, groupID: String?,
        token: String, userID: String
    ) async throws -> FeedPost {
        struct Row: Encodable {
            let author_id: String
            let caption: String
            let image_url: String?
            let recipe: Recipe?
            let kind: String
            let group_id: String?
        }
        let rows: [FeedPost] = try await send(
            "POST", "posts",
            body: [Row(author_id: userID, caption: caption, image_url: imageURL ?? recipe?.img,
                       recipe: recipe, kind: kind, group_id: groupID)],
            token: token, returning: true
        )
        guard let post = rows.first else { throw SocialError.server("Post failed") }
        return post
    }

    /// Recipe share convenience (kept for the detail screen's Share button).
    static func createPost(recipe: Recipe, caption: String, token: String, userID: String) async throws -> FeedPost {
        try await createPost(kind: "recipe", caption: caption, imageURL: recipe.img, recipe: recipe, groupID: nil, token: token, userID: userID)
    }

    // MARK: - Groups

    static func fetchGroups(token: String) async throws -> [CommunityGroup] {
        try await get("groups", query: "order=member_count.desc,name.asc&limit=100", token: token)
    }

    static func fetchMyGroupIDs(token: String, userID: String) async throws -> Set<String> {
        struct Row: Decodable { let group_id: String }
        let rows: [Row] = try await get("group_members", query: "user_id=eq.\(userID)&select=group_id", token: token)
        return Set(rows.map(\.group_id))
    }

    static func joinGroup(id: String, token: String, userID: String) async throws {
        struct Row: Encodable { let group_id: String; let user_id: String }
        try await send("POST", "group_members", body: [Row(group_id: id, user_id: userID)], token: token)
    }

    static func leaveGroup(id: String, token: String, userID: String) async throws {
        try await send("DELETE", "group_members", query: "group_id=eq.\(id)&user_id=eq.\(userID)", token: token)
    }

    // MARK: - Photos

    /// Uploads a JPEG to the public post-images bucket and returns its URL.
    static func uploadImage(_ data: Data, token: String, userID: String) async throws -> String {
        let key = "\(userID)-\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
        var request = URLRequest(url: baseURL.appending(path: "/api/storage/buckets/post-images/objects/\(key)"))
        request.httpMethod = "PUT"
        request.timeoutInterval = 60
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let boundary = "gs-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(key)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        let (respData, response) = try await URLSession.shared.data(for: request)
        try check(response, data: respData)
        // Serve via the stable object URL (the API responds with a versioned URL; either works).
        return baseURL.appending(path: "/api/storage/buckets/post-images/objects/\(key)").absoluteString
    }

    static func deletePost(id: String, token: String) async throws {
        try await send("DELETE", "posts", query: "id=eq.\(id)", token: token)
    }

    // MARK: - Reels

    /// The community reel feed: user-uploaded video posts, newest first. YouTube recipe reels
    /// are synthesised on the client from the catalog, so this only returns uploaded reels.
    static func fetchReels(token: String, limit: Int = 60) async throws -> [FeedPost] {
        try await get("posts",
                      query: "kind=eq.reel&hidden_at=is.null&order=created_at.desc&limit=\(limit)",
                      token: token)
    }

    /// Uploads a reel clip to the public reel-videos bucket and returns its object URL.
    static func uploadReelVideo(_ data: Data, token: String, userID: String) async throws -> String {
        let key = "\(userID)-\(Int(Date().timeIntervalSince1970 * 1000)).mp4"
        var request = URLRequest(url: baseURL.appending(path: "/api/storage/buckets/reel-videos/objects/\(key)"))
        request.httpMethod = "PUT"
        request.timeoutInterval = 120
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let boundary = "gs-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(key)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: video/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        let (respData, response) = try await URLSession.shared.data(for: request)
        try check(response, data: respData)
        return baseURL.appending(path: "/api/storage/buckets/reel-videos/objects/\(key)").absoluteString
    }

    /// Creates a reel post (kind = "reel"). `recipe` optionally links the clip to a recipe so
    /// viewers can open it; `thumbURL` is a poster frame for the feed.
    static func createReel(videoURL: String, thumbURL: String?, caption: String, recipe: Recipe?,
                           durationSeconds: Int?, token: String, userID: String) async throws -> FeedPost {
        struct Row: Encodable {
            let author_id: String
            let caption: String
            let recipe: Recipe?
            let kind: String
            let video_url: String
            let thumb_url: String?
            let duration_seconds: Int?
        }
        let rows: [FeedPost] = try await send(
            "POST", "posts",
            body: [Row(author_id: userID, caption: caption, recipe: recipe, kind: "reel",
                       video_url: videoURL, thumb_url: thumbURL ?? recipe?.img, duration_seconds: durationSeconds)],
            token: token, returning: true
        )
        guard let post = rows.first else { throw SocialError.server("Reel failed") }
        return post
    }

    static func like(postID: String, token: String, userID: String) async throws {
        struct Row: Encodable { let post_id: String; let user_id: String }
        try await send("POST", "likes", body: [Row(post_id: postID, user_id: userID)], token: token)
    }

    static func unlike(postID: String, token: String, userID: String) async throws {
        try await send("DELETE", "likes", query: "post_id=eq.\(postID)&user_id=eq.\(userID)", token: token)
    }

    static func fetchComments(postID: String, token: String) async throws -> [FeedComment] {
        try await get("comments", query: "post_id=eq.\(postID)&order=created_at.asc&limit=200", token: token)
    }

    static func addComment(postID: String, body: String, token: String, userID: String) async throws -> FeedComment {
        struct Row: Encodable { let post_id: String; let author_id: String; let body: String }
        let rows: [FeedComment] = try await send(
            "POST", "comments",
            body: [Row(post_id: postID, author_id: userID, body: body)],
            token: token, returning: true
        )
        guard let comment = rows.first else { throw SocialError.server("Comment failed") }
        return comment
    }

    // MARK: - Moderation

    /// Reasons offered when reporting. Raw values match the CHECK constraint on
    /// content_reports.reason.
    enum ReportReason: String, CaseIterable, Identifiable {
        case spam, harassment, hate, violence, sexual, misinformation, other
        var id: String { rawValue }

        var label: String {
            switch self {
            case .spam: return "Spam or scam"
            case .harassment: return "Harassment or bullying"
            case .hate: return "Hate speech"
            case .violence: return "Violence or threats"
            case .sexual: return "Sexual content"
            case .misinformation: return "Dangerous misinformation"
            case .other: return "Something else"
            }
        }
    }

    static func reportPost(id: String, reason: ReportReason, note: String,
                           token: String, userID: String) async throws {
        struct Row: Encodable {
            let reporter_id: String; let target_type: String
            let post_id: String; let reason: String; let note: String
        }
        try await send("POST", "content_reports", body: [Row(
            reporter_id: userID, target_type: "post", post_id: id,
            reason: reason.rawValue, note: note)], token: token)
    }

    static func reportComment(id: String, postID: String, reason: ReportReason, note: String,
                              token: String, userID: String) async throws {
        struct Row: Encodable {
            let reporter_id: String; let target_type: String
            let post_id: String; let comment_id: String; let reason: String; let note: String
        }
        try await send("POST", "content_reports", body: [Row(
            reporter_id: userID, target_type: "comment", post_id: postID, comment_id: id,
            reason: reason.rawValue, note: note)], token: token)
    }

    /// Blocking is enforced by RLS, so after this call the blocked user's posts and
    /// comments simply stop coming back from the server in either direction.
    static func block(userID blocked: String, token: String, userID: String) async throws {
        struct Row: Encodable { let blocker_id: String; let blocked_id: String }
        try await send("POST", "user_blocks", body: [Row(blocker_id: userID, blocked_id: blocked)], token: token)
    }

    static func unblock(userID blocked: String, token: String, userID: String) async throws {
        try await send("DELETE", "user_blocks",
                       query: "blocker_id=eq.\(userID)&blocked_id=eq.\(blocked)", token: token)
    }

    struct BlockedUser: Decodable, Identifiable {
        let blocked_id: String
        var id: String { blocked_id }
    }

    static func fetchBlocked(token: String) async throws -> [BlockedUser] {
        try await get("user_blocks", query: "select=blocked_id", token: token)
    }

    // MARK: - Account deletion

    /// Runs entirely on the server: it removes the auth user, and every social table
    /// cascades from that row. There is no client-side equivalent, by design.
    static func deleteAccount(token: String) async throws {
        var request = URLRequest(url: URL(string: "https://j7pth4qn.function2.insforge.app/account")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["action": "delete", "confirm": "DELETE"])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SocialError.server("Network error") }
        guard http.statusCode < 300 else {
            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            throw SocialError.server(json["error"] as? String ?? "Delete failed (\(http.statusCode))")
        }
    }

    // MARK: - Purchases

    /// Hands Apple's signed transaction to the backend, which verifies the signature and
    /// writes the plan. Returns the plan the server actually granted — never the one the
    /// client thinks it bought.
    static func submitPurchase(jws: String, token: String) async throws -> Entitlement.Plan {
        var request = URLRequest(url: URL(string: "https://j7pth4qn.function2.insforge.app/purchase")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["signed_transaction": jws])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SocialError.server("Network error") }
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard http.statusCode < 300 else {
            throw SocialError.server(json["error"] as? String ?? "Activation failed (\(http.statusCode))")
        }
        guard let raw = json["plan"] as? String, let plan = Entitlement.Plan(rawValue: raw) else {
            throw SocialError.server("Unexpected response")
        }
        return plan
    }

    /// The account's entitlement as the server sees it — the source of truth the AI-metering
    /// RPC actually enforces. The client mirrors this so the plan can't drift from what the
    /// server will allow (e.g. after a purchase verified on another device, or when StoreKit
    /// on this device has no record of the sub). Returns nil when the row doesn't exist yet.
    struct ServerEntitlement: Decodable {
        let plan: String
        let used: Int
        let top_up: Int
        let period: String
        let trial_until: String?
    }

    static func fetchEntitlement(token: String) async throws -> ServerEntitlement? {
        // RLS scopes the read to the caller's own row, so no user_id filter is needed.
        let rows: [ServerEntitlement] = try await get(
            "entitlements",
            query: "select=plan,used,top_up,period,trial_until&limit=1",
            token: token)
        return rows.first
    }

    // MARK: - Low-level records helpers

    private struct Profile: Decodable { let display_name: String }

    // MARK: - Account state sync

    private struct StateRow: Decodable { let data: AppStore.Persisted?; let updated_at: String? }
    private struct StateUpload: Encodable { let user_id: String; let data: AppStore.Persisted }

    /// The user's synced app state, or nil if they've never synced from any device.
    static func fetchUserState(token: String, userID: String) async throws -> AppStore.Persisted? {
        let rows: [StateRow] = try await get(
            "user_state", query: "user_id=eq.\(userID)&select=data,updated_at&limit=1", token: token)
        return rows.first?.data
    }

    /// Upserts the whole app-state blob for this user (last-write-wins per device).
    static func saveUserState(_ state: AppStore.Persisted, token: String, userID: String) async throws {
        var request = URLRequest(url: recordsURL("user_state", query: nil))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Insert-or-update on the user_id primary key.
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder().encode([StateUpload(user_id: userID, data: state)])
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response, data: data)
    }

    private static func recordsURL(_ table: String, query: String?) -> URL {
        var url = baseURL.appending(path: "/api/database/records/\(table)")
        if let query, var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            comps.percentEncodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            url = comps.url ?? url
        }
        return url
    }

    private static func get<T: Decodable>(_ table: String, query: String?, token: String) async throws -> T {
        var request = URLRequest(url: recordsURL(table, query: query))
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response, data: data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    @discardableResult
    private static func send<Body: Encodable, T: Decodable>(
        _ method: String, _ table: String, query: String? = nil,
        body: Body? = nil, token: String, returning: Bool = false
    ) async throws -> T {
        var request = URLRequest(url: recordsURL(table, query: query))
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if returning { request.setValue("return=representation", forHTTPHeaderField: "Prefer") }
        if let body { request.httpBody = try JSONEncoder().encode(body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response, data: data)
        if returning { return try JSONDecoder().decode(T.self, from: data) }
        // Callers not asking for rows use EmptyReply.
        return try JSONDecoder().decode(T.self, from: "{}".data(using: .utf8)!)
    }

    private static func send<Body: Encodable>(
        _ method: String, _ table: String, query: String? = nil, body: Body? = nil, token: String
    ) async throws {
        let _: EmptyReply = try await send(method, table, query: query, body: body, token: token, returning: false)
    }

    private static func send(_ method: String, _ table: String, query: String? = nil, token: String) async throws {
        let none: String? = nil
        let _: EmptyReply = try await send(method, table, query: query, body: none, token: token, returning: false)
    }

    private struct EmptyReply: Decodable {}

    private static func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw SocialError.server("Network error") }
        if http.statusCode == 401 { throw SocialError.sessionExpired }
        guard http.statusCode < 300 else {
            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            throw SocialError.server(json["message"] as? String ?? "Server error \(http.statusCode)")
        }
    }
}

// MARK: - Wire models (snake_case matches the backend)

struct FeedPost: Codable, Identifiable, Hashable {
    let id: String
    let author_id: String
    let author_name: String
    let caption: String
    let recipe: Recipe?
    let image_url: String?
    let kind: String
    let group_id: String?
    var like_count: Int
    var comment_count: Int
    let created_at: String
    // Reel fields — present only on kind == "reel". Optional so older/other posts decode.
    var video_url: String? = nil
    var youtube_id: String? = nil
    var thumb_url: String? = nil
    var duration_seconds: Int? = nil

    var imageURL: URL? { URL(string: image_url ?? recipe?.img ?? "") }
    var isQuestion: Bool { kind == "question" }
    var isReel: Bool { kind == "reel" }
    var videoURL: URL? { URL(string: video_url ?? "") }
    var thumbURL: URL? { URL(string: thumb_url ?? recipe?.img ?? "") }

    var relativeTime: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: created_at)
            ?? ISO8601DateFormatter().date(from: created_at)
        guard let date else { return "" }
        let seconds = -date.timeIntervalSinceNow
        if seconds < 90 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
        return "\(Int(seconds / 86_400))d"
    }
}

struct CommunityGroup: Codable, Identifiable, Hashable {
    let id: String
    let slug: String
    let name: String
    let emoji: String
    let description: String
    var member_count: Int
    var post_count: Int
}

struct FeedComment: Codable, Identifiable, Hashable {
    let id: String
    let post_id: String
    let author_id: String
    let author_name: String
    let body: String
    let created_at: String
}
