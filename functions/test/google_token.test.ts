import assert from 'node:assert/strict';
import { test } from 'node:test';

import { GoogleAuthRevoked, googleApi, type OAuthConfig } from '../src/calendar.js';

const config: OAuthConfig = {
  clientId: 'synthetic-client',
  clientSecret: 'synthetic-secret',
  redirectUri: 'https://unused.example/callback',
  appUrl: 'https://unused.example',
  tokenKey: '',
};
const grant = { churchId: 'C1', revision: 'first-grant' };

test('Google PATCH clears the opposite date field when changing event type, while POST sends only its date type', async () => {
  const requests: { url: string; method?: string; body: Record<string, unknown> }[] = [];
  const google = googleApi({ fetch: async (url, init) => {
    const body = JSON.parse(init!.body as string) as Record<string, unknown>;
    requests.push({ url, method: init!.method, body });
    return Response.json({ id: 'event', summary: body.summary, start: body.start, end: body.end });
  } });
  const allDay = { id: 'event', title: '退修會', start: '2026-10-10', end: '2026-10-12', allDay: true, description: '保留說明' };
  await google.upsert('access', 'church@example.com', allDay);
  assert.equal(requests[0].method, 'PATCH');
  assert.match(requests[0].url, /church%40example\.com\/events\/event$/);
  assert.deepEqual(requests[0].body, {
    summary: '退修會', description: '保留說明',
    // No group given (#84): whose it is stays as Google has it.
    start: { date: '2026-10-10', dateTime: null },
    end: { date: '2026-10-12', dateTime: null },
  });

  await google.upsert('access', 'church@example.com', { ...allDay, start: '2026-10-10T10:00:00+08:00', end: '2026-10-10T12:00:00+08:00', allDay: false });
  assert.equal(requests[1].method, 'PATCH');
  assert.deepEqual(requests[1].body.start, { dateTime: '2026-10-10T10:00:00+08:00', date: null });
  assert.deepEqual(requests[1].body.end, { dateTime: '2026-10-10T12:00:00+08:00', date: null });
  assert.equal('recurrence' in requests[1].body, false, 'unrelated Google fields are not patched');

  await google.upsert('access', 'church@example.com', { ...allDay, id: undefined });
  assert.equal(requests[2].method, 'POST');
  assert.deepEqual(requests[2].body.start, { date: '2026-10-10' });
  assert.deepEqual(requests[2].body.end, { date: '2026-10-12' });

  await google.upsert('access', 'church@example.com', { ...allDay, group: '' });
  assert.deepEqual(requests[3].body.extendedProperties, { private: { marthaGroup: '' } }, "given back to the church");
  await google.setGroup('access', 'church@example.com', 'series', 'ministry:worship');
  assert.equal(requests[4].method, 'PATCH');
  assert.match(requests[4].url, /events\/series$/);
  assert.deepEqual(requests[4].body, { extendedProperties: { private: { marthaGroup: 'ministry:worship' } } }, 'only whose it is');
});

test('one church reuses its unexpired Google access token', async (t) => {
  let refreshes = 0;
  const fetch = async () => {
    refreshes++;
    return Response.json({ access_token: `access-${refreshes}`, expires_in: 3600 });
  };
  t.mock.method(globalThis, 'fetch', fetch);
  const google = googleApi({ fetch, now: () => new Date('2026-10-10T00:00:00Z') });
  assert.equal(await google.accessToken('synthetic-refresh', config, grant), 'access-1');
  assert.equal(await google.accessToken('synthetic-refresh', config, grant), 'access-1');
  assert.equal(refreshes, 1);
});

test('Google tokens refresh a minute before expiry, using the request start time', async () => {
  let time = Date.parse('2026-10-10T00:00:00Z');
  let refreshes = 0;
  const fetch = async () => {
    refreshes++;
    time += 10_000;
    return Response.json({ access_token: `access-${refreshes}`, expires_in: 120 });
  };
  const google = googleApi({ fetch, now: () => new Date(time) });
  assert.equal(await google.accessToken('synthetic-refresh', config, grant), 'access-1');
  time = Date.parse('2026-10-10T00:00:59Z');
  assert.equal(await google.accessToken('synthetic-refresh', config, grant), 'access-1');
  time += 1000;
  assert.equal(await google.accessToken('synthetic-refresh', config, grant), 'access-2');
  assert.equal(refreshes, 2);
});

