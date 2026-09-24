-- AI customer service.
--
-- Each app gets an assistant (support_apps) that answers from its own knowledge articles
-- (support_articles) and the customer's own account data, running on the self-hosted Ollama
-- behind https://ai.goodiessnap.com. Conversations hand over to a human agent in the admin
-- console when the assistant can't or shouldn't answer.
--
-- Customers can READ their own conversations and nothing else. Every write — a customer
-- message, an AI reply, an agent reply, a status change — goes through the `support` or
-- `admin` edge function with the service key, so the server decides who may say what and
-- the handoff rules can't be bypassed from a device.
--
-- app_id is on every row so the same tables serve every app; an assistant only ever sees
-- rows for its own app.

-- ============ Per-app assistant settings ============

CREATE TABLE public.support_apps (
  id TEXT PRIMARY KEY CHECK (id ~ '^[a-z0-9-]{2,32}$'),
  name TEXT NOT NULL,
  -- Who the assistant is, what the app does, tone and rules. Facts go in articles.
  instructions TEXT NOT NULL DEFAULT '',
  -- Shown to the customer when the conversation is handed to a person.
  handoff_message TEXT NOT NULL DEFAULT 'I''m passing this to our team — a person will reply here as soon as possible.',
  chat_model TEXT NOT NULL DEFAULT 'qwen2.5:3b',
  embed_model TEXT NOT NULL DEFAULT 'nomic-embed-text',
  enabled BOOLEAN NOT NULL DEFAULT TRUE,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============ Knowledge base ============

CREATE TABLE public.support_articles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  app_id TEXT NOT NULL REFERENCES public.support_apps(id) ON DELETE CASCADE,
  title TEXT NOT NULL CHECK (char_length(title) BETWEEN 1 AND 200),
  body TEXT NOT NULL CHECK (char_length(body) BETWEEN 1 AND 8000),
  active BOOLEAN NOT NULL DEFAULT TRUE,
  -- Vector from embed_model, as a JSON array. NULL until the support function computes it
  -- (it backfills lazily and whenever title/body change — see the trigger below). A few
  -- hundred articles per app are ranked in the function, so no vector extension is needed.
  embedding JSONB,
  embedding_model TEXT,
  updated_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX support_articles_app_idx ON public.support_articles (app_id) WHERE active;

-- An edited article must be re-embedded, or search would match the old text.
CREATE OR REPLACE FUNCTION public.support_articles_touch()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  NEW.updated_at := NOW();
  IF NEW.title IS DISTINCT FROM OLD.title OR NEW.body IS DISTINCT FROM OLD.body THEN
    NEW.embedding := NULL;
    NEW.embedding_model := NULL;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER support_articles_touch
  BEFORE UPDATE ON public.support_articles
  FOR EACH ROW EXECUTE FUNCTION public.support_articles_touch();

-- ============ Conversations ============

CREATE TABLE public.support_conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  app_id TEXT NOT NULL REFERENCES public.support_apps(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  -- ai:          the assistant is answering
  -- needs_human: handed over, waiting for an agent
  -- human:       an agent has replied; the assistant stays quiet
  -- closed:      resolved; a new customer message reopens it with the assistant
  status TEXT NOT NULL DEFAULT 'ai'
    CHECK (status IN ('ai', 'needs_human', 'human', 'closed')),
  -- Why it was handed over: customer_asked, sensitive_topic, low_confidence, ai_unavailable,
  -- rate_limited.
  handoff_reason TEXT,
  subject TEXT NOT NULL DEFAULT '' CHECK (char_length(subject) <= 120),
  assigned_to UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  last_message_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- The customer's "my conversation" lookup and the agent inbox.
CREATE INDEX support_conversations_user_idx
  ON public.support_conversations (user_id, app_id, last_message_at DESC);
CREATE INDEX support_conversations_inbox_idx
  ON public.support_conversations (app_id, status, last_message_at DESC);

CREATE TABLE public.support_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES public.support_conversations(id) ON DELETE CASCADE,
  -- user: the customer · ai: the assistant · agent: a person on the team · system: status notes
  sender TEXT NOT NULL CHECK (sender IN ('user', 'ai', 'agent', 'system')),
  -- The agent who wrote it (sender = 'agent'); NULL otherwise.
  author_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  -- Shown to the customer for agent replies, so they see a name, not an id.
  author_name TEXT,
  body TEXT NOT NULL CHECK (char_length(body) BETWEEN 1 AND 4000),
  -- For AI replies: which model answered, how long it took, and whether the backup model
  -- was used because the VPS was down or too slow.
  model TEXT,
  latency_ms INT,
  fallback BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX support_messages_conversation_idx
  ON public.support_messages (conversation_id, created_at);

-- ============ Access ============
-- Read-only from the client. Writes happen only through the edge functions (service key).

REVOKE ALL ON public.support_apps, public.support_articles,
              public.support_conversations, public.support_messages FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.support_apps, public.support_articles,
              public.support_conversations, public.support_messages FROM authenticated;
GRANT SELECT ON public.support_apps, public.support_articles,
              public.support_conversations, public.support_messages TO authenticated;

ALTER TABLE public.support_apps ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_articles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_messages ENABLE ROW LEVEL SECURITY;

-- The assistant's instructions and knowledge base are staff-only.
CREATE POLICY "admins read support apps" ON public.support_apps
  FOR SELECT TO authenticated USING (public.is_admin());
CREATE POLICY "admins read support articles" ON public.support_articles
  FOR SELECT TO authenticated USING (public.is_admin());

-- Customers see their own conversations; staff see all of them.
CREATE POLICY "own support conversations readable" ON public.support_conversations
  FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));
