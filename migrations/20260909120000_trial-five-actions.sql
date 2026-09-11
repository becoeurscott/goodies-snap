-- Lower the Pro trial's action cap from 25 to 5.
--
-- `trial_allowance()` is the server-side source of truth for how many AI actions a Pro
-- trial may spend before it ends; the app mirrors it in `Promo.trialActions`. Redefining
-- the function here changes the cap for all new spends immediately (consume_ai_action
-- reads it live), without touching anyone's already-recorded usage.
CREATE OR REPLACE FUNCTION public.trial_allowance()
RETURNS INT LANGUAGE sql IMMUTABLE AS $$ SELECT 5 $$;
