-- Make every catalog recipe's cuisine filterable.
--
-- ~190 imported recipes (TheMealDB entries with no `strArea`) have an empty `cuisine`. The app
-- already DISPLAYS their `category` in place of the cuisine (Recipe.recipe: cuisine.isEmpty ?
-- category), so a card reads "Dessert"/"Vegetarian"/… — but the Discover cuisine chips are built
-- from the raw `cuisine` column and skip the empty ones, and the filter matches `cuisine=eq.X`,
-- so those types never appear as chips and can't be filtered.
--
-- Backfilling the empty cuisine with the category makes the stored value match what's shown, so
-- the chip list, the filter, and the card label all line up with zero client changes.

UPDATE public.catalog_recipes
   SET cuisine = category
 WHERE (cuisine IS NULL OR cuisine = '')
   AND category IS NOT NULL
   AND category <> '';
