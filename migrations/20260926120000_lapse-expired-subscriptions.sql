-- Subscriptions end without the app telling us: once a subscription expires, iOS stops
-- listing it, so no receipt is re-sent. The plan is therefore lapsed on the server: an account
-- with App Store transactions but none still active goes back to free. A renewal the server
-- hasn't seen yet is self-healing — the next app launch re-sends the renewed receipt.
-- Accounts with no App Store transaction (admin-granted plans, trials) are left alone.
CREATE OR REPLACE FUNCTION public.lapse_expired_plan(p_user UUID)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  UPDATE public.entitlements e
     SET plan = 'free', updated_at = NOW()
   WHERE e.user_id = p_user
     AND e.plan <> 'free'
     AND EXISTS (SELECT 1 FROM public.app_store_transactions t WHERE t.user_id = p_user)
     AND NOT EXISTS (
       SELECT 1 FROM public.app_store_transactions t
        WHERE t.user_id = p_user
          AND t.revoked_at IS NULL
          -- A day's grace for Apple's renewal and billing-retry timing.
          AND (t.expires_at IS NULL OR t.expires_at > NOW() - INTERVAL '1 day'));
END;
$$;

CREATE OR REPLACE FUNCTION public.lapse_expired_plans()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE n integer := 0; r record;
BEGIN
  FOR r IN SELECT DISTINCT user_id FROM public.app_store_transactions LOOP
    PERFORM public.lapse_expired_plan(r.user_id);
  END LOOP;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$$;

REVOKE ALL ON FUNCTION public.lapse_expired_plan(UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.lapse_expired_plans() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.consume_ai_action(p_action text, p_needs_camera boolean DEFAULT false)
 RETURNS TABLE(allowed boolean, reason text, remaining integer, plan text, usage_id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
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

  INSERT INTO public.entitlements (user_id) VALUES (uid)
  ON CONFLICT (user_id) DO NOTHING;

  -- A subscription that ended (or was refunded) drops back to free before deciding.
  PERFORM public.lapse_expired_plan(uid);

  SELECT * INTO ent FROM public.entitlements WHERE user_id = uid FOR UPDATE;

  IF ent.period <> now_period THEN
    UPDATE public.entitlements
       SET period = now_period, used = 0, updated_at = NOW()
     WHERE user_id = uid
    RETURNING * INTO ent;
  END IF;

  on_trial := ent.trial_until IS NOT NULL AND ent.trial_until > NOW();
  effective_plan := CASE WHEN on_trial AND ent.plan = 'free' THEN 'pro' ELSE ent.plan END;

  -- Camera is Pro, except for an account's very first scan.
  IF p_needs_camera AND effective_plan <> 'pro'
     AND EXISTS (SELECT 1 FROM public.ai_usage u WHERE u.user_id = uid AND u.action = 'scan') THEN
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

  UPDATE public.entitlements
     SET used = used + 1,
         top_up = CASE WHEN ent.used + 1 > allowance THEN GREATEST(top_up - 1, 0) ELSE top_up END,
         updated_at = NOW()
   WHERE user_id = uid;

  INSERT INTO public.ai_usage (user_id, action) VALUES (uid, p_action)
  RETURNING id INTO new_usage;

  RETURN QUERY SELECT TRUE, 'ok', left_now - 1, ent.plan, new_usage;
END;
$function$;
