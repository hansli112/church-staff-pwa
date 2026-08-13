// Shared fixtures for the Pages Functions tests.
//
// No dependencies on purpose: Node 22 already provides fetch/Response/Headers,
// WebCrypto and atob/btoa, which is the same surface the Workers runtime gives
// the functions. Adding a Miniflare/wrangler dev server would test the same code
// far more slowly.

export const CALENDAR_ID = 'church@group.calendar.google.com';
export const PROJECT_ID = 'demo-church-staff';
export const ADMIN_UID = 'admin-uid';
export const MEMBER_UID = 'member-uid';

function base64Url(bytes) {
  let binary = '';
  for (const byte of new Uint8Array(bytes)) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/// A structurally valid Firebase ID token. The signature is nonsense because
/// nothing in the Worker verifies it — Firestore does, and Firestore is faked
/// here. See the comment on uidFromIdToken.
export function idToken(uid) {
  const header = base64Url(new TextEncoder().encode(JSON.stringify({ alg: 'RS256' })));
  const payload = base64Url(new TextEncoder().encode(JSON.stringify({ sub: uid })));
  return `${header}.${payload}.signature`;
}

let cachedServiceAccount = null;

/// Generates a real RSA key so the JWT signing path runs for real rather than
/// being stubbed out — a malformed PEM or a wrong algorithm would slip through
/// a stub.
export async function serviceAccountJson() {
  if (cachedServiceAccount) return cachedServiceAccount;
  const pair = await crypto.subtle.generateKey(
    {
      name: 'RSASSA-PKCS1-v1_5',
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: 'SHA-256',
    },
    true,
    ['sign', 'verify'],
  );
  const pkcs8 = await crypto.subtle.exportKey('pkcs8', pair.privateKey);
  const body = base64Url(pkcs8).replace(/-/g, '+').replace(/_/g, '/');
  const pem = `-----BEGIN PRIVATE KEY-----\n${body}\n-----END PRIVATE KEY-----\n`;
  cachedServiceAccount = JSON.stringify({
    client_email: 'calendar-writer@demo.iam.gserviceaccount.com',
    private_key: pem,
  });
  return cachedServiceAccount;
}

export async function testEnv(overrides = {}) {
  return {
    FIREBASE_PROJECT_ID: PROJECT_ID,
    GOOGLE_CALENDAR_ID: CALENDAR_ID,
    GOOGLE_SERVICE_ACCOUNT_JSON: await serviceAccountJson(),
    ...overrides,
  };
}

export function request(method, { token = idToken(ADMIN_UID), body } = {}) {
  return new Request('https://app.example/api/calendar/events', {
    method,
    headers: {
      ...(token === null ? {} : { Authorization: `Bearer ${token}` }),
      ...(body === undefined ? {} : { 'content-type': 'application/json' }),
    },
    ...(body === undefined
      ? {}
      : { body: typeof body === 'string' ? body : JSON.stringify(body) }),
  });
}

/// Routes the three upstreams the functions talk to. Every call is recorded so
/// a test can assert what was actually sent to Google, not just what came back.
export function fakeFetch({ roles = { [ADMIN_UID]: 'admin', [MEMBER_UID]: 'member' }, calendar } = {}) {
  const calls = [];

  const impl = async (url, init = {}) => {
    const target = String(url);
    calls.push({ url: target, method: init.method ?? 'GET', body: init.body, init });

    if (target.startsWith('https://oauth2.googleapis.com/token')) {
      return Response.json({ access_token: 'test-access-token', expires_in: 3600 });
    }

    if (target.startsWith('https://firestore.googleapis.com/')) {
      const uid = decodeURIComponent(target.split('/documents/users/')[1].split('?')[0]);
      if (!(uid in roles)) return new Response('{}', { status: 404 });
      const role = roles[uid];
      if (role === null) return Response.json({ name: `users/${uid}`, fields: {} });
      return Response.json({ name: `users/${uid}`, fields: { role: { stringValue: role } } });
    }

    if (target.startsWith('https://www.googleapis.com/calendar/')) {
      if (typeof calendar === 'function') return calendar(target, init);
      return Response.json({ id: 'created-event-id', status: 'confirmed' }, { status: 200 });
    }

    throw new Error(`unexpected fetch to ${target}`);
  };

  impl.calls = calls;
  impl.calendarCalls = () =>
    calls.filter((call) => call.url.startsWith('https://www.googleapis.com/calendar/'));
  return impl;
}

/// Silences the console.error calls the functions make on the failure paths, so
/// expected failures do not bury the real test output.
export function muteConsoleError() {
  const original = console.error;
  console.error = () => {};
  return () => {
    console.error = original;
  };
}
