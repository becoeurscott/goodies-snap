import Foundation

/// Offline grocery price estimates, in cents, for a typical single unit of purchase.
///
/// Why this exists: real prices come from `PriceService` (Kroger), which stays unavailable
/// until Kroger approves the app. Onboarding sells the app on "what will this actually cost
/// me?", so the cost steps need a number on day one. These are US national-average shelf
/// prices for the *package you put in the basket* — a tub of parmesan, a pound of chicken —
/// not the fraction a recipe uses. That matches what the user pays at the till, and it is
/// what the shopping list is for.
///
/// Every surface that shows one of these must say "estimated". The moment a store is
/// connected, `PriceService` wins and these are never consulted — see `AppStore.priceCents`.
enum IngredientPrices {

    /// When this table was last reviewed, shown in the disclosure copy so the estimate
    /// carries its own age rather than looking like live data.
    static let asOf = "2026"

    /// Fallback per aisle, for an ingredient with no entry of its own.
    private static let byAisle: [String: Int] = [
        "Produce": 229,
        "Meat": 749,
        "Seafood": 1099,
        "Dairy": 449,
        "Pantry": 329,
        "Spices": 349,
        "Other": 349,
    ]

    /// Keyed by a distinctive lowercase fragment of the ingredient name. Matching is
    /// longest-key-first, so "chicken thigh" beats the generic "chicken".
    private static let table: [String: Int] = [
        // Meat & poultry
        "chicken breast": 699, "chicken thigh": 549, "chicken wing": 599, "whole chicken": 899,
        "ground chicken": 629, "ground turkey": 649, "turkey": 899, "chicken": 649,
        "ground beef": 749, "beef mince": 749, "steak": 1399, "sirloin": 1299, "ribeye": 1799,
        "brisket": 1199, "beef": 899, "pork chop": 649, "pork belly": 899, "ground pork": 599,
        "pork": 699, "bacon": 799, "sausage": 649, "chorizo": 749, "ham": 699,
        "lamb": 1299, "meatball": 749, "pepperoni": 549, "prosciutto": 899,

        // Seafood
        "salmon": 1399, "tuna steak": 1499, "tuna": 249, "shrimp": 1099,
        "prawn": 1099, "cod": 1199, "tilapia": 799, "white fish": 999, "crab": 1599,
        "scallop": 1799, "mussel": 699, "squid": 899, "calamari": 899, "anchovy": 329,
        "sardine": 279, "fish sauce": 349, "fish": 999,

        // Dairy & eggs
        "heavy cream": 429, "double cream": 429, "sour cream": 279, "cream cheese": 329,
        "whipping cream": 429, "cream": 379, "whole milk": 389, "milk": 379,
        "almond milk": 379, "oat milk": 449, "coconut milk": 219, "buttermilk": 299,
        "parmesan": 599, "parmigiano": 699, "mozzarella": 449, "cheddar": 449, "feta": 449,
        "gruyere": 799, "goat cheese": 549, "ricotta": 399, "cottage cheese": 379,
        "cream fraiche": 429, "mascarpone": 549, "blue cheese": 599, "halloumi": 599,
        "cheese": 449, "butter": 499, "ghee": 899, "greek yogurt": 549, "yogurt": 449,
        "yoghurt": 449, "egg": 429, "eggs": 429,

        // Produce — vegetables
        "onion": 149, "red onion": 169, "spring onion": 129, "scallion": 129, "shallot": 249,
        "garlic": 109, "ginger": 149, "tomato": 249, "cherry tomato": 349, "potato": 399,
        "sweet potato": 249, "carrot": 149, "celery": 229, "cucumber": 129, "zucchini": 169,
        "courgette": 169, "eggplant": 199, "aubergine": 199, "bell pepper": 179,
        "red pepper": 179, "pepper": 179, "chili": 129, "chilli": 129, "jalape": 139,
        "broccoli": 249, "cauliflower": 349, "cabbage": 199, "kale": 249, "spinach": 349,
        "lettuce": 229, "romaine": 299, "arugula": 349, "rocket": 349, "salad": 349,
        "mushroom": 299, "asparagus": 449, "green bean": 249, "pea": 199, "corn": 149,
        "leek": 249, "beetroot": 229, "beet": 229, "squash": 299, "pumpkin": 349,
        "brussels sprout": 349, "bok choy": 229, "radish": 179, "turnip": 179,

        // Produce — fruit & herbs
        "avocado": 179, "lemon": 89, "lime": 69, "orange": 109, "apple": 129, "banana": 69,
        "mango": 149, "pineapple": 349, "strawberr": 449, "blueberr": 449, "raspberr": 449,
        "grape": 399, "pear": 129, "peach": 149, "coconut": 299, "date": 449, "raisin": 299,
        "basil": 249, "cilantro": 149, "coriander": 149, "parsley": 149, "mint": 199,
        "rosemary": 229, "thyme": 229, "sage": 229, "dill": 199, "chive": 199,
        "bay leaf": 229, "herb": 199,

        // Pantry — grains, pasta, bread
        "pasta": 199, "spaghetti": 199, "penne": 199, "linguine": 219, "lasagna": 249,
        "noodle": 229, "ramen": 149, "rice": 349, "basmati": 399, "jasmine rice": 399,
        "arborio": 449, "risotto rice": 449, "quinoa": 549, "couscous": 329, "bulgur": 299,
        "barley": 279, "oat": 399, "bread": 349, "sourdough": 499, "baguette": 279,
        "tortilla": 329, "pita": 299, "naan": 349, "bun": 349, "breadcrumb": 249,
        "flour": 399, "cornstarch": 229, "corn flour": 229, "baking powder": 219,
        "baking soda": 129, "yeast": 249, "puff pastry": 449, "phyllo": 449, "filo": 449,

        // Pantry — tins, sauces, oils
        "olive oil": 899, "sesame oil": 449, "vegetable oil": 449, "coconut oil": 649,
        "sunflower oil": 449, "oil": 499, "butter bean": 149, "black bean": 129,
        "kidney bean": 129, "chickpea": 129, "lentil": 229, "bean": 149,
        "tomato paste": 109, "passata": 199, "tomato sauce": 179,
        "soy sauce": 329, "tamari": 429, "worcestershire": 349, "hot sauce": 329,
        "sriracha": 379, "ketchup": 329, "mustard": 279, "mayonnaise": 449, "mayo": 449,
        "vinegar": 279, "balsamic": 499, "honey": 649, "maple syrup": 799,
        "peanut butter": 399, "tahini": 649, "miso": 549, "curry paste": 349,
        "stock": 279, "broth": 279, "bouillon": 329, "wine": 999, "beer": 899,
        "nut": 799, "almond": 799, "cashew": 899, "walnut": 849, "peanut": 449,
        "sesame seed": 349, "pine nut": 1099, "chia": 599, "sugar": 349, "brown sugar": 349,
        "chocolate": 449, "cocoa": 499, "vanilla": 699, "gelatin": 299, "cornflake": 429,

        // Spices
        "salt": 179, "black pepper": 349, "cumin": 299, "paprika": 299, "smoked paprika": 349,
        "turmeric": 299, "cinnamon": 329, "nutmeg": 449, "cardamom": 649, "clove": 399,
        "oregano": 279, "chili powder": 299, "chilli powder": 299, "curry powder": 329,
        "garam masala": 349, "cayenne": 279, "five spice": 349, "za'atar": 449,
        "saffron": 1299, "star anise": 449, "fennel seed": 279, "mustard seed": 249,
        "red pepper flake": 279, "seasoning": 299, "spice": 299,

        // Other
        "tofu": 279, "tempeh": 379, "seitan": 449, "hummus": 399, "olive": 349,
        "caper": 349, "pickle": 349, "kimchi": 549, "sauerkraut": 449, "seaweed": 399,
        "nori": 399, "water": 0, "ice": 0,
    ]

