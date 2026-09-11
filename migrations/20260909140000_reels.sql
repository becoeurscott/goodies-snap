-- Community reels: the Community tab becomes a full-screen vertical video feed.
--
-- Reels reuse the existing `posts` table (and therefore its likes, comments, reports,
-- blocking and moderation with zero new plumbing). A reel is a post with kind='reel' that
-- carries a video: either an uploaded clip (video_url, in the reel-videos bucket) or a
-- YouTube-sourced clip (youtube_id). YouTube recipe reels are also synthesised on the client
-- from the catalog, so this table only needs to hold user-uploaded reels — but youtube_id is
-- here too so a curated YouTube reel can be persisted if we ever want server-side likes on it.

ALTER TABLE public.posts
  ADD COLUMN IF NOT EXISTS video_url TEXT,
  ADD COLUMN IF NOT EXISTS youtube_id TEXT,
  ADD COLUMN IF NOT EXISTS thumb_url TEXT,
  ADD COLUMN IF NOT EXISTS duration_seconds INT;

-- 'reel' joins the allowed kinds.
ALTER TABLE public.posts DROP CONSTRAINT IF EXISTS posts_kind_check;
ALTER TABLE public.posts
  ADD CONSTRAINT posts_kind_check
  CHECK (kind IN ('recipe', 'photo', 'text', 'question', 'reel'));

-- A reel counts as content even with no recipe/image/caption, as long as it has a video.
ALTER TABLE public.posts DROP CONSTRAINT IF EXISTS posts_has_content;
ALTER TABLE public.posts
  ADD CONSTRAINT posts_has_content CHECK (
    recipe IS NOT NULL
    OR image_url IS NOT NULL
    OR video_url IS NOT NULL
    OR youtube_id IS NOT NULL
    OR char_length(caption) > 0
  );

-- A reel must actually carry a video.
ALTER TABLE public.posts DROP CONSTRAINT IF EXISTS posts_reel_has_video;
ALTER TABLE public.posts
  ADD CONSTRAINT posts_reel_has_video CHECK (
    kind <> 'reel' OR video_url IS NOT NULL OR youtube_id IS NOT NULL
  );

-- Let authors set the video fields when they post a reel. author_name stays trigger-filled.
GRANT INSERT (video_url, youtube_id, thumb_url, duration_seconds) ON public.posts TO authenticated;

-- The reel feed is "newest visible reels first"; index exactly that access path.
CREATE INDEX IF NOT EXISTS posts_reel_idx
  ON public.posts (created_at DESC)
  WHERE kind = 'reel' AND hidden_at IS NULL;
