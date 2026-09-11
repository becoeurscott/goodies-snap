import { createClient } from 'npm:@insforge/sdk';

/**
 * goodiesSnap AI proxy.
 *
 * The provider key lives here as a server secret and never ships in the app binary.
 * Every call spends exactly one metered action, checked and recorded in Postgres before
 * the model is contacted; a failure on our side refunds it. This is what makes the
 * paywall a real control rather than a client-side suggestion.
 */

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

const AISLES = ['Produce', 'Meat', 'Seafood', 'Dairy', 'Pantry', 'Spices', 'Other'];

// Scanning is cheap and Haiku names the same dish; recipe writing stays on Sonnet.
const MODEL_SCAN = 'anthropic/claude-haiku-4.5';
const MODEL_RECIPE = 'anthropic/claude-sonnet-5';

const RECIPE_SYSTEM = `You are the recipe engine inside goodiesSnap, a recipe-keeper app. \
Extract or reconstruct one complete recipe from the user's content. Quantities use \
metric-friendly home-cook units. Each ingredient gets the single best supermarket-aisle \
category. Steps are clear, one action each, no life stories. Estimate calories and macros \
per serving honestly. Always give realistic non-zero prep_minutes and cook_minutes: if the \
source states them, use those; otherwise estimate sensible values from the ingredients and \
steps (a typical home recipe is at least 5 minutes prep, and cook_minutes may be 0 only for \
genuinely no-cook dishes like a salad or smoothie). cuisine is a short label like "Italian", \
"Thai", "West African", or "Breakfast". If the content contains no plausible recipe at all, use the title "Not a recipe" \
and leave ingredients and steps empty. When the content is a YouTube cooking video whose \
description or chapters contain timestamps, fill step_seconds with the start time in whole \
seconds for each step, aligned to steps by index (use -1 for any step you cannot place). If \
there are no timestamps, return an empty step_seconds array.`;

const RECIPE_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['title', 'cuisine', 'prep_minutes', 'cook_minutes', 'servings',
             'calories_per_serving', 'protein_g', 'carbs_g', 'fat_g', 'ingredients', 'steps', 'step_seconds', 'notes'],
  properties: {
    title: { type: 'string' },
    cuisine: { type: 'string' },
    prep_minutes: { type: 'integer' },
    cook_minutes: { type: 'integer' },
    servings: { type: 'integer' },
    calories_per_serving: { type: 'integer' },
    protein_g: { type: 'integer' },
    carbs_g: { type: 'integer' },
    fat_g: { type: 'integer' },
    ingredients: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['name', 'qty', 'category'],
        properties: {
          name: { type: 'string' },
          qty: { type: 'string' },
          category: { type: 'string', enum: AISLES },
        },
      },
    },
    steps: { type: 'array', items: { type: 'string' } },
    step_seconds: { type: 'array', items: { type: 'integer' } },
    notes: { type: 'string' },
  },
};

const SCAN_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['dish_name', 'weight_grams', 'ingredients', 'possible_dishes'],
  properties: {
    dish_name: { type: 'string' },
    weight_grams: { type: 'integer' },
    ingredients: {
      type: 'array', minItems: 2, maxItems: 8,
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['name', 'percent', 'grams'],
        properties: {
          name: { type: 'string' },
          percent: { type: 'number' },
          grams: { type: 'integer' },
        },
      },
    },
    possible_dishes: {
      type: 'array', minItems: 2, maxItems: 5,
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['name', 'confidence', 'blurb'],
        properties: {
          name: { type: 'string' },
          confidence: { type: 'integer' },
          blurb: { type: 'string' },
        },
      },
    },
  },
};

