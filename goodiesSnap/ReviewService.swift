import Foundation

/// Recipe reviews (`recipe_reviews`): a star rating + text a signed-in user leaves on a
/// recipe. Reading is public (anon key); writing/reporting needs the user's token.
enum ReviewService {
    private static let baseURL = SocialAPI.baseURL
    private static let anonKey = SocialAPI.anonKey

    /// All visible reviews for a recipe, newest first. Blocked/hidden ones are filtered by
    /// RLS, so what comes back is already safe to show.
    static func reviews(recipeKey: String) async throws -> [RecipeReview] {
        let q = "recipe_key=eq.\(recipeKey)&select=*&order=created_at.desc&limit=200"
        var comps = URLComponents(url: baseURL.appending(path: "/api/database/records/recipe_reviews"),
                                  resolvingAgainstBaseURL: false)!
        comps.percentEncodedQuery = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        var req = URLRequest(url: comps.url!)
        req.timeoutInterval = 30
        req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try check(resp, data)
        return try JSONDecoder().decode([RecipeReview].self, from: data)
    }

    /// Creates or updates the caller's review (one per recipe). Pass `existingID` to edit.
    @discardableResult
    static func submit(recipeKey: String, title: String, rating: Int, body: String,
                       token: String, userID: String, existingID: String?) async throws -> RecipeReview {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = existingID {
            let rows: [RecipeReview] = try await send(
                "PATCH", "recipe_reviews?id=eq.\(id)",
                body: ["rating": rating, "body": trimmed], token: token, returning: true)
            guard let r = rows.first else { throw SocialAPI.SocialError.server("Couldn't save your review") }
            return r
        } else {
            let payload: [String: Any] = [
                "recipe_key": recipeKey, "recipe_title": title,
                "user_id": userID, "rating": rating, "body": trimmed,
            ]
            let rows: [RecipeReview] = try await send(
                "POST", "recipe_reviews", body: payload, token: token, returning: true)
            guard let r = rows.first else { throw SocialAPI.SocialError.server("Couldn't post your review") }
            return r
        }
    }

    static func delete(id: String, token: String) async throws {
        _ = try await send("DELETE", "recipe_reviews?id=eq.\(id)", body: nil, token: token, returning: false) as [RecipeReview]
    }

    /// Files a report against a review, reusing the shared moderation table.
    static func report(id: String, reason: SocialAPI.ReportReason, note: String,
                       token: String, userID: String) async throws {
        let payload: [String: Any] = [
            "reporter_id": userID, "target_type": "review", "review_id": id,
            "reason": reason.rawValue, "note": note,
        ]
        _ = try await send("POST", "content_reports", body: payload, token: token, returning: false) as [RecipeReview]
    }

    // MARK: - Transport

    @discardableResult
    private static func send<T: Decodable>(_ method: String, _ path: String,
                                           body: [String: Any]?, token: String, returning: Bool) async throws -> [T] {
        var req = URLRequest(url: baseURL.appending(path: "/api/database/records/\(path)"))
        req.httpMethod = method
        req.timeoutInterval = 30
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if returning { req.setValue("return=representation", forHTTPHeaderField: "Prefer") }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: [body]) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        try check(resp, data)
        if returning, !data.isEmpty { return (try? JSONDecoder().decode([T].self, from: data)) ?? [] }
        return []
    }

    private static func check(_ resp: URLResponse, _ data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { throw SocialAPI.SocialError.server("Network error") }
        if http.statusCode == 401 { throw SocialAPI.SocialError.sessionExpired }
        guard http.statusCode < 300 else {
            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            throw SocialAPI.SocialError.server(json["message"] as? String ?? "Server error \(http.statusCode)")
        }
    }
}

/// A review as stored (snake_case matches Postgres).
struct RecipeReview: Codable, Identifiable, Hashable {
    let id: String
    let recipe_key: String
    let user_id: String
    let author_name: String
    let rating: Int
    let body: String
    let created_at: String

    var relativeTime: String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: created_at) ?? ISO8601DateFormatter().date(from: created_at)
        guard let date else { return "" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}
