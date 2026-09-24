/**
 * Sign in with Apple for goodiesSnap.
 *
 * The iOS app sends Apple's identity token (a JWT signed by Apple) from
 * ASAuthorizationController. This function verifies that token against Apple's public keys,
 * then creates or finds the matching InsForge user and returns session tokens — the same
 * shape google-auth.ts returns, so the client handles both identically.
 *
 * KEYING BY `sub`, NOT EMAIL. Apple only returns the user's email on the *first*
 * authorization; every later sign-in carries only the stable `sub`. Keying the account on
 * a real email would therefore mint a second account on the second sign-in. So the InsForge
 * account is keyed to a deterministic email derived from Apple's `sub` (like the guest
 * function derives one from the device id): the same Apple user always lands on the same
 * account. The real email, when Apple sends it, is kept only as a display fallback.
 *
 * Trade-off: an Apple user is not auto-linked to a pre-existing Google/password account that
 * happens to share the same real email. Cross-provider linking is out of scope and not
 * required for Guideline 4.8 — an equivalent, working Apple login is.
 */

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

const b64url = (buf: ArrayBuffer | Uint8Array) =>
  btoa(String.fromCharCode(...new Uint8Array(buf)))
    .replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');

function b64urlToBytes(s: string): Uint8Array {
  const pad = s.length % 4 === 0 ? '' : '='.repeat(4 - (s.length % 4));
  const b64 = s.replace(/-/g, '+').replace(/_/g, '/') + pad;
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(input));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, '0')).join('');
}

async function signJWT(payload: Record<string, unknown>, secret: string): Promise<string> {
  const enc = new TextEncoder();
  const h = b64url(enc.encode(JSON.stringify({ alg: 'HS256', typ: 'JWT' })));
  const p = b64url(enc.encode(JSON.stringify(payload)));
  const key = await crypto.subtle.importKey(
    'raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  );
  const sig = await crypto.subtle.sign('HMAC', key, enc.encode(`${h}.${p}`));
  return `${h}.${p}.${b64url(sig)}`;
}

interface AppleJWK { kid: string; n: string; e: string; kty: string; alg?: string }

/** Verify Apple's identity token: RS256 signature against Apple's JWKS, plus iss/aud/exp. */
async function verifyAppleToken(
  idToken: string,
  allowedAudiences: string[],
): Promise<{ sub: string; email?: string } | null> {
  // A malformed token is an authentication failure, not a server error — any parse/verify
  // exception below returns null (→ 401), never a 500.
  try {
    const parts = idToken.split('.');
    if (parts.length !== 3) return null;
    const header = JSON.parse(new TextDecoder().decode(b64urlToBytes(parts[0])));
    const claims = JSON.parse(new TextDecoder().decode(b64urlToBytes(parts[1])));

    // Signature: fetch Apple's keys, pick the one named by the token header's kid.
    const jwksRes = await fetch('https://appleid.apple.com/auth/keys');
    if (!jwksRes.ok) return null;
    const { keys } = (await jwksRes.json()) as { keys: AppleJWK[] };
    const jwk = keys.find((k) => k.kid === header.kid);
    if (!jwk) return null;

    const key = await crypto.subtle.importKey(
      'jwk',
      { kty: jwk.kty, n: jwk.n, e: jwk.e, alg: 'RS256', ext: true },
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
      false,
      ['verify'],
    );
    const ok = await crypto.subtle.verify(
      'RSASSA-PKCS1-v1_5',
      key,
      b64urlToBytes(parts[2]),
      new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
    );
    if (!ok) return null;

    // Claims: Apple is the issuer, the token is for THIS app, and it hasn't expired.
    if (claims.iss !== 'https://appleid.apple.com') return null;
    if (allowedAudiences.length > 0 && !allowedAudiences.includes(claims.aud)) return null;
    if (typeof claims.exp === 'number' && claims.exp < Math.floor(Date.now() / 1000)) return null;
    if (!claims.sub) return null;

    return { sub: claims.sub as string, email: claims.email as string | undefined };
  } catch (e) {
    console.error('apple-auth: token verification error', String(e));
    return null;
  }
}

export default async function (req: Request) {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  const baseURL = Deno.env.get('INSFORGE_BASE_URL');
  const adminKey = Deno.env.get('API_KEY');
  const anonKey = Deno.env.get('ANON_KEY');
  const jwtSecret = Deno.env.get('JWT_SECRET');
  if (!baseURL || !adminKey || !anonKey || !jwtSecret)
    return json({ error: 'server_not_configured' }, 503);

  // Accept the app's bundle id (and any extra ids set via APPLE_CLIENT_ID) as the audience.
  const bundleId = Deno.env.get('APPLE_CLIENT_ID') || 'com.goodies.goodiesSnap';
  const allowedAudiences = bundleId.split(',').map((s) => s.trim()).filter(Boolean);
  const emailDomain = Deno.env.get('APPLE_EMAIL_DOMAIN') || 'appleid.goodiessnap.app';

  let body: { identity_token?: string; name?: string };
  try { body = await req.json(); } catch { return json({ error: 'bad_request' }, 400); }

  const idToken = body.identity_token;
  if (!idToken) return json({ error: 'identity_token_required' }, 400);

  const verified = await verifyAppleToken(idToken, allowedAudiences);
  if (!verified) return json({ error: 'invalid_apple_token' }, 401);

  const appleSub = verified.sub;
  // Deterministic account identity from the Apple sub — stable across every sign-in.
  const digest = await sha256Hex(`${appleSub}:${adminKey}`);
  const email = `apple_${digest.slice(0, 32)}@${emailDomain}`;
  const password = `asi_${digest.slice(32, 56)}_a1`;
  const name = body.name || (verified.email as string | undefined) || 'Cook';
  const admin = { Authorization: `Bearer ${adminKey}`, 'Content-Type': 'application/json' };

  const listRes = await fetch(
    `${baseURL}/api/auth/users?email=${encodeURIComponent(email)}`,
    { headers: admin },
  );
  const listBody = listRes.ok ? await listRes.json() : [];
  const users = Array.isArray(listBody) ? listBody : (listBody?.users ?? listBody?.data ?? []);
  const existing = users[0];

  let userId: string;
  let isNew = false;
  let accessToken: string;
  let refreshToken: string;

  if (existing?.id) {
    // Existing Apple user — mint a JWT directly. Apple's verified token is the proof.
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
      console.error('apple-auth: user creation failed', createRes.status, detail);
      return json({ error: 'user_creation_failed' }, 500);
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
        console.error('apple-auth: session creation failed', sessionRes.status, detail);
        return json({ error: 'session_creation_failed' }, 500);
      }
      const session = await sessionRes.json();
      accessToken = session.accessToken;
      refreshToken = session.refreshToken;
    }
  }

  return json({
    accessToken,
    refreshToken,
    user: { id: userId, name },
    is_new_user: isNew,
  });
}
