-- Admin security hardening.
--
-- CRITICAL FIX: the original social-feed migration granted table-wide INSERT/UPDATE on
-- profiles to `authenticated`. Once `is_admin` was added to that table, the grant let ANY
-- signed-in user PATCH their own row to is_admin = true and self-promote to admin (and then
-- set their own plan to pro, defeating billing). RLS only restricts which ROW you may write,
-- not which COLUMNS. We re-scope the grant to the harmless columns and add a trigger as
-- defence in depth. The `admin` edge function still sets is_admin via the service key.

REVOKE INSERT, UPDATE ON public.profiles FROM authenticated;
-- The app inserts {id, display_name}; created_at/terms_accepted_at carry defaults.
GRANT INSERT (id, display_name, terms_accepted_at, created_at) ON public.profiles TO authenticated;
GRANT UPDATE (display_name, terms_accepted_at) ON public.profiles TO authenticated;

-- Defence in depth: even if a future grant widens the columns, a non-admin can never change
-- is_admin or reassign the row's id.
CREATE OR REPLACE FUNCTION public.guard_profile_privileged()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  IF (NEW.is_admin IS DISTINCT FROM OLD.is_admin OR NEW.id IS DISTINCT FROM OLD.id)
     AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'not allowed to change privileged profile fields';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS profiles_guard_privileged ON public.profiles;
CREATE TRIGGER profiles_guard_privileged
BEFORE UPDATE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.guard_profile_privileged();

-- Admin read access for the control-room panels that read these tables directly under RLS.
-- (Both are otherwise owner-only.)
DROP POLICY IF EXISTS "admins read all transactions" ON public.app_store_transactions;
CREATE POLICY "admins read all transactions" ON public.app_store_transactions
  FOR SELECT TO authenticated USING (public.is_admin());

DROP POLICY IF EXISTS "admins read all blocks" ON public.user_blocks;
CREATE POLICY "admins read all blocks" ON public.user_blocks
  FOR SELECT TO authenticated USING (public.is_admin());
