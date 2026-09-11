import Foundation
import UIKit

/// Real AI recipe extraction with structured outputs. Raw HTTPS is used because Swift has no
/// official SDK for either backend.
///
/// Two providers are supported and picked from the key itself: an `sk-or-…` key goes to
/// OpenRouter's OpenAI-compatible endpoint, anything else to the Anthropic Messages API.
enum RecipeExtractor {

    enum ExtractionError: LocalizedError {
        case noAPIKey
        case badURL
        case pageFetchFailed
        case refused(String?)
        case apiError(Int, String)
        case emptyResponse

        /// User-facing copy only. These strings are shown in toasts, so they must never name
        /// the backend, the model, or leak an upstream error — see `debugDetail` for that.
        var errorDescription: String? {
            switch self {
            case .noAPIKey: return "Recipe AI is unavailable right now. Please try again later."
            case .badURL: return "That link doesn't look valid"
            case .pageFetchFailed: return "Couldn't open that page"
            case .refused: return "We couldn't read that one — try another link or photo."
            case .apiError: return "Something went wrong. Please try again."
            case .emptyResponse: return "We couldn't find a recipe in that"
            }
        }

        /// Console-only diagnostics; never shown in the UI.
        var debugDetail: String {
            switch self {
            case .noAPIKey: return "no credential configured"
            case .badURL: return "bad url"
            case .pageFetchFailed: return "page fetch failed"
            case .refused(let why): return "refused: \(why ?? "-")"
            case .apiError(let code, let msg): return "api \(code): \(msg)"
            case .emptyResponse: return "empty/undecodable payload"
            }
        }
    }

    // MARK: - Providers

    enum Provider {
        case anthropic
        case openRouter

        /// OpenRouter issues `sk-or-v1-…` keys; Anthropic's look like `sk-ant-…`.
        static func forKey(_ key: String) -> Provider {
            key.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("sk-or-") ? .openRouter : .anthropic
        }

        var label: String {
            switch self {
            case .anthropic: return "Anthropic"
            case .openRouter: return "OpenRouter"
            }
        }

        /// Vision + structured outputs on both paths.
        var model: String {
            switch self {
            case .anthropic: return "claude-opus-5"
            case .openRouter: return "anthropic/claude-sonnet-5"
            }
        }
    }

    /// Backend-neutral message content, converted to each provider's own shape at send time.
    private enum ContentPart {
        case text(String)
        case jpeg(Data)
    }

    // MARK: - Public entry points

    /// Extract a recipe from pasted text, a URL, or a YouTube link.
    static func extract(from input: String, apiKey: String, sourceLabel: String) async throws -> Recipe {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var content = trimmed
        var imageURL: String?

        if let videoID = youTubeID(from: trimmed) {
            // No official transcript access from-device; the watch page's title +
            // description is usually enough for the model to reconstruct the recipe.
            let page = try await fetchPage(url: "https://www.youtube.com/watch?v=\(videoID)")
            content = """
            YouTube cooking video. Reconstruct the most plausible full recipe from its metadata.
            \(metaSummary(of: page))
            """
            imageURL = "https://img.youtube.com/vi/\(videoID)/hqdefault.jpg"
        } else if trimmed.range(of: #"^https?://"#, options: [.regularExpression, .caseInsensitive]) != nil {
            let page = try await fetchPage(url: trimmed)
            imageURL = ogImage(of: page)
            content = "Recipe web page content:\n" + plainText(of: page)
        }

        // 20k chars covers any real recipe page. The cap matters commercially, not just
        // technically: links are the priciest action, and uncapped page text is what pushes
        // a heavy annual subscriber past break-even.
        var recipe = try await callRecipe(
            parts: [.text(String(content.prefix(20_000)))],
            apiKey: apiKey, sourceLabel: sourceLabel, imageURL: imageURL
        )
        recipe.videoID = youTubeID(from: trimmed)
        return recipe
    }

