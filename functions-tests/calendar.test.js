import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

import { onRequestPost } from '../functions/api/calendar/events.js';
import { onRequestDelete, onRequestPatch } from '../functions/api/calendar/events/[id].js';
import {
  buildGoogleEvent,
  getAccessToken,
  requireEditor,
  resetAccessTokenCache,
  uidFromIdToken,
} from '../worker/google_calendar.js';
import { notifyPayload } from '../worker/line_notify.js';
import {
  ADMIN_NAME,
  ADMIN_UID,
  CALENDAR_EDITOR_NAME,
  CALENDAR_EDITOR_UID,
  CALENDAR_ID,
  NOTIFY_SECRET,
  ROSTER_EDITOR_UID,
  MEMBER_UID,
  fakeFetch,
  idToken,
  muteConsoleError,
  notifyingEnv,
  request,
  testEnv,
} from './helpers.js';

/// The route handlers use the global fetch, so that is what gets swapped. This
/// keeps the tests exercising the real wiring instead of a hand-passed seam the
/// production code never uses.
/// Must await before restoring: returning the pending promise from inside the
/// try would put the real fetch back while the handler is still mid-flight, and
/// the test would quietly talk to Google over the network.
async function withFetch(impl, fn) {
  const original = globalThis.fetch;
  globalThis.fetch = impl;
  try {
    return await fn();
  } finally {
    globalThis.fetch = original;
  }
}

beforeEach(() => resetAccessTokenCache());

// ---------------------------------------------------------------------------

