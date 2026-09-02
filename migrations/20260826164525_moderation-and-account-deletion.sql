-- Moderation (App Store guideline 1.2) and the data side of account deletion (5.1.1(v)).
--
-- Blocking and report-hiding are enforced in RLS rather than in the client, so a
-- tampered app cannot see content its user has blocked or that has been hidden.

-- ============ Tables ============

CREATE TABLE public.user_blocks (
  blocker_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  blocked_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (blocker_id, blocked_id),
  CONSTRAINT no_self_block CHECK (blocker_id <> blocked_id)
);
CREATE INDEX user_blocks_blocked_idx ON public.user_blocks (blocked_id);

CREATE TABLE public.content_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  target_type TEXT NOT NULL CHECK (target_type IN ('post', 'comment')),
  post_id UUID REFERENCES public.posts(id) ON DELETE CASCADE,
  comment_id UUID REFERENCES public.comments(id) ON DELETE CASCADE,
  reason TEXT NOT NULL CHECK (reason IN
    ('spam', 'harassment', 'hate', 'violence', 'sexual', 'misinformation', 'other')),
  note TEXT NOT NULL DEFAULT '' CHECK (char_length(note) <= 500),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- Exactly one target, matching target_type.
  CONSTRAINT one_target CHECK (
    (target_type = 'post'    AND post_id IS NOT NULL AND comment_id IS NULL) OR
    (target_type = 'comment' AND comment_id IS NOT NULL)
  )
);
-- One report per person per item: partial indexes because a plain UNIQUE would treat
-- the NULL side as distinct and let the same person report the same item repeatedly.
CREATE UNIQUE INDEX content_reports_post_once
  ON public.content_reports (reporter_id, post_id) WHERE target_type = 'post';
CREATE UNIQUE INDEX content_reports_comment_once
  ON public.content_reports (reporter_id, comment_id) WHERE target_type = 'comment';
CREATE INDEX content_reports_created_idx ON public.content_reports (created_at DESC);

-- Hidden content stays in the table (a moderator still needs to read it) but drops
-- out of every feed via the SELECT policies below.
ALTER TABLE public.posts    ADD COLUMN hidden_at TIMESTAMPTZ;
ALTER TABLE public.comments ADD COLUMN hidden_at TIMESTAMPTZ;

-- Recorded so we can show what a user agreed to, and when.
ALTER TABLE public.profiles ADD COLUMN terms_accepted_at TIMESTAMPTZ;

-- ============ Helpers ============

-- SECURITY DEFINER: called from the posts/comments SELECT policies, and reading
-- user_blocks directly from a policy would recurse through that table's own RLS.
--
-- Blocking hides the pair in BOTH directions: if it only hid the blocked user from
-- the blocker, the blocked user could still read and reply to the person avoiding them.
CREATE OR REPLACE FUNCTION public.is_blocked_pair(p_other UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_blocks b
    WHERE (b.blocker_id = auth.uid() AND b.blocked_id = p_other)
       OR (b.blocker_id = p_other     AND b.blocked_id = auth.uid())
  );
$$;

-- Auto-hide on repeated independent reports. This is the "act on reports" mechanism:
-- content is out of every feed within seconds, without waiting for a human, and the
-- report rows stay for review.
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
      UPDATE public.posts SET hidden_at = NOW()
        WHERE id = NEW.post_id AND hidden_at IS NULL;
    END IF;
  ELSE
    SELECT COUNT(DISTINCT reporter_id) INTO reports
      FROM public.content_reports WHERE comment_id = NEW.comment_id AND target_type = 'comment';
    IF reports >= threshold THEN
      UPDATE public.comments SET hidden_at = NOW()
        WHERE id = NEW.comment_id AND hidden_at IS NULL;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER content_reports_hide_trigger
AFTER INSERT ON public.content_reports
FOR EACH ROW EXECUTE FUNCTION public.hide_reported_content();

-- Reporting your own content to hide it would be a griefing vector in reverse; block it.
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
  ELSE
    SELECT author_id INTO owner FROM public.comments WHERE id = NEW.comment_id;
  END IF;
  IF owner = NEW.reporter_id THEN
    RAISE EXCEPTION 'cannot report your own content';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER content_reports_self_check
BEFORE INSERT ON public.content_reports
FOR EACH ROW EXECUTE FUNCTION public.reject_self_report();

-- ============ Visibility ============
-- Replaces the blanket "readable to everyone" policies.

DROP POLICY "posts readable" ON public.posts;
CREATE POLICY "posts readable" ON public.posts
  FOR SELECT TO authenticated
  USING (
    NOT public.is_blocked_pair(author_id)
    -- An author keeps seeing their own hidden post, so removal is visible to them
    -- rather than looking like data loss.
    AND (hidden_at IS NULL OR author_id = (SELECT auth.uid()))
  );

DROP POLICY "comments readable" ON public.comments;
CREATE POLICY "comments readable" ON public.comments
  FOR SELECT TO authenticated
  USING (
    NOT public.is_blocked_pair(author_id)
    AND (hidden_at IS NULL OR author_id = (SELECT auth.uid()))
  );

-- ============ Grants and RLS on the new tables ============

GRANT SELECT, DELETE ON public.user_blocks TO authenticated;
GRANT INSERT (blocker_id, blocked_id) ON public.user_blocks TO authenticated;

GRANT SELECT ON public.content_reports TO authenticated;
GRANT INSERT (reporter_id, target_type, post_id, comment_id, reason, note)
  ON public.content_reports TO authenticated;

ALTER TABLE public.user_blocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.content_reports ENABLE ROW LEVEL SECURITY;

-- Only ever your own blocks: nobody can enumerate who blocked them.
CREATE POLICY "own blocks readable" ON public.user_blocks
  FOR SELECT TO authenticated USING (blocker_id = (SELECT auth.uid()));
CREATE POLICY "own blocks insert" ON public.user_blocks
  FOR INSERT TO authenticated WITH CHECK (blocker_id = (SELECT auth.uid()));
CREATE POLICY "own blocks delete" ON public.user_blocks
  FOR DELETE TO authenticated USING (blocker_id = (SELECT auth.uid()));

-- Reports are write-and-forget: a reporter sees their own, nobody sees anyone else's.
CREATE POLICY "own reports readable" ON public.content_reports
  FOR SELECT TO authenticated USING (reporter_id = (SELECT auth.uid()));
CREATE POLICY "own reports insert" ON public.content_reports
  FOR INSERT TO authenticated WITH CHECK (reporter_id = (SELECT auth.uid()));
