-- Cached YouTube view counts for recipe reels.
--
-- The YouTube Data API is free but quota'd (10,000 units/day; a batched videos.list of up to
-- 50 ids costs 1 unit). Caching keeps a busy feed from re-asking for the same clips all day,
-- and lets the feed render instantly from Postgres while a refresh runs behind it.
--
-- Unlike dish artwork, view counts *change*, so rows carry `checked_at` and the reader takes a
-- max age rather than treating any hit as final.

CREATE TABLE IF NOT EXISTS public.youtube_stats (
  video_id   TEXT PRIMARY KEY,
  view_count BIGINT NOT NULL DEFAULT 0,
  checked_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.youtube_stats ENABLE ROW LEVEL SECURITY;

-- Anyone signed in may read; writes go through the SECURITY DEFINER function below so the
-- shared cache can't be filled with made-up numbers.
DROP POLICY IF EXISTS youtube_stats_read ON public.youtube_stats;
CREATE POLICY youtube_stats_read ON public.youtube_stats
  FOR SELECT TO authenticated USING (true);

-- ============ Read ============
-- Returns only rows fresher than `p_max_age`; anything older is reported as absent so the
-- caller refetches it.
CREATE OR REPLACE FUNCTION public.get_youtube_stats(p_ids TEXT[], p_max_age INTERVAL DEFAULT '24 hours')
RETURNS TABLE (video_id TEXT, view_count BIGINT)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT s.video_id, s.view_count
    FROM public.youtube_stats s
   WHERE s.video_id = ANY(p_ids)
     AND s.checked_at > NOW() - p_max_age;
$$;

-- ============ Write ============
-- Batch upsert. The two arrays are positional: p_ids[i] carries p_views[i].
CREATE OR REPLACE FUNCTION public.cache_youtube_stats(p_ids TEXT[], p_views BIGINT[])
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_ids IS NULL OR array_length(p_ids, 1) IS NULL THEN RETURN; END IF;

  INSERT INTO public.youtube_stats (video_id, view_count, checked_at)
  SELECT unnest(p_ids), unnest(p_views), NOW()
  ON CONFLICT (video_id) DO UPDATE
    SET view_count = EXCLUDED.view_count,
        checked_at = NOW();
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_youtube_stats(TEXT[], INTERVAL) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cache_youtube_stats(TEXT[], BIGINT[]) TO authenticated;