describe('buildGoogleEvent', () => {
  const base = { title: '青年小組', allDay: true, start: '2026-08-20' };

  test('requires a title', () => {
    assert.throws(() => buildGoogleEvent({ ...base, title: '   ' }), {
      status: 400,
      message: '請填寫標題',
    });
  });

  test('trims the title', () => {
    assert.equal(buildGoogleEvent({ ...base, title: '  聚會 ' }).summary, '聚會');
  });

  test('rejects a title longer than the limit', () => {
    assert.throws(() => buildGoogleEvent({ ...base, title: 'a'.repeat(201) }), {
      status: 400,
    });
  });

  test('requires allDay to be stated explicitly', () => {
    assert.throws(() => buildGoogleEvent({ title: 'x', start: '2026-08-20' }), {
      status: 400,
    });
  });

  test('rejects a non-object body', () => {
    assert.throws(() => buildGoogleEvent(null), { status: 400 });
    assert.throws(() => buildGoogleEvent([]), { status: 400 });
  });

  // Google's end.date is exclusive. Getting this wrong makes every all-day
  // event render one day short — or, for a single-day event, not at all.
  test('a single-day all-day event ends the next day', () => {
    const event = buildGoogleEvent(base);
    assert.deepEqual(event.start, { date: '2026-08-20' });
    assert.deepEqual(event.end, { date: '2026-08-21' });
  });

  test('a multi-day all-day event ends the day after the inclusive end', () => {
    const event = buildGoogleEvent({ ...base, end: '2026-08-22' });
    assert.deepEqual(event.end, { date: '2026-08-23' });
  });

  test('the exclusive end rolls over a month boundary', () => {
    const event = buildGoogleEvent({ ...base, start: '2026-08-31', end: '2026-08-31' });
    assert.deepEqual(event.end, { date: '2026-09-01' });
  });

  test('the exclusive end rolls over a leap day', () => {
    const event = buildGoogleEvent({ ...base, start: '2028-02-28', end: '2028-02-29' });
    assert.deepEqual(event.end, { date: '2028-03-01' });
  });

  test('rejects a date that matches the shape but does not exist', () => {
    assert.throws(() => buildGoogleEvent({ ...base, start: '2026-02-30' }), {
      status: 400,
      message: '開始日期不是有效的日期',
    });
    assert.throws(() => buildGoogleEvent({ ...base, start: '2026-13-01' }), { status: 400 });
  });

  test('rejects a slash-separated date', () => {
    assert.throws(() => buildGoogleEvent({ ...base, start: '2026/08/20' }), { status: 400 });
  });

  test('rejects an end before the start', () => {
    assert.throws(() => buildGoogleEvent({ ...base, end: '2026-08-19' }), {
      status: 400,
      message: '結束日期不能早於開始日期',
    });
  });

  test('a timed event carries the Taipei time zone and normalised seconds', () => {
    const event = buildGoogleEvent({
      title: '禱告會',
      allDay: false,
      start: '2026-08-20T19:00',
      end: '2026-08-20T21:30',
    });
    assert.deepEqual(event.start, { dateTime: '2026-08-20T19:00:00', timeZone: 'Asia/Taipei' });
    assert.deepEqual(event.end, { dateTime: '2026-08-20T21:30:00', timeZone: 'Asia/Taipei' });
  });

  test('a timed event without an end collapses to a zero-length event', () => {
    const event = buildGoogleEvent({ title: 'x', allDay: false, start: '2026-08-20T19:00' });
    assert.equal(event.end.dateTime, '2026-08-20T19:00:00');
  });

  test('rejects an impossible time', () => {
    assert.throws(
      () => buildGoogleEvent({ title: 'x', allDay: false, start: '2026-08-20T25:00' }),
      { status: 400 },
    );
    assert.throws(
      () => buildGoogleEvent({ title: 'x', allDay: false, start: '2026-08-20T12:61' }),
      { status: 400, message: '開始時間不是有效的時間' },
    );
  });

  test('rejects a timed end before the start', () => {
    assert.throws(
      () =>
        buildGoogleEvent({
          title: 'x',
          allDay: false,
          start: '2026-08-20T19:00',
          end: '2026-08-20T18:59',
        }),
      { status: 400, message: '結束時間不能早於開始時間' },
    );
  });

  test('a timed event may span days', () => {
    const event = buildGoogleEvent({
      title: '退修會',
      allDay: false,
      start: '2026-08-20T19:00',
      end: '2026-08-22T12:00',
    });
    assert.equal(event.end.dateTime, '2026-08-22T12:00:00');
  });

  test('an empty location is kept so an edit can clear it', () => {
    assert.equal(buildGoogleEvent({ ...base, location: '  ' }).location, '');
  });

  test('an omitted location is left untouched', () => {
    assert.equal('location' in buildGoogleEvent(base), false);
  });

  // Without these nulls, switching an event between all-day and timed leaves
  // both representations on the resource and the API rejects it.
  test('a patch clears the opposite time representation', () => {
    const allDay = buildGoogleEvent(base, { forPatch: true });
    assert.equal(allDay.start.dateTime, null);
    assert.equal(allDay.end.dateTime, null);

    const timed = buildGoogleEvent(
      { title: 'x', allDay: false, start: '2026-08-20T19:00' },
      { forPatch: true },
    );
    assert.equal(timed.start.date, null);
    assert.equal(timed.end.date, null);
  });

  test('a create carries no clearing nulls', () => {
    const event = buildGoogleEvent(base);
    assert.equal('dateTime' in event.start, false);
  });
});

// ---------------------------------------------------------------------------

describe('uidFromIdToken', () => {
  test('reads sub out of the payload', () => {
    assert.equal(uidFromIdToken(idToken('abc123')), 'abc123');
  });

  test('rejects a token that is not three segments', () => {
    assert.throws(() => uidFromIdToken('not-a-token'), { status: 401 });
  });

  test('rejects a payload that is not JSON', () => {
    assert.throws(() => uidFromIdToken('a.!!!.c'), { status: 401 });
  });

  // A uid is only ever used to build a Firestore document path.
  test('rejects a uid containing a path separator', () => {
    assert.throws(() => uidFromIdToken(idToken('../../settings/roster_templates')), {
      status: 401,
    });
  });

  test('rejects a payload with no subject', () => {
    assert.throws(() => uidFromIdToken(idToken(undefined)), { status: 401 });
  });
});

// ---------------------------------------------------------------------------

