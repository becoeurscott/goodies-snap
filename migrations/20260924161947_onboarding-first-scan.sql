-- One real photo scan before Pro.
--
-- Onboarding used to only *describe* the camera ("Part of Pro") because consume_ai_action
-- refused every scan from a non-Pro account. New users already get 5 free AI actions, so
-- the first scan now runs for real and is paid from those same actions. Only the first:
-- once an account has a 'scan' row in ai_usage, the camera is Pro again.
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
