import { Buffer } from 'node:buffer';
import { createClient } from 'npm:@insforge/sdk';
import {
  Environment,
  SignedDataVerifier,
} from 'npm:@apple/app-store-server-library@1.4.0';

/**
 * goodiesSnap purchase verification.
 *
 * The app sends Apple's signed transaction (JWS). We verify it here rather than trusting
 * the client, because the AI quota is enforced in Postgres and `entitlements.plan` is the
 * thing that decides how much a user can spend. A device that can set its own plan can
 * set its own bill.
 *
 * Verification uses Apple's own library, which validates the full x5c certificate chain
 * up to the pinned Apple Root CA G3 below — hand-rolled JWS parsing is exactly the kind
 * of crypto that looks right and isn't.
 */

// Apple Root CA - G3, SHA-256 63343ABF...653E9179, from apple.com/certificateauthority.
const APPLE_ROOT_CA_G3 = 'MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtfTjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySrMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM6BgD56KyKA==';

const BUNDLE_ID = 'com.goodies.goodiesSnap';

const PLAN_FOR_PRODUCT: Record<string, string> = {
  'com.goodies.goodiesSnap.plus.monthly': 'plus',
  'com.goodies.goodiesSnap.plus.yearly': 'plus',
  'com.goodies.goodiesSnap.pro.monthly': 'pro',
  'com.goodies.goodiesSnap.pro.yearly': 'pro',
};

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

export default async function (req: Request) {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  const baseURL = Deno.env.get('INSFORGE_BASE_URL');
  const adminKey = Deno.env.get('API_KEY');
  if (!baseURL || !adminKey) return json({ error: 'server_not_configured' }, 503);

  const auth = req.headers.get('Authorization') ?? '';
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  if (!token) return json({ error: 'not_signed_in' }, 401);

  let body: { signed_transaction?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'bad_request' }, 400);
  }
  const signed = body.signed_transaction;
  if (!signed || typeof signed !== 'string') return json({ error: 'missing_transaction' }, 400);

  const client = createClient({ baseUrl: baseURL, accessToken: token });
  let userId: string;
  try {
    const { data, error } = await client.auth.getCurrentUser();
    if (error || !data?.user?.id) return json({ error: 'not_signed_in' }, 401);
    userId = data.user.id;
  } catch {
    return json({ error: 'not_signed_in' }, 401);
  }

  // Production needs the numeric App Store id, which only exists once the app record does.
  // Until APP_APPLE_ID is set, sandbox (and therefore TestFlight) still verifies.
  const appAppleId = Number(Deno.env.get('APP_APPLE_ID') ?? '') || undefined;
  const roots = [Buffer.from(APPLE_ROOT_CA_G3, 'base64')];

  const environments: Environment[] = appAppleId
    ? [Environment.PRODUCTION, Environment.SANDBOX]
    : [Environment.SANDBOX];

  let payload: Record<string, unknown> | null = null;
  let usedEnv: Environment | null = null;
  let lastError = '';

  // The same receipt verifies under exactly one environment; try each rather than
  // guessing from an unverified payload field.
  for (const environment of environments) {
    try {
      const verifier = new SignedDataVerifier(roots, true, environment, BUNDLE_ID, appAppleId);
      payload = await verifier.verifyAndDecodeTransaction(signed) as Record<string, unknown>;
      usedEnv = environment;
      break;
    } catch (err) {
      lastError = String((err as Error)?.message ?? err);
    }
  }

  if (!payload || !usedEnv) {
    console.error('transaction verification failed', lastError);
    return json({ error: 'verification_failed' }, 400);
  }

  const productId = String(payload.productId ?? '');
  const plan = PLAN_FOR_PRODUCT[productId];
  if (!plan) return json({ error: 'unknown_product' }, 400);

  const originalId = String(payload.originalTransactionId ?? '');
  if (!originalId) return json({ error: 'verification_failed' }, 400);

  const expiresMs = Number(payload.expiresDate ?? 0);
  const expiresAt = expiresMs ? new Date(expiresMs).toISOString() : null;
  const revoked = Boolean(payload.revocationDate);

  const rpc = await fetch(`${baseURL}/api/database/rpc/apply_app_store_purchase`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${adminKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      p_user: userId,
      p_original_transaction_id: originalId,
      p_product_id: productId,
      p_plan: plan,
      p_environment: usedEnv === Environment.PRODUCTION ? 'Production' : 'Sandbox',
      p_expires_at: expiresAt,
      p_revoked: revoked,
    }),
  });

  if (!rpc.ok) {
    console.error('apply_app_store_purchase failed', rpc.status, await rpc.text());
    return json({ error: 'activation_failed' }, 502);
  }

  const rows = await rpc.json();
  const row = Array.isArray(rows) ? rows[0] : rows;
  const granted = row?.granted_plan ?? 'free';

  if (row?.reason === 'already_bound') {
    // Deliberately explicit: this is a real support case, not a generic failure.
    return json({ error: 'already_bound', plan: 'free' }, 409);
  }

  console.log(`purchase ${productId} -> ${granted} for ${userId} (${usedEnv})`);
  return json({ plan: granted });
}