describe('requireEditor', () => {
  test('rejects a request with no Authorization header', async () => {
    const env = await testEnv();
    await assert.rejects(requireEditor(request('POST', { token: null }), env, fakeFetch()), {
      status: 401,
      message: '請先登入',
    });
  });

  test('rejects an empty bearer token', async () => {
    const env = await testEnv();
    await assert.rejects(requireEditor(request('POST', { token: '  ' }), env, fakeFetch()), {
      status: 401,
    });
  });

  test('accepts an admin and returns the uid and name', async () => {
    const env = await testEnv();
    assert.deepEqual(await requireEditor(request('POST'), env, fakeFetch()), {
      uid: ADMIN_UID,
      name: ADMIN_NAME,
    });
  });

  // 權限看 group，不看 role：這個人的 role 只是 staff。
  test('accepts a member of calendar-editors regardless of role', async () => {
    const env = await testEnv();
    assert.deepEqual(
      await requireEditor(
        request('POST', { token: idToken(CALENDAR_EDITOR_UID) }),
        env,
        fakeFetch(),
      ),
      { uid: CALENDAR_EDITOR_UID, name: CALENDAR_EDITOR_NAME },
    );
  });

  // 沒有 name 的舊帳號照樣能編行事曆 —— 名字只影響通知長什麼樣。
  test('accepts an editor whose document has no name', async () => {
    const env = await testEnv();
    const fetchImpl = fakeFetch({ users: { [ADMIN_UID]: { role: 'admin' } } });
    assert.deepEqual(await requireEditor(request('POST'), env, fetchImpl), {
      uid: ADMIN_UID,
      name: null,
    });
  });

  // 只有空白的名字等於沒有名字，否則通知裡會多出一行只有冒號的東西。
  test('treats a blank name as no name', async () => {
    const env = await testEnv();
    const fetchImpl = fakeFetch({ users: { [ADMIN_UID]: { role: 'admin', name: '   ' } } });
    assert.equal((await requireEditor(request('POST'), env, fetchImpl)).name, null);
  });

  // 遮罩少一個欄位就等於白跑一趟：名字拿不到，通知就永遠是匿名的。
  test('asks Firestore for the name field', async () => {
    const env = await testEnv();
    const fetchImpl = fakeFetch();
    await requireEditor(request('POST'), env, fetchImpl);
    const [lookup] = fetchImpl.calls.filter((call) =>
      call.url.startsWith('https://firestore.googleapis.com/'),
    );
    assert.match(lookup.url, /mask\.fieldPaths=name/);
  });

  // 兩個 group 正交：服事表編輯者碰不到行事曆。
  test('rejects a member of a different group', async () => {
    const env = await testEnv();
    await assert.rejects(
      requireEditor(request('POST', { token: idToken(ROSTER_EDITOR_UID) }), env, fakeFetch()),
      { status: 403, message: '沒有編輯行事曆的權限' },
    );
  });

  // 沒有 groups 欄位的舊帳號 —— 全部既有使用者都是這個形狀。
  test('rejects a user document written before groups existed', async () => {
    const env = await testEnv();
    const fetchImpl = fakeFetch({ users: { [MEMBER_UID]: { role: 'leader' } } });
    await assert.rejects(
      requireEditor(request('POST', { token: idToken(MEMBER_UID) }), env, fetchImpl),
      { status: 403 },
    );
  });

  // Firestore 對空陣列回的是 { arrayValue: {} }，沒有 values。
  test('rejects an empty groups array', async () => {
    const env = await testEnv();
    const fetchImpl = fakeFetch({ users: { [MEMBER_UID]: { role: 'staff', groups: [] } } });
    await assert.rejects(
      requireEditor(request('POST', { token: idToken(MEMBER_UID) }), env, fetchImpl),
      { status: 403 },
    );
  });

  // 名字打錯不能當成某種權限放行。
  test('rejects an unknown group name', async () => {
    const env = await testEnv();
    const fetchImpl = fakeFetch({
      users: { [MEMBER_UID]: { role: 'staff', groups: ['calendar-editor'] } },
    });
    await assert.rejects(
      requireEditor(request('POST', { token: idToken(MEMBER_UID) }), env, fetchImpl),
      { status: 403 },
    );
  });

  test('rejects a non-admin member', async () => {
    const env = await testEnv();
    await assert.rejects(
      requireEditor(request('POST', { token: idToken(MEMBER_UID) }), env, fakeFetch()),
      { status: 403, message: '沒有編輯行事曆的權限' },
    );
  });

  // A removed member keeps a valid Firebase Auth token but loses users/{uid}.
  test('rejects a signed-in account with no user document', async () => {
    const env = await testEnv();
    await assert.rejects(
      requireEditor(request('POST', { token: idToken('ghost') }), env, fakeFetch()),
      { status: 403, message: '這個帳號沒有權限' },
    );
  });

  test('rejects a user document with no role field', async () => {
    const env = await testEnv();
    const fetchImpl = fakeFetch({ users: { [ADMIN_UID]: null } });
    await assert.rejects(requireEditor(request('POST'), env, fetchImpl), { status: 403 });
  });

  test('maps a Firestore rejection to a re-login prompt', async () => {
    const env = await testEnv();
    const fetchImpl = async () => new Response('{}', { status: 401 });
    await assert.rejects(requireEditor(request('POST'), env, fetchImpl), {
      status: 401,
      message: '登入狀態已過期，請重新登入',
    });
  });

  test('maps a Firestore outage to a retry prompt', async () => {
    const restore = muteConsoleError();
    try {
      const env = await testEnv();
      const fetchImpl = async () => new Response('boom', { status: 500 });
      await assert.rejects(requireEditor(request('POST'), env, fetchImpl), { status: 502 });
    } finally {
      restore();
    }
  });

  test('fails closed when the project id is not configured', async () => {
    const restore = muteConsoleError();
    try {
      const env = await testEnv({ FIREBASE_PROJECT_ID: '' });
      await assert.rejects(requireEditor(request('POST'), env, fakeFetch()), { status: 500 });
    } finally {
      restore();
    }
  });
});

