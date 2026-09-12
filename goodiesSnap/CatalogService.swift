import Foundation

/// Reads the server-side recipe catalog (the `catalog_recipes` table) that powers Discover.
///
/// Browsing does not require an account, so these calls use the anon key — the RLS policy
/// only exposes published rows. Rows are converted into the app's own `Recipe` so the
/// existing detail, cook mode and shopping-list code work unchanged.
enum CatalogService {
    private static let baseURL = SocialAPI.baseURL
    private static let anonKey = SocialAPI.anonKey

    /// One catalog row as it comes off the wire (snake_case matches Postgres).
    struct Row: Decodable {
        let id: String
        let source: String
        let source_id: String?
        let title: String
        let cuisine: String
        let category: String
        let image_url: String?
        let prep_minutes: Int
        let cook_minutes: Int
        let servings: Int
        let calories_per_serving: Int
        let protein_g: Int
        let carbs_g: Int
        let fat_g: Int
        let ingredients: [WireIngredient]
        let steps: [String]
        let tags: [String]
        let notes: String

        struct WireIngredient: Decodable { let name: String; let qty: String; let category: String }

        /// Converts to the app's Recipe. The id is namespaced so a saved catalog recipe
        /// never collides with a user's own or a seed recipe.
        var recipe: Recipe {
            Recipe(
                id: "cat_" + (source_id ?? id),
                title: title,
                cuisine: cuisine.isEmpty ? category : cuisine,
                img: image_url ?? "",
                source: "goodiesSnap Discover",
                prep: prep_minutes,
                cook: cook_minutes,
                servings: max(1, servings),
                cal: calories_per_serving,
                macros: Macros(protein: protein_g, carbs: carbs_g, fat: fat_g),
                tags: tags,
                favorite: false,
                ingredients: ingredients.map { Ingredient(name: $0.name, qty: $0.qty, category: $0.category) },
                steps: steps,
                notes: Self.cleanedNotes(notes),
                videoID: CatalogService.youTubeID(in: notes)
            )
        }