    /// Identify a dish from a photo and generate its recipe (vision).
    static func extract(fromImage image: UIImage, apiKey: String) async throws -> Recipe {
        guard let jpeg = downscaled(image, maxEdge: 1568).jpegData(compressionQuality: 0.8) else {
            throw ExtractionError.emptyResponse
        }
        return try await callRecipe(
            parts: [
                .jpeg(jpeg),
                .text("Identify this dish and produce a complete, realistic home-cook recipe for it. If the dish is ambiguous, pick the most likely interpretation and mention the alternative in the notes."),
            ],
            apiKey: apiKey, sourceLabel: "Photo scan", imageURL: nil
        )
    }

    /// Identify a dish and its visible ingredients from a photo.
    static func analyzeFoodPhoto(_ image: UIImage, apiKey: String) async throws -> FoodScanAnalysis {
        guard let jpeg = downscaled(image, maxEdge: 1568).jpegData(compressionQuality: 0.8) else {
            throw ExtractionError.emptyResponse
        }
        let parts: [ContentPart] = [
            .jpeg(jpeg),
            .text("""
                Identify the food in this image. Return the most likely dish name, an estimated plate \
                weight in grams, and the visible ingredients with approximate percentage of the plate \
                and grams. Use short ingredient names. If uncertain, still return the most likely result.

                Also return possible_dishes: 3-5 specific, cookable dish names this could be, best \
                first, each with a confidence 0-100 and a one-line blurb saying what makes it that dish. \
                Make them real recipe names a cook could search for, not generic categories.
                """),
        ]
        return try await callFoodScan(parts: parts, apiKey: apiKey)
    }

    /// Write a full recipe for a dish the scanner suggested. This is the slow call the
    /// scan-results screen shows its loader for — it's a full generation, not a lookup.
    static func generateRecipe(forDish dish: String, detected: [IngredientConfidence], apiKey: String) async throws -> Recipe {
        let detectedList = detected.isEmpty
            ? "none detected"
            : detected.map { "\($0.name) (~\($0.grams) g)" }.joined(separator: ", ")
        let prompt = """
        Write a complete, realistic home-cook recipe for: \(dish)

        A photo of the finished plate was analysed and these components were visible: \(detectedList).
        Honour those components where they make sense for the dish, and add whatever else the dish \
        genuinely needs. Scale the recipe to a normal household serving count.
        """
        return try await callRecipe(
            parts: [.text(prompt)],
            apiKey: apiKey,
            sourceLabel: "Dish scan",
            imageURL: nil
        )
    }

    // MARK: - Model call

    private static let system = """
    You are the recipe engine inside goodiesSnap, a recipe-keeper app. Extract or reconstruct one \
    complete recipe from the user's content. Quantities use metric-friendly home-cook units. \
    Each ingredient gets the single best supermarket-aisle category. Steps are clear, one action \
    each, no life stories. Estimate calories and macros per serving honestly. cuisine is a short \
    label like "Italian", "Thai", "West African", or "Breakfast". If the content contains no \
    plausible recipe at all, use the title "Not a recipe" and leave ingredients and steps empty. \
    When the content is a YouTube cooking video whose description or chapters contain timestamps, \
    fill step_seconds with the start time in whole seconds for each step, aligned to steps by \
    index (use -1 for any step you cannot place). If there are no timestamps, return an empty \
    step_seconds array.
    """