// ---------------------------------------------------------------------------

describe('getAccessToken', () => {
  test('signs a JWT and exchanges it', async () => {
    const env = await testEnv();
    const fetchImpl = fakeFetch();
    assert.equal(await getAccessToken(env, fetchImpl), 'test-access-token');

    const exchange = fetchImpl.calls.find((call) => call.url.includes('oauth2.googleapis.com'));
    const params = new URLSearchParams(exchange.body);
    assert.equal(params.get('grant_type'), 'urn:ietf:params:oauth:grant-type:jwt-bearer');

    const [, payload] = params.get('assertion').split('.');
    const claims = JSON.parse(Buffer.from(payload, 'base64url').toString());
    assert.equal(claims.scope, 'https://www.googleapis.com/auth/calendar.events');
    assert.equal(claims.aud, 'https://oauth2.googleapis.com/token');
    assert.equal(claims.exp - claims.iat, 3600);
  });

  test('reuses a cached token instead of minting a second one', async () => {
    const env = await testEnv();
    const fetchImpl = fakeFetch();
    await getAccessToken(env, fetchImpl, 1_000_000);
    await getAccessToken(env, fetchImpl, 1_000_000 + 60_000);
    assert.equal(fetchImpl.calls.length, 1);
  });

  test('mints a fresh token once the cached one is near expiry', async () => {
    const env = await testEnv();
    const fetchImpl = fakeFetch();
    await getAccessToken(env, fetchImpl, 1_000_000);
    await getAccessToken(env, fetchImpl, 1_000_000 + 3_600_000);
    assert.equal(fetchImpl.calls.length, 2);
  });

  test('fails closed on a malformed service account', async () => {
    const restore = muteConsoleError();
    try {
      const env = await testEnv({ GOOGLE_SERVICE_ACCOUNT_JSON: 'not json' });
      await assert.rejects(getAccessToken(env, fakeFetch()), { status: 500 });
    } finally {
      restore();
    }
  });

  test('fails closed on a service account with no private key', async () => {
    const restore = muteConsoleError();
    try {
      const env = await testEnv({ GOOGLE_SERVICE_ACCOUNT_JSON: '{"client_email":"a@b.c"}' });
      await assert.rejects(getAccessToken(env, fakeFetch()), { status: 500 });
    } finally {
      restore();
    }
  });
});

// ---------------------------------------------------------------------------

