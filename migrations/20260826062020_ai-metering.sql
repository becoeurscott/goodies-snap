-- Server-side AI entitlement + metering.
--
-- Until now the quota lived on the device, which made it a product control, not a
-- security control. This moves the counter behind the database: the edge function is
-- the only thing that can spend an action, and it does so through a SECURITY DEFINER
-- function that derives the user from the caller's JWT.

-- ============ Entitlements ============

CREATE TABLE public.entitlements (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  plan TEXT NOT NULL DEFAULT 'free' CHECK (plan IN ('free', 'plus', 'pro')),
  -- Calendar month the `used` counter belongs to, e.g. '2026-08'.
  period TEXT NOT NULL DEFAULT to_char(NOW(), 'YYYY-MM'),
  used INT NOT NULL DEFAULT 0 CHECK (used >= 0),
  -- Purchased top-ups and promo bonuses; these do NOT reset monthly.
  top_up INT NOT NULL DEFAULT 0 CHECK (top_up >= 0),
  -- Pro trial: grants camera + a capped number of actions until this instant.
  trial_until TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Append-only record of what was actually spent, for cost analysis and support.
CREATE TABLE public.ai_usage (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  action TEXT NOT NULL,
  model TEXT,
  -- Cost in millionths of a dollar, so the cheapest call is still an integer.
  cost_micros INT NOT NULL DEFAULT 0,
  refunded BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX ai_usage_user_idx ON public.ai_usage (user_id, created_at DESC);

-- ============ Allowance rules (mirror of Entitlement.Plan in the app) ============

CREATE OR REPLACE FUNCTION public.plan_allowance(p_plan TEXT)
RETURNS INT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE p_plan WHEN 'pro' THEN 400 WHEN 'plus' THEN 100 ELSE 5 END;
$$;

-- Actions a Pro trial may spend before the days run out. The action cap, not the day
-- count, is what bounds acquisition cost.
CREATE OR REPLACE FUNCTION public.trial_allowance()
RETURNS INT LANGUAGE sql IMMUTABLE AS $$ SELECT 25 $$;

-- ============ Spend one action (the only way to spend) ============

CREATE OR REPLACE FUNCTION public.consume_ai_action(p_action TEXT, p_needs_camera BOOLEAN DEFAULT FALSE)
RETURNS TABLE (allowed BOOLEAN, reason TEXT, remaining INT, plan TEXT, usage_id UUID)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  uid UUID := auth.uid();
  ent public.entitlements%ROWTYPE;
  now_period TEXT := to_char(NOW(), 'YYYY-MM');
  on_trial BOOLEAN;
  effective_plan TEXT;
  allowance INT;
  left_now INT;
  new_usage UUID;
BEGIN
  IF uid IS NULL THEN
    RETURN QUERY SELECT FALSE, 'unauthenticated', 0, 'free', NULL::UUID;
    RETURN;
  END IF;

  -- First call for a user creates their row.
  INSERT INTO public.entitlements (user_id) VALUES (uid)
  ON CONFLICT (user_id) DO NOTHING;

  SELECT * INTO ent FROM public.entitlements WHERE user_id = uid FOR UPDATE;

  -- Monthly rollover: every plan's allowance refreshes, Free included.
  IF ent.period <> now_period THEN
    UPDATE public.entitlements
       SET period = now_period, used = 0, updated_at = NOW()
     WHERE user_id = uid
    RETURNING * INTO ent;
  END IF;

  on_trial := ent.trial_until IS NOT NULL AND ent.trial_until > NOW();
  effective_plan := CASE WHEN on_trial AND ent.plan = 'free' THEN 'pro' ELSE ent.plan END;

  IF p_needs_camera AND effective_plan <> 'pro' THEN
    RETURN QUERY SELECT FALSE, 'camera_is_pro', 0, ent.plan, NULL::UUID;
    RETURN;
  END IF;

  allowance := CASE
    WHEN on_trial AND ent.plan = 'free' THEN public.trial_allowance()
    ELSE public.plan_allowance(ent.plan)
  END;
  left_now := (allowance + ent.top_up) - ent.used;

  IF left_now <= 0 THEN
    RETURN QUERY SELECT FALSE, 'quota_exhausted', 0, ent.plan, NULL::UUID;
    RETURN;
  END IF;

  -- Spend from the monthly allowance first, then from purchased top-ups.
  UPDATE public.entitlements
     SET used = used + 1,
         top_up = CASE WHEN ent.used + 1 > allowance THEN GREATEST(top_up - 1, 0) ELSE top_up END,
         updated_at = NOW()
   WHERE user_id = uid;

  INSERT INTO public.ai_usage (user_id, action) VALUES (uid, p_action)
  RETURNING id INTO new_usage;

  RETURN QUERY SELECT TRUE, 'ok', left_now - 1, ent.plan, new_usage;
END;
$$;

-- Give an action back when the model call fails on our side, so a user never pays for
-- our error. Only the row's owner can refund, and only once.
CREATE OR REPLACE FUNCTION public.refund_ai_action(p_usage_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  uid UUID := auth.uid();
  rows_touched INT;
BEGIN
  IF uid IS NULL THEN RETURN FALSE; END IF;

  UPDATE public.ai_usage
     SET refunded = TRUE
   WHERE id = p_usage_id AND user_id = uid AND refunded = FALSE;
  GET DIAGNOSTICS rows_touched = ROW_COUNT;
  IF rows_touched = 0 THEN RETURN FALSE; END IF;

  UPDATE public.entitlements
     SET used = GREATEST(used - 1, 0), updated_at = NOW()
   WHERE user_id = uid;
  RETURN TRUE;
END;
$$;

-- Record what the call actually cost, once it's known.
CREATE OR REPLACE FUNCTION public.record_ai_cost(p_usage_id UUID, p_model TEXT, p_cost_micros INT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  UPDATE public.ai_usage
     SET model = p_model, cost_micros = GREATEST(p_cost_micros, 0)
   WHERE id = p_usage_id AND user_id = auth.uid();
END;
$$;

-- ============ Privileges + RLS ============

GRANT SELECT ON public.entitlements, public.ai_usage TO authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.entitlements, public.ai_usage FROM anon, authenticated;

GRANT EXECUTE ON FUNCTION public.consume_ai_action(TEXT, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.refund_ai_action(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_ai_cost(UUID, TEXT, INT) TO authenticated;

ALTER TABLE public.entitlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_usage ENABLE ROW LEVEL SECURITY;

CREATE POLICY "own entitlement readable" ON public.entitlements
  FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));
CREATE POLICY "own usage readable" ON public.ai_usage
  FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));
