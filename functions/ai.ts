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
per serving honestly. cuisine is a short label like "Italian", "Thai", "West African", or \
"Breakfast". If the content contains no plausible recipe at all, use the title "Not a recipe" \
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