describe('POST /api/calendar/events', () => {
  test('creates the event and returns Google\'s item', async () => {
    const env = await testEnv();
    const fetchImpl = fakeFetch();
    const response = await withFetch(fetchImpl, () =>
      onRequestPost({
        request: request('POST', { body: { title: '聚會', allDay: true, start: '2026-08-20' } }),
        env,
      }),
    );

    assert.equal(response.status, 201);
    assert.deepEqual(await response.json(), { id: 'created-event-id', status: 'confirmed' });

    const [call] = fetchImpl.calendarCalls();
    assert.equal(call.method, 'POST');
    assert.equal(
      call.url,
      `https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(CALENDAR_ID)}/events`,
    );
    assert.deepEqual(JSON.parse(call.body), {
      summary: '聚會',
      start: { date: '2026-08-20' },
      end: { date: '2026-08-21' },
    });
  });

  // Authorization has to happen before anything reaches Google, not after.
  test('a member gets 403 and nothing is sent to Google', async () => {
    const env = await testEnv();
    const fetchImpl = fakeFetch();
    const response = await withFetch(fetchImpl, () =>
      onRequestPost({
        request: request('POST', {
          token: idToken(MEMBER_UID),
          body: { title: '聚會', allDay: true, start: '2026-08-20' },
        }),
        env,
      }),
    );

    assert.equal(response.status, 403);
    assert.equal(fetchImpl.calendarCalls().length, 0);
  });

  test('an unauthenticated request gets 401 and nothing is sent to Google', async () => {
    const env = await testEnv();
    const fetchImpl = fakeFetch();
    const response = await withFetch(fetchImpl, () =>
      onRequestPost({ request: request('POST', { token: null, body: {} }), env }),
    );

    assert.equal(response.status, 401);
    assert.equal(fetchImpl.calls.length, 0);
  });

  test('an invalid body gets 400 and nothing is sent to Google', async () => {
    const env = await testEnv();
    const fetchImpl = fakeFetch();
    const response = await withFetch(fetchImpl, () =>
      onRequestPost({ request: request('POST', { body: { allDay: true, start: '2026-08-20' } }), env }),
    );

    assert.equal(response.status, 400);
    assert.deepEqual(await response.json(), { error: '請填寫標題' });
    assert.equal(fetchImpl.calendarCalls().length, 0);
  });

  test('a body that is not JSON gets 400', async () => {
    const env = await testEnv();
    const fetchImpl = fakeFetch();
    const response = await withFetch(fetchImpl, () =>
      onRequestPost({ request: request('POST', { body: '{not json' }), env }),
    );
    assert.equal(response.status, 400);
  });

  // The usual cause is the calendar not being shared with the service account,
  // so the message has to point the operator at that rather than say "failed".
  test('a forbidden calendar surfaces as a permission message', async () => {
    const restore = muteConsoleError();
    try {
      const env = await testEnv();
      const fetchImpl = fakeFetch({ calendar: () => new Response('forbidden', { status: 403 }) });
      const response = await withFetch(fetchImpl, () =>
        onRequestPost({
          request: request('POST', { body: { title: 'x', allDay: true, start: '2026-08-20' } }),
          env,
        }),
      );
      assert.equal(response.status, 502);
      assert.deepEqual(await response.json(), { error: '沒有權限寫入這本日曆，請聯絡管理員' });
    } finally {
      restore();
    }
  });
});

// ---------------------------------------------------------------------------

