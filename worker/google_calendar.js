// Shared logic for the /api/calendar/* Pages Functions.
//
// Lives outside functions/ on purpose: everything inside functions/ is subject
// to file-based routing, and a helper module accidentally becoming a public
// route is the kind of mistake that is invisible until someone finds it.
//
// Why the calendar is written from here at all: the browser reads the calendar
// with a public API key (see lib/core/config/google_calendar_config.dart), and
// an API key cannot write. Writing needs either per-admin OAuth or a service
// account. A service account keeps the credential off the client and means
// admins do not need their own Google account on the calendar — but that
// credential must never reach the browser, hence this server side.

const CALENDAR_SCOPE = 'https://www.googleapis.com/auth/calendar.events';
const TOKEN_ENDPOINT = 'https://oauth2.googleapis.com/token';
const CALENDAR_API = 'https://www.googleapis.com/calendar/v3';
const FIRESTORE_API = 'https://firestore.googleapis.com/v1';

// Must match GoogleCalendarConfig.timeZone. The client sends wall-clock time
// with no offset; this is what makes "19:00" mean 19:00 in Taipei.
export const TIME_ZONE = 'Asia/Taipei';

const MAX_TITLE = 200;
const MAX_LOCATION = 300;
const MAX_DESCRIPTION = 4000;

/** Upstream call budget. Without it a hung Google request holds the request open. */
const UPSTREAM_TIMEOUT_MS = 10000;

export class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.name = 'HttpError';
    this.status = status;
  }
}

export function jsonResponse(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      // These are private, admin-only responses; no intermediary should keep them.
      'cache-control': 'no-store',
    },
  });
}

export function errorResponse(error) {
  if (error instanceof HttpError) {
    return jsonResponse({ error: error.message }, error.status);
  }
  return jsonResponse({ error: '操作失敗，請稍後再試' }, 500);
}

/** Wraps a handler so thrown HttpErrors become responses instead of 500s. */
export async function handle(fn) {
  try {
    return await fn();
  } catch (error) {
    if (!(error instanceof HttpError)) {
      console.error('calendar function failed', error);
    }
    return errorResponse(error);
  }
}

function requireEnv(env, key) {
  const value = env?.[key];
  if (typeof value !== 'string' || value.trim() === '') {
    // Deliberately not naming the variable to the client — the operator finds
    // it in the Cloudflare log line below.
    console.error(`missing environment variable ${key}`);
    throw new HttpError(500, '伺服器設定不完整，請聯絡管理員');
  }
  return value.trim();
}

// ---------------------------------------------------------------------------
// Caller identity
// ---------------------------------------------------------------------------

function base64UrlToBytes(text) {
  const padded = text.replace(/-/g, '+').replace(/_/g, '/');
  const binary = atob(padded + '='.repeat((4 - (padded.length % 4)) % 4));
  return Uint8Array.from(binary, (char) => char.charCodeAt(0));
}

/// Reads `sub` out of a Firebase ID token **without verifying the signature**.
///
/// That is safe here only because the uid is used for exactly one thing: to
/// build the Firestore URL that is then fetched *with the caller's own token*.
/// Firestore verifies the signature, expiry and audience, and firestore.rules
/// only lets a caller read their own users/{uid} doc. A forged payload either
/// fails the signature check or points at a doc the caller cannot read.
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

/// Rejects anyone who is not an admin, and returns their uid.
///
/// The role lives in Firestore, not in the token's custom claims, so this reads
/// users/{uid} as the caller. Doing it that way also means the token is fully
/// verified by Firestore and the service account needs no Firestore IAM grant.
export async function requireAdmin(request, env, fetchImpl = fetch) {
  const header = request.headers.get('Authorization') ?? '';
  if (!header.startsWith('Bearer ')) {
    throw new HttpError(401, '請先登入');
  }
  const token = header.slice('Bearer '.length).trim();
  if (token === '') throw new HttpError(401, '請先登入');

  const projectId = requireEnv(env, 'FIREBASE_PROJECT_ID');
  const uid = uidFromIdToken(token);
  const url =
    `${FIRESTORE_API}/projects/${encodeURIComponent(projectId)}` +
    `/databases/(default)/documents/users/${encodeURIComponent(uid)}` +
    '?mask.fieldPaths=role';

  const response = await fetchWithTimeout(fetchImpl, url, {
    headers: { Authorization: `Bearer ${token}` },
  });

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
  if (doc?.fields?.role?.stringValue !== 'admin') {
    throw new HttpError(403, '只有管理員可以編輯行事曆');
  }
  return uid;
}

