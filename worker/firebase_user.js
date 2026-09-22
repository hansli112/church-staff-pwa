// Who is calling, and may they do this.
//
// Lives outside functions/ for the same reason google_calendar.js does:
// everything under functions/ is routed by filename, and a helper module
// accidentally becoming a public route is invisible until someone finds it.
//
// Split out of google_calendar.js when /api/roster/ needed the same check
// against a different group. The group name is the only difference, and an
// authorization check that exists in two copies is one that will be fixed in
// one copy.

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

function base64UrlToBytes(value) {
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
function displayName(doc) {
  const value = doc?.fields?.name?.stringValue;
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  return trimmed === '' ? null : trimmed;
}

/// admin is root, otherwise membership of [group].
///
/// Firestore's REST encoding is nested and every level is optional: a user
/// created before the field existed has no `groups` at all, and an empty array
/// comes back as `{ arrayValue: {} }` with no `values`. Anything unreadable
/// must land on "no access" rather than throw — a shape surprise here would
/// otherwise turn into a 500 on a request that should simply be refused.
function hasGroup(doc, group) {
  const fields = doc?.fields;
  if (fields?.role?.stringValue === 'admin') return true;
  const values = fields?.groups?.arrayValue?.values;
  if (!Array.isArray(values)) return false;
  return values.some((entry) => entry?.stringValue === group);
}

/// Rejects anyone outside [group], and returns
/// `{ uid, name, token, isAdmin, zoneTypes }`.
///
/// [zoneTypes] and [isAdmin] come back because group membership is only half
/// the answer: canEditRosterType() in firestore.rules reads the group as "may
/// edit rosters" and the zone as "which one". A caller who only has 青崇 must
/// not be able to act on 主日 just because the group check passed.
///
/// The role lives in Firestore, not in the token's custom claims, so this reads
/// users/{uid} as the caller. Doing it that way also means the token is fully
/// verified by Firestore and the service account needs no Firestore IAM grant.
///
/// [denied] is the message for someone who is signed in but lacks the group —
/// it names the specific thing they cannot do, which is the only part a caller
/// can act on.
export async function requireGroupMember(
  request,
  env,
  { group, denied },
  fetchImpl = fetch,
) {
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

  const doc = await response.json();
  if (!hasGroup(doc, group)) throw new HttpError(403, denied);
  return {
    uid,
    name: displayName(doc),
    token,
    isAdmin: doc?.fields?.role?.stringValue === 'admin',
    zoneTypes: stringArrayField(doc?.fields?.zoneTypes),
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
