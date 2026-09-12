-- Undo the cuisine←category backfill (20260911160000). It's superseded by a faceted Discover
-- filter that keeps Country (from `cuisine`) and Food type (from `category`) as separate facets,
-- so cuisine should hold real countries again and stay empty for area-less recipes (those are
-- filterable by their Food type instead). Backfilled rows are exactly those where cuisine equals
-- category — no real country cuisine ever equals a food-type category, so this is precise.

UPDATE public.catalog_recipes
   SET cuisine = ''
 WHERE cuisine = category;
