-- Per-user app state, so a signed-in user's recipes, saved items, meal plan, taste answers
-- and name follow them to any device (the promise on the auth screen).
--
-- The whole app state is stored as one JSONB blob keyed by user. The client owns the shape
-- (it's the app's `Persisted` snapshot); the server only guards ownership and timestamps it.
-- Last-write-wins per device, merged client-side on sign-in — good enough for a single-user
-- recipe keeper, and far simpler than modelling every recipe as its own row.

CREATE TABLE public.user_state (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  data JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Stamp updated_at on every write so a client can tell which copy is newer.
CREATE OR REPLACE FUNCTION public.touch_user_state()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;

CREATE TRIGGER user_state_touch_trigger
BEFORE INSERT OR UPDATE ON public.user_state
FOR EACH ROW EXECUTE FUNCTION public.touch_user_state();

-- ============ Grants + RLS ============

GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_state TO authenticated;

ALTER TABLE public.user_state ENABLE ROW LEVEL SECURITY;

-- A user can only ever see or touch their own row.
CREATE POLICY "own state select" ON public.user_state
  FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));
CREATE POLICY "own state insert" ON public.user_state
  FOR INSERT TO authenticated WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY "own state update" ON public.user_state
  FOR UPDATE TO authenticated
  USING (user_id = (SELECT auth.uid())) WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY "own state delete" ON public.user_state
  FOR DELETE TO authenticated USING (user_id = (SELECT auth.uid()));
