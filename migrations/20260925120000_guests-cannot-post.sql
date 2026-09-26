-- Guests (profiles.is_guest, set only by the guest edge function) haven't accepted the Terms,
-- the community rules or the 13+ check, so they may read the community but not publish to it.
-- The app already hides posting from guests; this makes the server refuse it too.

CREATE OR REPLACE FUNCTION public.is_guest_user(uid uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE((SELECT is_guest FROM public.profiles WHERE id = uid), false)
$$;
REVOKE ALL ON FUNCTION public.is_guest_user(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.is_guest_user(uuid) TO authenticated;

ALTER POLICY "own posts insert" ON public.posts
  WITH CHECK (author_id = (SELECT auth.uid()) AND NOT public.is_guest_user((SELECT auth.uid())));

ALTER POLICY "own comments insert" ON public.comments
  WITH CHECK (author_id = (SELECT auth.uid()) AND NOT public.is_guest_user((SELECT auth.uid())));