    /// Keys sorted longest-first, so the most specific match wins ("chicken breast" before
    /// "chicken"). Computed once — this runs for every item on every list render.
    private static let keysByLength: [String] = table.keys.sorted { $0.count > $1.count }

    /// Best estimate for an ingredient name, in cents. `category` is the shopping aisle when
    /// the item carries one; an unknown name falls back to that aisle's average.
    ///
    /// Returns nil only for things that genuinely cost nothing (water, ice), so the list can
    /// leave them unpriced rather than showing $0.00 as if it were a lookup failure.
    static func cents(for name: String, category: String = "") -> Int? {
        let needle = normalize(name)
        guard !needle.isEmpty else { return nil }
        if let key = keysByLength.first(where: { needle.contains($0) }) {
            let value = table[key] ?? 0
            return value > 0 ? value : nil
        }
        let aisle = category.isEmpty ? Aisle.guess(for: name) : category
        return byAisle[aisle] ?? byAisle["Other"]
    }

    /// The canonical token an ingredient name resolves to, for deciding whether two recipes
    /// want the *same* thing. "2 cloves garlic" and "garlic, minced" both land on "garlic",
    /// which is what lets the week planner count a shared ingredient once. Falls back to the
    /// normalised name so unlisted ingredients still match each other.
    static func matchKey(for name: String) -> String? {
        let needle = normalize(name)
        guard !needle.isEmpty else { return nil }
        return keysByLength.first(where: { needle.contains($0) }) ?? needle
    }

