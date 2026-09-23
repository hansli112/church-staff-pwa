// Who is calling, and Firestore read as them.
//
// Lives outside functions/ for the same reason google_calendar.js does:
// everything under functions/ is routed by filename, and a helper module
// accidentally becoming a public route is invisible until someone finds it.
//
// What the caller may *do* is not decided here — that is authorize.js, which
// reads the profile identifyCaller() returns.

const FIRESTORE_API = 'https://firestore.googleapis.com/v1';

/** Upstream call budget. Without it a hung Firestore request holds the request open. */
const LOOKUP_TIMEOUT_MS = 10000;

export class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.name = 'HttpError';
    this.status = status;
  }
}

export function requireEnv(env, key) {
  const value = env?.[key];
  if (typeof value !== 'string' || value.trim() === '') {
    // Deliberately not naming the variable to the client — the operator finds
    // it in the Cloudflare log line below.
    console.error(`missing environment variable ${key}`);
    throw new HttpError(500, '伺服器設定不完整，請聯絡管理員');
  }
  return value.trim();
}

/// Also decodes the service account key in google_calendar.js — the PEM body is
/// plain base64, which this accepts as well.
export function base64UrlToBytes(value) {
  const padded = value.replace(/-/g, '+').replace(/_/g, '/');
  const binary = atob(padded + '='.repeat((4 - (padded.length % 4)) % 4));
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

/// The uid out of a Firebase ID token, without verifying the signature.
///
/// Not verifying here is deliberate: the uid is only used to build the
/// Firestore URL that is then fetched *with the caller's own token*. Firestore
/// verifies the signature, expiry and audience, and firestore.rules decides
/// what that uid may read. A forged token gets a 401 from Firestore, not
/// access. The one thing that must be checked locally is that the uid cannot
/// escape its path segment — hence the `/` rejection below.
export function uidFromIdToken(token) {
  const parts = token.split('.');
  if (parts.length !== 3) throw new HttpError(401, '登入狀態無效，請重新登入');
  let payload;
  try {
    payload = JSON.parse(new TextDecoder().decode(base64UrlToBytes(parts[1])));
  } catch {
    throw new HttpError(401, '登入狀態無效，請重新登入');
  }
  const uid = payload?.sub ?? payload?.user_id;
  if (typeof uid !== 'string' || uid === '' || uid.includes('/')) {
    throw new HttpError(401, '登入狀態無效，請重新登入');
  }
  return uid;
}

/// The caller's bearer token, or a 401.
///
/// Returned as well as used because callers pass it straight back to Firestore:
/// every read this worker makes on the caller's behalf goes out as the caller,
/// so firestore.rules stays the single arbiter.
export function bearerToken(request) {
  const header = request.headers.get('Authorization') ?? '';
  if (!header.startsWith('Bearer ')) throw new HttpError(401, '請先登入');
  const token = header.slice('Bearer '.length).trim();
  if (token === '') throw new HttpError(401, '請先登入');
  return token;
}

/// The user's own `name` field, or null.
///
/// Not to be confused with the document's own `name` — that is the Firestore
/// resource path (`projects/.../users/{uid}`) and sits one level up, outside
/// `fields`. Anything missing or of another shape lands on null: a nameless
/// notification is a worse message, not a failed request.
function displayName(fields) {
  const value = fields?.name?.stringValue;
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  return trimmed === '' ? null : trimmed;
}

/// Rejects a caller who is not signed in or has no account, and returns
/// `{ uid, name, token, role, groups, zoneTypes }` read from users/{uid}.
///
/// The role lives in Firestore, not in the token's custom claims, so this reads
/// users/{uid} as the caller. Doing it that way also means the token is fully
/// verified by Firestore and the service account needs no Firestore IAM grant.
///
/// Firestore's REST encoding is nested and every level is optional: a user
/// created before a field existed has no field at all. Anything unreadable
/// comes back as null or an empty list — "no access" to authorize(), rather
/// than a throw that would turn a refusal into a 500.
export async function identifyCaller(request, env, fetchImpl = fetch) {
  const token = bearerToken(request);
  const projectId = requireEnv(env, 'FIREBASE_PROJECT_ID');
  const uid = uidFromIdToken(token);
  const url =
    `${FIRESTORE_API}/projects/${encodeURIComponent(projectId)}` +
    `/databases/(default)/documents/users/${encodeURIComponent(uid)}` +
    '?mask.fieldPaths=role&mask.fieldPaths=groups&mask.fieldPaths=name' +
    '&mask.fieldPaths=zoneTypes';

  const response = await fetchAsCaller(fetchImpl, url, token);

  if (response.status === 401 || response.status === 403) {
    throw new HttpError(401, '登入狀態已過期，請重新登入');
  }
  // A member removed from the app keeps a valid Firebase Auth token but has no
  // users/{uid} doc — same reasoning as isActiveUser() in firestore.rules.
  if (response.status === 404) {
    throw new HttpError(403, '這個帳號沒有權限');
  }
  if (!response.ok) {
    console.error('firestore role lookup failed', response.status);
    throw new HttpError(502, '無法確認權限，請稍後再試');
  }

  const fields = (await response.json())?.fields;
  const role = fields?.role?.stringValue;
  return {
    uid,
    name: displayName(fields),
    token,
    role: typeof role === 'string' ? role : null,
    groups: stringArrayField(fields?.groups),
    zoneTypes: stringArrayField(fields?.zoneTypes),
  };
}

/// A Firestore array-of-strings field, defensively.
///
/// A user created before zoneTypes existed has no field at all, and an empty
/// array comes back as `{ arrayValue: {} }` with no `values`. Both mean "no
/// zones", which must read as "no access", not as a crash.
function stringArrayField(field) {
  const values = field?.arrayValue?.values;
  if (!Array.isArray(values)) return [];
  return values.map((entry) => entry?.stringValue).filter((v) => typeof v === 'string');
}

/// GETs a Firestore document as the caller. Returns null on 404.
///
/// Every read goes out with the caller's own token, so a user who cannot read
/// the document under firestore.rules cannot read it through this worker
/// either — the worker adds no privilege of its own.
export async function readDocument(env, path, token, fetchImpl = fetch) {
  const projectId = requireEnv(env, 'FIREBASE_PROJECT_ID');
  const url =
    `${FIRESTORE_API}/projects/${encodeURIComponent(projectId)}` +
    `/databases/(default)/documents/${path}`;
  const response = await fetchAsCaller(fetchImpl, url, token);
  if (response.status === 404) return null;
  if (response.status === 401 || response.status === 403) {
    throw new HttpError(401, '登入狀態已過期，請重新登入');
  }
  if (!response.ok) {
    console.error('firestore read failed', path, response.status);
    throw new HttpError(502, '讀取設定失敗，請稍後再試');
  }
  return response.json();
}

/// Lists a collection as the caller, following pageToken to the end.
///
/// [mask] limits which fields come back. For users/ that matters beyond payload
/// size: the documents also hold email addresses and FCM tokens, and this
/// worker only ever needs the display name. Asking for less is the cheapest
/// way not to handle what it does not need.
export async function listDocuments(env, collection, token, { mask = [], fetchImpl = fetch } = {}) {
  const projectId = requireEnv(env, 'FIREBASE_PROJECT_ID');
  const base =
    `${FIRESTORE_API}/projects/${encodeURIComponent(projectId)}` +
    `/databases/(default)/documents/${collection}`;
  const masks = mask.map((field) => `&mask.fieldPaths=${encodeURIComponent(field)}`).join('');

  const documents = [];
  let pageToken = '';
  // A hard stop rather than `while (true)`: a server that keeps handing back
  // the same token would otherwise spin until the request is killed.
  for (let page = 0; page < 20; page += 1) {
    const url = `${base}?pageSize=300${masks}${pageToken}`;
    const response = await fetchAsCaller(fetchImpl, url, token);
    if (response.status === 401 || response.status === 403) {
      throw new HttpError(401, '登入狀態已過期，請重新登入');
    }
    if (!response.ok) {
      console.error('firestore list failed', collection, response.status);
      throw new HttpError(502, '讀取名單失敗，請稍後再試');
    }
    const body = await response.json();
    documents.push(...(body.documents ?? []));
    if (!body.nextPageToken) return documents;
    pageToken = `&pageToken=${encodeURIComponent(body.nextPageToken)}`;
  }
  console.error('firestore list did not terminate', collection);
  throw new HttpError(502, '讀取名單失敗，請稍後再試');
}

async function fetchAsCaller(fetchImpl, url, token) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), LOOKUP_TIMEOUT_MS);
  try {
    return await fetchImpl(url, {
      headers: { Authorization: `Bearer ${token}` },
      signal: controller.signal,
    });
  } catch (error) {
    if (error instanceof HttpError) throw error;
    console.error('firestore request failed', url, error);
    throw new HttpError(502, '無法連上伺服器，請稍後再試');
  } finally {
    clearTimeout(timer);
  }
}
