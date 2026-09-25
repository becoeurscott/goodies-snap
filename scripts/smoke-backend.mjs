import { readFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';

const source = readFileSync(new URL('../goodiesSnap/SocialService.swift', import.meta.url), 'utf8');
const base = source.match(/static let baseURL = URL\(string: "([^"]+)"/)[1];
const anon = source.match(/static let anonKey = "([^"]+)"/)[1];
const info = new URL('../fastlane/metadata/review_information/', import.meta.url);
async function request(url, body, token = anon) {
  const response = await fetch(url, { method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify(body), signal: AbortSignal.timeout(90000) });
  const data = await response.json();
  return { status: response.status, data };
}
const login = await request(`${base}/api/auth/sessions?client_type=mobile`, {
  method: 'password', email: readFileSync(new URL('demo_user.txt', info), 'utf8').trim(),
  password: readFileSync(new URL('demo_password.txt', info), 'utf8').trim()
});
console.log('Review account sign-in:', login.status, login.data.error || 'OK');
if (login.status === 401 && process.argv.includes('--create-review-account')) {
  const created = await request(`${base}/api/auth/users?client_type=mobile`, {
    email: readFileSync(new URL('demo_user.txt', info), 'utf8').trim(),
    password: readFileSync(new URL('demo_password.txt', info), 'utf8').trim(), name: 'App Review'
  });
  console.log('Review account setup:', created.status, created.data.error || 'OK');
}
const guest = await request(`${base}/functions/guest`, { action: 'start', device_id: randomUUID() });
console.log('Guest session:', guest.status, guest.data.error || 'OK');
const token = guest.data.accessToken || guest.data.access_token || guest.data.token;
if (!token || guest.data.is_new_guest !== true) {
  console.log('Refusing further tests: a fresh device must receive a new guest identity.');
  process.exitCode = 1;
} else {
  try {
    const ai = await request(`${base}/functions/ai`, { action: 'extract', content: 'Tomato toast: serves 1. Toast 2 slices of bread for 3 minutes. Slice 1 tomato. Top the toast with tomato, 1 teaspoon olive oil and a pinch of salt. Serve immediately.' }, token);
    console.log('AI recipe:', ai.status, ai.data.error || ai.data.data?.title || 'OK');
    if (ai.status !== 200) console.log('AI failure:', JSON.stringify(ai.data));
    const purchase = await request(`${base}/functions/purchase`, { signed_transaction: 'invalid-test-receipt' }, token);
    console.log('Invalid receipt rejected:', purchase.status, purchase.data.error);
  } finally {
    const retired = await request(`${base}/functions/guest`, { action: 'retire' }, token);
    console.log('Test guest removed:', retired.status, retired.data.retired ?? retired.data.error);
  }
}