    /// A cheaper stand-in for an expensive ingredient, with the saving it implies.
    ///
    /// Only swaps that genuinely cook the same way are listed — this is a shopping
    /// suggestion, not a recipe rewrite, and suggesting something that ruins the dish to
    /// save a dollar would be worse than suggesting nothing.
    struct Swap {
        let from: String
        let to: String
        let fromCents: Int
        let toCents: Int
        var saving: Int { max(0, fromCents - toCents) }
    }

    private static let swaps: [String: String] = [
        "parmesan": "grana padano",
        "parmigiano": "grana padano",
        "heavy cream": "evaporated milk",
        "whipping cream": "evaporated milk",
        "pine nut": "sunflower seed",
        "saffron": "turmeric",
        "ribeye": "sirloin",
        "sirloin": "chuck steak",
        "steak": "chuck steak",
        "salmon": "trout",
        "shrimp": "frozen shrimp",
        "prawn": "frozen shrimp",
        "scallop": "frozen shrimp",
        "cod": "pollock",
        "maple syrup": "honey",
        "cashew": "peanut",
        "walnut": "peanut",
        "almond": "peanut",
        "mascarpone": "cream cheese",
        "gruyere": "cheddar",
        "goat cheese": "feta",
        "tuna steak": "tuna",
        "arborio": "rice",
        "basmati": "rice",
        "chicken breast": "chicken thigh",
        "ground beef": "ground turkey",
        "olive oil": "sunflower oil",
        "balsamic": "vinegar",
        "tahini": "peanut butter",
        "vanilla": "vanilla essence",
    ]

    /// Prices for the swap targets that aren't themselves table entries.
    private static let swapTargetPrices: [String: Int] = [
        "grana padano": 399,
        "evaporated milk": 189,
        "sunflower seed": 249,
        "chuck steak": 699,
        "trout": 999,
        "frozen shrimp": 799,
        "pollock": 649,
        "vanilla essence": 299,
    ]

    /// The best saving available on this ingredient, or nil when it is already cheap or has
    /// no sensible substitute.
    static func swap(for name: String) -> Swap? {
        guard let key = matchKey(for: name), let target = swaps[key] else { return nil }
        guard let fromCents = table[key] else { return nil }
        let toCents = swapTargetPrices[target] ?? table[target] ?? fromCents
        guard fromCents - toCents >= 75 else { return nil }   // not worth the user's attention
        return Swap(from: key, to: target, fromCents: fromCents, toCents: toCents)
    }

    /// Strips quantities, units and packaging words so "2 cups (400g) diced tomatoes, drained"
    /// matches on "tomato". Without this the table would need every phrasing a model emits.
    private static func normalize(_ raw: String) -> String {
        var s = raw.lowercased()
        // Anything after a comma is preparation ("finely chopped"), not identity.
        if let comma = s.firstIndex(of: ",") { s = String(s[s.startIndex..<comma]) }
        // Parenthetical conversions.
        s = s.replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
        // Leading quantities and fractions.
        s = s.replacingOccurrences(of: #"[0-9]+([./][0-9]+)?"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[¼½¾⅓⅔⅛]"#, with: " ", options: .regularExpression)
        for unit in Self.units {
            s = s.replacingOccurrences(
                of: "\\b\(unit)s?\\b", with: " ", options: [.regularExpression])
        }
        s = s.replacingOccurrences(of: #"[^a-z ]"#, with: " ", options: .regularExpression)
        return s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
    }

    /// Words stripped before matching. Deliberately excludes "ground", "whole" and "clove":
    /// those carry identity here ("ground beef", "whole milk", "ground cloves") and stripping
    /// them would make those keys unreachable.
    private static let units = [
        "g", "kg", "mg", "oz", "lb", "lbs", "ml", "l", "cup", "tbsp", "tsp", "tablespoon",
        "teaspoon", "pinch", "dash", "handful", "bunch", "sprig", "slice", "piece",
        "can", "tin", "jar", "packet", "pack", "package", "bag", "box", "stick", "head",
        "fillet", "large", "medium", "small", "fresh", "dried",
        "chopped", "diced", "minced", "sliced", "grated", "crushed", "ripe",
        "boneless", "skinless", "extra", "virgin", "of", "to", "taste", "optional",
    ]
}
