-- functions/guest.ts marks a device's onboarding account with profiles.is_guest = true, and
-- its retire action deletes only rows still carrying that flag. The column was never created,
-- so the mark silently failed (PATCH of a non-existent column) and retire always answered
-- "not_a_guest" — guest accounts could never be cleaned up and accumulated indefinitely.
--
-- is_guest is server-maintained: only the guest edge function (service key) ever sets it.
-- End users must not be able to flip their own flag, so revoke column UPDATE from the
-- runtime roles. Default false means every existing and future real account is a non-guest.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS is_guest boolean NOT NULL DEFAULT false;

REVOKE UPDATE (is_guest) ON public.profiles FROM authenticated, anon;