    private static let schema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["title", "cuisine", "prep_minutes", "cook_minutes", "servings",
                     "calories_per_serving", "protein_g", "carbs_g", "fat_g",
                     "ingredients", "steps", "step_seconds", "notes"],
        "properties": [
            "title": ["type": "string"],
            "cuisine": ["type": "string"],
            "prep_minutes": ["type": "integer"],
            "cook_minutes": ["type": "integer"],
            "servings": ["type": "integer"],
            "calories_per_serving": ["type": "integer"],
            "protein_g": ["type": "integer"],
            "carbs_g": ["type": "integer"],
            "fat_g": ["type": "integer"],
            "ingredients": [
                "type": "array",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["name", "qty", "category"],
                    "properties": [
                        "name": ["type": "string"],
                        "qty": ["type": "string"],
                        "category": ["type": "string", "enum": Aisle.order],
                    ],
                ],
            ],
            "steps": ["type": "array", "items": ["type": "string"]],
            "step_seconds": ["type": "array", "items": ["type": "integer"]],
            "notes": ["type": "string"],
        ],
    ]

    private struct ExtractedRecipe: Decodable {
        let title: String
        let cuisine: String
        let prep_minutes: Int
        let cook_minutes: Int
        let servings: Int
        let calories_per_serving: Int
        let protein_g: Int
        let carbs_g: Int
        let fat_g: Int
        let ingredients: [ExtractedIngredient]
        let steps: [String]
        let step_seconds: [Int]?
        let notes: String
    }

    private struct ExtractedIngredient: Decodable {
        let name: String
        let qty: String
        let category: String
    }

    private static let foodScanSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["dish_name", "weight_grams", "ingredients", "possible_dishes"],
        "properties": [
            "dish_name": ["type": "string"],
            "weight_grams": ["type": "integer"],
            "ingredients": [
                "type": "array",
                "minItems": 2,
                "maxItems": 8,
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["name", "percent", "grams"],
                    "properties": [
                        "name": ["type": "string"],
                        "percent": ["type": "number"],
                        "grams": ["type": "integer"],
                    ],
                ],
            ],
            "possible_dishes": [
                "type": "array",
                "minItems": 2,
                "maxItems": 5,
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["name", "confidence", "blurb"],
                    "properties": [
                        "name": ["type": "string"],
                        "confidence": ["type": "integer"],
                        "blurb": ["type": "string"],
                    ],
                ],
            ],
        ],
    ]

    private struct ExtractedFoodScan: Decodable {
        let dish_name: String
        let weight_grams: Int
        let ingredients: [ExtractedFoodIngredient]
        let possible_dishes: [ExtractedDishSuggestion]
    }

    private struct ExtractedFoodIngredient: Decodable {
        let name: String
        let percent: Double
        let grams: Int
    }

    private struct ExtractedDishSuggestion: Decodable {
        let name: String
        let confidence: Int
        let blurb: String
    }

    /// Sends one structured-output request and returns the raw JSON payload the model produced.
    /// Both providers are driven from here so the callers stay backend-agnostic.
    private static func requestStructuredJSON(
        parts: [ContentPart],
        system: String,
        schema: [String: Any],
        schemaName: String,
        maxTokens: Int,
        apiKey: String
    ) async throws -> Data {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ExtractionError.noAPIKey }
        let provider = Provider.forKey(key)

        var request: URLRequest
        let body: [String: Any]

        switch provider {
        case .anthropic:
            request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            // Server-side fallbacks: if Opus 5's safety classifiers decline a benign
            // request, the API re-runs it on the recommended fallback model.
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
            body = [
                "model": provider.model,
                "max_tokens": maxTokens,
                "fallbacks": "default",
                "system": system,
                "output_config": [
                    "effort": "low",
                    "format": ["type": "json_schema", "schema": schema],
                ],
                "messages": [["role": "user", "content": parts.map(anthropicBlock)]],
            ]

        case .openRouter:
            request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            // OpenRouter attributes traffic with these; they show up on the dashboard.
            request.setValue("https://goodiessnap.app", forHTTPHeaderField: "HTTP-Referer")
            request.setValue("goodiesSnap", forHTTPHeaderField: "X-Title")
            body = [
                "model": provider.model,
                "max_tokens": maxTokens,
                "messages": [
                    ["role": "system", "content": system],
                    ["role": "user", "content": parts.map(openAIBlock)],
                ],
                "response_format": [
                    "type": "json_schema",
                    "json_schema": ["name": schemaName, "strict": true, "schema": schema],
                ],
            ]
        }

        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ExtractionError.pageFetchFailed }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ExtractionError.emptyResponse
        }
        guard http.statusCode == 200 else {
            let message = (json["error"] as? [String: Any])?["message"] as? String ?? "unknown"
            throw ExtractionError.apiError(http.statusCode, message)
        }
        // OpenRouter can return 200 with an error body when an upstream provider fails.
        if let err = json["error"] as? [String: Any] {
            let code = (err["code"] as? Int) ?? 200
            throw ExtractionError.apiError(code, err["message"] as? String ?? "unknown")
        }

        let text: String
        switch provider {
        case .anthropic:
            if json["stop_reason"] as? String == "refusal" {
                throw ExtractionError.refused((json["stop_details"] as? [String: Any])?["explanation"] as? String)
            }
            guard let blocks = json["content"] as? [[String: Any]],
                  let t = blocks.first(where: { $0["type"] as? String == "text" })?["text"] as? String else {
                throw ExtractionError.emptyResponse
            }
            text = t

        case .openRouter:
            guard let choice = (json["choices"] as? [[String: Any]])?.first,
                  let message = choice["message"] as? [String: Any] else {
                throw ExtractionError.emptyResponse
            }
            if let refusal = message["refusal"] as? String, !refusal.isEmpty {
                throw ExtractionError.refused(refusal)
            }
            guard let t = message["content"] as? String, !t.isEmpty else {
                throw ExtractionError.emptyResponse
            }
            // A truncated answer is invalid JSON; say so rather than failing to decode.
            if choice["finish_reason"] as? String == "length" {
                throw ExtractionError.apiError(200, "the answer was cut off — try a shorter source")
            }
            text = t
        }

        guard let payload = text.data(using: .utf8) else { throw ExtractionError.emptyResponse }
        return payload
    }

    private static func anthropicBlock(_ part: ContentPart) -> [String: Any] {
        switch part {
        case .text(let t):
            return ["type": "text", "text": t]
        case .jpeg(let data):
            return [
                "type": "image",
                "source": ["type": "base64", "media_type": "image/jpeg", "data": data.base64EncodedString()],
            ]
        }
    }

    private static func openAIBlock(_ part: ContentPart) -> [String: Any] {
        switch part {
        case .text(let t):
            return ["type": "text", "text": t]
        case .jpeg(let data):
            return [
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(data.base64EncodedString())"],
            ]
        }
    }

    private static func callRecipe(
        parts: [ContentPart],
        apiKey: String,
        sourceLabel: String,
        imageURL: String?
    ) async throws -> Recipe {
        let payload = try await requestStructuredJSON(
            parts: parts,
            system: system,
            schema: schema,
            schemaName: "recipe",
            maxTokens: 16000,
            apiKey: apiKey
        )
        return try recipe(from: payload, sourceLabel: sourceLabel, imageURL: imageURL)
    }

    /// Decode the structured payload into a `Recipe`. Shared by the on-device and proxy paths.
    private static func recipe(from payload: Data, sourceLabel: String, imageURL: String?) throws -> Recipe {
        let extracted = try JSONDecoder().decode(ExtractedRecipe.self, from: payload)
        guard !extracted.ingredients.isEmpty, !extracted.steps.isEmpty else {
            throw ExtractionError.emptyResponse
        }

        // Safety net for when the model returns 0 minutes (it does when the source states no
        // times): estimate from the recipe's size so a card never shows "0 min".
        var prep = max(0, extracted.prep_minutes)
        var cook = max(0, extracted.cook_minutes)
        if prep + cook == 0 {
            // ~2 min prep per ingredient (5-25), ~4 min cook per step (10-60).
            prep = min(25, max(5, extracted.ingredients.count * 2))
            cook = min(60, max(10, extracted.steps.count * 4))
        } else if prep == 0 {
            prep = min(25, max(5, extracted.ingredients.count * 2))
        }

        return Recipe(
            id: "r\(Int(Date().timeIntervalSince1970 * 1000))",
            title: extracted.title,
            cuisine: extracted.cuisine,
            img: imageURL ?? fallbackImage(for: extracted.cuisine),
            source: sourceLabel,
            prep: prep,
            cook: cook,
            servings: max(1, extracted.servings),
            cal: extracted.calories_per_serving,
            macros: Macros(protein: extracted.protein_g, carbs: extracted.carbs_g, fat: extracted.fat_g),
            tags: [], favorite: false,
            ingredients: extracted.ingredients.map {
                Ingredient(name: $0.name, qty: $0.qty, category: Aisle.order.contains($0.category) ? $0.category : "Other")
            },
            steps: extracted.steps,
            notes: extracted.notes,
            stepSeconds: (extracted.step_seconds?.isEmpty ?? true) ? nil : extracted.step_seconds
        )
    }

    private static func callFoodScan(parts: [ContentPart], apiKey: String) async throws -> FoodScanAnalysis {
        let payload = try await requestStructuredJSON(
            parts: parts,
            system: """
            You are the food vision engine inside goodiesSnap. Identify a meal from the photo and \
            return only structured JSON. Percentages should roughly add to 100. Use common grocery \
            names because the app will match them against saved recipes.
            """,
            schema: foodScanSchema,
            schemaName: "food_scan",
            maxTokens: 4000,
            apiKey: apiKey
        )

        return try foodScan(from: payload)
    }

    /// Decode the structured payload into a `FoodScanAnalysis`. Shared by both paths.
    private static func foodScan(from payload: Data) throws -> FoodScanAnalysis {
        let extracted = try JSONDecoder().decode(ExtractedFoodScan.self, from: payload)
        // Providers don't always honour the schema's maxItems, so cap here — the flower
        // shows six and a long tail of trace ingredients is noise on the shopping list.
        let ingredients = extracted.ingredients.prefix(8).map {
            IngredientConfidence(name: $0.name, percent: $0.percent, grams: $0.grams, image: ingredientImage(for: $0.name))
        }
        guard !ingredients.isEmpty else { throw ExtractionError.emptyResponse }
        let suggestions = extracted.possible_dishes.map {
            FoodScanSuggestion(name: $0.name, confidence: max(1, min(100, $0.confidence)), blurb: $0.blurb)
        }
        return FoodScanAnalysis(
            dishName: extracted.dish_name,
            weightGrams: max(1, extracted.weight_grams),
            ingredients: ingredients,
            suggestions: suggestions.sorted { $0.confidence > $1.confidence }
        )
    }

    // MARK: - Server proxy (metered)

    /// Result of a metered call: the app mirrors `remaining`/`plan` so the UI can show the
    /// quota without a second round trip.
    struct ProxyResult<T> {
        let value: T
        let remaining: Int
        let plan: String
    }

    enum ProxyError: LocalizedError {
        case notSignedIn
        /// Server refused before spending anything: quota gone, or camera on a non-Pro plan.
        case notEntitled(reason: String, remaining: Int, plan: String)
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notSignedIn: return "Sign in to use Recipe AI"
            case .notEntitled(let reason, _, _):
                return reason == "camera_is_pro"
                    ? "Dish scanning is a Pro feature"
                    : "You've used all your AI actions this month"
            case .failed: return "Something went wrong. Please try again."
            }
        }
    }

    /// The AI proxy holds the provider key as a server secret and meters every call, so the
    /// quota is enforced in Postgres rather than on the device.
    private static let proxyURL = URL(string: "https://j7pth4qn.function2.insforge.app/ai")!

    private static func callProxy(body: [String: Any], token: String) async throws -> ProxyResult<Data> {
        var request = URLRequest(url: proxyURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProxyError.failed("bad response")
        }

        if http.statusCode == 402 {
            throw ProxyError.notEntitled(
                reason: json["error"] as? String ?? "quota_exhausted",
                remaining: json["remaining"] as? Int ?? 0,
                plan: json["plan"] as? String ?? "free"
            )
        }
        if http.statusCode == 401 { throw ProxyError.notSignedIn }
        guard http.statusCode == 200, let payload = json["data"] else {
            let detail = (json["detail"] as? String) ?? (json["error"] as? String) ?? "unknown"
            print("[ai proxy] \(http.statusCode): \(detail)")
            throw ProxyError.failed(detail)
        }

        return ProxyResult(
            value: try JSONSerialization.data(withJSONObject: payload),
            remaining: json["remaining"] as? Int ?? 0,
            plan: json["plan"] as? String ?? "free"
        )
    }

    /// Extract a recipe from text/link/video through the metered proxy.
    static func proxyExtract(from input: String, token: String, sourceLabel: String) async throws -> ProxyResult<Recipe> {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var content = trimmed
        var imageURL: String?

        // Page fetching stays on-device: it needs no key, and it keeps the function fast.
        if let videoID = youTubeID(from: trimmed) {
            let page = try await fetchPage(url: "https://www.youtube.com/watch?v=\(videoID)")
            content = "YouTube cooking video. Reconstruct the most plausible full recipe from its metadata.\n" + metaSummary(of: page)
            imageURL = "https://img.youtube.com/vi/\(videoID)/hqdefault.jpg"
        } else if trimmed.range(of: #"^https?://"#, options: [.regularExpression, .caseInsensitive]) != nil {
            let page = try await fetchPage(url: trimmed)
            imageURL = ogImage(of: page)
            content = "Recipe web page content:\n" + plainText(of: page)
        }

        let result = try await callProxy(
            body: ["action": "extract", "content": String(content.prefix(20_000))],
            token: token
        )
        var built = try recipe(from: result.value, sourceLabel: sourceLabel, imageURL: imageURL)
        built.videoID = youTubeID(from: trimmed)
        return ProxyResult(
            value: built,
            remaining: result.remaining, plan: result.plan
        )
    }

    /// Analyse a dish photo through the metered proxy.
    static func proxyAnalyzeFoodPhoto(_ image: UIImage, token: String) async throws -> ProxyResult<FoodScanAnalysis> {
        guard let jpeg = downscaled(image, maxEdge: 1568).jpegData(compressionQuality: 0.8) else {
            throw ProxyError.failed("could not encode image")
        }
        let result = try await callProxy(
            body: ["action": "scan", "image_base64": jpeg.base64EncodedString()],
            token: token
        )
        return ProxyResult(value: try foodScan(from: result.value), remaining: result.remaining, plan: result.plan)
    }

    /// Write a recipe for a scanned dish through the metered proxy.
    static func proxyGenerateRecipe(forDish dish: String, detected: [IngredientConfidence], token: String) async throws -> ProxyResult<Recipe> {
        let detectedList = detected.isEmpty
            ? "none detected"
            : detected.map { "\($0.name) (~\($0.grams) g)" }.joined(separator: ", ")
        let result = try await callProxy(
            body: ["action": "recipe_for_dish", "dish": dish, "detected": detectedList],
            token: token
        )
        return ProxyResult(
            value: try recipe(from: result.value, sourceLabel: "Dish scan", imageURL: nil),
            remaining: result.remaining, plan: result.plan
        )
    }

    /// Asks the proxy for a photo of `dish` from Google Images. Returns nil rather than
    /// throwing — artwork is a nicety, and a miss must never interrupt the scan.
    ///
    /// Costs no AI action: the proxy answers this one before the meter.
    static func proxyDishImage(dish: String, token: String) async -> String? {
        guard let result = try? await callProxy(
            body: ["action": "image_search", "dish": dish], token: token
        ) else { return nil }
        struct Wire: Decodable { let image: String? }
        return (try? JSONDecoder().decode(Wire.self, from: result.value))?.image
    }

    // MARK: - Page fetching & HTML utilities

    private static func fetchPage(url: String) async throws -> String {
        guard let u = URL(string: url) else { throw ExtractionError.badURL }
        var request = URLRequest(url: u)
        request.timeoutInterval = 20
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                throw ExtractionError.pageFetchFailed
            }
            return html
        } catch {
            throw ExtractionError.pageFetchFailed
        }
    }

    static func youTubeID(from text: String) -> String? {
        let patterns = [
            #"youtu\.be/([A-Za-z0-9_-]{6,})"#,
            #"youtube\.com/watch\?[^ ]*v=([A-Za-z0-9_-]{6,})"#,
            #"youtube\.com/shorts/([A-Za-z0-9_-]{6,})"#,
        ]
        for p in patterns {
            if let match = text.range(of: p, options: .regularExpression) {
                let s = String(text[match])
                if let idRange = s.range(of: #"([A-Za-z0-9_-]{6,})$"#, options: .regularExpression) {
                    return String(s[idRange])
                }
            }
        }
        return nil
    }

    private static func metaSummary(of html: String) -> String {
        var parts: [String] = []
        if let t = metaContent(html, matching: #"<title[^>]*>([^<]+)</title>"#) {
            parts.append("Title: \(t)")
        }
        for name in ["og:title", "og:description", "description"] {
            if let c = metaTag(html, property: name) {
                parts.append("\(name): \(c)")
            }
        }
        // The truncated og:description omits the chapter list; the full description (which
        // carries the "0:00 Step" timestamps we align steps to) lives in the watch page's
        // embedded player JSON as "shortDescription".
        if let full = youTubeFullDescription(html) {
            parts.append("Full description (may include timestamps):\n\(full)")
        }
        return parts.joined(separator: "\n")
    }

    /// Pull the un-truncated video description out of the YouTube watch page's embedded JSON.
    private static func youTubeFullDescription(_ html: String) -> String? {
        guard let range = html.range(of: #""shortDescription":"((?:[^"\\]|\\.)*)""#,
                                     options: .regularExpression) else { return nil }
        var raw = String(html[range])
        raw = raw.replacingOccurrences(of: #""shortDescription":""#, with: "")
        if raw.hasSuffix("\"") { raw.removeLast() }
        // JSON-unescape the parts that matter for reading timestamps.
        let unescaped = raw
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\u0026", with: "&")
        return String(unescaped.prefix(4_000))
    }

    private static func ogImage(of html: String) -> String? {
        let img = metaTag(html, property: "og:image")
        return img?.hasPrefix("http") == true ? img : nil
    }

    private static func metaTag(_ html: String, property: String) -> String? {
        // content= may come before or after property=/name=
        let patterns = [
            #"<meta[^>]+(?:property|name)=["']\#(property)["'][^>]+content=["']([^"']+)["']"#,
            #"<meta[^>]+content=["']([^"']+)["'][^>]+(?:property|name)=["']\#(property)["']"#,
        ]
        for p in patterns {
            if let c = metaContent(html, matching: p) { return c }
        }
        return nil
    }

    private static func metaContent(_ html: String, matching pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: html) else { return nil }
        return decodeEntities(String(html[range]))
    }

    /// Crude tag-stripper: good enough to hand page text to the model.
    private static func plainText(of html: String) -> String {
        var s = html
        for block in ["script", "style", "nav", "footer", "svg", "noscript"] {
            s = s.replacingOccurrences(
                of: "<\(block)[\\s\\S]*?</\(block)>",
                with: " ", options: [.regularExpression, .caseInsensitive]
            )
        }
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        s = decodeEntities(s)
        s = s.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "(\\s*\\n\\s*)+", with: "\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    private static func downscaled(_ image: UIImage, maxEdge: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxEdge else { return image }
        let scale = maxEdge / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private static func fallbackImage(for cuisine: String) -> String {
        let map: [String: String] = [
            "italian": "https://images.unsplash.com/photo-1563379926898-05f4575a45d8?w=800&q=80",
            "mexican": "https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=800&q=80",
            "thai": "https://images.unsplash.com/photo-1585032226651-759b368d7246?w=800&q=80",
            "breakfast": "https://images.unsplash.com/photo-1490474418585-ba9bad8fd0ea?w=800&q=80",
            "mediterranean": "https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=800&q=80",
        ]
        return map[cuisine.lowercased()]
            ?? "https://images.unsplash.com/photo-1547592166-23ac45744acd?w=800&q=80"
    }

    private static func ingredientImage(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("salmon") { return "https://images.unsplash.com/photo-1599084993091-1cb5c0721cc6?w=300&q=80" }
        if n.contains("rice") { return "https://images.unsplash.com/photo-1586201375761-83865001e31c?w=300&q=80" }
        if n.contains("cucumber") { return "https://images.unsplash.com/photo-1449300079323-02e209d9d3a6?w=300&q=80" }
        if n.contains("spinach") { return "https://images.unsplash.com/photo-1576045057995-568f588f82fb?w=300&q=80" }
        if n.contains("lettuce") { return "https://images.unsplash.com/photo-1622206151226-18ca2c9ab4a1?w=300&q=80" }
        if n.contains("tomato") { return "https://images.unsplash.com/photo-1592924357228-91a4daadcfea?w=300&q=80" }
        if n.contains("chicken") { return "https://images.unsplash.com/photo-1604503468506-a8da13d82791?w=300&q=80" }
        return "https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=300&q=80"
    }
}
