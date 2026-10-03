// A Google access token for a service account whose key JSON sits in a
// Cloudflare secret.
//
// Shared by the calendar writer (GOOGLE_SERVICE_ACCOUNT_JSON) and account
// management (ACCOUNT_ADMIN_KEY): two separate accounts with separate grants,
// so a leak of one does not hand over the other. Lives outside functions/ for
// the same reason every helper here does — nothing under functions/ may be
// importable as a route.

import { HttpError, base64UrlToBytes, requireEnv } from './firebase_user.js';

const TOKEN_ENDPOINT = 'https://oauth2.googleapis.com/token';

/** Upstream call budget. Without it a hung Google request holds the request open. */
const TOKEN_TIMEOUT_MS = 10000;

// One entry per secret name: the two accounts never share a token.
const cachedTokens = new Map();

/** Test seam — the module-level cache would otherwise leak between cases. */
export function resetServiceAccountTokens() {
  cachedTokens.clear();
}

function bytesToBase64Url(bytes) {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function textToBase64Url(text) {
  return bytesToBase64Url(new TextEncoder().encode(text));
}

async function importPrivateKey(pem) {
  const body = pem
    .replace(/-----BEGIN [A-Z ]+-----/, '')
    .replace(/-----END [A-Z ]+-----/, '')
    .replace(/\s+/g, '');
  let der;
  try {
    der = base64UrlToBytes(body);
  } catch {
    throw new HttpError(500, '伺服器設定不完整，請聯絡管理員');
  }
  return crypto.subtle.importKey(
    'pkcs8',
    der,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
}

/// The parsed key file in [secret]. Only the secret's name is ever logged.
export function serviceAccount(env, secret) {
  const raw = requireEnv(env, secret);
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch {
    console.error(`${secret} is not valid JSON`);
    throw new HttpError(500, '伺服器設定不完整，請聯絡管理員');
  }
  if (!parsed?.client_email || !parsed?.private_key) {
    console.error(`${secret} is missing client_email/private_key`);
    throw new HttpError(500, '伺服器設定不完整，請聯絡管理員');
  }
  return parsed;
}

async function safeText(response) {
  try {
    return (await response.text()).slice(0, 500);
  } catch {
    return '<unreadable>';
  }
}

/// Mints (and caches) an access token for the account in [secret].
///
/// Cached in the isolate rather than per request: minting costs an RSA signature
/// plus a round trip to Google, and the token is good for an hour. The 60s
/// safety margin covers a token that expires mid-flight.
///
/// [unreachable] is the message a caller's users see when Google cannot be
/// reached, phrased for what they were trying to do.
export async function serviceAccountToken(
  env,
  { secret, scope, unreachable },
  fetchImpl = fetch,
  now = Date.now(),
) {
  const cached = cachedTokens.get(secret);
  if (cached && cached.expiresAt > now + 60000) {
    return cached.token;
  }

  const account = serviceAccount(env, secret);
  const issuedAt = Math.floor(now / 1000);
  const header = { alg: 'RS256', typ: 'JWT' };
  const claims = {
    iss: account.client_email,
    scope,
    aud: TOKEN_ENDPOINT,
    iat: issuedAt,
    exp: issuedAt + 3600,
  };

  const unsigned = `${textToBase64Url(JSON.stringify(header))}.${textToBase64Url(
    JSON.stringify(claims),
  )}`;
  // The literal \n in the JSON key file survives JSON.parse as a real newline,
  // but a value pasted through a dashboard field may not — normalise both.
  const key = await importPrivateKey(account.private_key.replace(/\\n/g, '\n'));
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(unsigned),
  );
  const assertion = `${unsigned}.${bytesToBase64Url(new Uint8Array(signature))}`;

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TOKEN_TIMEOUT_MS);
  let response;
  try {
    response = await fetchImpl(TOKEN_ENDPOINT, {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion,
      }).toString(),
      signal: controller.signal,
    });
  } catch (error) {
    console.error('token request failed', secret, error);
    throw new HttpError(502, unreachable);
  } finally {
    clearTimeout(timer);
  }

  if (!response.ok) {
    console.error('token exchange failed', secret, response.status, await safeText(response));
    throw new HttpError(502, unreachable);
  }
  const data = await response.json();
  if (typeof data?.access_token !== 'string') {
    throw new HttpError(502, unreachable);
  }

  const lifetimeMs = (Number(data.expires_in) || 3600) * 1000;
  cachedTokens.set(secret, { token: data.access_token, expiresAt: now + lifetimeMs });
  return data.access_token;
}
