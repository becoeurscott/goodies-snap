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
                notes: notes
            )
        }
    }

    /// Fetches a page of the catalog, newest first, optionally filtered by cuisine and a
    /// title search. Cuisine filtering happens server-side; search is a case-insensitive
    /// `ilike` so it stays cheap.
    static func fetch(cuisine: String? = nil, search: String = "",
                      limit: Int = 60, offset: Int = 0) async throws -> [Row] {
        var q = "select=*&published=eq.true&order=created_at.desc&limit=\(limit)&offset=\(offset)"
        if let cuisine, !cuisine.isEmpty { q += "&cuisine=eq.\(cuisine)" }
        let term = search.trimmingCharacters(in: .whitespaces)
        if !term.isEmpty {
            let escaped = term.replacingOccurrences(of: " ", with: "%20")
            q += "&title=ilike.*\(escaped)*"
        }
        return try await get("catalog_recipes", query: q)
    }

    /// The distinct cuisines present, for the filter chips. Uses PostgREST's distinct
    /// modifier so the app doesn't pull the whole table just to list them.
    static func cuisines() async throws -> [String] {
        struct CuisineRow: Decodable { let cuisine: String }
        let rows: [CuisineRow] = try await get(
            "catalog_recipes", query: "select=cuisine&published=eq.true")
        return Array(Set(rows.map(\.cuisine).filter { !$0.isEmpty })).sorted()
    }

    // MARK: - Transport

    private static func get<T: Decodable>(_ table: String, query: String) async throws -> T {
        var comps = URLComponents(url: baseURL.appending(path: "/api/database/records/\(table)"),
                                  resolvingAgainstBaseURL: false)!
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
