-- Guest (anonymous) sessions.
--
-- Onboarding now extracts a real recipe BEFORE the user has an account, and every AI call
-- goes through the metered proxy, which needs a real user token (functions/ai.ts rejects an
-- anonymous caller with 401). So the app opens a throwaway account on first launch, keyed to
-- a device id it keeps in the Keychain, and upgrades to a real account at the end of the flow.
--
-- Marking those rows matters for two reasons: the admin dashboard's user counts would
-- otherwise be dominated by people who only ever opened the app once, and abandoned guests
-- need reaping.

ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_guest BOOLEAN NOT NULL DEFAULT FALSE;

-- When a guest converts we clear the flag; nothing else about the row changes, so the user
-- keeps their id and everything that references it.
CREATE INDEX IF NOT EXISTS profiles_is_guest_idx ON public.profiles (is_guest) WHERE is_guest;

-- is_guest is a privileged field for the same reason is_admin is: a signed-in user must not
-- be able to set it (a guest that marks itself real, or a real account that hides itself from
-- the dashboard by marking itself a guest). Only the service key — the `guest` edge function —
-- may write it.
CREATE OR REPLACE FUNCTION public.guard_profile_privileged()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  IF (NEW.is_admin IS DISTINCT FROM OLD.is_admin
      OR NEW.admin_role IS DISTINCT FROM OLD.admin_role
      OR NEW.is_guest IS DISTINCT FROM OLD.is_guest
      OR NEW.id IS DISTINCT FROM OLD.id)
     AND (SELECT auth.uid()) IS NOT NULL       -- a real signed-in user, not the service key
     AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'not allowed to change privileged profile fields';
  END IF;
  RETURN NEW;
END;
$$;
