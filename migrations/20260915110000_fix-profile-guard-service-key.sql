-- Fix: the privileged-field guard on profiles also blocked the service key.
--
-- guard_profile_privileged() raised whenever is_admin/admin_role/id changed and the caller
-- was NOT public.is_admin(). But the `admin` edge function writes with the service key, whose
-- auth.uid() is NULL, so is_admin() is false — meaning legitimate set_role/set_admin writes
-- were rejected. Distinguish a real authenticated end-user (auth.uid() present) from the
-- service-key path (auth.uid() NULL): only block the former. anon has no UPDATE grant on
-- profiles, so the guard's job — stop a signed-in non-admin escalating themselves — is intact.

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
     AND (SELECT auth.uid()) IS NOT NULL       -- a real signed-in user, not the service key
     AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'not allowed to change privileged profile fields';
  END IF;
  RETURN NEW;
END;
$$;
