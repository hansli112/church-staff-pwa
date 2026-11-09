import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

import { Timestamp } from 'firebase-admin/firestore';

import { redeemInvite } from '../src/invites.js';
import { sendJoinedPushes } from '../src/joinedPushes.js';
import { caller, clearFirestore, db, deps, fakePush, seedChurch, setNow } from './support.js';

const appUrl = 'https://app.example';

beforeEach(async () => {
  await clearFirestore();
  await seedChurch('C1', { alice: 'admin', bob: 'staff' });
  await db.doc('users/alice').set({ name: 'alice', fcm: { phone: 'tok-alice' } });
  await db.doc('users/bob').set({ name: 'bob', fcm: { phone: 'tok-bob' } });
  for (const [uid, name] of [['carol', '新朋友'], ['dave', '大衛'], ['erin', '以琳'], ['frank', '法蘭克']]) {
    await db.doc(`users/${uid}`).set({ name });
  }
  await db.doc('invites/JOINME2026').set({
    cid: 'C1',
    churchName: 'C1',
    expiresAt: Timestamp.fromDate(new Date('2026-12-31T00:00:00Z')),
    revoked: false,
  });
});

const at = (local: string) => setNow(new Date(`${local}+08:00`));

function push() {
  const p = fakePush();
  const d = { ...deps, messaging: p.messaging, appUrl };
  return { sent: p.sent, join: (uid: string) => redeemInvite(d, caller(uid), { code: 'JOINME2026' }), sendDue: () => sendJoinedPushes(d) };
}

describe('someone joining by invite', () => {
  test('the first is told to the admins at once; who joins within the hour comes after it, as one', async () => {
    const { sent, join, sendDue } = push();
    at('2026-11-09T10:00:00');
    await join('carol');
    assert.deepEqual(
      sent.map((s) => [s.tokens, s.title, s.body, s.link]),
      [[['tok-alice'], 'C1', '「新朋友」加入了教會', '/c/C1?to=%2Fme%2Fmembers']],
    );

    at('2026-11-09T10:20:00');
    await join('dave');
    at('2026-11-09T10:40:00');
    await join('erin');
    await join('erin');
    at('2026-11-09T10:45:00');
    await sendDue();
    assert.equal(sent.length, 1, 'within the hour, nothing more');

    // The run's push is written a few seconds after its clock is read.
    at('2026-11-09T11:00:05');
    await sendDue();
    assert.equal(sent[1].body, '「大衛」等 2 人加入了教會');
    await sendDue();
    assert.equal(sent.length, 2, 'told once');

    at('2026-11-09T11:30:00');
    await join('frank');
    assert.equal(sent.length, 2, 'an hour since the last');
    at('2026-11-09T12:00:00');
    await sendDue();
    assert.equal(sent[2]?.body, '「法蘭克」加入了教會');
  });

  test('at night, waits for 7:00', async () => {
    const { sent, join, sendDue } = push();
    at('2026-11-09T23:00:00');
    await join('carol');
    at('2026-11-10T06:00:00');
    await sendDue();
    assert.equal(sent.length, 0);
    at('2026-11-10T07:00:00');
    await sendDue();
    assert.deepEqual(sent.map((s) => s.body), ['「新朋友」加入了教會']);
  });

  test('a church closed meanwhile is told nothing', async () => {
    const { sent, join, sendDue } = push();
    at('2026-11-09T10:00:00');
    await join('carol');
    at('2026-11-09T10:10:00');
    await join('dave');
    await db.doc('churches/C1').update({ status: 'suspended' });
    at('2026-11-09T11:00:00');
    await sendDue();
    assert.equal(sent.length, 1);
    assert.equal((await db.doc('joinedPushes/C1').get()).exists, false);
  });
});
