import { createClient } from 'npm:@insforge/sdk';

/**
 * AI customer service.
 *
 * The customer talks to this function; it stores their message, decides whether the assistant
 * may answer, builds the context (the app's instructions, the most relevant knowledge articles,
 * the customer's own account facts and the recent conversation) and asks the self-hosted model
 * on the VPS (https://ai.goodiessnap.com, Ollama behind a key-checking proxy). When the VPS is
 * down or too slow, the same request goes to the backup model on OpenRouter; when both fail,
 * or the topic needs a person, the conversation is handed to the team, who answer from the
 * admin console.
 *
 * Every write uses the service key after the caller has been identified from their own token.
 * Customers can only read their own rows (RLS), so nothing here trusts ids from the body
 * beyond looking them up under the caller's user id.
 *
 * Actions:
 *   history { app, after? }         → the customer's current conversation and its messages
 *   send    { app, text }           → stores the message and returns the reply (if any)
 *
 * Secrets: OLLAMA_URL, OLLAMA_API_KEY; optional OPENROUTER_API_KEY (backup model),
 * SUPPORT_OLLAMA_TIMEOUT_MS, SUPPORT_FALLBACK_MODEL.
 */

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const APP_RE = /^[a-z0-9-]{2,32}$/;

const MAX_TEXT = 2000;
// Per customer, across conversations. Generous for a real conversation, tight for a script.
const RATE_WINDOW_MIN = 10;
const RATE_PER_WINDOW = 20;
const RATE_PER_DAY = 150;

const HISTORY_TURNS = 8;
const TOP_ARTICLES = 3;
// Cosine similarity below this is noise for nomic-embed-text; such articles are left out.
// Kept low on purpose: a marginal article costs a few prompt tokens, a missing one costs
// a wrong answer.
const MIN_SIMILARITY = 0.3;

// The customer explicitly wants a person. English and French.
const ASKS_FOR_HUMAN = new RegExp(
  [
    String.raw`\b(human|real person|a person|someone real|agent|operator|representative|customer service|talk to (someone|somebody|a person))\b`,
    String.raw`\b(humain|une personne|quelqu'un|un conseiller|une conseill[eè]re|un agent|parler [àa] (quelqu'un|une personne|un humain))\b`,
  ].join('|'),
  'i',
);
// Money, legal and account-security topics always go to a person.
const SENSITIVE = new RegExp(
  [
    String.raw`\b(refund|chargeback|charged twice|double charged|money back|dispute|lawyer|legal action|sue|fraud|scam|stolen|hacked|someone (else )?(logged|got) into)\b`,
    String.raw`\b(rembours\w*|d[ée]bit[ée] deux fois|avocat|plainte|poursuite|fraude|arnaque|vol[ée]?|pirat[ée]|pirat\w+)\b`,
  ].join('|'),
  'i',
);

const REPLY_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['reply', 'handoff'],
  properties: {
    reply: { type: 'string' },
    // true when the assistant can't answer from what it was given, or the customer needs
    // something only the team can do.
    handoff: { type: 'boolean' },
  },
};

const OUTPUT_RULES = `Answer with JSON only: {"reply": "<your message to the customer>", "handoff": <true|false>}.
Set "handoff" to true when the articles and account details don't contain the answer, when the customer needs something only the team can do (refunds, billing problems, account changes, bugs you can't solve), or when the customer is upset. When handoff is true, "reply" is one short sentence acknowledging the request — the team will take over.`;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

type Msg = { role: 'system' | 'user' | 'assistant'; content: string };
type Reply = { reply: string; handoff: boolean; model: string; fallback: boolean; latencyMs: number };

/** Cosine similarity of two equal-length vectors. */
function cosine(a: number[], b: number[]): number {
  let dot = 0, na = 0, nb = 0;
  for (let i = 0; i < a.length && i < b.length; i++) {
    dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i];
  }
  return na && nb ? dot / Math.sqrt(na * nb) : 0;
}

/** Word-overlap score, the stand-in ranking when embeddings are unavailable. */
function overlap(query: string, text: string): number {
  const words = (s: string) => new Set(s.toLowerCase().split(/[^\p{L}\p{N}]+/u).filter((w) => w.length > 3));
  const q = words(query);
  if (q.size === 0) return 0;
  const t = words(text);
  let hits = 0;
  q.forEach((w) => { if (t.has(w)) hits++; });
  return hits / q.size;
}