describe('PATCH and DELETE /api/calendar/events/:id', () => {
  test('patches the event by id', async () => {
    const env = await testEnv();
    const fetchImpl = fakeFetch();
    const response = await withFetch(fetchImpl, () =>
      onRequestPatch({
        request: request('PATCH', {
          body: { title: '改名', allDay: false, start: '2026-08-20T19:00', end: '2026-08-20T20:00' },
        }),
        env,
        params: { id: 'abc 123' },
      }),
    );

    assert.equal(response.status, 200);
    const [call] = fetchImpl.calendarCalls();
    assert.equal(call.method, 'PATCH');
    assert.ok(call.url.endsWith('/events/abc%20123'));
    const sent = JSON.parse(call.body);
    assert.equal(sent.summary, '改名');
    assert.equal(sent.start.date, null);
  });

  test('deletes the event and answers 204 with no body', async () => {
    const env = await testEnv();
    const fetchImpl = fakeFetch({ calendar: () => new Response(null, { status: 204 }) });
    const response = await withFetch(fetchImpl, () =>
      onRequestDelete({ request: request('DELETE'), env, params: { id: 'abc' } }),
    );

    assert.equal(response.status, 204);
    assert.equal(fetchImpl.calendarCalls()[0].method, 'DELETE');
  });

  test('a member cannot delete', async () => {
    const env = await testEnv();
    const fetchImpl = fakeFetch();
    const response = await withFetch(fetchImpl, () =>
      onRequestDelete({
        request: request('DELETE', { token: idToken(MEMBER_UID) }),
        env,
        params: { id: 'abc' },
      }),
    );

    assert.equal(response.status, 403);
    assert.equal(fetchImpl.calendarCalls().length, 0);
  });

  test('an already-deleted event reads as gone rather than as a server error', async () => {
    const env = await testEnv();
    const fetchImpl = fakeFetch({ calendar: () => new Response('{}', { status: 410 }) });
    const response = await withFetch(fetchImpl, () =>
      onRequestDelete({ request: request('DELETE'), env, params: { id: 'abc' } }),
    );

    assert.equal(response.status, 404);
    assert.deepEqual(await response.json(), { error: '這個活動已經不存在了' });
  });

  test('a missing id is rejected before anything reaches Google', async () => {
    const env = await testEnv();
    const fetchImpl = fakeFetch();
    const response = await withFetch(fetchImpl, () =>
      onRequestDelete({ request: request('DELETE'), env, params: {} }),
    );

    assert.equal(response.status, 400);
    assert.equal(fetchImpl.calendarCalls().length, 0);
  });
});

// ---------------------------------------------------------------------------

/// What Google actually answers a create with — note the `+08:00` offset on the
/// timed form and the exclusive `end.date` on the all-day form. The payload sent
/// to n8n is built from this shape, so the fixtures copy it rather than
/// simplifying it.
const CREATED_TIMED = {
  id: 'evt-timed',
  status: 'confirmed',
  summary: '小組聚會',
  location: '教會 2F',
  description: '記得帶聖經',
  htmlLink: 'https://calendar.google.com/event?eid=evt-timed',
  start: { dateTime: '2026-09-01T19:00:00+08:00', timeZone: 'Asia/Taipei' },
  end: { dateTime: '2026-09-01T21:00:00+08:00', timeZone: 'Asia/Taipei' },
};

const CREATED_ALL_DAY = {
  id: 'evt-all-day',
  status: 'confirmed',
  summary: '教會大掃除',
  htmlLink: 'https://calendar.google.com/event?eid=evt-all-day',
  start: { date: '2026-09-05' },
  end: { date: '2026-09-06' },
};

function creating(event) {
  return fakeFetch({ calendar: () => Response.json(event, { status: 200 }) });
}

const CREATE_BODY = { title: '小組聚會', allDay: false, start: '2026-09-01T19:00' };

/// requireEditor() 回傳的形狀，測 notifyPayload 時不必再跑一次權限檢查。
const ADMIN_ACTOR = { uid: ADMIN_UID, name: ADMIN_NAME };

