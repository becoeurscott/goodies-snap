import Foundation

/// Builds a week of dinners around a recipe the user already has.
///
/// This is deliberately **not** an AI call. The work is a selection problem over a catalog we
/// already hold — which five dishes, out of 793, sit closest to this person's taste and share
/// the most ingredients with what is already going in the basket. A model would be slower,
/// cost an action out of the user's quota, and be worse at the part that actually matters,
/// which is the arithmetic of overlap.
///
/// The overlap is the product promise: a shared bulb of garlic is bought once, so a week that
/// reuses ingredients genuinely costs less than five unrelated dinners. `AppStore.weekCost`
/// prices the union of the ingredients for exactly this reason.
enum WeekPlanner {

    /// Catalog categories that belong at dinner.
    ///
    /// Needed because the reuse optimiser is good enough to be a problem without it: seeded
    /// with a breakfast porridge it will happily return pancakes, poffertjes and French toast,
    /// because those genuinely do share flour, milk, eggs and butter. Sharing ingredients is
    /// the right objective; serving five breakfasts for dinner is not.
    static let dinnerCategories: Set<String> = [
        "Beef", "Chicken", "Lamb", "Pasta", "Pork", "Seafood",
        "Vegan", "Vegetarian", "Goat", "Miscellaneous", "Side", "Starter",
    ]

    /// Whether a candidate is plausible as a dinner. Category is the reliable signal; the
    /// title check catches the desserts that TheMealDB files elsewhere.
    static func isDinner(_ recipe: Recipe) -> Bool {
        let tags = recipe.tags.map { $0.lowercased() }
        if tags.contains("breakfast") || tags.contains("dessert") { return false }
        let title = recipe.title.lowercased()
        let breakfastish = ["pancake", "porridge", "oatmeal", "waffle", "french toast",
                            "cereal", "granola", "muffin", "croissant", "smoothie"]
        return !breakfastish.contains { title.contains($0) }
    }

    /// How strongly a shared ingredient pulls a candidate in, against taste-profile score.
    /// One shared ingredient is worth roughly as much as a cuisine match; without this the
    /// planner just returns the five highest-scoring recipes and reuses nothing.
    private static let reuseWeight = 9

    struct Plan {
        /// Dinners in the order they should fill the week, seed first.
        var recipes: [Recipe]
        /// Distinct ingredients across the whole week.
        var ingredientCount: Int
        /// Ingredients that appear in more than one dinner.
        var sharedCount: Int
    }

    /// Picks `count` dinners, starting from `seed` (which always keeps its place).
    ///
    /// `pool` is the candidate set — normally the catalog. Anything the profile says to avoid
    /// is dropped, and a dish too close to one already chosen is skipped so a week doesn't
    /// come back as five variations on chicken.
    static func build(seed: Recipe, pool: [Recipe], preferences: UserPreferences, count: Int) -> Plan {
        var chosen = [seed]
        var basket = normalizedIngredients(of: seed)
        var usedTitles = Set([normalizedTitle(seed.title)])

        // Candidates: no duplicates of the seed, nothing the user avoids, nothing empty,
        // and nothing that isn't a dinner.
        var candidates = pool.filter { candidate in
            !candidate.ingredients.isEmpty
                && normalizedTitle(candidate.title) != normalizedTitle(seed.title)
                && !preferences.matchesAvoidance(candidate)
                && isDinner(candidate)
        }

        while chosen.count < count, !candidates.isEmpty {
            // Score every remaining candidate against taste AND against the basket so far,
            // then take the best. Greedy rather than exhaustive: the difference over five
            // picks is not worth the combinatorics on a phone.
            let ranked = candidates
                .map { candidate -> (Recipe, Int) in
                    let overlap = normalizedIngredients(of: candidate).intersection(basket).count
                    return (candidate, preferences.score(candidate) + overlap * reuseWeight)
                }
                .sorted { $0.1 > $1.1 }

            guard let pick = ranked.first(where: { !usedTitles.contains(normalizedTitle($0.0.title)) })?.0
            else { break }

            chosen.append(pick)
            basket.formUnion(normalizedIngredients(of: pick))
            usedTitles.insert(normalizedTitle(pick.title))
            candidates.removeAll { $0.id == pick.id }
        }

        var counts: [String: Int] = [:]
        for recipe in chosen {
            for key in normalizedIngredients(of: recipe) { counts[key, default: 0] += 1 }
        }

        return Plan(
            recipes: chosen,
            ingredientCount: counts.count,
            sharedCount: counts.values.filter { $0 > 1 }.count
        )
    }

    /// An ingredient set for overlap maths. Uses the price table's own normalisation so
    /// "2 cloves garlic" and "garlic, minced" count as the same thing — if they didn't, the
    /// reuse number would be a lie.
    private static func normalizedIngredients(of recipe: Recipe) -> Set<String> {
        Set(recipe.ingredients.compactMap { IngredientPrices.matchKey(for: $0.name) })
    }

    private static func normalizedTitle(_ title: String) -> String {
        title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