/** Parses the model's JSON answer, tolerating a stray code fence or reasoning preamble. */
function parseReply(raw: string): { reply: string; handoff: boolean } | null {
  const text = raw.replace(/<think>[\s\S]*?<\/think>/g, '').trim();
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start >= 0 && end > start) {
    try {
      const obj = JSON.parse(text.slice(start, end + 1));
      if (typeof obj?.reply === 'string' && obj.reply.trim()) {
        return { reply: obj.reply.trim(), handoff: obj.handoff === true };
      }
    } catch { /* fall through */ }
  }
  return text ? { reply: text, handoff: false } : null;
}

/**
 * The platform's gateway drops a request that sends nothing for 30 seconds, but a CPU-only
 * VPS can take longer than that to answer. Anything quick (errors, handoffs, history) is
 * returned as is, with its real status. A slow answer is streamed instead: a space every few
 * seconds keeps the connection open — JSON allows leading whitespace — then the real body.
 */
const QUICK_MS = 2_000;
const HEARTBEAT_MS = 5_000;

export default async function (req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
  const pending = handle(req);
  const quick = await Promise.race([pending, new Promise<null>((r) => setTimeout(() => r(null), QUICK_MS))]);
  if (quick) return quick;

  const enc = new TextEncoder();
  const stream = new ReadableStream({
    async start(controller) {
      const beat = setInterval(() => controller.enqueue(enc.encode(' ')), HEARTBEAT_MS);
      try {
        controller.enqueue(enc.encode(' '));
        const res = await pending;
        controller.enqueue(enc.encode(await res.text()));
      } catch (err) {
        console.error('support stream failed:', err instanceof Error ? err.message : err);
        controller.enqueue(enc.encode(JSON.stringify({ error: 'support_failed' })));
      } finally {
        clearInterval(beat);
        controller.close();
      }
    },
  });
  return new Response(stream, { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } });
}

