-- goodiesSnap social feed: profiles, posts (recipe payload), likes, comments.

-- ============ Tables ============

CREATE TABLE public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name TEXT NOT NULL CHECK (char_length(display_name) BETWEEN 1 AND 60),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE public.posts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  author_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  -- Denormalized so the feed renders without a join from the mobile client.
  author_name TEXT NOT NULL,
  caption TEXT NOT NULL DEFAULT '' CHECK (char_length(caption) <= 500),
  recipe JSONB NOT NULL,
  image_url TEXT,
  like_count INT NOT NULL DEFAULT 0,
  comment_count INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX posts_created_at_idx ON public.posts (created_at DESC);
CREATE INDEX posts_author_idx ON public.posts (author_id);

CREATE TABLE public.likes (
  post_id UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (post_id, user_id)
);
CREATE INDEX likes_user_idx ON public.likes (user_id);

CREATE TABLE public.comments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  author_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  author_name TEXT NOT NULL,
  body TEXT NOT NULL CHECK (char_length(body) BETWEEN 1 AND 500),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX comments_post_idx ON public.comments (post_id, created_at);

-- ============ Counter triggers ============
-- SECURITY DEFINER so a liker/commenter can bump the counter on a post they
-- don't own (posts UPDATE is otherwise owner-only and column-restricted).

CREATE OR REPLACE FUNCTION public.bump_like_count()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.posts SET like_count = like_count + 1 WHERE id = NEW.post_id;
    RETURN NEW;
  ELSE
    UPDATE public.posts SET like_count = GREATEST(like_count - 1, 0) WHERE id = OLD.post_id;
    RETURN OLD;
  END IF;
END;
$$;

CREATE TRIGGER likes_count_trigger
AFTER INSERT OR DELETE ON public.likes
FOR EACH ROW EXECUTE FUNCTION public.bump_like_count();

CREATE OR REPLACE FUNCTION public.bump_comment_count()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.posts SET comment_count = comment_count + 1 WHERE id = NEW.post_id;
    RETURN NEW;
  ELSE
    UPDATE public.posts SET comment_count = GREATEST(comment_count - 1, 0) WHERE id = OLD.post_id;
    RETURN OLD;
  END IF;
END;
$$;

CREATE TRIGGER comments_count_trigger
AFTER INSERT OR DELETE ON public.comments
FOR EACH ROW EXECUTE FUNCTION public.bump_comment_count();

-- ============ Author identity guards ============
-- author_id/author_name and counters must not drift from the authenticated user.

CREATE OR REPLACE FUNCTION public.stamp_post_author()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  NEW.author_name := COALESCE(
    (SELECT display_name FROM public.profiles WHERE id = NEW.author_id),
    'Cook'
  );
  NEW.like_count := 0;
  NEW.comment_count := 0;
  RETURN NEW;
END;
$$;

CREATE TRIGGER posts_stamp_author
BEFORE INSERT ON public.posts
FOR EACH ROW EXECUTE FUNCTION public.stamp_post_author();

CREATE OR REPLACE FUNCTION public.stamp_comment_author()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  NEW.author_name := COALESCE(
    (SELECT display_name FROM public.profiles WHERE id = NEW.author_id),
    'Cook'
  );
  RETURN NEW;
END;
$$;

CREATE TRIGGER comments_stamp_author
BEFORE INSERT ON public.comments
FOR EACH ROW EXECUTE FUNCTION public.stamp_comment_author();

-- ============ Privileges ============

GRANT USAGE ON SCHEMA public TO anon, authenticated;

-- Reads: signed-in users see everything (the feed is app-wide).
GRANT SELECT ON public.profiles, public.posts, public.likes, public.comments TO authenticated;

-- Writes: narrow the default broad grants to exactly what the app does.
REVOKE INSERT, UPDATE, DELETE ON public.profiles, public.posts, public.likes, public.comments
  FROM anon, authenticated;

GRANT INSERT, UPDATE ON public.profiles TO authenticated;
GRANT INSERT (author_id, caption, recipe, image_url), DELETE ON public.posts TO authenticated;
GRANT UPDATE (caption) ON public.posts TO authenticated;
GRANT INSERT (post_id, user_id), DELETE ON public.likes TO authenticated;
GRANT INSERT (post_id, author_id, body), DELETE ON public.comments TO authenticated;

-- ============ RLS ============

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.comments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "profiles readable" ON public.profiles
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "own profile insert" ON public.profiles
  FOR INSERT TO authenticated WITH CHECK (id = (SELECT auth.uid()));
CREATE POLICY "own profile update" ON public.profiles
  FOR UPDATE TO authenticated
  USING (id = (SELECT auth.uid())) WITH CHECK (id = (SELECT auth.uid()));

CREATE POLICY "posts readable" ON public.posts
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "own posts insert" ON public.posts
  FOR INSERT TO authenticated WITH CHECK (author_id = (SELECT auth.uid()));
CREATE POLICY "own posts update" ON public.posts
  FOR UPDATE TO authenticated
  USING (author_id = (SELECT auth.uid())) WITH CHECK (author_id = (SELECT auth.uid()));
CREATE POLICY "own posts delete" ON public.posts
  FOR DELETE TO authenticated USING (author_id = (SELECT auth.uid()));

CREATE POLICY "likes readable" ON public.likes
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "own likes insert" ON public.likes
  FOR INSERT TO authenticated WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY "own likes delete" ON public.likes
  FOR DELETE TO authenticated USING (user_id = (SELECT auth.uid()));

CREATE POLICY "comments readable" ON public.comments
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "own comments insert" ON public.comments
  FOR INSERT TO authenticated WITH CHECK (author_id = (SELECT auth.uid()));
CREATE POLICY "own comments delete" ON public.comments
  FOR DELETE TO authenticated USING (author_id = (SELECT auth.uid()));