test('concurrent callers in one church share an in-progress Google token refresh', async () => {
  let refreshes = 0;
  let release!: () => void;
  const gate = new Promise<void>((resolve) => { release = resolve; });
  const fetch = async () => {
    refreshes++;
    await gate;
    return Response.json({ access_token: 'shared-access', expires_in: 3600 });
  };
  const google = googleApi({ fetch });
  const requests = Array.from({ length: 8 }, () => google.accessToken('synthetic-refresh', config, grant));
  release();
  assert.deepEqual(await Promise.all(requests), Array(8).fill('shared-access'));
  assert.equal(refreshes, 1);
});

test('a failed revoke still forgets the cached Google access token', async () => {
  let revoked = false;
  const fetch = async (url: string) => {
    if (url.includes('/revoke?')) { revoked = true; throw new Error('revoke unavailable'); }
    return revoked
      ? Response.json({ error: 'invalid_grant' }, { status: 400 })
      : Response.json({ access_token: 'old-access', expires_in: 3600 });
  };
  const google = googleApi({ fetch });
  await google.accessToken('synthetic-refresh', config, grant);
  await assert.rejects(google.revoke('synthetic-refresh'), /revoke unavailable/);
  await assert.rejects(google.accessToken('synthetic-refresh', config, grant), GoogleAuthRevoked);
});

test('a token refresh finishing after revoke cannot repopulate the grant cache', async () => {
  let refreshes = 0;
  let release!: () => void;
  const gate = new Promise<void>((resolve) => { release = resolve; });
  const fetch = async (url: string) => {
    if (url.includes('/revoke?')) return new Response(null, { status: 200 });
    const attempt = ++refreshes;
    if (attempt === 1) await gate;
    return Response.json({ access_token: `access-${attempt}`, expires_in: 3600 });
  };
  const google = googleApi({ fetch });
  const old = google.accessToken('synthetic-refresh', config, grant);
  await google.revoke('synthetic-refresh');
  release();
  await old;
  assert.equal(await google.accessToken('synthetic-refresh', config, grant), 'access-2');
  assert.equal(refreshes, 2);
});

test('a rejected Google access token is refreshed on the next request, without retrying a write', async () => {
  let refreshes = 0;
  let writes = 0;
  const fetch = async (url: string) => {
    if (url === 'https://oauth2.googleapis.com/token') {
      return Response.json({ access_token: `access-${++refreshes}`, expires_in: 3600 });
    }
    writes++;
    return new Response('Unauthorized', { status: 401 });
  };
  const google = googleApi({ fetch });
  const token = await google.accessToken('synthetic-refresh', config, grant);
  await assert.rejects(google.upsert(token, 'calendar', { title: '活動', start: '2026-10-10', end: '2026-10-11', allDay: true }), /google 401/);
  assert.equal(writes, 1);
  assert.equal(await google.accessToken('synthetic-refresh', config, grant), 'access-2');
});

test('malformed token responses fail rather than authorizing a Google request', async () => {
  let attempts = 0;
  const google = googleApi({ fetch: async () => {
    attempts++;
    return Response.json(attempts === 1 ? { expires_in: 3600 } : { access_token: 'valid-access', expires_in: 3600 });
  } });
  await assert.rejects(google.accessToken('synthetic-refresh', config, grant), /access token/);
  assert.equal(await google.accessToken('synthetic-refresh', config, grant), 'valid-access');
  assert.equal(attempts, 2);
});

test('token reuse never crosses church, grant revision, account, or OAuth configuration', async () => {
  let refreshes = 0;
  const google = googleApi({ fetch: async () => Response.json({ access_token: `access-${++refreshes}`, expires_in: 3600 }) });
  assert.equal(await google.accessToken('synthetic-refresh', config, grant), 'access-1');
  assert.equal(await google.accessToken('synthetic-refresh', config, { ...grant, churchId: 'C2' }), 'access-2');
  assert.equal(await google.accessToken('synthetic-refresh', config, { ...grant, revision: 'reconnected' }), 'access-3');
  assert.equal(await google.accessToken('different-account', config, grant), 'access-4');
  assert.equal(await google.accessToken('synthetic-refresh', { ...config, clientSecret: 'rotated-secret' }, grant), 'access-5');
  assert.equal(await google.accessToken('synthetic-refresh', config, grant), 'access-1');
  assert.equal(await google.accessToken('synthetic-refresh', config), 'access-6');
  assert.equal(await google.accessToken('synthetic-refresh', config), 'access-7');
  assert.equal(refreshes, 7);
});

