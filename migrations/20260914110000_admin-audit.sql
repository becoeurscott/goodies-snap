-- Admin audit log: one row per privileged action taken through the `admin` edge function,
-- so there's an accountable, viewable trail (who did what to whom, when). Rows are written by
-- the function using the service key (which bypasses RLS); no client role may write them, and
-- only admins may read them.

CREATE TABLE public.admin_audit (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id UUID,                         -- the admin who acted (from their verified token)
  actor_name TEXT NOT NULL DEFAULT '',
  action TEXT NOT NULL,                  -- e.g. delete_user, hide_content, set_plan
  target_type TEXT NOT NULL DEFAULT '',  -- user | post | comment | review | catalog | group | report
  target_id TEXT,
  detail JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX admin_audit_created_idx ON public.admin_audit (created_at DESC);

ALTER TABLE public.admin_audit ENABLE ROW LEVEL SECURITY;

-- Admins can read the trail; nobody can write it except the service key (RLS-bypassing).
CREATE POLICY "admins read audit" ON public.admin_audit
  FOR SELECT TO authenticated USING (public.is_admin());
