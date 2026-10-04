import assert from 'node:assert/strict';
import { createHmac, randomBytes } from 'node:crypto';
import { beforeEach, describe, test } from 'node:test';

import { Timestamp } from 'firebase-admin/firestore';

import { decrypt } from '../src/calendar.js';
import { purgeDeletedChurches } from '../src/church.js';
import { deliver, webhookRotateSecret, webhookSave, webhookTest, type WebhookDeps } from '../src/webhook.js';
import { caller, clearFirestore, db, deps, fakeFetch, rejectsWith, seedChurch, setNow, type FakeResponse } from './support.js';

const HOOK = 'https://n8n.example/webhook/abc';
const key = randomBytes(32).toString('base64');

function hookDeps(answer: FakeResponse = { status: 200 }) {
  const f = fakeFetch({ [HOOK]: answer });
  const d: WebhookDeps = { ...deps, fetch: f.fetch, secretKey: key };
  return { d, requests: f.requests };
}

async function church(cid = 'C1', extra: Record<string, unknown> = {}) {
  await seedChurch(cid, { pastor: 'admin', mei: 'staff' }, { name: '恩典堂', ...extra });
}

const settings = async (cid = 'C1') => (await db.doc(`churches/${cid}/settings/webhook`).get()).data();
const sealed = async (cid = 'C1') => (await db.doc(`webhookSecrets/${cid}`).get()).data();

beforeEach(async () => {
  await clearFirestore();
  setNow(new Date('2026-10-04T10:00:00+08:00'));
});

describe('webhook settings', () => {
  test('the first save makes a secret, shown once, stored sealed', async () => {
    await church();
    const { d } = hookDeps();
    const r = await webhookSave(d, caller('pastor'), { churchId: 'C1', url: HOOK, events: { calendar: true, roster: false } });
    assert.match(r.secret!, /^whsec_/);
    const s = await settings();
    assert.equal(s!.url, HOOK);
    assert.deepEqual(s!.events, { calendar: true, roster: false });
    assert.equal(JSON.stringify(s).includes(r.secret!), false, 'not in what admins read');
    const stored = (await sealed())!.secret as string;
    assert.notEqual(stored, r.secret);
    assert.equal(decrypt(stored, key), r.secret);

    const again = await webhookSave(d, caller('pastor'), { churchId: 'C1', url: HOOK, events: { calendar: true, roster: true } });
    assert.equal(again.secret, null, 'never shown again');
    assert.equal(decrypt((await sealed())!.secret as string, key), r.secret);
  });

  test('an admin may type the secret, or replace it', async () => {
    await church();
    const { d } = hookDeps();
    const mine = 'my-own-secret-123456';
    assert.equal((await webhookSave(d, caller('pastor'), { churchId: 'C1', url: HOOK, secret: mine })).secret, null);
    assert.equal(decrypt((await sealed())!.secret as string, key), mine);
    const rotated = await webhookRotateSecret(d, caller('pastor'), { churchId: 'C1' });
    assert.match(rotated.secret!, /^whsec_/);
    assert.equal(decrypt((await sealed())!.secret as string, key), rotated.secret);
    await rejectsWith(webhookRotateSecret(d, caller('pastor'), { churchId: 'C1', secret: 'short' }), 'unknown');
  });

  test('https only, admins of that church only', async () => {
    await church();
    await church('C2');
    const { d } = hookDeps();
    await rejectsWith(webhookSave(d, caller('pastor'), { churchId: 'C1', url: 'http://n8n.example/x' }), 'unknown');
    await rejectsWith(webhookSave(d, caller('mei'), { churchId: 'C1', url: HOOK }), 'permissionDenied');
    await db.doc('churches/C2/members/pastor').delete();
    await rejectsWith(webhookSave(d, caller('pastor'), { churchId: 'C2', url: HOOK }), 'permissionDenied');
    await rejectsWith(webhookTest(d, caller('mei'), { churchId: 'C1' }), 'permissionDenied');
  });

  test('turning it off forgets the URL and the secret', async () => {
    await church();
    const { d } = hookDeps();
    await webhookSave(d, caller('pastor'), { churchId: 'C1', url: HOOK });
    await webhookSave(d, caller('pastor'), { churchId: 'C1', url: null });
    assert.equal(await settings(), undefined);
    assert.equal(await sealed(), undefined);
  });
});

