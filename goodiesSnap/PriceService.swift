import Foundation

/// Talks to the `prices` edge function (Kroger pricing). The Kroger credentials live on the
/// server; this only ever sends ingredient names and a chosen store id, with the user's
/// auth token. Until Kroger approves the app and the secrets are set, every call throws
/// `.notConfigured` and the UI simply hides prices.
enum PriceService {
    private static let url = URL(string: "https://j7pth4qn.function2.insforge.app/prices")!

    struct Store: Codable, Identifiable, Hashable {
        let location_id: String
        let name: String
        let address: String
        var id: String { location_id }
    }

    enum PriceError: LocalizedError {
        case notConfigured, notSignedIn, failed(String)
        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Store pricing isn't available yet."
            case .notSignedIn: return "Sign in to see store prices."
            case .failed(let m): return m
            }
        }
    }

    static func stores(zip: String, token: String) async throws -> [Store] {
        struct Reply: Decodable { let stores: [Store] }
        let data = try await call(["action": "locations", "zip": zip], token: token)
        return (try JSONDecoder().decode(Reply.self, from: data)).stores
    }

    /// One priced match from the store: cents (nil = no price) and an optional product image.
    struct Priced: Decodable { let cents: Int?; let image: String? }

    /// Returns a Priced keyed by the ingredient name that was sent.
    static func prices(items: [String], locationID: String, token: String) async throws -> [String: Priced] {
        struct Reply: Decodable { let prices: [String: Priced] }
        let data = try await call(["action": "prices", "items": items, "location_id": locationID], token: token)
        return (try JSONDecoder().decode(Reply.self, from: data)).prices
    }

    private static func call(_ body: [String: Any], token: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        switch code {
        case 200..<300: return data
        case 503: throw PriceError.notConfigured
        case 401: throw PriceError.notSignedIn
        default:
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw PriceError.failed(msg ?? "Couldn't load prices (\(code))")
        }
    }
}