describe('notifyPayload', () => {
  test('flattens a timed event', () => {
    assert.deepEqual(notifyPayload('created', CREATED_TIMED, ADMIN_ACTOR), {
      action: 'created',
      source: 'pwa',
      id: 'evt-timed',
      title: '小組聚會',
      allDay: false,
      start: '2026-09-01T19:00:00+08:00',
      end: '2026-09-01T21:00:00+08:00',
      location: '教會 2F',
      description: '記得帶聖經',
      link: 'https://calendar.google.com/event?eid=evt-timed',
      actorUid: ADMIN_UID,
      actorName: ADMIN_NAME,
    });
  });

  // 名字是給群組看的，uid 是給事後追查用的 —— 少了任一個都補不回來。
  test('carries both the uid and the name of the editor', () => {
    const payload = notifyPayload('created', CREATED_TIMED, {
      uid: CALENDAR_EDITOR_UID,
      name: CALENDAR_EDITOR_NAME,
    });
    assert.equal(payload.actorUid, CALENDAR_EDITOR_UID);
    assert.equal(payload.actorName, CALENDAR_EDITOR_NAME);
  });

  // 沒有名字時送 null 而不是省略，n8n 那端才看得到一致的形狀。
  test('sends a null name for an editor without one', () => {
    const payload = notifyPayload('created', CREATED_TIMED, { uid: ADMIN_UID, name: null });
    assert.equal(payload.actorUid, ADMIN_UID);
    assert.equal(payload.actorName, null);
  });

  test('reports the inclusive end date for an all-day event', () => {
    // Google stores 9/6 for a single day on 9/5; the group must be told 9/5.
    const payload = notifyPayload('created', CREATED_ALL_DAY, ADMIN_ACTOR);
    assert.equal(payload.allDay, true);
    assert.equal(payload.start, '2026-09-05');
    assert.equal(payload.end, '2026-09-05');
  });

  test('a multi-day all-day event keeps its span', () => {
    const payload = notifyPayload(
      'created',
      { start: { date: '2026-10-10' }, end: { date: '2026-10-13' } },
      ADMIN_ACTOR,
    );
    assert.equal(payload.start, '2026-10-10');
    assert.equal(payload.end, '2026-10-12');
  });

  test('missing optional fields become empty rather than undefined', () => {
    // JSON.stringify drops undefined keys, which would make the n8n side see a
    // different shape depending on what the event happened to carry.
    const payload = notifyPayload('created', { id: 'x' }, ADMIN_ACTOR);
    assert.deepEqual(payload, {
      action: 'created',
      source: 'pwa',
      id: 'x',
      title: null,
      allDay: false,
      start: null,
      end: null,
      location: '',
      description: '',
      link: null,
      actorUid: ADMIN_UID,
      actorName: ADMIN_NAME,
    });
  });
});

