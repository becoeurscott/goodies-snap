-- TheMealDB ships no prep/cook times, so all 793 imported catalog recipes had
-- prep_minutes = cook_minutes = 0 — every Discover card read "0 min" and difficulty "Easy".
-- Estimate plausible times from recipe size (matches the client-side fallback in
-- RecipeExtractor): ~2 min prep per ingredient (5-25), ~4 min cook per step (10-60).
-- Guarded to rows that are still 0/0 so it never clobbers a real value.

UPDATE public.catalog_recipes
SET prep_minutes = LEAST(25, GREATEST(5, COALESCE(jsonb_array_length(ingredients), 0) * 2)),
    cook_minutes = LEAST(60, GREATEST(10, COALESCE(jsonb_array_length(steps), 0) * 4)),
    updated_at = NOW()
WHERE prep_minutes = 0 AND cook_minutes = 0;
