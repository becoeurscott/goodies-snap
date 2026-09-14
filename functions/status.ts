/**
 * Public app status: maintenance state + the public subset of app_config. Unauthenticated —
 * the iOS app polls this at launch to decide whether to show a maintenance screen or force an
 * update. The query explicitly restricts app_config to `is_public = true`, so no private or
 * security config is ever exposed even though the read uses the service key. No secrets are
 * returned; read-only.
 */

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  });
}

export default async function (req: Request) {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });

  const baseURL = Deno.env.get('INSFORGE_BASE_URL');
  const key = Deno.env.get('API_KEY');
  if (!baseURL || !key) return json({ error: 'server_not_configured' }, 503);
  const headers = { Authorization: `Bearer ${key}` };

  let maintenance = { enabled: false, message: '', min_build: 0 };
  const config: Record<string, unknown> = {};
  try {
    const m = await fetch(`${baseURL}/api/database/records/maintenance_state?select=enabled,message,min_build&limit=1`, { headers });
    if (m.ok) { const rows = await m.json(); if (Array.isArray(rows) && rows[0]) maintenance = rows[0]; }
  } catch { /* default to not-in-maintenance */ }
  try {
    // Only ever public rows — never the private/security config.
    const c = await fetch(`${baseURL}/api/database/records/app_config?is_public=eq.true&select=key,value`, { headers });
    if (c.ok) { const rows = await c.json(); for (const r of (rows || [])) config[r.key] = r.value; }
  } catch { /* no public config */ }

  return json({ maintenance, config });
}