// ---------------------------------------------------------------------------
// Service account access token
// ---------------------------------------------------------------------------

let cachedToken = null;

/** Test seam — the module-level cache would otherwise leak between cases. */
export function resetAccessTokenCache() {
  cachedToken = null;
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

function serviceAccount(env) {
  const raw = requireEnv(env, 'GOOGLE_SERVICE_ACCOUNT_JSON');
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch {
    console.error('GOOGLE_SERVICE_ACCOUNT_JSON is not valid JSON');
    throw new HttpError(500, '伺服器設定不完整，請聯絡管理員');
  }
  if (!parsed?.client_email || !parsed?.private_key) {
    console.error('GOOGLE_SERVICE_ACCOUNT_JSON is missing client_email/private_key');
    throw new HttpError(500, '伺服器設定不完整，請聯絡管理員');
  }
  return parsed;
}

/// Mints (and caches) an access token for the service account.
///
/// Cached in the isolate rather than per request: minting costs an RSA signature
/// plus a round trip to Google, and the token is good for an hour. The 60s
/// safety margin covers a token that expires mid-flight.
export async function getAccessToken(env, fetchImpl = fetch, now = Date.now()) {
  if (cachedToken && cachedToken.expiresAt > now + 60000) {
    return cachedToken.token;
  }

  const account = serviceAccount(env);
  const issuedAt = Math.floor(now / 1000);
  const header = { alg: 'RS256', typ: 'JWT' };
  const claims = {
    iss: account.client_email,
    scope: CALENDAR_SCOPE,
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

  const response = await fetchWithTimeout(fetchImpl, TOKEN_ENDPOINT, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }).toString(),
  });

  if (!response.ok) {
    console.error('token exchange failed', response.status, await safeText(response));
    throw new HttpError(502, '無法連上 Google 日曆，請稍後再試');
  }
  const data = await response.json();
  if (typeof data?.access_token !== 'string') {
    throw new HttpError(502, '無法連上 Google 日曆，請稍後再試');
  }

  const lifetimeMs = (Number(data.expires_in) || 3600) * 1000;
  cachedToken = { token: data.access_token, expiresAt: now + lifetimeMs };
  return cachedToken.token;
}

// ---------------------------------------------------------------------------
// Request body -> Google event resource
// ---------------------------------------------------------------------------

const DATE_PATTERN = /^(\d{4})-(\d{2})-(\d{2})$/;
const DATE_TIME_PATTERN = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?$/;

/// Parses `YYYY-MM-DD`, rejecting values that match the shape but are not real
/// dates (2026-02-30 would otherwise roll over into March).
function parseDate(text, label) {
  const match = typeof text === 'string' ? DATE_PATTERN.exec(text) : null;
  if (!match) throw new HttpError(400, `${label}格式不正確`);
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const stamp = Date.UTC(year, month - 1, day);
  const roundTrip = new Date(stamp);
  if (
    roundTrip.getUTCFullYear() !== year ||
    roundTrip.getUTCMonth() !== month - 1 ||
    roundTrip.getUTCDate() !== day
  ) {
    throw new HttpError(400, `${label}不是有效的日期`);
  }
  return stamp;
}

function formatDate(stamp) {
  return new Date(stamp).toISOString().slice(0, 10);
}

/// Normalises `YYYY-MM-DDTHH:MM[:SS]` and validates both halves.
function parseDateTime(text, label) {
  const match = typeof text === 'string' ? DATE_TIME_PATTERN.exec(text) : null;
  if (!match) throw new HttpError(400, `${label}格式不正確`);
  parseDate(`${match[1]}-${match[2]}-${match[3]}`, label);
  const hour = Number(match[4]);
  const minute = Number(match[5]);
  const second = Number(match[6] ?? '0');
  if (hour > 23 || minute > 59 || second > 59) {
    throw new HttpError(400, `${label}不是有效的時間`);
  }
  const pad = (value) => String(value).padStart(2, '0');
  return `${match[1]}-${match[2]}-${match[3]}T${pad(hour)}:${pad(minute)}:${pad(second)}`;
}

function optionalText(value, label, max) {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== 'string') throw new HttpError(400, `${label}格式不正確`);
  const trimmed = value.trim();
  if (trimmed === '') return '';
  if (trimmed.length > max) throw new HttpError(400, `${label}太長了（上限 ${max} 字）`);
  return trimmed;
}

