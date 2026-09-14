/**
 * Google Sign-In for goodiesSnap.
 *
 * The iOS app sends the Google ID token from the Google Sign-In SDK.
 * This function verifies the token with Google, creates or finds the InsForge
 * user, creates a session, and returns the same shape the app already expects.
 *
 * For NEW users: creates the account with a server-side password and signs in.
 * For EXISTING users: updates their password (the Google token proves email
 * ownership) and signs in. This means an email+password user who switches to
 * Google sign-in will need Google (or a password reset) going forward.
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

export default async function (req: Request) {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  const baseURL = Deno.env.get('INSFORGE_BASE_URL');
  const adminKey = Deno.env.get('API_KEY');
  const googleClientID = Deno.env.get('GOOGLE_CLIENT_ID');
  if (!baseURL || !adminKey) return json({ error: 'server_not_configured' }, 503);

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

  if (googleClientID && gUser.aud !== googleClientID) {
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

  if (existing?.id) {
    userId = existing.id;
    // Set the password so we can create a session. The Google token already
    // proved email ownership, so this is equivalent to a verified password reset.
    await fetch(`${baseURL}/api/auth/users/${userId}`, {
      method: 'PATCH',
      headers: admin,
      body: JSON.stringify({ password }),
    });
  } else {
    // 3. Create a new user.
    const createRes = await fetch(`${baseURL}/api/auth/users`, {
      method: 'POST',
      headers: admin,
      body: JSON.stringify({ email, password, name, email_verified: true }),
    });
    if (!createRes.ok) {
      const detail = await createRes.text();
      console.error('google-auth: user creation failed', createRes.status, detail);
      return json({ error: 'user_creation_failed' }, 500);
    }
    const created = await createRes.json();
    userId = created.id ?? created.user?.id;
    isNew = true;
  }

  // 4. Create a session via the normal sign-in endpoint.
  const sessionRes = await fetch(`${baseURL}/api/auth/sessions?client_type=web`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${adminKey}` },
    body: JSON.stringify({ method: 'password', email, password }),
  });
  if (!sessionRes.ok) {
    const detail = await sessionRes.text();
    console.error('google-auth: session creation failed', sessionRes.status, detail);
    return json({ error: 'session_creation_failed' }, 500);
  }
  const session = await sessionRes.json();

  return json({
    accessToken: session.accessToken,
    refreshToken: session.refreshToken,
    user: { id: userId, name },
    is_new_user: isNew,
  });
}