async function handle(req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  const baseURL = Deno.env.get('INSFORGE_BASE_URL');
  const serviceKey = Deno.env.get('API_KEY');
  const ollamaURL = (Deno.env.get('OLLAMA_URL') ?? '').replace(/\/+$/, '');
  const ollamaKey = Deno.env.get('OLLAMA_API_KEY') ?? '';
  const openRouterKey = Deno.env.get('OPENROUTER_API_KEY') ?? '';
  if (!baseURL || !serviceKey) return json({ error: 'server_not_configured' }, 503);

  const token = req.headers.get('Authorization')?.replace('Bearer ', '') ?? '';
  if (!token) return json({ error: 'unauthorized' }, 401);

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return json({ error: 'bad_request' }, 400); }

  // Who is calling — from the token, never from the body.
  const client = createClient({ baseUrl: baseURL, accessToken: token });
  let userId: string;
  try {
    const { data, error } = await client.auth.getCurrentUser();
    if (error || !data?.user?.id) return json({ error: 'unauthorized' }, 401);
    userId = data.user.id;
  } catch {
    return json({ error: 'unauthorized' }, 401);
  }

  const appId = String(body.app ?? '');
  if (!APP_RE.test(appId)) return json({ error: 'unknown_app' }, 400);

  // ---- service-key REST helpers ----
  const svc = { Authorization: `Bearer ${serviceKey}`, 'Content-Type': 'application/json' };
  const rest = (path: string, opts: RequestInit = {}) =>
    fetch(`${baseURL}/api/database/records/${path}`, { ...opts, headers: { ...svc, ...(opts.headers || {}) } });
  async function select<T = Record<string, unknown>>(path: string): Promise<T[]> {
    const r = await rest(path);
    if (!r.ok) throw new Error(`read ${path.split('?')[0]} ${r.status}: ${await r.text()}`);
    const rows = await r.json();
    return Array.isArray(rows) ? rows : [];
  }
  async function insert(table: string, row: Record<string, unknown>) {
    const r = await rest(table, { method: 'POST', body: JSON.stringify([row]) });
    if (!r.ok) throw new Error(`insert ${table} ${r.status}: ${await r.text()}`);
  }
  async function patch(table: string, query: string, values: Record<string, unknown>) {
    const r = await rest(`${table}?${query}`, { method: 'PATCH', body: JSON.stringify(values) });
    if (!r.ok) throw new Error(`update ${table} ${r.status}: ${await r.text()}`);
  }

  // ---- context builders (scoped to this caller and app) ----

  /** Top articles for the question, embedding-ranked; word overlap if the VPS can't embed. */
  async function relevantArticles(query: string, embedModel: string) {
    const rows = await select<{ id: string; title: string; body: string; embedding: number[] | null; embedding_model: string | null }>(
      `support_articles?app_id=eq.${appId}&active=is.true&select=id,title,body,embedding,embedding_model&limit=500`,
    );
    if (rows.length === 0) return [];
    const model = embedModel;

    try {
      // Backfill articles that are new, edited, or embedded with another model. The
      // search_document/search_query prefixes are how nomic-embed-text was trained to tell
      // passages from questions; other embedding models just see them as a word.
      const stale = rows.filter((r) => !Array.isArray(r.embedding) || r.embedding_model !== model);
      if (stale.length) {
        const vecs = await embed(stale.map((r) => `search_document: ${r.title}\n\n${r.body}`), model);
        await Promise.all(stale.map((r, i) => {
          r.embedding = vecs[i];
          return patch('support_articles', `id=eq.${r.id}`, { embedding: vecs[i], embedding_model: model });
        }));
      }
      const [q] = await embed([`search_query: ${query}`], model);
      return rows
        .map((r) => ({ ...r, score: cosine(q, r.embedding as number[]) }))
        .filter((r) => r.score >= MIN_SIMILARITY)
        .sort((a, b) => b.score - a.score)
        .slice(0, TOP_ARTICLES);
    } catch (err) {
      console.warn('embedding unavailable, using word overlap:', err instanceof Error ? err.message : err);
      return rows
        .map((r) => ({ ...r, score: overlap(query, `${r.title} ${r.body}`) }))
        .filter((r) => r.score > 0)
        .sort((a, b) => b.score - a.score)
        .slice(0, TOP_ARTICLES);
    }
  }

  /** Plain-text facts about the caller's own account, for the assistant to answer from. */
  async function accountFacts(): Promise<string> {
    const [profile, ent, subs] = await Promise.all([
      select(`profiles?id=eq.${userId}&select=display_name,created_at&limit=1`).catch(() => []),
      select(`entitlements?user_id=eq.${userId}&select=plan,used,top_up,period,trial_until&limit=1`).catch(() => []),
      select(`app_store_transactions?user_id=eq.${userId}&select=plan,product_id,environment,expires_at,revoked_at&order=updated_at.desc&limit=3`).catch(() => []),
    ]);
    const p = profile[0] ?? {};
    const e = ent[0] ?? {};
    const day = (v: unknown) => (v ? String(v).slice(0, 10) : 'none');
    const plan = String(e.plan ?? 'free');
    const onTrial = e.trial_until && new Date(String(e.trial_until)) > new Date();
    // Mirrors plan_allowance()/trial_allowance() in the database; a trial has its own small cap.
    const allowance = onTrial && plan === 'free' ? 5 : plan === 'pro' ? 400 : plan === 'plus' ? 100 : 5;
    const used = Number(e.used ?? 0);
    const topUp = Number(e.top_up ?? 0);
    // Do the arithmetic here: a 3B model asked for "100 minus 42" answers 6 surprisingly often.
    const remaining = Math.max(0, allowance - used) + topUp;
    const lines = [
      `- Name: ${p.display_name ?? 'unknown'}; member since ${day(p.created_at)}`,
      `- Plan: ${plan}${onTrial ? ` (Pro trial until ${day(e.trial_until)})` : ''}`,
      `- AI actions remaining right now: ${remaining} (this month ${used} used of ${allowance} included, plus ${topUp} top-up)`,
    ];
    if (subs.length === 0) lines.push('- App Store subscription: none on record');
    subs.forEach((s) => lines.push(
      `- App Store subscription: ${s.plan} (${s.product_id}), expires ${day(s.expires_at)}` +
      `${s.revoked_at ? `, revoked ${day(s.revoked_at)}` : ''}${s.environment === 'Sandbox' ? ', sandbox' : ''}`,
    ));
    lines.push(`- Today's date: ${new Date().toISOString().slice(0, 10)}`);
    return lines.join('\n');
  }

  // ======================= model calls =======================

  async function embed(inputs: string[], model: string): Promise<number[][]> {
    if (!ollamaURL) throw new Error('OLLAMA_URL not set');
    const res = await fetch(`${ollamaURL}/api/embed`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${ollamaKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ model, input: inputs, keep_alive: -1 }),
      signal: AbortSignal.timeout(20_000),
    });
    if (!res.ok) throw new Error(`embed ${res.status}`);
    const out = await res.json();
    if (!Array.isArray(out?.embeddings) || out.embeddings.length !== inputs.length) throw new Error('embed: bad shape');
    return out.embeddings;
  }

  /** The VPS first; the backup model only when the VPS fails or runs out of time. */
  async function askModel(messages: Msg[], model: string): Promise<Reply | null> {
    const started = Date.now();
    const timeout = Number(Deno.env.get('SUPPORT_OLLAMA_TIMEOUT_MS') ?? 45_000);

    if (ollamaURL) {
      try {
        const res = await fetch(`${ollamaURL}/api/chat`, {
          method: 'POST',
          headers: { Authorization: `Bearer ${ollamaKey}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({
            model, messages, stream: false, format: REPLY_SCHEMA, keep_alive: -1,
            options: { temperature: 0.3, num_ctx: 4096, num_predict: 400 },
          }),
          signal: AbortSignal.timeout(timeout),
        });
        if (!res.ok) throw new Error(`ollama ${res.status}: ${(await res.text()).slice(0, 200)}`);
        const parsed = parseReply(String((await res.json())?.message?.content ?? ''));
        if (parsed) return { ...parsed, model, fallback: false, latencyMs: Date.now() - started };
        throw new Error('ollama: empty reply');
      } catch (err) {
        console.warn('VPS model failed, trying backup:', err instanceof Error ? err.message : err);
      }
    }

    if (!openRouterKey) return null;
    const backup = Deno.env.get('SUPPORT_FALLBACK_MODEL') ?? 'anthropic/claude-haiku-4.5';
    try {
      const res = await fetch('https://openrouter.ai/api/v1/chat/completions', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${openRouterKey}`,
          'Content-Type': 'application/json',
          'X-Title': 'goodiesSnap support',
        },
        body: JSON.stringify({
          model: backup, max_tokens: 600, temperature: 0.3, messages,
          response_format: { type: 'json_schema', json_schema: { name: 'support_reply', strict: true, schema: REPLY_SCHEMA } },
        }),
        signal: AbortSignal.timeout(30_000),
      });
      const out = await res.json().catch(() => null);
      if (!res.ok || !out || out.error) throw new Error(`openrouter ${res.status}: ${out?.error?.message ?? ''}`);
      const parsed = parseReply(String(out.choices?.[0]?.message?.content ?? ''));
      if (parsed) return { ...parsed, model: backup, fallback: true, latencyMs: Date.now() - started };
    } catch (err) {
      console.error('backup model failed:', err instanceof Error ? err.message : err);
    }
    return null;
  }

  const MSG_FIELDS = 'id,sender,author_name,body,created_at';
  const currentConversation = async () =>
    (await select<{ id: string; status: string }>(
      `support_conversations?app_id=eq.${appId}&user_id=eq.${userId}&select=id,status&order=last_message_at.desc&limit=1`,
    ))[0] ?? null;

  try {
    const app = (await select<Record<string, string | boolean>>(
      `support_apps?id=eq.${appId}&select=id,name,instructions,handoff_message,chat_model,embed_model,enabled&limit=1`,
    ))[0];
    if (!app) return json({ error: 'unknown_app' }, 404);

    // ======================= HISTORY =======================
    if (body.action === 'history') {
      const conv = await currentConversation();
      if (!conv) return json({ data: { conversation: null, messages: [] } });
      const after = typeof body.after === 'string' && !isNaN(Date.parse(body.after))
        ? `&created_at=gt.${new Date(body.after).toISOString()}` : '';
      const messages = await select(
        `support_messages?conversation_id=eq.${conv.id}${after}&select=${MSG_FIELDS}&order=created_at.asc&limit=200`,
      );
      return json({ data: { conversation: conv, messages } });
    }

    if (body.action !== 'send') return json({ error: 'unknown_action' }, 400);

    // ======================= SEND =======================
    const text = String(body.text ?? '').trim().slice(0, MAX_TEXT);
    if (!text) return json({ error: 'empty_message' }, 400);

    // Rate limit on the customer's own messages. Past the limit the message is still kept —
    // the team sees it — but the assistant stops spending the VPS on this customer.
    const myConvs = await select<{ id: string }>(
      `support_conversations?user_id=eq.${userId}&select=id&order=last_message_at.desc&limit=50`,
    );
    let rateLimited = false;
    if (myConvs.length) {
      const ids = myConvs.map((c) => c.id).join(',');
      const since = (mins: number) => new Date(Date.now() - mins * 60_000).toISOString();
      const recent = await select(
        `support_messages?conversation_id=in.(${ids})&sender=eq.user&created_at=gte.${since(24 * 60)}&select=created_at&limit=${RATE_PER_DAY + 1}`,
      );
      const windowStart = Date.now() - RATE_WINDOW_MIN * 60_000;
      const inWindow = recent.filter((m) => Date.parse(String(m.created_at)) >= windowStart).length;
      rateLimited = recent.length >= RATE_PER_DAY || inWindow >= RATE_PER_WINDOW;
    }

    // Reuse the open conversation; a closed one stays closed and a new one starts.
    let conv = await currentConversation();
    const now = () => new Date().toISOString();
    if (!conv || conv.status === 'closed') {
      conv = { id: crypto.randomUUID(), status: 'ai' };
      await insert('support_conversations', {
        id: conv.id, app_id: appId, user_id: userId, status: 'ai',
        subject: text.replace(/\s+/g, ' ').slice(0, 120),
      });
    }

    const userMsg = { id: crypto.randomUUID(), sender: 'user', author_name: null, body: text, created_at: now() };
    await insert('support_messages', { ...userMsg, conversation_id: conv.id });
    await patch('support_conversations', `id=eq.${conv.id}`, { last_message_at: userMsg.created_at });

    const out: Record<string, unknown>[] = [userMsg];
    const respond = (status: string) => json({ data: { conversation: { id: conv!.id, status }, messages: out } });

    // A person owns this conversation: the assistant stays out of it.
    if (conv.status === 'needs_human' || conv.status === 'human') return respond(conv.status);

    async function handOff(reason: string, lead?: string) {
      const reply = [lead, String(app.handoff_message)].filter(Boolean).join(' ');
      const msg = { id: crypto.randomUUID(), sender: 'ai', author_name: null, body: reply, created_at: now() };
      await insert('support_messages', { ...msg, conversation_id: conv!.id });
      await patch('support_conversations', `id=eq.${conv!.id}`, {
        status: 'needs_human', handoff_reason: reason, last_message_at: msg.created_at,
      });
      out.push(msg);
      return respond('needs_human');
    }

    if (!app.enabled) return handOff('assistant_disabled');
    if (rateLimited) return handOff('rate_limited');
    if (ASKS_FOR_HUMAN.test(text)) return handOff('customer_asked');
    if (SENSITIVE.test(text)) return handOff('sensitive_topic');

    // ---- context ----
    const [history, articles, facts] = await Promise.all([
      select<{ sender: string; body: string }>(
        `support_messages?conversation_id=eq.${conv.id}&select=sender,body&order=created_at.desc&limit=${HISTORY_TURNS * 2 + 1}`,
      ).then((rows) => rows.reverse()),
      relevantArticles(text, String(app.embed_model)),
      accountFacts(),
    ]);

    const system = [
      String(app.instructions),
      OUTPUT_RULES,
    ].join('\n\n');
    // Static instructions first and dynamic context after, so Ollama can reuse the cached
    // prompt prefix between customers — on a CPU-only VPS that's most of the latency.
    const context = [
      `Knowledge articles:\n${articles.length ? articles.map((a) => `### ${a.title}\n${a.body}`).join('\n\n') : '(none relevant)'}`,
      `This customer's account:\n${facts}`,
    ].join('\n\n');

    const messages: Msg[] = [
      { role: 'system', content: system },
      { role: 'system', content: context },
      ...history.map((m): Msg => ({
        role: m.sender === 'user' ? 'user' : 'assistant',
        content: m.sender === 'agent' ? `[Team member] ${m.body}` : m.body,
      })),
    ];

    const answer = await askModel(messages, String(app.chat_model));
    if (!answer) return handOff('ai_unavailable');
    if (answer.handoff) return handOff('low_confidence', answer.reply);

    const aiMsg = { id: crypto.randomUUID(), sender: 'ai', author_name: null, body: answer.reply.slice(0, 4000), created_at: now() };
    await insert('support_messages', {
      ...aiMsg, conversation_id: conv.id,
      model: answer.model, latency_ms: answer.latencyMs, fallback: answer.fallback,
    });
    await patch('support_conversations', `id=eq.${conv.id}`, { last_message_at: aiMsg.created_at });
    out.push(aiMsg);
    return respond('ai');

  } catch (err) {
    console.error('support failed:', err instanceof Error ? err.message : err);
    return json({ error: 'support_failed' }, 500);
  }
}
