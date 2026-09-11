-- Daily spend ceiling for image search.
--
-- Google's Custom Search API bills $5/1000 queries with no cap of its own: a traffic spike,
-- a retry loop or an abusive client would just keep spending. This is the circuit breaker.
--
-- Counted in queries because that is the billed unit. Only real Google calls are counted —
-- cache hits are free and must not consume budget.

CREATE TABLE IF NOT EXISTS public.image_search_budget (
  day        DATE PRIMARY KEY,
  queries    INTEGER NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.image_search_budget ENABLE ROW LEVEL SECURITY;

-- Admins can watch the spend; nobody writes except through claim/release below.
DROP POLICY IF EXISTS image_search_budget_admin_read ON public.image_search_budget;
CREATE POLICY image_search_budget_admin_read ON public.image_search_budget
  FOR SELECT TO authenticated USING (public.is_admin());

-- ============ Claim ============
-- Atomically takes one query from today's allowance. Returns TRUE if the caller may go to
-- Google, FALSE once the ceiling is reached.
--
-- The INSERT ... ON CONFLICT DO UPDATE with the WHERE guard is what makes this safe under
-- concurrency: two edge-function instances racing on the same row cannot both pass the limit,
-- because the increment and the test happen in one statement.
CREATE OR REPLACE FUNCTION public.claim_image_search(p_limit INTEGER)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ok BOOLEAN;
BEGIN
  INSERT INTO public.image_search_budget (day, queries)
  VALUES (CURRENT_DATE, 1)
  ON CONFLICT (day) DO UPDATE
    SET queries = public.image_search_budget.queries + 1,
        updated_at = NOW()
    WHERE public.image_search_budget.queries < p_limit
  RETURNING TRUE INTO v_ok;

  RETURN COALESCE(v_ok, FALSE);
END;
$$;

-- ============ Release ============
-- Hands a claimed slot back when the call never actually reached Google (network error,
-- non-200). Without this a flapping upstream would burn the day's budget on nothing.
CREATE OR REPLACE FUNCTION public.release_image_search()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.image_search_budget
     SET queries = GREATEST(0, queries - 1), updated_at = NOW()
   WHERE day = CURRENT_DATE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_image_search(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.release_image_search() TO authenticated;
