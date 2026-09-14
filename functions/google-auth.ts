/**
 * Google Sign-In for goodiesSnap.
 *
 * The iOS app sends the Google ID token from the Google Sign-In SDK.
 * This function verifies the token with Google, creates or finds the InsForge
 * user, and returns session tokens.
 *
 * For NEW users: creates the account and uses the tokens from the creation response.
 * For EXISTING users: mints a JWT directly using the JWT_SECRET (the Google token
 * already proves email ownership, so this is a verified identity assertion).
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

function serverPassword(googleSub: string, secret: string): string {
  return `gsi_${googleSub}_${secret.slice(0, 16)}`;
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

export default async function (req: Request) {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  const baseURL = Deno.env.get('INSFORGE_BASE_URL');
  const adminKey = Deno.env.get('API_KEY');
  const anonKey = Deno.env.get('ANON_KEY');
  const jwtSecret = Deno.env.get('JWT_SECRET');
  const googleClientID = Deno.env.get('GOOGLE_CLIENT_ID');
  const googleIOSClientID = Deno.env.get('GOOGLE_IOS_CLIENT_ID');
  if (!baseURL || !adminKey || !anonKey || !jwtSecret)
    return json({ error: 'server_not_configured' }, 503);

  let body: { id_token?: string; name?: string };
  try { body = await req.json(); } catch { return json({ error: 'bad_request' }, 400); }

  const idToken = body.id_token;
  if (!idToken) return json({ error: 'id_token_required' }, 400);

  // 1. Verify the Google ID token with Google's endpoint.
  const verifyRes = await fetch(
    `https://oauth2.googleapis.com/tokeninfo?id_token=${encodeURIComponent(idToken)}`,
  );
  if (!verifyRes.ok) return json({ error: 'invalid_google_token' }, 401);
  const gUser = await verifyRes.json();

  const allowedAudiences = [googleClientID, googleIOSClientID].filter(Boolean);
  if (allowedAudiences.length > 0 && !allowedAudiences.includes(gUser.aud)) {
    return json({ error: 'token_audience_mismatch' }, 401);
  }

  const email = gUser.email as string | undefined;
  if (!email) return json({ error: 'no_email_in_token' }, 400);
  const name = body.name || (gUser.name as string) || 'Cook';
  const googleSub = gUser.sub as string;
  const password = serverPassword(googleSub, adminKey);
  const admin = { Authorization: `Bearer ${adminKey}`, 'Content-Type': 'application/json' };

  // 2. Look up existing user by email.
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
    // Existing user — mint a JWT directly. The Google token already proved
    // email ownership, so this is a verified identity assertion.
    userId = existing.id;
    const now = Math.floor(Date.now() / 1000);
    const accessPayload = {
      sub: userId,
      email,
      iat: now,
      exp: now + 3600,
      iss: 'insforge',
      'x-insforge-role': 'authenticated',
    };
    const refreshPayload = {
      sub: userId,
      email,
      iat: now,
      exp: now + 30 * 24 * 3600,
      iss: 'insforge',
      type: 'refresh',
    };
    accessToken = await signJWT(accessPayload, jwtSecret);
    refreshToken = await signJWT(refreshPayload, jwtSecret);
  } else {
    // 3. Create a new user and sign in with the deterministic password.
    const createRes = await fetch(`${baseURL}/api/auth/users?client_type=mobile`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${anonKey}` },
      body: JSON.stringify({ email, password, name }),
    });
    if (!createRes.ok) {
      const detail = await createRes.text();
      console.error('google-auth: user creation failed', createRes.status, detail);
      return json({ error: 'user_creation_failed' }, 500);
    }
    const created = await createRes.json();
    userId = created.id ?? created.user?.id;
    isNew = true;

    // The creation response may already include tokens.
    if (created.accessToken) {
      accessToken = created.accessToken;
      refreshToken = created.refreshToken;
    } else {
      // Sign in with the password we just set.
      const sessionRes = await fetch(`${baseURL}/api/auth/sessions?client_type=mobile`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${anonKey}` },
        body: JSON.stringify({ method: 'password', email, password }),
      });
      if (!sessionRes.ok) {
        const detail = await sessionRes.text();
        console.error('google-auth: session creation failed', sessionRes.status, detail);
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
