import Foundation

/// Client for the `support` edge function: AI customer service with handoff to the team.
/// The function identifies the caller from their token, stores every message, and answers
/// from the help articles; hard cases (refunds, "talk to a person", low confidence) are
/// marked `needs_human` and answered from the admin console.
enum SupportAPI {
    static let appID = "goodiessnap"

    struct Message: Decodable, Identifiable, Equatable {
        let id: String
        let sender: String          // "user" | "ai" | "agent"
        let author_name: String?
        let body: String
        let created_at: String
    }

    struct Conversation: Decodable { let id: String; let status: String }

    struct Payload: Decodable {
        let conversation: Conversation?
        let messages: [Message]
    }

    private struct Envelope: Decodable { let data: Payload?; let error: String? }

    enum SupportError: Error { case server(String) }

    static func history(token: String) async throws -> Payload {
        try await call(["app": appID, "action": "history"], token: token)
    }

    static func send(_ text: String, token: String) async throws -> Payload {
        try await call(["app": appID, "action": "send", "text": text], token: token)
    }

    private static func call(_ body: [String: String], token: String) async throws -> Payload {
        var request = URLRequest(url: SocialAPI.baseURL.appending(path: "/functions/support"))
        request.httpMethod = "POST"
        // The self-hosted model can take close to a minute; the function streams keep-alive
        // whitespace while it thinks, so a generous timeout is safe.
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, _) = try await URLSession.shared.data(for: request)
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        if let payload = envelope.data { return payload }
        throw SupportError.server(envelope.error ?? "unknown")
    }
}
