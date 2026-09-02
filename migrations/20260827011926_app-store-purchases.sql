-- App Store subscriptions: the record of which Apple transaction granted which plan.
--
-- Without this table, one paid subscription could be replayed against any number of
-- accounts: the App Store signs a transaction for an Apple Account, not for a goodiesSnap
-- user, so we have to bind the two ourselves and refuse a second binding.

CREATE TABLE public.app_store_transactions (
  -- Apple's stable id for the whole subscription lifetime, across renewals.
  original_transaction_id TEXT PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  product_id TEXT NOT NULL,
  plan TEXT NOT NULL CHECK (plan IN ('free', 'plus', 'pro')),
  environment TEXT NOT NULL CHECK (environment IN ('Sandbox', 'Production')),
  expires_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX app_store_transactions_user_idx ON public.app_store_transactions (user_id);

-- Readable by its owner so the app can show "subscribed via the App Store"; never
-- writable from the client. Only the purchase function (admin key) writes here.
GRANT SELECT ON public.app_store_transactions TO authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.app_store_transactions FROM authenticated, anon;

ALTER TABLE public.app_store_transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "own transactions readable" ON public.app_store_transactions
  FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));

-- Applies a verified purchase. SECURITY DEFINER because entitlements is deliberately
-- read-only to users — this is the only way a plan is ever raised.
--
-- Returns the plan actually granted, which the caller returns to the app. A transaction
-- already bound to a different user grants nothing.
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

REVOKE ALL ON FUNCTION public.apply_app_store_purchase(UUID, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, BOOLEAN) FROM PUBLIC, anon, authenticated;
