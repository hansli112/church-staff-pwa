import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { beforeEach, describe, test } from 'node:test';

import { Timestamp } from 'firebase-admin/firestore';

import { purgeDeletedChurches } from '../src/church.js';
import { dutyChanges, queueRosterChange, sendRosterChanges } from '../src/rosterWebhook.js';
import { webhookSave, type WebhookDeps } from '../src/webhook.js';
import { caller, clearFirestore, db, deps, fakeFetch, seedChurch, setNow } from './support.js';

const HOOK = 'https://n8n.example/roster';
const key = randomBytes(32).toString('base64');

let f: ReturnType<typeof fakeFetch>;
let d: WebhookDeps;

async function church(cid = 'C1', events = { calendar: false, roster: true }) {
  await seedChurch(cid, { pastor: 'admin' }, { name: '恩典堂' });
  await db.doc(`churches/${cid}/members/pastor`).update({ name: '王牧師' });
  await db.doc(`churches/${cid}/settings/services`).set({ services: [{ id: 'sunday', name: '主日崇拜' }], ids: ['sunday'] });
  await webhookSave(d, caller('pastor'), { churchId: cid, url: HOOK, events });
}

let n = 0;
/** Writes a roster day and queues it as the trigger would. */
async function write(cid: string, day: string, duties: { role: string; people: string[] }[], via?: string) {
  const ref = db.doc(`churches/${cid}/rosters/${day}_sunday`);
  const before = await ref.get();
  await ref.set({ type: 'sunday', dateKey: day, duties, ...(via ? { via } : {}) });
  return queueRosterChange(d, cid, before, await ref.get(), 'pastor', `ev${++n}`);
}

const bodies = () => f.requests.map((r) => JSON.parse(r.body));

beforeEach(async () => {
  await clearFirestore();
  setNow(new Date('2026-10-01T10:00:00+08:00'));
  f = fakeFetch({ [HOOK]: { status: 200 } });
  d = { ...deps, fetch: f.fetch, secretKey: key };
});

describe('roster webhooks', () => {
  test('who was put on and taken off each duty', () => {
    assert.deepEqual(
      dutyChanges(
        [
          { role: '司琴', people: ['陳志豪'] },
          { role: '招待', people: ['李美玉'] },
        ],
        [
          { role: '司琴', people: ['李美玉'] },
          { role: '招待', people: ['李美玉'] },
          { role: '音控', people: ['林同工'] },
        ],
      ),
      [
        { duty: '司琴', added: ['李美玉'], removed: ['陳志豪'] },
        { duty: '音控', added: ['林同工'], removed: [] },
      ],
    );
  });

  test('changes within the window go out as one notice, then the outbox is empty', async () => {
    await church();
    await write('C1', '2026-10-04', [{ role: '司琴', people: ['李美玉'] }]);
    await write('C1', '2026-10-04', [{ role: '司琴', people: ['陳志豪'] }]);
    await write('C1', '2026-10-11', [{ role: '招待', people: ['李美玉', '陳志豪'] }]);
    assert.equal(await sendRosterChanges(d), 1);
    assert.equal(f.requests.length, 1);
    assert.equal(f.requests[0].headers['x-martha-event'], 'roster.changed');
    const body = bodies()[0];
    assert.equal(body.source, 'martha');
    assert.equal(body.churchId, 'C1');
    assert.equal(body.churchName, '恩典堂');
    assert.equal(body.count, 3);
    assert.equal(body.imported, false);
    assert.deepEqual(body.changes[1], {
      date: '2026-10-04',
      serviceId: 'sunday',
      serviceName: '主日崇拜',
      duties: [{ duty: '司琴', added: ['陳志豪'], removed: ['李美玉'] }],
      actorUid: 'pastor',
      actorName: '王牧師',
      via: 'app',
    });
    assert.equal((await db.collection('webhookOutbox/C1/rosterChanges').get()).size, 0);
    assert.equal(await sendRosterChanges(d), 0, 'nothing left to send');
  });

  test('an import is one summary', async () => {
    await church();
    for (let day = 4; day <= 25; day += 7) {
      await write('C1', `2026-10-${String(day).padStart(2, '0')}`, [{ role: '司會', people: ['王牧師'] }], 'import');
    }
    await sendRosterChanges(d);
    assert.equal(f.requests.length, 1);
    assert.equal(bodies()[0].count, 4);
    assert.equal(bodies()[0].imported, true);
  });

  test('each church gets its own single notice', async () => {
    await church('C1');
    await church('C2');
    await write('C1', '2026-10-04', [{ role: '司琴', people: ['甲'] }]);
    await write('C2', '2026-10-04', [{ role: '司琴', people: ['乙'] }]);
    await write('C2', '2026-10-11', [{ role: '司琴', people: ['丙'] }]);
    assert.equal(await sendRosterChanges(d), 2);
    const byChurch = Object.fromEntries(bodies().map((b) => [b.churchId, b.count]));
    assert.deepEqual(byChurch, { C1: 1, C2: 2 });
  });

  test('nothing is queued when roster notices are off, for past days, or when nobody moved', async () => {
    await church('Off', { calendar: true, roster: false });
    assert.equal(await write('Off', '2026-10-04', [{ role: '司琴', people: ['甲'] }]), false);
    await church('C1');
    assert.equal(await write('C1', '2026-09-27', [{ role: '司琴', people: ['甲'] }]), false, 'past day');
    await write('C1', '2026-10-04', [{ role: '司琴', people: ['甲'] }]);
    assert.equal(await write('C1', '2026-10-04', [{ role: '司琴', people: ['甲'] }]), false, 'same people');
    await sendRosterChanges(d);
    assert.equal(bodies()[0].count, 1);
  });

  test('a suspended church sends nothing and its outbox is dropped', async () => {
    await church();
    await write('C1', '2026-10-04', [{ role: '司琴', people: ['甲'] }]);
    await db.doc('churches/C1').update({ status: 'suspended' });
    assert.equal(await write('C1', '2026-10-11', [{ role: '司琴', people: ['乙'] }]), false);
    assert.equal(await sendRosterChanges(d), 0);
    assert.equal(f.requests.length, 0);
    assert.equal((await db.collection('webhookOutbox/C1/rosterChanges').get()).size, 0);
  });

  test('purging a church clears its outbox', async () => {
    await church('Old');
    await write('Old', '2026-10-04', [{ role: '司琴', people: ['甲'] }]);
    await db.doc('churches/Old').update({ status: 'deleted', deletedAt: Timestamp.fromDate(new Date('2026-08-01T00:00:00Z')) });
    await purgeDeletedChurches(deps);
    assert.equal((await db.collection('webhookOutbox/Old/rosterChanges').get()).size, 0);
  });
});
