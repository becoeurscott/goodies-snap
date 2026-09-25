/**
 * Guest (anonymous) sessions for goodiesSnap onboarding.
 *
 * Onboarding is value-first: the user pastes a video link and gets a real extracted recipe
 * before they are ever asked for an account. Every AI call runs through the metered proxy,
 * and `functions/ai.ts` rejects a caller with no user token — so "no account yet" and "can
 * run the AI" are contradictory unless somebody stands in for the user. That stand-in is a
 * guest account: a real InsForge user with a machine-generated email, opened on first launch
 * and keyed to a device id the app keeps in the Keychain.
 *
 * Keyed to the device (not random per launch) so an interrupted onboarding resumes on the
 * same account instead of minting a new one — and so deleting and reinstalling the app does
 * not hand out a fresh free quota, because the Keychain survives deletion.
 *
 * InsForge has no in-place anonymous upgrade (its `/api/auth/tokens/anon` mints an anon-ROLE
 * token with no user id, which `ai.ts` rejects, and the profile API cannot change an email or
 * password). So converting is not an upgrade of this row — the app creates a real account and
 * pushes its local state to it, which carries the onboarding recipe across, and then retires
 * the guest.
 *
 * Actions:
 *   start  — create-or-mint a session for a device id. No auth (the anon key only).
 *   retire — delete this guest, once a real account has taken over. Guest token required.
 */

import { createClient } from 'npm:@insforge/sdk';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

const GUEST_EMAIL_DOMAIN = 'guest.goodiessnap.app';

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

async function sha256Hex(input: string): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(input));
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

