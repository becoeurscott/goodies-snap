import Foundation

struct Macros: Codable, Hashable {
    var protein: Int
    var carbs: Int
    var fat: Int
}

struct Ingredient: Codable, Hashable, Identifiable {
    var name: String
    var qty: String
    var category: String

    var id: String { name + "|" + qty }
}

struct Recipe: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var cuisine: String
    var img: String
    var source: String
    var prep: Int
    var cook: Int
    var servings: Int
    var cal: Int
    var macros: Macros
    var tags: [String]
    var favorite: Bool
    var ingredients: [Ingredient]
    var steps: [String]
    var notes: String

    var totalMinutes: Int { prep + cook }
    var meta: String { "\(totalMinutes) min · \(cal) cal · \(cuisine)" }
    var imageURL: URL? { URL(string: img) }
}

struct ShoppingItem: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var qty: String
    var category: String
    var done: Bool
    /// Which recipe this item came from, so the list can group by recipe. Nil = added by
    /// hand. Optional with defaults keeps older persisted lists decodable.
    var recipeID: String? = nil
    var recipeTitle: String? = nil
    /// Last looked-up store price, in cents, and the store it came from. Cached so the list
    /// doesn't re-query on every render.
    var priceCents: Int? = nil
    var priceStore: String? = nil
    /// Product image from the store lookup (Kroger), shown next to the item.
    var priceImage: String? = nil
}

struct UserPreferences: Codable, Hashable {
    var goal: String = ""
    var diet: String = ""
    var avoid: [String] = []
    var maxMinutes: Int = 30
    var servings: Int = 2
    var skill: String = ""

    var isComplete: Bool {
        !goal.isEmpty && !diet.isEmpty && !skill.isEmpty
    }

    var summary: String {
        let dietLabel = diet == "Anything" ? "flexible" : diet.lowercased()
        return "\(dietLabel) · \(maxMinutes) min · serves \(servings)"
    }

    func matchesAvoidance(_ recipe: Recipe) -> Bool {
        let haystack = ([recipe.title, recipe.cuisine] + recipe.tags + recipe.ingredients.map(\.name))
            .joined(separator: " ")
            .lowercased()
        return avoid.contains { item in
            let needle = item.lowercased()
            guard !needle.isEmpty else { return false }
            return haystack.contains(needle)
        }
    }

    func score(_ recipe: Recipe) -> Int {
        var score = 0
        let tags = recipe.tags.map { $0.lowercased() }
        let cuisine = recipe.cuisine.lowercased()

        if recipe.totalMinutes <= maxMinutes { score += 18 }
        if abs(recipe.servings - servings) <= 1 { score += 8 }

        switch goal {
        case "Eat healthier":
            if recipe.cal <= 550 { score += 12 }
            if tags.contains("fresh") || tags.contains("low carb") { score += 10 }
        case "Save time":
            if recipe.totalMinutes <= 25 || tags.contains("quick") { score += 20 }
        case "Meal prep":
            if tags.contains("meal prep") || tags.contains("make ahead") { score += 20 }
        case "Try new food":
            if ["Thai", "Mexican", "Mediterranean"].contains(recipe.cuisine) { score += 12 }
        default:
            break
        }

        switch diet {
        case "Vegetarian":
            if tags.contains("vegetarian") { score += 24 }
        case "High protein":
            if tags.contains("high protein") || recipe.macros.protein >= 25 { score += 24 }
        case "Low carb":
            if tags.contains("low carb") || recipe.macros.carbs <= 35 { score += 24 }
        case "Mediterranean":
            if cuisine == "mediterranean" { score += 24 }
        default:
            score += 4
        }

        if skill == "Beginner", recipe.steps.count <= 6 { score += 8 }
        if skill == "Confident", recipe.totalMinutes >= 25 { score += 4 }
        return score
    }
}

/// A candidate recipe for a scanned dish.
///
/// `recipeID` is set when the match is already in the user's library; when it's nil the match is
/// an AI suggestion whose full recipe gets fetched on demand (that call is what needs the loader).
struct FoodScanMatch: Hashable, Identifiable {
    var recipeID: String?
    var dishName: String
    var confidence: Int
    var detectedIngredients: [IngredientConfidence]
    /// One-line "why this matches", shown under the title before a recipe exists.
    var blurb: String = ""

    var isInLibrary: Bool { recipeID != nil }
    var id: String { recipeID ?? "ai:\(dishName.lowercased())" }
}

struct IngredientConfidence: Hashable, Identifiable {
    var name: String
    var percent: Double
    var grams: Int
    var image: String

    var id: String { name }

    /// Shopping-friendly quantity derived from the estimated plate weight.
    var shoppingQty: String {
        grams <= 0 ? "" : (grams >= 1000 ? String(format: "%.1f kg", Double(grams) / 1000) : "\(grams) g")
    }
}

struct FoodScanAnalysis: Hashable {
    var dishName: String
    var weightGrams: Int
    var ingredients: [IngredientConfidence]
    /// Dish names the model thinks this could be, best first — turned into fetchable matches.
    var suggestions: [FoodScanSuggestion] = []
}

struct FoodScanSuggestion: Hashable {
    var name: String
    var confidence: Int
    var blurb: String
}

enum Aisle {
    static let order = ["Produce", "Meat", "Seafood", "Dairy", "Pantry", "Spices", "Other"]

    /// Best-guess supermarket aisle for a loose ingredient name (used for scanned foods,
    /// which arrive without a category).
    static func guess(for name: String) -> String {
        let n = name.lowercased()
        let table: [(String, [String])] = [
            ("Seafood", ["salmon", "tuna", "shrimp", "prawn", "cod", "fish", "crab", "squid", "octopus", "anchov"]),
            ("Meat", ["chicken", "beef", "pork", "lamb", "bacon", "ham", "sausage", "turkey", "steak", "mince"]),
            ("Dairy", ["milk", "cheese", "yogurt", "yoghurt", "butter", "cream", "feta", "mozzarella", "parmesan", "egg"]),
            ("Produce", ["tomato", "onion", "garlic", "lettuce", "spinach", "cucumber", "pepper", "carrot", "potato",
                         "avocado", "lime", "lemon", "herb", "basil", "cilantro", "coriander", "parsley", "cabbage",
                         "broccoli", "mushroom", "corn", "bean", "pea", "apple", "mango", "salad", "greens", "scallion"]),
            ("Spices", ["salt", "pepper corn", "cumin", "paprika", "chili", "chilli", "curry", "spice", "cinnamon", "turmeric"]),
            ("Pantry", ["rice", "pasta", "noodle", "bread", "tortilla", "flour", "sugar", "oil", "vinegar", "sauce",
                        "soy", "sesame", "stock", "broth", "quinoa", "couscous", "lentil", "chickpea", "honey"]),
        ]
        for (aisle, keys) in table where keys.contains(where: { n.contains($0) }) {
            return aisle
        }
        return "Other"
    }
}
