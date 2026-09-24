import Foundation

/// Customer-service chat, backed by the `support` edge function.
///
/// The function stores every message, lets the AI assistant (the self-hosted model on the VPS)
/// answer when it can, and hands the conversation to the team when it can't — team replies
/// then arrive in the same conversation. The app only ever sends text and reads back messages;
/// every decision is made on the server.
enum SupportAPI {
    static let appID = "goodiessnap"
    private static let url = URL(string: "https://j7pth4qn.function2.insforge.app/support")!

    struct Message: Decodable, Identifiable, Equatable {
        let id: String
        /// "user", "ai", "agent" or "system".
        let sender: String
        let authorName: String?
        let body: String
        let createdAt: String

        enum CodingKeys: String, CodingKey {
            case id, sender, body
            case authorName = "author_name"
            case createdAt = "created_at"
        }

        var isMine: Bool { sender == "user" }
        var date: Date? { SupportAPI.parseDate(createdAt) }
    }

    struct Conversation: Decodable, Equatable {
        let id: String
        /// "ai", "needs_human", "human" or "closed".
        let status: String
    }

    struct Thread: Decodable {
        let conversation: Conversation?
        let messages: [Message]
    }

    enum SupportError: Error {
        case notSignedIn
        case failed
    }

    /// The customer's current conversation. With `after`, only messages newer than it.
    static func history(after: String? = nil, token: String) async throws -> Thread {
        var body: [String: Any] = ["action": "history", "app": appID]
        if let after { body["after"] = after }
        return try await call(body, token: token, timeout: 20)
    }

    /// Sends a message and returns it with the assistant's reply, if the assistant answered.
    /// The VPS model runs on CPU, so a reply can take a while — hence the long timeout.
    static func send(_ text: String, token: String) async throws -> Thread {
        try await call(["action": "send", "app": appID, "text": text], token: token, timeout: 120)
    }

    private static func call(_ body: [String: Any], token: String, timeout: TimeInterval) async throws -> Thread {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SupportError.failed }
        if http.statusCode == 401 { throw SupportError.notSignedIn }
        guard http.statusCode == 200 else {
            print("[support] \(http.statusCode): \(String(data: data, encoding: .utf8) ?? "")")
            throw SupportError.failed
        }
        struct Envelope: Decodable { let data: Thread }
        return try JSONDecoder().decode(Envelope.self, from: data).data
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso = ISO8601DateFormatter()

    /// Postgres timestamps come back with 0–6 fractional digits; ISO8601DateFormatter only
    /// reliably reads 3, so trim to milliseconds first.
    static func parseDate(_ s: String) -> Date? {
        let trimmed = s.replacingOccurrences(of: #"(\.\d{3})\d+"#, with: "$1", options: .regularExpression)
        return isoFractional.date(from: trimmed) ?? iso.date(from: trimmed)
    }
}