describe('delivering', () => {
  test('a test ping is signed over the timestamp and body, and recorded', async () => {
    await church();
    const { d, requests } = hookDeps();
    const { secret } = await webhookSave(d, caller('pastor'), { churchId: 'C1', url: HOOK });
    const r = await webhookTest(d, caller('pastor'), { churchId: 'C1' });
    assert.deepEqual(r, { ok: true, status: 200, error: null });

    const req = requests[0];
    assert.equal(req.method, 'POST');
    assert.equal(req.headers['content-type'], 'application/json');
    assert.equal(req.headers['x-martha-event'], 'ping');
    assert.match(req.headers['x-martha-delivery'], /^[0-9a-f-]{36}$/);
    const ts = req.headers['x-martha-timestamp'];
    assert.equal(ts, String(Date.parse('2026-10-04T10:00:00+08:00') / 1000));
    const expected = createHmac('sha256', secret!).update(`${ts}.${req.body}`).digest('hex');
    assert.equal(req.headers['x-martha-signature'], `sha256=${expected}`);
    const other = createHmac('sha256', secret!).update(`${Number(ts) + 1}.${req.body}`).digest('hex');
    assert.notEqual(req.headers['x-martha-signature'], `sha256=${other}`, 'the timestamp is signed');
    assert.deepEqual(JSON.parse(req.body), { source: 'martha', churchId: 'C1', churchName: '恩典堂' });

    const last = (await settings())!.lastDelivery;
    assert.equal(last.ok, true);
    assert.equal(last.status, 200);
    assert.equal(last.event, 'ping');
    assert.ok(last.at instanceof Timestamp);
  });

  test('failures are recorded as an HTTP status or a timeout, never thrown', async () => {
    await church();
    for (const [answer, expected] of [
      [{ status: 500 }, { ok: false, status: 500, error: 'http' }],
      [{ redirect: 'https://elsewhere.example/' }, { ok: false, status: 302, error: 'http' }],
      [{ delayMs: 6000 }, { ok: false, status: null, error: 'timeout' }],
    ] as const) {
      const { d } = hookDeps(answer);
      await webhookSave(d, caller('pastor'), { churchId: 'C1', url: HOOK });
      assert.deepEqual(await deliver(d, 'C1', 'ping', {}), expected);
      assert.deepEqual({ ...(await settings())!.lastDelivery, at: undefined, event: undefined }, { ...expected, at: undefined, event: undefined });
    }
    const dead = { ...deps, fetch: fakeFetch().fetch, secretKey: key };
    assert.deepEqual(await deliver(dead, 'C1', 'ping', {}), { ok: false, status: null, error: 'network' });
  });

  test('only switched-on events are sent', async () => {
    await church();
    const { d, requests } = hookDeps();
    await webhookSave(d, caller('pastor'), { churchId: 'C1', url: HOOK, events: { calendar: true, roster: false } });
    assert.equal(await deliver(d, 'C1', 'roster.changed', {}), null);
    assert.ok(await deliver(d, 'C1', 'calendar.created', {}));
    assert.deepEqual(requests.map((r) => r.headers['x-martha-event']), ['calendar.created']);
  });

  test('a suspended or deleted church sends nothing', async () => {
    await church();
    const { d, requests } = hookDeps();
    await webhookSave(d, caller('pastor'), { churchId: 'C1', url: HOOK, events: { calendar: true, roster: true } });
    for (const status of ['suspended', 'deleted']) {
      await db.doc('churches/C1').update({ status });
      assert.equal(await deliver(d, 'C1', 'calendar.created', {}), null);
    }
    assert.equal(requests.length, 0);
  });

  test('purging a church removes its webhook settings and secret', async () => {
    await church('Old');
    const { d } = hookDeps();
    await webhookSave(d, caller('pastor'), { churchId: 'Old', url: HOOK });
    await db.doc('churches/Old').update({ status: 'deleted', deletedAt: Timestamp.fromDate(new Date('2026-08-01T00:00:00Z')) });
    await purgeDeletedChurches(deps);
    assert.equal(await settings('Old'), undefined);
    assert.equal(await sealed('Old'), undefined);
  });
});