// Per-million-token prices, used to record what each call cost.
const PRICES: Record<string, { in: number; out: number }> = {
  'anthropic/claude-haiku-4.5': { in: 1.0, out: 5.0 },
  'anthropic/claude-sonnet-5': { in: 3.0, out: 15.0 },
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

/** One structured-output call to OpenRouter. */
async function callModel(opts: {
  key: string;
  model: string;
  system: string;
  parts: Array<Record<string, unknown>>;
  schema: unknown;
  schemaName: string;
  maxTokens: number;
}) {
  const res = await fetch('https://openrouter.ai/api/v1/chat/completions', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${opts.key}`,
      'Content-Type': 'application/json',
      'HTTP-Referer': 'https://goodiessnap.app',
      'X-Title': 'goodiesSnap',
    },
    body: JSON.stringify({
      model: opts.model,
      max_tokens: opts.maxTokens,
      messages: [
        { role: 'system', content: opts.system },
        { role: 'user', content: opts.parts },
      ],
      response_format: {
        type: 'json_schema',
        json_schema: { name: opts.schemaName, strict: true, schema: opts.schema },
      },
    }),
  });

  const body = await res.json().catch(() => null);
  if (!res.ok || !body) {
    throw new Error(`upstream ${res.status}: ${body?.error?.message ?? 'no body'}`);
  }
  // OpenRouter can return 200 with an error body when a provider fails.
  if (body.error) throw new Error(`upstream: ${body.error.message ?? 'unknown'}`);

  const choice = body.choices?.[0];
  if (choice?.message?.refusal) throw new Error(`refused: ${choice.message.refusal}`);
  if (choice?.finish_reason === 'length') throw new Error('the answer was cut off');

  const text = choice?.message?.content;
  if (!text) throw new Error('empty response');

  const price = PRICES[opts.model] ?? { in: 3, out: 15 };
  const usage = body.usage ?? {};
  const costMicros = Math.round(
    ((usage.prompt_tokens ?? 0) * price.in + (usage.completion_tokens ?? 0) * price.out),
  );

  return { payload: JSON.parse(text), costMicros, model: opts.model };
}

/**
 * Image-search queries allowed per day, across all users. Google bills $5/1000, so this is a
 * spend ceiling of about $1/day. Override with IMAGE_SEARCH_DAILY_LIMIT; set it to 100 to stay
 * inside Google's free daily allowance entirely.
 */
const DEFAULT_IMAGE_LIMIT = 200;

/** Normalised cache key for a dish name: lowercase, alphanumerics and single spaces. */
function dishKey(dish: string): string {
  return dish.toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim().replace(/\s+/g, ' ');
}

/**
 * Looks a dish up on Google Images via the Custom Search JSON API and returns the first
 * usable photo URL, or null.
 *
 * Runs here rather than on the device so the key never ships in the binary. Restricted to
 * photos licensed for reuse (`rights`) — an app cannot paste arbitrary search results onto
 * saved recipes. Returns null (never throws) when the keys are unset or the quota is spent,
 * so the caller falls back to the user's own scan photo.
 */
async function googleImage(dish: string): Promise<{ image: string | null; reached: boolean }> {
  const key = Deno.env.get('GOOGLE_CSE_KEY');
  const cx = Deno.env.get('GOOGLE_CSE_CX');
  if (!key || !cx || !dish.trim()) return { image: null, reached: false };

  const url = new URL('https://www.googleapis.com/customsearch/v1');
  url.searchParams.set('key', key);
  url.searchParams.set('cx', cx);
  url.searchParams.set('q', `${dish} recipe dish`);
  url.searchParams.set('searchType', 'image');
  url.searchParams.set('imgType', 'photo');
  url.searchParams.set('imgSize', 'large');
  url.searchParams.set('num', '3');
  url.searchParams.set('safe', 'active');
  // Only images the licence allows us to reuse.
  url.searchParams.set('rights', 'cc_publicdomain|cc_attribute|cc_sharealike');

  try {
    const res = await fetch(url.toString());
    if (!res.ok) {
      console.error('google image search failed:', res.status, await res.text());
      // 4xx/5xx from Google is not a "no such dish" answer, so don't let it be cached.
      return { image: null, reached: false };
    }
    const body = await res.json();
    const items: any[] = body.items ?? [];
    const hit = items.find((i) => typeof i.link === 'string' && /^https:/.test(i.link));
    return { image: hit?.link ?? null, reached: true };
  } catch (err) {
    console.error('google image search threw:', err);
    return { image: null, reached: false };
  }
}

export default async function (req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  const key = Deno.env.get('OPENROUTER_API_KEY');
  if (!key) return json({ error: 'server_not_configured' }, 503);

  const token = req.headers.get('Authorization')?.replace('Bearer ', '') ?? null;
  if (!token) return json({ error: 'unauthorized' }, 401);

  const client = createClient({
    baseUrl: Deno.env.get('INSFORGE_BASE_URL'),
    accessToken: token,
  });

  const { data: userData } = await client.auth.getCurrentUser();
  if (!userData?.user?.id) return json({ error: 'unauthorized' }, 401);

  let req_body: any;
  try {
    req_body = await req.json();
  } catch {
    return json({ error: 'bad_request' }, 400);
  }

  const action: string = req_body?.action ?? '';
  const needsCamera = action === 'scan';

  // Artwork lookup is not a model call, so it is deliberately outside the meter — charging a
  // user an AI action to fetch a thumbnail would be indefensible. It is billed per query
  // though ($5/1000), so it goes through a shared cache first and only ever reaches Google
  // on a genuine miss.
  if (action === 'image_search') {
    const dish: string = String(req_body.dish ?? '').slice(0, 120);
    const key = dishKey(dish);
    if (!key) return json({ data: { image: null } });

    const { data: cached } = await client.database.rpc('get_dish_artwork', { p_key: key });
    const row = Array.isArray(cached) ? cached[0] : cached;
    // A cached miss is still a cache hit: we already paid to learn there is nothing here.
    if (row?.found) return json({ data: { image: row.image_url ?? null, cached: true } });

    // Circuit breaker. Google has no spend cap of its own, so this is the only thing between
    // a traffic spike and an unbounded bill.
    const limit = Number(Deno.env.get('IMAGE_SEARCH_DAILY_LIMIT') ?? DEFAULT_IMAGE_LIMIT);
    const { data: claimed } = await client.database
      .rpc('claim_image_search', { p_limit: limit });
    // A scalar-returning RPC can come back bare or wrapped, depending on the client.
    const allowed = Array.isArray(claimed)
      ? (claimed[0]?.claim_image_search ?? claimed[0])
      : claimed;
    if (allowed !== true) {
      // Over budget for today. Answer null but do NOT cache it — nothing was looked up, and
      // caching this would permanently blacklist the dish for a temporary condition.
      console.warn(`image search budget spent (${limit}/day); serving null for "${dish}"`);
      return json({ data: { image: null, cached: false, budget_exhausted: true } });
    }

    const { image, reached } = await googleImage(dish);
    if (!reached) {
      await client.database.rpc('release_image_search');
      return json({ data: { image: null, cached: false } });
    }

    // Only a real answer from Google gets cached, misses included.
    await client.database.rpc('cache_dish_artwork', {
      p_key: key, p_name: dish, p_url: image, p_source: 'google',
    });
    return json({ data: { image, cached: false } });
  }

  // 1. Spend the action first — never call the model on an unmetered request.
  const { data: gate, error: gateError } = await client.database
    .rpc('consume_ai_action', { p_action: action, p_needs_camera: needsCamera });
  if (gateError) return json({ error: 'metering_failed', detail: gateError.message }, 500);

  const decision = Array.isArray(gate) ? gate[0] : gate;
  if (!decision?.allowed) {
    return json({
      error: decision?.reason ?? 'not_allowed',
      remaining: decision?.remaining ?? 0,
      plan: decision?.plan ?? 'free',
    }, 402);
  }

  // 2. Run the model.
  try {
    let result;
    switch (action) {
      case 'extract': {
        const content: string = String(req_body.content ?? '').slice(0, 20_000);
        if (!content.trim()) throw new Error('nothing to extract');
        result = await callModel({
          key, model: MODEL_RECIPE, system: RECIPE_SYSTEM,
          parts: [{ type: 'text', text: content }],
          schema: RECIPE_SCHEMA, schemaName: 'recipe', maxTokens: 4000,
        });
        break;
      }
      case 'scan': {
        const image: string = String(req_body.image_base64 ?? '');
        if (!image) throw new Error('no image');
        result = await callModel({
          key, model: MODEL_SCAN, system: 'You identify food in photos precisely.',
          parts: [
            { type: 'image_url', image_url: { url: `data:image/jpeg;base64,${image}` } },
            { type: 'text', text:
              'Identify the food in this image. Return the most likely dish name, an estimated ' +
              'plate weight in grams, and the visible ingredients with approximate percentage of ' +
              'the plate and grams. Use short ingredient names. If uncertain, still return the ' +
              'most likely result.\n\nAlso return possible_dishes: 3-5 specific, cookable dish ' +
              'names this could be, best first, each with a confidence 0-100 and a one-line blurb ' +
              'saying what makes it that dish. Make them real recipe names a cook could search ' +
              'for, not generic categories.' },
          ],
          schema: SCAN_SCHEMA, schemaName: 'food_scan', maxTokens: 1500,
        });
        break;
      }
      case 'recipe_for_dish': {
        const dish: string = String(req_body.dish ?? '');
        if (!dish) throw new Error('no dish');
        const detected: string = String(req_body.detected ?? 'none detected');
        result = await callModel({
          key, model: MODEL_RECIPE, system: RECIPE_SYSTEM,
          parts: [{ type: 'text', text:
            `Write a complete, realistic home-cook recipe for: ${dish}\n\n` +
            `A photo of the finished plate was analysed and these components were visible: ${detected}. ` +
            'Honour those components where they make sense for the dish, and add whatever else the ' +
            'dish genuinely needs. Scale the recipe to a normal household serving count.' }],
          schema: RECIPE_SCHEMA, schemaName: 'recipe', maxTokens: 4000,
        });
        break;
      }
      default:
        throw new Error(`unknown action ${action}`);
    }

    // 3. Record the real cost against the usage row.
    await client.database.rpc('record_ai_cost', {
      p_usage_id: decision.usage_id,
      p_model: result.model,
      p_cost_micros: result.costMicros,
    });

    return json({
      data: result.payload,
      remaining: decision.remaining,
      plan: decision.plan,
    });
  } catch (err) {
    // The user should never pay for our failure.
    await client.database.rpc('refund_ai_action', { p_usage_id: decision.usage_id });
    console.error('ai proxy failed:', err instanceof Error ? err.message : err);
    return json({ error: 'model_failed', detail: String(err) }, 502);
  }
}