test('unknown or already-expiring token lifetimes are not reused', async () => {
  for (const expires_in of [undefined, null, '3600', 0, -1, 60, Number.MAX_VALUE]) {
    let refreshes = 0;
    const google = googleApi({ fetch: async () => Response.json({ access_token: `access-${++refreshes}`, expires_in }) });
    assert.equal(await google.accessToken('synthetic-refresh', config, grant), 'access-1');
    assert.equal(await google.accessToken('synthetic-refresh', config, grant), 'access-2');
    assert.equal(refreshes, 2);
  }
});

test('failed concurrent token refreshes are shared but never poison the next request', async () => {
  let refreshes = 0;
  let release!: () => void;
  const gate = new Promise<void>((resolve) => { release = resolve; });
  const google = googleApi({ fetch: async () => {
    if (++refreshes === 1) { await gate; throw new Error('Google unavailable'); }
    return Response.json({ access_token: 'recovered', expires_in: 3600 });
  } });
  const requests = Array.from({ length: 8 }, () => google.accessToken('synthetic-refresh', config, grant));
  release();
  const failed = await Promise.allSettled(requests);
  assert.equal(failed.filter((r) => r.status === 'rejected').length, 8);
  assert.equal(refreshes, 1);
  assert.equal(await google.accessToken('synthetic-refresh', config, grant), 'recovered');
  assert.equal(refreshes, 2);
});

test('a warm instance bounds retained tokens when many churches connect', async () => {
  let refreshes = 0;
  const google = googleApi({ fetch: async () => Response.json({ access_token: `access-${++refreshes}`, expires_in: 3600 }) });
  for (let i = 0; i < 1000; i++) await google.accessToken('synthetic-refresh', config, { ...grant, churchId: `C${i}` });
  assert.equal(await google.accessToken('synthetic-refresh', config, { ...grant, churchId: 'C0' }), 'access-1001');
});

test('a stalled refresh cannot keep later callers attached indefinitely or overwrite their token', async () => {
  let time = 0;
  let refreshes = 0;
  let release!: () => void;
  const gate = new Promise<void>((resolve) => { release = resolve; });
  const google = googleApi({ now: () => new Date(time), fetch: async () => {
    const attempt = ++refreshes;
    if (attempt === 1) await gate;
    return Response.json({ access_token: `access-${attempt}`, expires_in: 3600 });
  } });
  const old = google.accessToken('synthetic-refresh', config, grant);
  time += 61_000;
  const later = google.accessToken('synthetic-refresh', config, grant);
  release();
  assert.equal(await later, 'access-2');
  await old;
  assert.equal(await google.accessToken('synthetic-refresh', config, grant), 'access-2');
  assert.equal(refreshes, 2);
});

test('refreshes started during revoke cannot refill its cache after revoke succeeds or fails', async () => {
  for (const fails of [false, true]) {
    let finishRevoke!: () => void;
    let finishRefresh!: () => void;
    const revokeGate = new Promise<void>((resolve) => { finishRevoke = resolve; });
    const refreshGate = new Promise<void>((resolve) => { finishRefresh = resolve; });
    let refreshes = 0;
    const google = googleApi({ fetch: async (url) => {
      if (url.includes('/revoke?')) {
        await revokeGate;
        if (fails) throw new Error('revoke unavailable');
        return new Response(null, { status: 200 });
      }
      const attempt = ++refreshes;
      await refreshGate;
      return Response.json({ access_token: `access-${attempt}`, expires_in: 3600 });
    } });
    const revoking = google.revoke('synthetic-refresh').then(() => null, (error: Error) => error);
    const duringRevoke = google.accessToken('synthetic-refresh', config, grant);
    finishRevoke();
    const outcome = await revoking;
    if (fails) assert.match(outcome!.message, /revoke unavailable/);
    else assert.equal(outcome, null);
    finishRefresh();
    await duringRevoke;
    assert.equal(await google.accessToken('synthetic-refresh', config, grant), 'access-2');
    assert.equal(refreshes, 2);
  }
});
