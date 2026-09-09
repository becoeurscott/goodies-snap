-- Recipe reviews: a star rating + optional text a signed-in user leaves on a recipe.
--
-- Keyed by the app's Recipe.id string (e.g. "cat_52772"), so catalog recipes reviewed by
-- different people all collect the same reviews. One review per person per recipe.
-- Reviews are user-generated content, so they carry the same block + report + auto-hide
-- protections as posts/comments.

CREATE TABLE public.recipe_reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recipe_key TEXT NOT NULL,                 -- the app's Recipe.id
  recipe_title TEXT NOT NULL DEFAULT '',    -- denormalized, for "your reviews" contexts
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  author_name TEXT NOT NULL DEFAULT '',     -- filled by trigger from the profile
  rating INT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  body TEXT NOT NULL DEFAULT '' CHECK (char_length(body) <= 1000),
  hidden_at TIMESTAMPTZ,                     -- set by moderation; drops it from feeds
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (recipe_key, user_id)               -- one review per person per recipe
);
CREATE INDEX recipe_reviews_recipe_idx ON public.recipe_reviews (recipe_key, created_at DESC);
CREATE INDEX recipe_reviews_user_idx ON public.recipe_reviews (user_id);

-- author_name is server-set from the profile (never trusted from the client), and
-- updated_at tracks edits. SECURITY DEFINER so it can read profiles under RLS.
CREATE OR REPLACE FUNCTION public.set_review_author()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  NEW.author_name := COALESCE(
    (SELECT display_name FROM public.profiles WHERE id = NEW.user_id), 'Cook');
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;

CREATE TRIGGER recipe_reviews_author_trigger
BEFORE INSERT OR UPDATE ON public.recipe_reviews
FOR EACH ROW EXECUTE FUNCTION public.set_review_author();

-- ============ Grants + RLS ============

GRANT SELECT ON public.recipe_reviews TO anon, authenticated;
GRANT INSERT (recipe_key, recipe_title, user_id, rating, body) ON public.recipe_reviews TO authenticated;
GRANT UPDATE (rating, body) ON public.recipe_reviews TO authenticated;
GRANT DELETE ON public.recipe_reviews TO authenticated;

ALTER TABLE public.recipe_reviews ENABLE ROW LEVEL SECURITY;

-- Visible to everyone (browsing reviews needs no account), minus blocked authors and
-- hidden reviews — but an author always sees their own, even when hidden.
CREATE POLICY "reviews readable" ON public.recipe_reviews
  FOR SELECT TO anon, authenticated
  USING (
    public.is_blocked_pair(user_id) = FALSE
    AND (hidden_at IS NULL OR user_id = (SELECT auth.uid()))
  );
CREATE POLICY "own review insert" ON public.recipe_reviews
  FOR INSERT TO authenticated WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY "own review update" ON public.recipe_reviews
  FOR UPDATE TO authenticated
  USING (user_id = (SELECT auth.uid())) WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY "own review delete" ON public.recipe_reviews
  FOR DELETE TO authenticated USING (user_id = (SELECT auth.uid()));
-- Admins can remove any review (mirrors the admin post/comment delete policies).
CREATE POLICY "admins delete any review" ON public.recipe_reviews
  FOR DELETE TO authenticated USING (public.is_admin());

-- ============ Reporting: extend content_reports to cover reviews ============

ALTER TABLE public.content_reports
  ADD COLUMN review_id UUID REFERENCES public.recipe_reviews(id) ON DELETE CASCADE;

ALTER TABLE public.content_reports DROP CONSTRAINT content_reports_target_type_check;
ALTER TABLE public.content_reports
  ADD CONSTRAINT content_reports_target_type_check
  CHECK (target_type IN ('post', 'comment', 'review'));

ALTER TABLE public.content_reports DROP CONSTRAINT one_target;
ALTER TABLE public.content_reports
  ADD CONSTRAINT one_target CHECK (
    (target_type = 'post'    AND post_id IS NOT NULL AND comment_id IS NULL AND review_id IS NULL) OR
    (target_type = 'comment' AND comment_id IS NOT NULL AND post_id IS NULL AND review_id IS NULL) OR
    (target_type = 'review'  AND review_id IS NOT NULL AND post_id IS NULL AND comment_id IS NULL)
  );

CREATE UNIQUE INDEX content_reports_review_once
  ON public.content_reports (reporter_id, review_id) WHERE target_type = 'review';

GRANT INSERT (review_id) ON public.content_reports TO authenticated;

-- Auto-hide reviews on repeated independent reports, matching posts/comments.
CREATE OR REPLACE FUNCTION public.hide_reported_content()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  reports INT;
  threshold CONSTANT INT := 3;
BEGIN
  IF NEW.target_type = 'post' THEN
    SELECT COUNT(DISTINCT reporter_id) INTO reports
      FROM public.content_reports WHERE post_id = NEW.post_id AND target_type = 'post';
    IF reports >= threshold THEN
      UPDATE public.posts SET hidden_at = NOW() WHERE id = NEW.post_id AND hidden_at IS NULL;
    END IF;
  ELSIF NEW.target_type = 'comment' THEN
    SELECT COUNT(DISTINCT reporter_id) INTO reports
      FROM public.content_reports WHERE comment_id = NEW.comment_id AND target_type = 'comment';
    IF reports >= threshold THEN
      UPDATE public.comments SET hidden_at = NOW() WHERE id = NEW.comment_id AND hidden_at IS NULL;
    END IF;
  ELSE
    SELECT COUNT(DISTINCT reporter_id) INTO reports
      FROM public.content_reports WHERE review_id = NEW.review_id AND target_type = 'review';
    IF reports >= threshold THEN
      UPDATE public.recipe_reviews SET hidden_at = NOW() WHERE id = NEW.review_id AND hidden_at IS NULL;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- Reject reporting your own review.
CREATE OR REPLACE FUNCTION public.reject_self_report()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  owner UUID;
BEGIN
  IF NEW.target_type = 'post' THEN
    SELECT author_id INTO owner FROM public.posts WHERE id = NEW.post_id;
  ELSIF NEW.target_type = 'comment' THEN
    SELECT author_id INTO owner FROM public.comments WHERE id = NEW.comment_id;
  ELSE
    SELECT user_id INTO owner FROM public.recipe_reviews WHERE id = NEW.review_id;
  END IF;
  IF owner = NEW.reporter_id THEN
    RAISE EXCEPTION 'cannot report your own content';
  END IF;
  RETURN NEW;
END;
$$;
