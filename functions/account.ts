import { createClient } from 'npm:@insforge/sdk';

/**
 * goodiesSnap account deletion (App Store guideline 5.1.1(v)).
 *
 * Deletion has to run server-side: the client cannot be trusted to erase its own rows,
 * and removing the auth user needs an admin credential that must never ship in the app.
 * Every social table references auth.users(id) ON DELETE CASCADE, so removing the user
 * takes profiles, posts, likes, comments, group memberships, blocks, reports,
 * entitlements and AI usage with it.
 *
 * Storage is NOT covered by that cascade, so uploaded photos are deleted first. They are
 * removed before the account rather than after, because once the user is gone we can no
 * longer prove which objects were theirs.
 */

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

const BUCKET = 'post-images';

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
  // Checked before anything is touched: a half-configured server must not partially
  // delete an account.
  if (!baseURL || !adminKey) return json({ error: 'server_not_configured' }, 503);

  const auth = req.headers.get('Authorization') ?? '';
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  if (!token) return json({ error: 'not_signed_in' }, 401);

  let body: { action?: string; confirm?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'bad_request' }, 400);
  }
  if (body.action !== 'delete') return json({ error: 'unknown_action' }, 400);
  // A deliberate second signal, so a stray POST can never erase an account.
  if (body.confirm !== 'DELETE') return json({ error: 'confirmation_required' }, 400);

  // Identify the caller from their own token: the user id is never taken from the
  // request body, or one user could delete another.
  const client = createClient({ baseUrl: baseURL, accessToken: token });
  let userId: string;
  try {
    const { data, error } = await client.auth.getCurrentUser();
    if (error || !data?.user?.id) return json({ error: 'not_signed_in' }, 401);
    userId = data.user.id;
  } catch {
    return json({ error: 'not_signed_in' }, 401);
  }

  const admin = { Authorization: `Bearer ${adminKey}`, 'Content-Type': 'application/json' };

  // 1. Photos. Best-effort: a storage hiccup must not strand the user with an account
  // they have asked us to delete, so we record the failure and continue.
  let photosDeleted = 0;
  let photosFailed = false;
  try {
    const list = await fetch(
      `${baseURL}/api/storage/buckets/${BUCKET}/objects?prefix=${encodeURIComponent(userId)}/&limit=1000`,
      { headers: admin },
    );
    if (list.ok) {
      const payload = await list.json();
      const objects: string[] = (payload?.objects ?? payload?.data ?? payload ?? [])
        .map((o: { key?: string; name?: string }) => o?.key ?? o?.name)
        .filter((k: string | undefined): k is string => typeof k === 'string')
        // Defence in depth: only ever objects under this user's own prefix.
        .filter((k: string) => k.startsWith(`${userId}/`));
      for (const key of objects) {
        const del = await fetch(
          `${baseURL}/api/storage/buckets/${BUCKET}/objects/${encodeURIComponent(key)}`,
          { method: 'DELETE', headers: admin },
        );
        if (del.ok) photosDeleted++;
        else photosFailed = true;
      }
    } else {
      photosFailed = true;
    }
  } catch {
    photosFailed = true;
  }

  // 2. The account itself. Everything else cascades from this row.
  const res = await fetch(`${baseURL}/api/auth/users`, {
    method: 'DELETE',
    headers: admin,
    body: JSON.stringify({ userIds: [userId] }),
  });
  if (!res.ok) {
    const detail = await res.text();
    console.error('account delete failed', res.status, detail);
    return json({ error: 'delete_failed' }, 502);
  }

  console.log(`deleted account ${userId} (photos: ${photosDeleted}, storage_errors: ${photosFailed})`);
  return json({ deleted: true, photos_deleted: photosDeleted, photos_failed: photosFailed });
}
