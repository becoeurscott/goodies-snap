-- Platform controls: app configuration, maintenance switch, and in-app broadcasts.
--
-- All three are written only by the `admin` edge function (service key). NULL-safety is
-- critical: every visibility/enabled boolean is NOT NULL DEFAULT false and public policies
-- use `= true`, never `IS NOT false`, so private config never leaks to anon.

-- ---- app_config: a set of named JSON documents the apps may read (only the public ones) ----
CREATE TABLE public.app_config (
  key TEXT PRIMARY KEY,
  value JSONB NOT NULL DEFAULT '{}'::jsonb,
  is_public BOOLEAN NOT NULL DEFAULT false,   -- only public rows are exposed to the app
  version INT NOT NULL DEFAULT 1,
  updated_by UUID,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;
CREATE POLICY "admins read all config" ON public.app_config
  FOR SELECT TO authenticated USING (public.is_admin());
-- Public/anon (and authed apps) may read ONLY rows explicitly marked public.
CREATE POLICY "public config readable" ON public.app_config
  FOR SELECT TO anon, authenticated USING (is_public = true);

-- Append-only history for rollback.
CREATE TABLE public.app_config_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  config_key TEXT NOT NULL,
  value JSONB NOT NULL,
  version INT NOT NULL,
  created_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX app_config_history_key_idx ON public.app_config_history (config_key, version DESC);
ALTER TABLE public.app_config_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY "admins read config history" ON public.app_config_history
  FOR SELECT TO authenticated USING (public.is_admin());

-- ---- maintenance_state: a single row the apps poll ----
CREATE TABLE public.maintenance_state (
  id BOOLEAN PRIMARY KEY DEFAULT true CHECK (id),   -- enforces a single row
  enabled BOOLEAN NOT NULL DEFAULT false,
  message TEXT NOT NULL DEFAULT '',
  min_build INT NOT NULL DEFAULT 0,
  updated_by UUID,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
INSERT INTO public.maintenance_state (id) VALUES (true) ON CONFLICT DO NOTHING;
ALTER TABLE public.maintenance_state ENABLE ROW LEVEL SECURITY;
-- Apps must be able to read maintenance status without auth.
CREATE POLICY "maintenance readable" ON public.maintenance_state
  FOR SELECT TO anon, authenticated USING (true);

-- ---- broadcasts: in-app announcements (no push infra) read by signed-in users ----
CREATE TABLE public.broadcasts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  body TEXT NOT NULL DEFAULT '',
  kind TEXT NOT NULL DEFAULT 'announcement',
  audience JSONB NOT NULL DEFAULT '{}'::jsonb,   -- optional plan/role filters, applied client-side
  created_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX broadcasts_created_idx ON public.broadcasts (created_at DESC);
ALTER TABLE public.broadcasts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "broadcasts readable" ON public.broadcasts
  FOR SELECT TO authenticated USING (true);
