-- Dish artwork cache.
--
-- Image search is billed per query ($5/1000 on Google's Custom Search API), so the same
-- lookup must never be paid for twice. Cooks scan the same dishes as each other, which makes
-- a shared, global cache far more effective than a per-user one: the first person to scan a
-- katsu curry pays for it and everybody after them gets it free.
--
-- Misses are cached too (image_url NULL). A dish Google has nothing licensable for will
-- otherwise be re-queried on every scan forever, which is the expensive failure mode.

CREATE TABLE IF NOT EXISTS public.dish_artwork (
  dish_key    TEXT PRIMARY KEY,           -- normalised dish name (lowercased, squashed)
  dish_name   TEXT NOT NULL,              -- what was actually searched, for debugging
  image_url   TEXT,                       -- NULL = looked up, nothing usable found
  source      TEXT NOT NULL DEFAULT 'google',
  hits        INTEGER NOT NULL DEFAULT 0, -- how much money this row has saved
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  checked_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.dish_artwork ENABLE ROW LEVEL SECURITY;

-- Nobody writes this table directly; the two functions below are the only way in, so a user
-- cannot poison the shared cache with an arbitrary image URL.
DROP POLICY IF EXISTS dish_artwork_read ON public.dish_artwork;
CREATE POLICY dish_artwork_read ON public.dish_artwork
  FOR SELECT TO authenticated USING (true);

-- ============ Lookup ============
-- Returns (found, image_url). `found` distinguishes "cached as no result" from "never looked
-- up", which the caller needs in order to decide whether to spend a query.
CREATE OR REPLACE FUNCTION public.get_dish_artwork(p_key TEXT)
RETURNS TABLE (found BOOLEAN, image_url TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.dish_artwork SET hits = hits + 1 WHERE dish_key = p_key;

  RETURN QUERY
  SELECT TRUE, a.image_url FROM public.dish_artwork a WHERE a.dish_key = p_key;

  IF NOT FOUND THEN
    RETURN QUERY SELECT FALSE, NULL::TEXT;
  END IF;
END;
$$;

-- ============ Store ============
-- Upserts a result. Re-running refreshes checked_at so a stale miss can be retried later by
-- a maintenance job without changing this call site.
CREATE OR REPLACE FUNCTION public.cache_dish_artwork(
  p_key TEXT, p_name TEXT, p_url TEXT, p_source TEXT DEFAULT 'google'
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.dish_artwork (dish_key, dish_name, image_url, source)
  VALUES (p_key, p_name, p_url, p_source)
  ON CONFLICT (dish_key) DO UPDATE
    SET image_url  = EXCLUDED.image_url,
        dish_name  = EXCLUDED.dish_name,
        source     = EXCLUDED.source,
        checked_at = NOW();
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_dish_artwork(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cache_dish_artwork(TEXT, TEXT, TEXT, TEXT) TO authenticated;
