-- Community chat: when an author deletes the newest message in a channel, keep an empty
-- "This message was deleted" placeholder so everyone can see the latest message went away.
-- Older messages are still removed outright. Reels are never kept as placeholders.

ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

-- A placeholder has no content by design.
ALTER TABLE public.posts DROP CONSTRAINT IF EXISTS posts_has_content;
ALTER TABLE public.posts
  ADD CONSTRAINT posts_has_content CHECK (
    deleted_at IS NOT NULL
    OR recipe IS NOT NULL
    OR image_url IS NOT NULL
    OR video_url IS NOT NULL
    OR youtube_id IS NOT NULL
    OR char_length(caption) > 0
  );

-- Returns 'placeholder' when the post was wiped and kept, 'deleted' when it was removed.
CREATE OR REPLACE FUNCTION public.delete_my_post(p_post_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  p public.posts%ROWTYPE;
  is_newest BOOLEAN;
BEGIN
  SELECT * INTO p FROM public.posts WHERE id = p_post_id FOR UPDATE;
  IF NOT FOUND OR p.author_id IS DISTINCT FROM (SELECT auth.uid()) THEN
    RAISE EXCEPTION 'Post not found' USING ERRCODE = '42501';
  END IF;

  -- Channel = same group_id (NULL is the General channel).
  is_newest := p.deleted_at IS NULL
    AND p.kind <> 'reel'
    AND NOT EXISTS (
      SELECT 1 FROM public.posts q
      WHERE q.group_id IS NOT DISTINCT FROM p.group_id
        AND q.id <> p.id
        AND q.kind <> 'reel'
        AND q.hidden_at IS NULL
        AND q.deleted_at IS NULL
        AND q.created_at > p.created_at
    );

  IF NOT is_newest THEN
    DELETE FROM public.posts WHERE id = p.id;
    RETURN 'deleted';
  END IF;

  DELETE FROM public.likes WHERE post_id = p.id;
  DELETE FROM public.comments WHERE post_id = p.id;
  UPDATE public.posts
     SET deleted_at = NOW(),
         caption = '',
         recipe = NULL,
         image_url = NULL,
         video_url = NULL,
         youtube_id = NULL,
         thumb_url = NULL,
         duration_seconds = NULL,
         like_count = 0,
         comment_count = 0
   WHERE id = p.id;
  RETURN 'placeholder';
END;
$$;

REVOKE ALL ON FUNCTION public.delete_my_post(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_my_post(UUID) TO authenticated;
