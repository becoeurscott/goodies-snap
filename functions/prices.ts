import { createClient } from 'npm:@insforge/sdk';

/**
 * goodiesSnap store pricing via the Kroger Public API.
 *
 * Kroger's client id/secret live here as server secrets and never ship in the app. The app
 * sends ingredient names + a chosen store; we exchange client credentials for a token, look
 * up each product's price at that store, and return them. Requiring a signed-in caller
 * protects our Kroger quota from anonymous abuse, mirroring the AI proxy.
 *
 * Until KROGER_CLIENT_ID / KROGER_CLIENT_SECRET are set (after Kroger approves the app),
 * this returns 503 not_configured — the app then simply hides prices.
 */

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

const KROGER = 'https://api.kroger.com/v1';

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status, headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

async function krogerToken(id: string, secret: string): Promise<string> {
  const basic = btoa(`${id}:${secret}`);
  const r = await fetch(`${KROGER}/connect/oauth2/token`, {
    method: 'POST',
    headers: {
      Authorization: `Basic ${basic}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: 'grant_type=client_credentials&scope=product.compact',
  });
  if (!r.ok) throw new Error(`token ${r.status}`);
  return (await r.json()).access_token;
}

// Kroger's product search matches simple grocery terms, not recipe phrasing. Turn an
// ingredient name into an ordered list of search terms, most-specific first, so a miss on
// the full phrase falls back to the core noun ("Red Chilli Powder" -> "chili powder" ->
// "chili"; "Coriander Leaves" -> "coriander" -> "cilantro"; "Goat Meat" -> "goat").
const STOP = new Set(['fresh', 'chopped', 'minced', 'diced', 'sliced', 'ground', 'dried',
  'large', 'small', 'medium', 'boneless', 'skinless', 'ripe', 'peeled', 'organic', 'whole',
  'raw', 'cooked', 'to', 'taste', 'of', 'a', 'the', 'leaves', 'leaf']);
const SYNONYM: Record<string, string> = { chilli: 'chili', coriander: 'cilantro',
  aubergine: 'eggplant', courgette: 'zucchini', capsicum: 'pepper', prawns: 'shrimp' };

function candidates(name: string): string[] {
  const base = name.toLowerCase()
    .replace(/\([^)]*\)/g, ' ')     // drop parentheticals
    .replace(/,.*$/, ' ')           // drop everything after a comma
    .replace(/[^a-z\s]/g, ' ')      // drop digits/punctuation
    .replace(/\s+/g, ' ').trim();
  const words = base.split(' ').map((w) => SYNONYM[w] ?? w).filter((w) => w && !STOP.has(w));
  const out: string[] = [];
  const push = (t: string) => { t = t.trim(); if (t && !out.includes(t)) out.push(t); };
  push(words.join(' '));                                   // full cleaned phrase
  if (words.length > 2) push(words.slice(-2).join(' '));    // last two words
  if (words.length > 1) push(words[words.length - 1]);      // head noun
  if (words.length > 1) push(words[0]);                     // first noun (goat, ginger)
  // A lone unit word is useless as a grocery search.
  return out.filter((t) => !['powder', 'paste', 'meat', 'sauce', 'oil'].includes(t) || out.length === 1);
}

export default async function (req: Request) {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  const baseURL = Deno.env.get('INSFORGE_BASE_URL');
  const clientId = Deno.env.get('KROGER_CLIENT_ID');
  const clientSecret = Deno.env.get('KROGER_CLIENT_SECRET');
  if (!clientId || !clientSecret) return json({ error: 'not_configured' }, 503);

  const auth = req.headers.get('Authorization') ?? '';
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  if (!token) return json({ error: 'not_signed_in' }, 401);

  // Authenticate the caller (protects our Kroger quota).
  try {
    const client = createClient({ baseUrl: baseURL, accessToken: token });
    const { data, error } = await client.auth.getCurrentUser();
    if (error || !data?.user?.id) return json({ error: 'not_signed_in' }, 401);
  } catch {
    return json({ error: 'not_signed_in' }, 401);
  }

  let body: { action?: string; zip?: string; location_id?: string; items?: string[] };
  try { body = await req.json(); } catch { return json({ error: 'bad_request' }, 400); }

  let kToken: string;
  try { kToken = await krogerToken(clientId, clientSecret); }
  catch { return json({ error: 'kroger_unavailable' }, 502); }
  const kHeaders = { Authorization: `Bearer ${kToken}`, Accept: 'application/json' };

  // Find stores near a ZIP so the user can pick one.
  if (body.action === 'locations') {
    const zip = (body.zip || '').trim();
    if (!/^\d{5}$/.test(zip)) return json({ error: 'bad_zip' }, 400);
    const r = await fetch(
      `${KROGER}/locations?filter.zipCode.near=${zip}&filter.limit=8`, { headers: kHeaders });
    if (!r.ok) return json({ error: 'kroger_unavailable' }, 502);
    const data = await r.json();
    const stores = (data.data || []).map((s: any) => ({
      location_id: s.locationId,
      name: s.name,
      address: [s.address?.addressLine1, s.address?.city, s.address?.state].filter(Boolean).join(', '),
    }));
    return json({ stores });
  }

  // Price each item at the chosen store. Best-match product's promo price if present,
  // else regular price. Items with no match come back with price null.
  if (body.action === 'prices') {
    const locationId = (body.location_id || '').trim();
    const items = Array.isArray(body.items) ? body.items.slice(0, 60) : [];
    if (!locationId) return json({ error: 'no_location' }, 400);

    const results: Record<string, { cents: number | null; label: string | null; image: string | null }> = {};
    // Sequential to stay well under Kroger's rate limit; lists are short.
    for (const name of items) {
      results[name] = { cents: null, label: null, image: null };
      try {
        // Try progressively simpler search terms until one returns a priced product.
        for (const term of candidates(name)) {
          const r = await fetch(
            `${KROGER}/products?filter.term=${encodeURIComponent(term)}&filter.locationId=${locationId}&filter.limit=1`,
            { headers: kHeaders });
          if (!r.ok) continue;
          const p = (await r.json()).data?.[0];
          if (!p) continue;
          const price = p?.items?.[0]?.price;
          const dollars = price?.promo && price.promo > 0 ? price.promo : price?.regular;
          const imgs = p?.images ?? [];
          const front = imgs.find((im: any) => im.perspective === 'front') ?? imgs[0];
          const sizes = front?.sizes ?? [];
          const pick = sizes.find((z: any) => z.size === 'medium')
            ?? sizes.find((z: any) => z.size === 'small')
            ?? sizes.find((z: any) => z.size === 'thumbnail')
            ?? sizes[0];
          const image = pick?.url ?? null;
          if (dollars) { results[name] = { cents: Math.round(dollars * 100), label: p?.description ?? null, image }; break; }
          if (!results[name].image) results[name] = { cents: null, label: p?.description ?? null, image };
        }
      } catch { /* leave as null */ }
    }
    return json({ prices: results, location_id: locationId });
  }

  return json({ error: 'unknown_action' }, 400);
}
