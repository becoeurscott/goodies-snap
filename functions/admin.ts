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
 *   Support:    support_reply, support_close, support_set_status, support_article_upsert, support_article_delete,
 *               support_app_update
 */

// Defence in depth: this function is already bearer-authed and admin-gated, but there's no
// reason for any origin other than the control room to call it from a browser.
// The control room is served from InsForge hosting; goodiessnap.com is kept for when it moves.
const ALLOWED_ORIGINS = new Set([
  'https://j7pth4qn.insforge.site',
  'https://admin.goodiessnap.com',
  'https://goodiessnap.com',
  'https://www.goodiessnap.com',
]);
const CORS = {
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  'Vary': 'Origin',
};

/** Echoes the caller's origin back only when it is one of ours; anything else gets no CORS grant. */
function withCors(res: Response, origin: string | null): Response {
  const headers = new Headers(res.headers);
  if (origin && ALLOWED_ORIGINS.has(origin)) headers.set('Access-Control-Allow-Origin', origin);
  return new Response(res.body, { status: res.status, headers });
}

const BUCKET = 'post-images';
const PLANS = new Set(['free', 'plus', 'pro']);
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Role tiers. A legacy owner (is_admin=true, admin_role=null) resolves to SUPER_ADMIN.
const ROLE_RANK: Record<string, number> = {
  READ_ONLY: 0, SUPPORT: 1, MODERATOR: 2, ADMIN: 3, SUPER_ADMIN: 4,
};
// Minimum role required per action. Anything not listed defaults to SUPER_ADMIN (deny by
// default for unknown actions).
const PERMISSIONS: Record<string, string> = {
  set_plan: 'SUPPORT', add_top_up: 'SUPPORT', reset_quota: 'SUPPORT', set_trial: 'SUPPORT',
  hide_content: 'MODERATOR', delete_content: 'MODERATOR', delete_post: 'MODERATOR', delete_report: 'MODERATOR',
  catalog_upsert: 'ADMIN', catalog_delete: 'ADMIN', catalog_set_flags: 'ADMIN',
  group_upsert: 'ADMIN', group_delete: 'ADMIN', delete_user: 'ADMIN',
  set_admin: 'ADMIN', set_role: 'SUPER_ADMIN',
  config_upsert: 'ADMIN', config_rollback: 'ADMIN', maintenance_set: 'ADMIN', broadcast_create: 'ADMIN',
  support_reply: 'SUPPORT', support_close: 'SUPPORT', support_set_status: 'SUPPORT', support_article_upsert: 'SUPPORT',
  support_article_delete: 'ADMIN', support_app_update: 'ADMIN',
};
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
  return withCors(await handle(req), req.headers.get('Origin'));
}