/// Turns the app's request body into a Google Calendar event resource.
///
/// The one genuinely surprising rule is the all-day end date: Google's `end.date`
/// is **exclusive**, so a single-day event on the 20th ends on the 21st. The app
/// sends the inclusive end date a person would type, and the conversion happens
/// here so both the client and the tests can stay in human terms.
///
/// [forPatch] adds explicit nulls for the *other* time representation. Edits go
/// out as PATCH so that fields this app does not manage (attendees, reminders,
/// recurrence on events created in Google Calendar itself) survive the edit —
/// but PATCH merges, so switching an event between all-day and timed would
/// otherwise leave the old `date`/`dateTime` in place and the API rejects an
/// event that carries both.
export function buildGoogleEvent(body, { forPatch = false } = {}) {
  if (body === null || typeof body !== 'object' || Array.isArray(body)) {
    throw new HttpError(400, '資料格式不正確');
  }

  const title = optionalText(body.title, '標題', MAX_TITLE);
  if (!title) throw new HttpError(400, '請填寫標題');

  if (typeof body.allDay !== 'boolean') {
    throw new HttpError(400, '資料格式不正確');
  }

  const event = { summary: title };

  const location = optionalText(body.location, '地點', MAX_LOCATION);
  if (location !== undefined) event.location = location;
  const description = optionalText(body.description, '說明', MAX_DESCRIPTION);
  if (description !== undefined) event.description = description;

  if (body.allDay) {
    const start = parseDate(body.start, '開始日期');
    const end = body.end === undefined || body.end === null
      ? start
      : parseDate(body.end, '結束日期');
    if (end < start) throw new HttpError(400, '結束日期不能早於開始日期');
    event.start = { date: formatDate(start) };
    event.end = { date: formatDate(end + 86400000) };
    if (forPatch) {
      event.start.dateTime = null;
      event.end.dateTime = null;
    }
  } else {
    const start = parseDateTime(body.start, '開始時間');
    const end = body.end === undefined || body.end === null
      ? start
      : parseDateTime(body.end, '結束時間');
    // Both strings are fixed-width and zero-padded, so lexical order is
    // chronological order.
    if (end < start) throw new HttpError(400, '結束時間不能早於開始時間');
    event.start = { dateTime: start, timeZone: TIME_ZONE };
    event.end = { dateTime: end, timeZone: TIME_ZONE };
    if (forPatch) {
      event.start.date = null;
      event.end.date = null;
    }
  }

  return event;
}

export async function readJsonBody(request) {
  try {
    return await request.json();
  } catch {
    throw new HttpError(400, '資料格式不正確');
  }
}

// ---------------------------------------------------------------------------
// Google Calendar calls
// ---------------------------------------------------------------------------

async function safeText(response) {
  try {
    return (await response.text()).slice(0, 500);
  } catch {
    return '<unreadable>';
  }
}

async function fetchWithTimeout(fetchImpl, url, init = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), UPSTREAM_TIMEOUT_MS);
  try {
    return await fetchImpl(url, { ...init, signal: controller.signal });
  } catch (error) {
    if (error instanceof HttpError) throw error;
    console.error('upstream request failed', url, error);
    throw new HttpError(502, '無法連上 Google 日曆，請稍後再試');
  } finally {
    clearTimeout(timer);
  }
}

/// Calls the Calendar API against the configured calendar.
///
/// `eventId` is appended as a path segment; it comes from the URL, so it is
/// encoded rather than interpolated raw.
export async function callCalendar(env, { method, eventId, body, fetchImpl = fetch }) {
  const calendarId = requireEnv(env, 'GOOGLE_CALENDAR_ID');
  const token = await getAccessToken(env, fetchImpl);

  let url = `${CALENDAR_API}/calendars/${encodeURIComponent(calendarId)}/events`;
  if (eventId) url += `/${encodeURIComponent(eventId)}`;

  const response = await fetchWithTimeout(fetchImpl, url, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      ...(body ? { 'content-type': 'application/json' } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });

  if (response.status === 404 || response.status === 410) {
    throw new HttpError(404, '這個活動已經不存在了');
  }
  if (response.status === 403) {
    // Almost always the calendar not being shared with the service account.
    console.error('calendar API forbidden', await safeText(response));
    throw new HttpError(502, '沒有權限寫入這本日曆，請聯絡管理員');
  }
  if (!response.ok) {
    console.error('calendar API failed', response.status, await safeText(response));
    throw new HttpError(502, '無法連上 Google 日曆，請稍後再試');
  }
  return response;
}
