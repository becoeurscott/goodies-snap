-- Admin role tiers.
--
-- Adds a refinement on top of the existing `profiles.is_admin` flag: a 5-tier role that the
-- `admin` edge function uses to gate individual actions. INVARIANT: every admin still has
-- is_admin = true, so the many RLS read policies that call public.is_admin() keep working —
-- admin_role only narrows what an admin may DO, never what the coarse read gate allows.
-- Legacy owners (is_admin = true, admin_role IS NULL) are treated as SUPER_ADMIN in code; we
-- deliberately do NOT backfill their rows (avoids a NULL-column write on live owner rows).

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS admin_role TEXT
  CHECK (admin_role IN ('READ_ONLY','SUPPORT','MODERATOR','ADMIN','SUPER_ADMIN'));

-- Extend the privileged-field guard so a non-admin can never set/raise their own role (the
-- column-scoped grant already omits admin_role; this is defence in depth, matching is_admin).
CREATE OR REPLACE FUNCTION public.guard_profile_privileged()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  IF (NEW.is_admin IS DISTINCT FROM OLD.is_admin
      OR NEW.admin_role IS DISTINCT FROM OLD.admin_role
      OR NEW.id IS DISTINCT FROM OLD.id)
     AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'not allowed to change privileged profile fields';
  END IF;
  RETURN NEW;
END;
$$;

-- Current caller's effective role (mirrors is_admin()): the explicit role, else SUPER_ADMIN for
-- a legacy owner, else NULL. SECURITY DEFINER so a policy can call it without recursing into
-- profiles' own RLS. Available for future tier-granular policies; is_admin() stays authoritative
-- for the existing read policies.
CREATE OR REPLACE FUNCTION public.admin_role()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT COALESCE(
    (SELECT p.admin_role FROM public.profiles p WHERE p.id = auth.uid()),
    (SELECT 'SUPER_ADMIN' FROM public.profiles p WHERE p.id = auth.uid() AND p.is_admin)
  );
$$;
