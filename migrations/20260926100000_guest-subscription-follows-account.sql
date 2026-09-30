-- A guest can subscribe (Apple rejects forced sign-up before purchase). When that person
-- signs up, the app re-sends the receipt and the subscription moves from the guest account
-- to the real one instead of being refused as already_bound.

CREATE OR REPLACE FUNCTION public.apply_app_store_purchase(
  p_user UUID,
  p_original_transaction_id TEXT,
  p_product_id TEXT,
  p_plan TEXT,
  p_environment TEXT,
  p_expires_at TIMESTAMPTZ,
  p_revoked BOOLEAN
)
RETURNS TABLE (granted_plan TEXT, reason TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  existing_user UUID;
  effective TEXT;
  previous TEXT;
BEGIN
  SELECT user_id INTO existing_user
    FROM public.app_store_transactions
   WHERE original_transaction_id = p_original_transaction_id;

  -- Bought while a guest, now signing in with a real account: the subscription follows the
  -- person. Only a guest (or an owner already deleted) gives it up, never a real account.
  IF existing_user IS NOT NULL AND existing_user <> p_user
     AND (EXISTS (SELECT 1 FROM public.profiles WHERE id = existing_user AND is_guest)
          -- Real accounts don't always have a profile row, so a missing profile is NOT a
          -- guest; only an owner deleted from auth altogether counts as gone.
          OR NOT EXISTS (SELECT 1 FROM auth.users WHERE id = existing_user)) THEN
    UPDATE public.app_store_transactions
       SET user_id = p_user, updated_at = NOW()
     WHERE original_transaction_id = p_original_transaction_id;
    UPDATE public.entitlements SET plan = 'free' WHERE user_id = existing_user;
    existing_user := p_user;
  END IF;

  IF existing_user IS NOT NULL AND existing_user <> p_user THEN
    -- Someone is trying to reuse a subscription that already belongs to another account.
    RETURN QUERY SELECT 'free'::TEXT, 'already_bound'::TEXT;
    RETURN;
  END IF;

  -- Lapsed or refunded subscriptions fall back to free.
  effective := CASE
    WHEN p_revoked THEN 'free'
    WHEN p_expires_at IS NOT NULL AND p_expires_at <= NOW() THEN 'free'
    ELSE p_plan
  END;

  INSERT INTO public.app_store_transactions AS t (
    original_transaction_id, user_id, product_id, plan, environment, expires_at, revoked_at)
  VALUES (
    p_original_transaction_id, p_user, p_product_id, p_plan, p_environment, p_expires_at,
    CASE WHEN p_revoked THEN NOW() ELSE NULL END)
  ON CONFLICT (original_transaction_id) DO UPDATE
    SET product_id = EXCLUDED.product_id,
        plan       = EXCLUDED.plan,
        expires_at = EXCLUDED.expires_at,
        revoked_at = EXCLUDED.revoked_at,
        updated_at = NOW();

  INSERT INTO public.entitlements (user_id) VALUES (p_user) ON CONFLICT (user_id) DO NOTHING;

  SELECT plan INTO previous FROM public.entitlements WHERE user_id = p_user FOR UPDATE;

  UPDATE public.entitlements
     SET plan = effective,
         period = to_char(NOW(), 'YYYY-MM'),
         -- A genuine upgrade starts a fresh allowance; re-confirming the same plan
         -- (every launch, every renewal) must NOT reset the counter, or the quota
         -- could be cleared at will by re-submitting the receipt.
         used = CASE WHEN effective <> previous AND effective <> 'free' THEN 0 ELSE used END,
         trial_until = CASE WHEN effective <> 'free' THEN NULL ELSE trial_until END
   WHERE user_id = p_user;

  RETURN QUERY SELECT effective, 'ok'::TEXT;
END;
$$;