CREATE POLICY "admins read support conversations" ON public.support_conversations
  FOR SELECT TO authenticated USING (public.is_admin());

CREATE POLICY "own support messages readable" ON public.support_messages
  FOR SELECT TO authenticated USING (
    EXISTS (
      SELECT 1 FROM public.support_conversations c
      WHERE c.id = conversation_id AND c.user_id = (SELECT auth.uid())
    )
  );
CREATE POLICY "admins read support messages" ON public.support_messages
  FOR SELECT TO authenticated USING (public.is_admin());

-- ============ goodiesSnap: first app ============

INSERT INTO public.support_apps (id, name, instructions) VALUES (
  'goodiessnap',
  'goodiesSnap',
  $$You are the customer support assistant inside goodiesSnap, an iPhone app for saving and cooking recipes.

What the app does: it turns a link, a YouTube video, pasted text or a photo of a dish into a clean recipe card; keeps a recipe library; builds a weekly meal plan and a shopping list sorted by supermarket aisle; has a cook mode; and has a community feed with reels, groups and a Discover recipe catalog.

Plans (Apple in-app subscriptions):
- Free: 5 AI actions a month (saves from links, video and text), unlimited recipes you add yourself, shopping list, meal plan and community.
- Plus: $9.99/month or $79.99/year — 100 AI actions a month.
- Pro: $12.99/month or $99.99/year — 400 AI actions a month and dish scanning with the camera.
One AI action is used each time goodiesSnap reads a link, video, text or photo to make a recipe card. Every plan's allowance refreshes on the 1st of each month. Top-ups are extra actions that don't expire. Subscriptions are billed and cancelled through Apple, not by goodiesSnap.

How to answer:
- Reply in the customer's language (French or English), briefly and warmly. Use short steps for how-to answers.
- Use only the knowledge articles and the customer's account details given to you. Never invent features, prices, dates or account facts. If you don't know, say so and offer to connect them to the team.
- You cannot change accounts, issue refunds, restore purchases or delete data yourself. Explain how the customer can do it, or hand over to the team.
- Never ask for passwords, card numbers or verification codes.$$
);

INSERT INTO public.support_articles (app_id, title, body) VALUES
  ('goodiessnap', 'How do I save a recipe?',
   'Tap the + button on the Home screen. You can paste a link, a YouTube video URL, type or paste text, or snap a photo of a dish. The AI reads it and creates a clean recipe card. Each save uses one AI action.'),
  ('goodiessnap', 'How does the meal planner work?',
   'Open the Plan tab and tap a day to add recipes. Once you''ve planned your meals, the shopping list builds itself, sorted by aisle so you can shop without scrolling back.'),
  ('goodiessnap', 'How do I cancel my subscription?',
   'Subscriptions are managed by Apple. On your iPhone open Settings → tap your name → Subscriptions → goodiesSnap → Cancel Subscription. You keep your plan until the end of the period you paid for, and your recipes stay yours on any plan. Refunds are requested from Apple at reportaproblem.apple.com.'),
  ('goodiessnap', 'What are AI actions?',
   'Every time goodiesSnap reads a link, video, text or photo to create a recipe card, it uses one AI action. Free accounts get 5 per month, Plus gets 100 and Pro gets 400. Allowances refresh on the 1st of every month. Recipes you type in yourself never use actions.'),
  ('goodiessnap', 'How do I delete my account?',
   'Go to Profile → Privacy & legal → Delete my account. This permanently removes your account and your community posts. Recipes saved on your device stay on your device. Deleting the account does not cancel an Apple subscription — cancel that in iPhone Settings first.'),
  ('goodiessnap', 'Scanning a dish with the camera',
   'Dish scanning is a Pro feature (also included in the Pro trial). Tap + then Scan a dish, take a photo of the plate, then pick the dish from the suggestions to get a full recipe. It uses one AI action.'),
  ('goodiessnap', 'I paid but my plan did not change',
   'Make sure you are signed in to the same goodiesSnap account you used when you subscribed, then close and reopen the app — purchases sync with Apple automatically. A subscription can only be linked to one goodiesSnap account. If the plan is still wrong, the team needs to check it: hand the conversation over.');