async function signJWT(
  payload: Record<string, unknown>,
  secret: string,
): Promise<string> {
  const enc = new TextEncoder();
  const header = { alg: 'HS256', typ: 'JWT' };
  const b64 = (buf: ArrayBuffer | Uint8Array) =>
    btoa(String.fromCharCode(...new Uint8Array(buf)))
      .replace(/=/g, '')
      .replace(/\+/g, '-')
      .replace(/\//g, '_');
  const h = b64(enc.encode(JSON.stringify(header)));
  const p = b64(enc.encode(JSON.stringify(payload)));
  const data = enc.encode(`${h}.${p}`);
  const key = await crypto.subtle.importKey(
    'raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  );
  const sig = await crypto.subtle.sign('HMAC', key, data);
  return `${h}.${p}.${b64(sig)}`;
}

/** A UUID the client generated. Anything else is a malformed or hand-rolled caller. */
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export default async function (req: Request) {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  const baseURL = Deno.env.get('INSFORGE_BASE_URL');
  const adminKey = Deno.env.get('API_KEY');
  const anonKey = Deno.env.get('ANON_KEY');
  const jwtSecret = Deno.env.get('JWT_SECRET');
  if (!baseURL || !adminKey || !anonKey || !jwtSecret) {
    return json({ error: 'server_not_configured' }, 503);
  }

  let body: { action?: string; device_id?: string };
  try { body = await req.json(); } catch { return json({ error: 'bad_request' }, 400); }

  const admin = { Authorization: `Bearer ${adminKey}`, 'Content-Type': 'application/json' };

  // ---- retire: a real account has taken over, so this guest is dead weight. ----
  if (body.action === 'retire') {
    const auth = req.headers.get('Authorization') ?? '';
    const token = auth.startsWith('Bearer ') ? auth.slice(7) : '';
    if (!token) return json({ error: 'not_signed_in' }, 401);

    // The user id comes from the caller's own token, never from the body — otherwise one
    // user could clear another's flag.
    let userId: string;
    try {
      const client = createClient({ baseUrl: baseURL, accessToken: token });
      const { data, error } = await client.auth.getCurrentUser();
      if (error || !data?.user?.id) return json({ error: 'not_signed_in' }, 401);
      userId = data.user.id;
    } catch {
      return json({ error: 'not_signed_in' }, 401);
    }

    // The safety property that makes this action harmless: it deletes only a row that is
    // still marked is_guest. A real account presenting its own token here is a no-op, so a
    // bug (or a stolen token) on this path cannot destroy anybody's account.
    const check = await fetch(
      `${baseURL}/api/database/records/profiles?id=eq.${encodeURIComponent(userId)}&select=is_guest&limit=1`,
      { headers: admin },
    );
    const rows = check.ok ? await check.json() : [];
    if (!Array.isArray(rows) || !rows[0]?.is_guest) return json({ retired: false, reason: 'not_a_guest' });

    const del = await fetch(`${baseURL}/api/auth/users`, {
      method: 'DELETE',
      headers: admin,
      body: JSON.stringify({ userIds: [userId] }),
    });
    if (!del.ok) {
      const detail = await del.text();
      console.error('guest retire failed', del.status, detail);
      return json({ error: 'retire_failed' }, 502);
    }
    return json({ retired: true });
  }

  // ---- start: create-or-mint the device's guest session. ----
  if (body.action && body.action !== 'start') return json({ error: 'unknown_action' }, 400);

  const deviceId = body.device_id ?? '';
  if (!UUID_RE.test(deviceId)) return json({ error: 'device_id_required' }, 400);

  // The email and password are derived from the device id and the server secret, so the
  // client never chooses them and cannot sign in as a guest it did not generate.
  const digest = await sha256Hex(`${deviceId}:${adminKey}`);
  const email = `guest_${digest.slice(0, 32)}@${GUEST_EMAIL_DOMAIN}`;
  // Satisfies the project's password policy (>= 8 chars, a digit, a lowercase letter).
  const password = `gst_${digest.slice(32, 56)}_a1`;
  const name = 'Guest';

  const listRes = await fetch(
    `${baseURL}/api/auth/users?email=${encodeURIComponent(email)}`,
    { headers: admin },
  );
  const listBody = listRes.ok ? await listRes.json() : [];
  const users = Array.isArray(listBody) ? listBody : (listBody?.users ?? listBody?.data ?? []);
  const existing = users[0];

  let userId: string;
  let accessToken: string;
  let refreshToken: string;
  let isNew = false;

  if (existing?.id) {
    // Returning device — mint a JWT directly. The device id plus the server secret is what
    // proves ownership here; the password is derived, never transmitted by the client.
    userId = existing.id;
    const now = Math.floor(Date.now() / 1000);
    accessToken = await signJWT(
      { sub: userId, email, iat: now, exp: now + 3600, iss: 'insforge', 'x-insforge-role': 'authenticated' },
      jwtSecret,
    );
    refreshToken = await signJWT(
      { sub: userId, email, iat: now, exp: now + 30 * 24 * 3600, iss: 'insforge', type: 'refresh' },
      jwtSecret,
    );
  } else {
    const createRes = await fetch(`${baseURL}/api/auth/users?client_type=mobile`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${anonKey}` },
      body: JSON.stringify({ email, password, name }),
    });
    if (!createRes.ok) {
      const detail = await createRes.text();
      console.error('guest: user creation failed', createRes.status, detail);
      return json({ error: 'guest_creation_failed' }, 500);
    }
    const created = await createRes.json();
    userId = created.id ?? created.user?.id;
    isNew = true;

    if (created.accessToken) {
      accessToken = created.accessToken;
      refreshToken = created.refreshToken;
    } else {
      const sessionRes = await fetch(`${baseURL}/api/auth/sessions?client_type=mobile`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${anonKey}` },
        body: JSON.stringify({ method: 'password', email, password }),
      });
      if (!sessionRes.ok) {
        const detail = await sessionRes.text();
        console.error('guest: session creation failed', sessionRes.status, detail);
        return json({ error: 'guest_session_failed' }, 500);
      }
      const session = await sessionRes.json();
      accessToken = session.accessToken;
      refreshToken = session.refreshToken;
    }
  }

  // Mark the profile. Done with the service key because is_guest is guarded against
  // end-user writes. Best-effort: a failed mark must not block onboarding.
  const mark = await fetch(
    `${baseURL}/api/database/records/profiles?id=eq.${encodeURIComponent(userId)}`,
    { method: 'PATCH', headers: admin, body: JSON.stringify({ is_guest: true, display_name: name }) },
  );
  if (!mark.ok) console.error('guest: profile mark failed', mark.status, await mark.text());

  return json({
    accessToken,
    refreshToken,
    user: { id: userId, name },
    is_new_guest: isNew,
  });
}
