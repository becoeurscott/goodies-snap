-- Community v2: general posts (text / photo / question / recipe), groups, membership.

-- ============ Posts: recipe becomes optional, add kind + group ============

ALTER TABLE public.posts ALTER COLUMN recipe DROP NOT NULL;
ALTER TABLE public.posts
  ADD COLUMN kind TEXT NOT NULL DEFAULT 'recipe'
    CHECK (kind IN ('recipe', 'photo', 'text', 'question')),
  ADD COLUMN group_id UUID;

-- A post must have something to show.
ALTER TABLE public.posts
  ADD CONSTRAINT posts_has_content CHECK (
    recipe IS NOT NULL OR image_url IS NOT NULL OR char_length(caption) > 0
  );

-- ============ Groups ============

CREATE TABLE public.groups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL CHECK (char_length(name) BETWEEN 1 AND 60),
  emoji TEXT NOT NULL DEFAULT '🍽️',
  description TEXT NOT NULL DEFAULT '',
  member_count INT NOT NULL DEFAULT 0,
  post_count INT NOT NULL DEFAULT 0,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE public.group_members (
  group_id UUID NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (group_id, user_id)
);
CREATE INDEX group_members_user_idx ON public.group_members (user_id);

ALTER TABLE public.posts
  ADD CONSTRAINT posts_group_fk FOREIGN KEY (group_id) REFERENCES public.groups(id) ON DELETE SET NULL;
CREATE INDEX posts_group_idx ON public.posts (group_id, created_at DESC);

-- ============ Counter triggers ============

CREATE OR REPLACE FUNCTION public.bump_member_count()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.groups SET member_count = member_count + 1 WHERE id = NEW.group_id;
    RETURN NEW;
  ELSE
    UPDATE public.groups SET member_count = GREATEST(member_count - 1, 0) WHERE id = OLD.group_id;
    RETURN OLD;
  END IF;
END;
$$;

CREATE TRIGGER group_members_count_trigger
AFTER INSERT OR DELETE ON public.group_members
FOR EACH ROW EXECUTE FUNCTION public.bump_member_count();

CREATE OR REPLACE FUNCTION public.bump_group_post_count()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'INSERT' AND NEW.group_id IS NOT NULL THEN
    UPDATE public.groups SET post_count = post_count + 1 WHERE id = NEW.group_id;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' AND OLD.group_id IS NOT NULL THEN
    UPDATE public.groups SET post_count = GREATEST(post_count - 1, 0) WHERE id = OLD.group_id;
    RETURN OLD;
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER posts_group_count_trigger
AFTER INSERT OR DELETE ON public.posts
FOR EACH ROW EXECUTE FUNCTION public.bump_group_post_count();

-- Posting into a group requires membership (checked server-side, not just in the app).
CREATE OR REPLACE FUNCTION public.require_group_membership()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  IF NEW.group_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.group_members
    WHERE group_id = NEW.group_id AND user_id = NEW.author_id
  ) THEN
    RAISE EXCEPTION 'join the group before posting in it';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER posts_require_membership
BEFORE INSERT ON public.posts
FOR EACH ROW EXECUTE FUNCTION public.require_group_membership();

-- ============ Privileges ============

GRANT SELECT ON public.groups, public.group_members TO authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.groups, public.group_members FROM anon, authenticated;
GRANT INSERT (slug, name, emoji, description, created_by) ON public.groups TO authenticated;
GRANT INSERT (group_id, user_id), DELETE ON public.group_members TO authenticated;

-- posts: allow the new columns on insert
GRANT INSERT (kind, group_id) ON public.posts TO authenticated;

-- ============ RLS ============

ALTER TABLE public.groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY;

CREATE POLICY "groups readable" ON public.groups
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "members create groups" ON public.groups
  FOR INSERT TO authenticated WITH CHECK (created_by = (SELECT auth.uid()));

CREATE POLICY "memberships readable" ON public.group_members
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "join self" ON public.group_members
  FOR INSERT TO authenticated WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY "leave self" ON public.group_members
  FOR DELETE TO authenticated USING (user_id = (SELECT auth.uid()));

-- ============ Starter groups ============

INSERT INTO public.groups (slug, name, emoji, description) VALUES
  ('weeknight-dinners', 'Weeknight Dinners', '🍳', 'Fast, low-fuss meals for busy evenings.'),
  ('baking-club', 'Baking Club', '🥐', 'Bread, pastry, cakes — share bakes and troubleshoot doughs.'),
  ('west-african-kitchen', 'West African Kitchen', '🍢', 'Suya, jollof, egusi and everything in between.'),
  ('meal-prep', 'Meal Prep Sunday', '🥡', 'Batch cooking, containers, and plans for the week.'),
  ('plant-based', 'Plant-Based Table', '🥬', 'Vegetarian and vegan cooking, swaps and ideas.'),
  ('ask-a-cook', 'Ask a Cook', '❓', 'Stuck on a step? Ask the community.');