async function handle(req: Request): Promise<Response> {
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
  let callerRole = '';
  try {
    const meRes = await fetch(
      `${baseURL}/api/database/records/profiles?id=eq.${callerId}&select=is_admin,admin_role,display_name&limit=1`,
      { headers: admin },
    );
    const me = await meRes.json();
    if (!Array.isArray(me) || !me[0]?.is_admin) return json({ error: 'not_admin' }, 403);
    actorName = me[0].display_name || '';
    // Legacy owners with no explicit role are full SUPER_ADMIN.
    callerRole = me[0].admin_role || 'SUPER_ADMIN';
  } catch {
    return json({ error: 'not_admin' }, 403);
  }

  const action = String(body.action || '');
  // Permission gate: unknown actions require SUPER_ADMIN (deny by default).
  const needRole = PERMISSIONS[action] ?? 'SUPER_ADMIN';
  if ((ROLE_RANK[callerRole] ?? -1) < ROLE_RANK[needRole]) return json({ error: 'insufficient_role' }, 403);

  // An admin may never act on themselves or on a peer/higher role. Used for role changes and
  // account deletion. Reads the target's rank with the service key.
  async function guardTarget(targetId: string): Promise<Response | null> {
    if (targetId === callerId) return json({ error: 'cannot_target_self' }, 400);
    const t = await getOne('profiles', `id=eq.${targetId}&select=is_admin,admin_role`);
    const targetRole = t?.is_admin ? (String(t.admin_role || 'SUPER_ADMIN')) : null;
    if (targetRole && (ROLE_RANK[callerRole] ?? -1) <= (ROLE_RANK[targetRole] ?? 99)) {
      return json({ error: 'target_outranks_you' }, 403);
    }
    return null;
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

  // ======================= USERS =======================

  if (action === 'delete_user') {
    const target = body.userId;
    if (!isUUID(target)) return json({ error: 'missing_user' }, 400);
    const blocked = await guardTarget(target); if (blocked) return blocked;

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
    const blocked = await guardTarget(target); if (blocked) return blocked;
    // Grant = ADMIN tier; revoke = clear both flags. Keeps the is_admin invariant.
    const grant = !!body.value;
    const patch = grant ? { is_admin: true, admin_role: 'ADMIN' } : { is_admin: false, admin_role: null };
    const res = await rest(`profiles?id=eq.${target}`, { method: 'PATCH', body: JSON.stringify(patch) });
    if (!res.ok) { console.error('set_admin', res.status, await res.text()); return json({ error: 'update_failed' }, 502); }
    await audit('set_admin', 'user', target, { value: grant });
    return json({ ok: true });
  }

  if (action === 'set_role') {
    const target = body.userId, role = String(body.role || '');
    if (!isUUID(target)) return json({ error: 'missing_user' }, 400);
    if (role !== '' && !(role in ROLE_RANK)) return json({ error: 'bad_role' }, 400);
    const blocked = await guardTarget(target); if (blocked) return blocked;
    // Can't assign a role at or above your own (a SUPER_ADMIN can assign anything incl. SUPER_ADMIN).
    if (role && ROLE_RANK[role] > ROLE_RANK[callerRole]) return json({ error: 'cannot_grant_above_self' }, 403);
    // Assigning a role sets is_admin=true (invariant); clearing removes admin entirely.
    const patch = role ? { is_admin: true, admin_role: role } : { is_admin: false, admin_role: null };
    const res = await rest(`profiles?id=eq.${target}`, { method: 'PATCH', body: JSON.stringify(patch) });
    if (!res.ok) { console.error('set_role', res.status, await res.text()); return json({ error: 'update_failed' }, 502); }
    await audit('set_role', 'user', target, { role: role || null });
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

  // ======================= PLATFORM CONTROLS =======================

  if (action === 'config_upsert') {
    const key = String(body.key || '');
    if (!key || typeof body.value !== 'object' || body.value === null) return json({ error: 'bad_request' }, 400);
    const isPublic = !!body.is_public;
    const cur = await getOne('app_config', `key=eq.${encodeURIComponent(key)}&select=version,value`);
    const version = (Number(cur?.version) || 0) + 1;
    // Snapshot the previous value first (if any) so it can be rolled back to.
    if (cur) {
      await rest('app_config_history', { method: 'POST',
        body: JSON.stringify([{ config_key: key, value: cur.value, version: Number(cur.version) || 0, created_by: callerId }]) });
    }
    const res = await rest('app_config', {
      method: 'POST', headers: { Prefer: 'resolution=merge-duplicates' },
      body: JSON.stringify([{ key, value: body.value, is_public: isPublic, version, updated_by: callerId, updated_at: new Date().toISOString() }]),
    });
    if (!res.ok) { console.error('config_upsert', res.status, await res.text()); return json({ error: 'save_failed' }, 502); }
    await audit('config_upsert', 'config', key, { version, is_public: isPublic });
    return json({ ok: true, version });
  }

  if (action === 'config_rollback') {
    const key = String(body.key || '');
    const version = asInt(body.version, 1, 1e9);
    if (!key || version === null) return json({ error: 'bad_request' }, 400);
    const snap = await getOne('app_config_history', `config_key=eq.${encodeURIComponent(key)}&version=eq.${version}&select=value`);
    if (!snap) return json({ error: 'version_not_found' }, 404);
    const cur = await getOne('app_config', `key=eq.${encodeURIComponent(key)}&select=version,value,is_public`);
    const nextVersion = (Number(cur?.version) || 0) + 1;
    if (cur) {
      await rest('app_config_history', { method: 'POST',
        body: JSON.stringify([{ config_key: key, value: cur.value, version: Number(cur.version) || 0, created_by: callerId }]) });
    }
    const res = await rest('app_config', {
      method: 'POST', headers: { Prefer: 'resolution=merge-duplicates' },
      body: JSON.stringify([{ key, value: snap.value, is_public: cur?.is_public ?? false, version: nextVersion, updated_by: callerId, updated_at: new Date().toISOString() }]),
    });
    if (!res.ok) return json({ error: 'rollback_failed' }, 502);
    await audit('config_rollback', 'config', key, { restored_from: version, version: nextVersion });
    return json({ ok: true, version: nextVersion });
  }

  if (action === 'maintenance_set') {
    const enabled = !!body.enabled;
    const message = typeof body.message === 'string' ? body.message : '';
    const minBuild = asInt(body.min_build, 0, 1e9) ?? 0;
    const res = await rest('maintenance_state?id=eq.true', {
      method: 'PATCH',
      body: JSON.stringify({ enabled, message, min_build: minBuild, updated_by: callerId, updated_at: new Date().toISOString() }),
    });
    if (!res.ok) { console.error('maintenance_set', res.status, await res.text()); return json({ error: 'update_failed' }, 502); }
    await audit('maintenance_set', 'maintenance', null, { enabled, min_build: minBuild });
    return json({ ok: true });
  }

  if (action === 'broadcast_create') {
    const title = String(body.title || '').trim();
    if (!title) return json({ error: 'title_required' }, 400);
    const row = {
      title, body: typeof body.body === 'string' ? body.body : '',
      kind: typeof body.kind === 'string' ? body.kind : 'announcement',
      audience: (body.audience && typeof body.audience === 'object') ? body.audience : {},
      created_by: callerId,
    };
    const res = await rest('broadcasts', { method: 'POST', body: JSON.stringify([row]) });
    if (!res.ok) { console.error('broadcast_create', res.status, await res.text()); return json({ error: 'save_failed' }, 502); }
    await audit('broadcast_create', 'broadcast', null, { title, kind: row.kind });
    return json({ ok: true });
  }

  // ======================= SUPPORT =======================

  if (action === 'support_reply') {
    const id = body.conversationId;
    const text = typeof body.text === 'string' ? body.text.trim().slice(0, 4000) : '';
    if (!isUUID(id) || !text) return json({ error: 'bad_request' }, 400);
    const conv = await getOne('support_conversations', `id=eq.${id}&select=id,status`);
    if (!conv) return json({ error: 'not_found' }, 404);
    const at = new Date().toISOString();
    const res = await rest('support_messages', {
      method: 'POST',
      body: JSON.stringify([{ conversation_id: id, sender: 'agent', author_id: callerId, author_name: actorName || 'goodiesSnap team', body: text, created_at: at }]),
    });
    if (!res.ok) { console.error('support_reply', res.status, await res.text()); return json({ error: 'save_failed' }, 502); }
    // A person answered: the assistant stays quiet in this conversation until it's handed back.
    await rest(`support_conversations?id=eq.${id}`, {
      method: 'PATCH', body: JSON.stringify({ status: 'human', assigned_to: callerId, last_message_at: at }),
    });
    await audit('support_reply', 'support_conversation', id, { length: text.length });
    return json({ ok: true });
  }

  if (action === 'support_set_status') {
    const id = body.conversationId;
    const status = String(body.status || '');
    // 'ai' hands the conversation back to the assistant; 'closed' resolves it.
    if (!isUUID(id) || !['ai', 'needs_human', 'closed'].includes(status)) return json({ error: 'bad_request' }, 400);
    const res = await rest(`support_conversations?id=eq.${id}`, {
      method: 'PATCH', body: JSON.stringify({ status, ...(status === 'ai' ? { handoff_reason: null } : {}) }),
    });
    if (!res.ok) return json({ error: 'update_failed' }, 502);
    await audit('support_set_status', 'support_conversation', id, { status });
    return json({ ok: true });
  }

  if (action === 'support_article_upsert') {
    const appId = String(body.app_id || '');
    const title = typeof body.title === 'string' ? body.title.trim() : '';
    const text = typeof body.body === 'string' ? body.body.trim() : '';
    if (!/^[a-z0-9-]{2,32}$/.test(appId) || !title || title.length > 200 || !text || text.length > 8000) {
      return json({ error: 'bad_request' }, 400);
    }
    const row = { app_id: appId, title, body: text, active: body.active !== false, updated_by: callerId };
    // Editing title/body clears the stored embedding (DB trigger); the support function
    // re-embeds it on the next customer question.
    const res = body.id !== undefined && body.id !== null && body.id !== ''
      ? (isUUID(body.id)
        ? await rest(`support_articles?id=eq.${body.id}`, { method: 'PATCH', body: JSON.stringify(row) })
        : null)
      : await rest('support_articles', { method: 'POST', body: JSON.stringify([row]) });
    if (!res) return json({ error: 'bad_id' }, 400);
    if (!res.ok) { console.error('support_article_upsert', res.status, await res.text()); return json({ error: 'save_failed' }, 502); }
    await audit('support_article_upsert', 'support_article', isUUID(body.id) ? body.id : null, { app_id: appId, title });
    return json({ ok: true });
  }

  if (action === 'support_article_delete') {
    if (!isUUID(body.id)) return json({ error: 'bad_id' }, 400);
    const res = await rest(`support_articles?id=eq.${body.id}`, { method: 'DELETE' });
    if (!res.ok) return json({ error: 'delete_failed' }, 502);
    await audit('support_article_delete', 'support_article', String(body.id), {});
    return json({ ok: true });
  }

  if (action === 'support_app_update') {
    const appId = String(body.id || '');
    if (!/^[a-z0-9-]{2,32}$/.test(appId)) return json({ error: 'bad_request' }, 400);
    const patch: Record<string, unknown> = { updated_at: new Date().toISOString() };
    if (typeof body.instructions === 'string') patch.instructions = body.instructions.slice(0, 20000);
    if (typeof body.handoff_message === 'string' && body.handoff_message.trim()) patch.handoff_message = body.handoff_message.trim().slice(0, 500);
    if (typeof body.chat_model === 'string' && /^[\w.:\/-]{1,80}$/.test(body.chat_model)) patch.chat_model = body.chat_model;
    if (typeof body.enabled === 'boolean') patch.enabled = body.enabled;
    const res = await rest(`support_apps?id=eq.${appId}`, { method: 'PATCH', body: JSON.stringify(patch) });
    if (!res.ok) { console.error('support_app_update', res.status, await res.text()); return json({ error: 'update_failed' }, 502); }
    await audit('support_app_update', 'support_app', appId, { fields: Object.keys(patch).filter((k) => k !== 'updated_at') });
    return json({ ok: true });
  }

  if (action === 'support_close') {
    const convId = body.conversationId;
    if (!isUUID(convId)) return json({ error: 'missing_conversation' }, 400);
    const res = await rest(`support_conversations?id=eq.${convId}`, {
      method: 'PATCH', body: JSON.stringify({ status: 'closed' }),
    });
    if (!res.ok) return json({ error: 'save_failed' }, 502);
    await audit('support_close', 'support_conversation', convId);
    return json({ ok: true });
  }

  return json({ error: 'unknown_action' }, 400);
}