        /// TheMealDB keeps the cooking video as a "Video: <url>" line inside `notes`. Once the
        /// id is lifted out into `videoID` the player shows it properly, so the raw link would
        /// just be a dead string under the recipe.
        static func cleanedNotes(_ notes: String) -> String {
            notes
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { line in
                    let l = line.lowercased()
                    return !(l.contains("youtu") && l.contains("video"))
                }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Fetches a page of the catalog, newest first, optionally filtered by cuisine and a
    /// title search. Cuisine filtering happens server-side; search is a case-insensitive
    /// `ilike` so it stays cheap.
    static func fetch(cuisines: Set<String> = [], categories: Set<String> = [], search: String = "",
                      maxTime: Int? = nil, maxCal: Int? = nil,
                      limit: Int = 60, offset: Int = 0) async throws -> [Row] {
        var q = "select=*&published=eq.true&order=created_at.desc&limit=\(limit)&offset=\(offset)"
        if cuisines.count == 1, let c = cuisines.first { q += "&cuisine=eq.\(encodeValue(c))" }
        else if cuisines.count > 1 { q += "&cuisine=in.(\(cuisines.sorted().map { encodeValue($0) }.joined(separator: ",")))" }
        if categories.count == 1, let c = categories.first { q += "&category=eq.\(encodeValue(c))" }
        else if categories.count > 1 { q += "&category=in.(\(categories.sorted().map { encodeValue($0) }.joined(separator: ",")))" }
        if let maxTime { q += "&cook_minutes=lte.\(maxTime)" }
        if let maxCal { q += "&calories_per_serving=lte.\(maxCal)" }
        let term = search.trimmingCharacters(in: .whitespaces)
        if !term.isEmpty {
            q += "&title=ilike.*\(encodeValue(term))*"
        }
        return try await get("catalog_recipes", query: q)
    }

    /// The distinct food-type categories present, for the Discover filter's Food type facet.
    static func categories() async throws -> [String] {
        struct CategoryRow: Decodable { let category: String }
        let rows: [CategoryRow] = try await get(
            "catalog_recipes", query: "select=category&published=eq.true")
        return Array(Set(rows.map(\.category).filter { !$0.isEmpty })).sorted()
    }

    /// The distinct cuisines present, for the filter chips. Uses PostgREST's distinct
    /// modifier so the app doesn't pull the whole table just to list them.
    static func cuisines() async throws -> [String] {
        struct CuisineRow: Decodable { let cuisine: String }
        let rows: [CuisineRow] = try await get(
            "catalog_recipes", query: "select=cuisine&published=eq.true")
        return Array(Set(rows.map(\.cuisine).filter { !$0.isEmpty })).sorted()
    }

    /// Recommendations tailored to the user's taste profile, drawn from the catalog.
    ///
    /// Diet maps to TheMealDB categories/cuisines the query can filter on server-side; the
    /// avoid-list is applied on the client (it needs to look inside each recipe's
    /// ingredients). Results are shuffled for variety so the dashboard isn't identical
    /// every launch.
    static func recommended(for prefs: UserPreferences, limit: Int = 8) async throws -> [Row] {
        var q = "select=*&published=eq.true&limit=48"

        switch prefs.diet {
        case "Vegetarian":
            q += "&category=in.(Vegetarian,Vegan)"
        case "High protein":
            q += "&category=in.(Chicken,Beef,Seafood,Pork,Lamb)"
        case "Low carb":
            q += "&category=in.(Seafood,Chicken,Beef,Lamb)"
        case "Mediterranean":
            q += "&cuisine=in.(Greek,Turkish,Italian,Moroccan,Spanish,Tunisian,Croatian)"
        default:
            break // "Anything" / unset: whole catalog
        }

        let rows: [Row] = try await get("catalog_recipes", query: q)
        // Exclude anything the user asked to avoid, then pick a varied handful.
        let filtered = rows.filter { !prefs.matchesAvoidance($0.recipe) }
        return Array(filtered.shuffled().prefix(limit))
    }

    /// Recipes that ship with a cooking video, for the community reel feed. TheMealDB stores
    /// the YouTube link in `notes` ("Video: <url>"); we pull those rows, parse the id, and
    /// hand back the recipe plus its video id. Shuffled so the feed varies between opens.
    struct ReelRecipe { let recipe: Recipe; let youtubeID: String }

    static func reelRecipes(limit: Int = 40) async throws -> [ReelRecipe] {
        // Over-fetch, then keep only rows whose note yields a usable id.
        let rows: [Row] = try await get(
            "catalog_recipes",
            query: "select=*&published=eq.true&notes=ilike.*youtu*&limit=200")
        let reels: [ReelRecipe] = rows.compactMap { row in
            guard let id = youTubeID(in: row.notes) else { return nil }
            return ReelRecipe(recipe: row.recipe, youtubeID: id)
        }
        return Array(reels.shuffled().prefix(limit))
    }

    /// Extracts a YouTube video id from a watch / shorts / youtu.be URL embedded in text.
    static func youTubeID(in text: String) -> String? {
        let patterns = [
            #"(?:v=)([A-Za-z0-9_-]{11})"#,
            #"(?:shorts/)([A-Za-z0-9_-]{11})"#,
            #"(?:youtu\.be/)([A-Za-z0-9_-]{11})"#,
            #"(?:embed/)([A-Za-z0-9_-]{11})"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
               let idRange = Range(match.range(at: 1), in: text) {
                return String(text[idRange])
            }
        }
        return nil
    }

    // MARK: - Transport

    /// Percent-encodes a dynamic value (a search term, a cuisine) so it is safe to drop into a
    /// PostgREST query string. Only unreserved characters are kept; everything else — spaces,
    /// accented letters, `&`, `%`, `(`… — is encoded. Non-ASCII input (e.g. a French search
    /// like "crème") is exactly what used to trap `percentEncodedQuery` and crash the app.
    private static let valueAllowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
    private static func encodeValue(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: valueAllowed) ?? ""
    }

    private static func get<T: Decodable>(_ table: String, query: String) async throws -> T {
        var comps = URLComponents(url: baseURL.appending(path: "/api/database/records/\(table)"),
                                  resolvingAgainstBaseURL: false)!
        // Every dynamic value in `query` is already percent-encoded (see encodeValue), and the
        // rest is ASCII structure, so this is a valid percent-encoded string and won't trap.
        comps.percentEncodedQuery = query
        var request = URLRequest(url: comps.url!)
        request.timeoutInterval = 30
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 300 else {
            throw NSError(domain: "catalog", code: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