describe('POST /api/calendar/events — LINE notification', () => {
  test('announces a created event to n8n', async () => {
    const env = await notifyingEnv();
    const fetchImpl = creating(CREATED_TIMED);
    const response = await withFetch(fetchImpl, () =>
      onRequestPost({ request: request('POST', { body: CREATE_BODY }), env }),
    );

    assert.equal(response.status, 201);
    assert.deepEqual(fetchImpl.notifyPayload(), {
      action: 'created',
      source: 'pwa',
      id: 'evt-timed',
      title: '小組聚會',
      allDay: false,
      start: '2026-09-01T19:00:00+08:00',
      end: '2026-09-01T21:00:00+08:00',
      location: '教會 2F',
      description: '記得帶聖經',
      link: 'https://calendar.google.com/event?eid=evt-timed',
      actorUid: ADMIN_UID,
      actorName: ADMIN_NAME,
    });
  });

  test('sends the shared secret as a header', async () => {
    const env = await notifyingEnv();
    const fetchImpl = creating(CREATED_TIMED);
    await withFetch(fetchImpl, () =>
      onRequestPost({ request: request('POST', { body: CREATE_BODY }), env }),
    );

    const [call] = fetchImpl.notifyCalls();
    assert.equal(call.method, 'POST');
    assert.equal(call.init.headers['x-notify-secret'], NOTIFY_SECRET);
    assert.equal(call.init.headers['content-type'], 'application/json');
  });

  test('records the editor who created it', async () => {
    const env = await notifyingEnv();
    const fetchImpl = creating(CREATED_TIMED);
    await withFetch(fetchImpl, () =>
      onRequestPost({
        request: request('POST', { token: idToken(CALENDAR_EDITOR_UID), body: CREATE_BODY }),
        env,
      }),
    );

    assert.equal(fetchImpl.notifyPayload().actorUid, CALENDAR_EDITOR_UID);
    // 群組讀得懂的是名字，不是 uid。
    assert.equal(fetchImpl.notifyPayload().actorName, CALENDAR_EDITOR_NAME);
  });

  test('stays quiet when the webhook is not configured', async () => {
    const env = await testEnv();
    const fetchImpl = creating(CREATED_TIMED);
    const response = await withFetch(fetchImpl, () =>
      onRequestPost({ request: request('POST', { body: CREATE_BODY }), env }),
    );

    assert.equal(response.status, 201);
    assert.equal(fetchImpl.notifyCalls().length, 0);
  });

  test('stays quiet when the secret is missing', async () => {
    // Half-configured must mean off, not "send it unauthenticated".
    const env = await notifyingEnv({ NOTIFY_WEBHOOK_SECRET: '' });
    const fetchImpl = creating(CREATED_TIMED);
    const response = await withFetch(fetchImpl, () =>
      onRequestPost({ request: request('POST', { body: CREATE_BODY }), env }),
    );

    assert.equal(response.status, 201);
    assert.equal(fetchImpl.notifyCalls().length, 0);
  });

  test('a rejected notification still leaves the event created', async () => {
    const restore = muteConsoleError();
    try {
      const env = await notifyingEnv();
      const fetchImpl = fakeFetch({
        calendar: () => Response.json(CREATED_TIMED, { status: 200 }),
        notify: () => new Response('nope', { status: 401 }),
      });
      const response = await withFetch(fetchImpl, () =>
        onRequestPost({ request: request('POST', { body: CREATE_BODY }), env }),
      );

      assert.equal(response.status, 201);
      assert.equal((await response.json()).id, 'evt-timed');
    } finally {
      restore();
    }
  });

  test('an unreachable n8n still leaves the event created', async () => {
    const restore = muteConsoleError();
    try {
      const env = await notifyingEnv();
      const fetchImpl = fakeFetch({
        calendar: () => Response.json(CREATED_TIMED, { status: 200 }),
        notify: () => {
          throw new TypeError('connection refused');
        },
      });
      const response = await withFetch(fetchImpl, () =>
        onRequestPost({ request: request('POST', { body: CREATE_BODY }), env }),
      );

      assert.equal(response.status, 201);
    } finally {
      restore();
    }
  });

  test('a failed create announces nothing', async () => {
    const restore = muteConsoleError();
    try {
      const env = await notifyingEnv();
      const fetchImpl = fakeFetch({
        calendar: () => new Response('boom', { status: 500 }),
      });
      const response = await withFetch(fetchImpl, () =>
        onRequestPost({ request: request('POST', { body: CREATE_BODY }), env }),
      );

      assert.notEqual(response.status, 201);
      assert.equal(fetchImpl.notifyCalls().length, 0);
    } finally {
      restore();
    }
  });

  test('a rejected caller announces nothing', async () => {
    const env = await notifyingEnv();
    const fetchImpl = creating(CREATED_TIMED);
    const response = await withFetch(fetchImpl, () =>
      onRequestPost({
        request: request('POST', { token: idToken(MEMBER_UID), body: CREATE_BODY }),
        env,
      }),
    );

    assert.equal(response.status, 403);
    assert.equal(fetchImpl.notifyCalls().length, 0);
  });

  test('the notification does not hold up the response', async () => {
    const env = await notifyingEnv();
    // n8n hangs until this is released. If the handler awaited the notification
    // instead of handing it to waitUntil, the await below would never return.
    let release;
    const hung = new Promise((resolve) => {
      release = resolve;
    });
    const fetchImpl = fakeFetch({
      calendar: () => Response.json(CREATED_TIMED, { status: 200 }),
      notify: async () => {
        await hung;
        return new Response(null, { status: 200 });
      },
    });
    const background = [];

    const response = await withFetch(fetchImpl, async () => {
      const result = await onRequestPost({
        request: request('POST', { body: CREATE_BODY }),
        env,
        waitUntil: (promise) => background.push(promise),
      });
      assert.equal(background.length, 1);
      release();
      // Drain inside withFetch: letting it settle after the real fetch is back
      // would put this test on the network.
      await Promise.all(background);
      return result;
    });

    assert.equal(response.status, 201);
    assert.equal(fetchImpl.notifyCalls().length, 1);
  });
});
