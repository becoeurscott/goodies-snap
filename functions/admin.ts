import { createClient } from 'npm:@insforge/sdk';

/**
 * goodiesSnap admin actions.
 *
 * Every privileged mutation the control-room dashboard performs runs through here so the
 * admin check happens on the server, not in the page. The caller is identified from their
 * own token; we then confirm `profiles.is_admin = true` for that id using the service key
 * (which bypasses RLS) before doing anything. Only after that gate do we act with the
 * service key, and every successful action is written to `admin_audit`. The client never
 * sees the service key — it just calls this function with the signed-in admin's normal token.
 *
 * Actions:
 *   Users:      delete_user, set_plan, set_admin, add_top_up, reset_quota, set_trial
 *   Moderation: hide_content {post|comment|review}, delete_content, delete_post, delete_report
 *   Catalog:    catalog_upsert, catalog_delete, catalog_set_flags
 *   Groups:     group_upsert, group_delete
 */

// Defence in depth: this function is already bearer-authed and admin-gated, but there's no
// reason for any origin other than the control room to call it from a browser.
const CORS = {
  'Access-Control-Allow-Origin': 'https://j7pth4qn.insforge.site',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  'Vary': 'Origin',
};

const BUCKET = 'post-images';
const PLANS = new Set(['free', 'plus', 'pro']);
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
// Every id is interpolated into a PostgREST URL; reject anything that isn't a plain UUID so a
// crafted value can't smuggle extra query filters.
const isUUID = (s: unknown): s is string => typeof s === 'string' && UUID_RE.test(s);

// Which table each moderation target lives in.
const CONTENT_TABLE: Record<string, string> = {
  post: 'posts', comment: 'comments', review: 'recipe_reviews',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

export default async function (req: Request) {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  const baseURL = Deno.env.get('INSFORGE_BASE_URL');
  const adminKey = Deno.env.get('API_KEY');
  if (!baseURL || !adminKey) return json({ error: 'server_not_configured' }, 503);

  const auth = req.headers.get('Authorization') ?? '';
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  if (!token) return json({ error: 'not_signed_in' }, 401);

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return json({ error: 'bad_request' }, 400); }

  // Who is calling — taken from the token, never from the body.
  const client = createClient({ baseUrl: baseURL, accessToken: token });
  let callerId: string;
  try {
    const { data, error } = await client.auth.getCurrentUser();
    if (error || !data?.user?.id) return json({ error: 'not_signed_in' }, 401);
    callerId = data.user.id;
  } catch {
    return json({ error: 'not_signed_in' }, 401);
  }

  const admin = { Authorization: `Bearer ${adminKey}`, 'Content-Type': 'application/json' };

  // The gate: the caller must be a real admin. Read with the service key so RLS can't
  // mask the flag. Grab the display name too, for the audit trail.
  let actorName = '';
  try {
    const meRes = await fetch(
      `${baseURL}/api/database/records/profiles?id=eq.${callerId}&select=is_admin,display_name&limit=1`,
      { headers: admin },
    );
    const me = await meRes.json();
    if (!Array.isArray(me) || !me[0]?.is_admin) return json({ error: 'not_admin' }, 403);
    actorName = me[0].display_name || '';
  } catch {
    return json({ error: 'not_admin' }, 403);
  }

  // ---- helpers (service key) ----
  const rest = (path: string, opts: RequestInit = {}) =>
    fetch(`${baseURL}/api/database/records/${path}`, { ...opts, headers: { ...admin, ...(opts.headers || {}) } });

  async function audit(action: string, targetType: string, targetId: string | null, detail: unknown = {}) {
    try {
      await rest('admin_audit', {
        method: 'POST',
        body: JSON.stringify([{ actor_id: callerId, actor_name: actorName, action, target_type: targetType, target_id: targetId, detail }]),
      });
    } catch { /* auditing must never block the action it records */ }
  }

  async function getOne(table: string, query: string): Promise<Record<string, unknown> | null> {
    const r = await rest(`${table}?${query}&limit=1`);
    if (!r.ok) return null;
    const rows = await r.json();
    return Array.isArray(rows) && rows[0] ? rows[0] : null;
  }

  // Upsert an entitlements row (merge on the user_id primary key).
  const upsertEnt = (row: Record<string, unknown>) =>
    rest('entitlements', { method: 'POST', headers: { Prefer: 'resolution=merge-duplicates' }, body: JSON.stringify([row]) });

  const nowPeriod = () => new Date().toISOString().slice(0, 7); // YYYY-MM
  const asInt = (v: unknown, min: number, max: number): number | null => {
    const n = Number(v);
    return Number.isInteger(n) && n >= min && n <= max ? n : null;
  };

  const action = String(body.action || '');

  // ======================= USERS =======================

  if (action === 'delete_user') {
    const target = body.userId;
    if (!isUUID(target)) return json({ error: 'missing_user' }, 400);
    if (target === callerId) return json({ error: 'cannot_delete_self' }, 400);

    let photosDeleted = 0;
    try {
      const list = await fetch(
        `${baseURL}/api/storage/buckets/${BUCKET}/objects?prefix=${encodeURIComponent(target)}/&limit=1000`,
        { headers: admin },
      );
      if (list.ok) {
        const payload = await list.json();
        const objects: string[] = (payload?.objects ?? payload?.data ?? payload ?? [])
          .map((o: { key?: string; name?: string }) => o?.key ?? o?.name)
          .filter((k: string | undefined): k is string => typeof k === 'string')
          .filter((k: string) => k.startsWith(`${target}/`));
        for (const key of objects) {
          const del = await fetch(
            `${baseURL}/api/storage/buckets/${BUCKET}/objects/${encodeURIComponent(key)}`,
            { method: 'DELETE', headers: admin },
          );
          if (del.ok) photosDeleted++;
        }
      }
    } catch { /* best effort */ }

    const res = await fetch(`${baseURL}/api/auth/users`, {
      method: 'DELETE', headers: admin, body: JSON.stringify({ userIds: [target] }),
    });
    if (!res.ok) {
      console.error('admin delete_user failed', res.status, await res.text());
      return json({ error: 'delete_failed' }, 502);
    }
    await audit('delete_user', 'user', target, { photos_deleted: photosDeleted });
    return json({ ok: true, photos_deleted: photosDeleted });
  }

  if (action === 'set_plan') {
    const target = body.userId, plan = body.plan;
    if (!isUUID(target) || typeof plan !== 'string' || !PLANS.has(plan)) return json({ error: 'bad_request' }, 400);
    const res = await upsertEnt({ user_id: target, plan });
    if (!res.ok) { console.error('set_plan', res.status, await res.text()); return json({ error: 'update_failed' }, 502); }
    await audit('set_plan', 'user', target, { plan });
    return json({ ok: true });
  }

  if (action === 'set_admin') {
    const target = body.userId;
    if (!isUUID(target)) return json({ error: 'missing_user' }, 400);
    if (target === callerId) return json({ error: 'cannot_change_self' }, 400);
    const res = await rest(`profiles?id=eq.${target}`, { method: 'PATCH', body: JSON.stringify({ is_admin: !!body.value }) });
    if (!res.ok) { console.error('set_admin', res.status, await res.text()); return json({ error: 'update_failed' }, 502); }
    await audit('set_admin', 'user', target, { value: !!body.value });
    return json({ ok: true });
  }

  if (action === 'add_top_up') {
    const target = body.userId;
    const amount = asInt(body.amount, -1000, 1000);
    if (!isUUID(target) || amount === null || amount === 0) return json({ error: 'bad_request' }, 400);
    const cur = await getOne('entitlements', `user_id=eq.${target}&select=top_up`);
    const next = Math.max(0, Number(cur?.top_up ?? 0) + amount);
    const res = await upsertEnt({ user_id: target, top_up: next });
    if (!res.ok) { console.error('add_top_up', res.status, await res.text()); return json({ error: 'update_failed' }, 502); }
    await audit('add_top_up', 'user', target, { amount, top_up: next });
    return json({ ok: true, top_up: next });
  }

  if (action === 'reset_quota') {
    const target = body.userId;
    if (!isUUID(target)) return json({ error: 'missing_user' }, 400);
    const res = await upsertEnt({ user_id: target, used: 0, period: nowPeriod() });
    if (!res.ok) { console.error('reset_quota', res.status, await res.text()); return json({ error: 'update_failed' }, 502); }
    await audit('reset_quota', 'user', target, { period: nowPeriod() });
    return json({ ok: true });
  }

  if (action === 'set_trial') {
    const target = body.userId;
    const days = asInt(body.days, 0, 365);
    if (!isUUID(target) || days === null) return json({ error: 'bad_request' }, 400);
    const until = days === 0 ? null : new Date(Date.now() + days * 86400000).toISOString();
    const res = await upsertEnt({ user_id: target, trial_until: until });
    if (!res.ok) { console.error('set_trial', res.status, await res.text()); return json({ error: 'update_failed' }, 502); }
    await audit('set_trial', 'user', target, { days, until });
    return json({ ok: true, trial_until: until });
  }

  // ======================= MODERATION =======================

  if (action === 'hide_content') {
    const table = CONTENT_TABLE[String(body.targetType)];
    if (!table || !isUUID(body.id)) return json({ error: 'bad_request' }, 400);
    const hidden = !!body.hidden;
    const res = await rest(`${table}?id=eq.${body.id}`, {
      method: 'PATCH', body: JSON.stringify({ hidden_at: hidden ? new Date().toISOString() : null }),
    });
    if (!res.ok) { console.error('hide_content', res.status, await res.text()); return json({ error: 'update_failed' }, 502); }
    await audit(hidden ? 'hide_content' : 'unhide_content', String(body.targetType), String(body.id), {});
    return json({ ok: true });
  }

  if (action === 'delete_content') {
    const table = CONTENT_TABLE[String(body.targetType)];
    if (!table || !isUUID(body.id)) return json({ error: 'bad_request' }, 400);
    const res = await rest(`${table}?id=eq.${body.id}`, { method: 'DELETE' });
    if (!res.ok) return json({ error: 'delete_failed' }, 502);
    await audit('delete_content', String(body.targetType), String(body.id), {});
    return json({ ok: true });
  }

  if (action === 'delete_post') {
    if (!isUUID(body.postId)) return json({ error: 'missing_post' }, 400);
    const res = await rest(`posts?id=eq.${body.postId}`, { method: 'DELETE' });
    if (!res.ok) return json({ error: 'delete_failed' }, 502);
    await audit('delete_content', 'post', String(body.postId), {});
    return json({ ok: true });
  }

  if (action === 'delete_report') {
    if (!isUUID(body.reportId)) return json({ error: 'missing_report' }, 400);
    const res = await rest(`content_reports?id=eq.${body.reportId}`, { method: 'DELETE' });
    if (!res.ok) return json({ error: 'delete_failed' }, 502);
    await audit('dismiss_report', 'report', String(body.reportId), {});
    return json({ ok: true });
  }

  // ======================= CATALOG =======================

  if (action === 'catalog_upsert') {
    const recipe = body.recipe;
    if (!recipe || typeof recipe !== 'object') return json({ error: 'bad_request' }, 400);
    const r = recipe as Record<string, unknown>;
    if (typeof r.title !== 'string' || !r.title.trim()) return json({ error: 'title_required' }, 400);
    if (r.id !== undefined && !isUUID(r.id)) return json({ error: 'bad_id' }, 400);
    const res = await rest('catalog_recipes', {
      method: 'POST', headers: { Prefer: 'resolution=merge-duplicates' }, body: JSON.stringify([r]),
    });
    if (!res.ok) { console.error('catalog_upsert', res.status, await res.text()); return json({ error: 'save_failed' }, 502); }
    await audit('catalog_upsert', 'catalog', (r.id as string) ?? null, { title: r.title });
    return json({ ok: true });
  }

  if (action === 'catalog_delete') {
    if (!isUUID(body.id)) return json({ error: 'bad_id' }, 400);
    const res = await rest(`catalog_recipes?id=eq.${body.id}`, { method: 'DELETE' });
    if (!res.ok) return json({ error: 'delete_failed' }, 502);
    await audit('catalog_delete', 'catalog', String(body.id), {});
    return json({ ok: true });
  }

  if (action === 'catalog_set_flags') {
    if (!isUUID(body.id)) return json({ error: 'bad_id' }, 400);
    const patch: Record<string, boolean> = {};
    if (typeof body.featured === 'boolean') patch.featured = body.featured;
    if (typeof body.published === 'boolean') patch.published = body.published;
    if (!Object.keys(patch).length) return json({ error: 'nothing_to_set' }, 400);
    const res = await rest(`catalog_recipes?id=eq.${body.id}`, { method: 'PATCH', body: JSON.stringify(patch) });
    if (!res.ok) return json({ error: 'update_failed' }, 502);
    await audit('catalog_set_flags', 'catalog', String(body.id), patch);
    return json({ ok: true });
  }

  // ======================= GROUPS =======================

  if (action === 'group_upsert') {
    const g: Record<string, unknown> = {};
    for (const k of ['name', 'slug', 'emoji', 'description']) if (typeof body[k] === 'string') g[k] = body[k];
    if (typeof g.name !== 'string' || !g.name.trim()) return json({ error: 'name_required' }, 400);
    if (body.id !== undefined) {
      if (!isUUID(body.id)) return json({ error: 'bad_id' }, 400);
      const res = await rest(`groups?id=eq.${body.id}`, { method: 'PATCH', body: JSON.stringify(g) });
      if (!res.ok) return json({ error: 'update_failed' }, 502);
      await audit('group_upsert', 'group', String(body.id), g);
    } else {
      if (typeof g.slug !== 'string' || !g.slug) return json({ error: 'slug_required' }, 400);
      g.created_by = callerId;
      const res = await rest('groups', { method: 'POST', body: JSON.stringify([g]) });
      if (!res.ok) { console.error('group_upsert', res.status, await res.text()); return json({ error: 'save_failed' }, 502); }
      await audit('group_upsert', 'group', null, g);
    }
    return json({ ok: true });
  }

  if (action === 'group_delete') {
    if (!isUUID(body.id)) return json({ error: 'bad_id' }, 400);
    const res = await rest(`groups?id=eq.${body.id}`, { method: 'DELETE' });
    if (!res.ok) return json({ error: 'delete_failed' }, 502);
    await audit('group_delete', 'group', String(body.id), {});
    return json({ ok: true });
  }

  return json({ error: 'unknown_action' }, 400);
}
