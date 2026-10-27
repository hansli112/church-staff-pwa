import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

import { Timestamp } from 'firebase-admin/firestore';

import { deleteAccount } from '../src/account.js';
import { forgetOldNotifications, NOTIFICATION_DAYS } from '../src/notificationList.js';
import { notifyMembers } from '../src/push.js';
import { onMemberDeleted } from '../src/triggers.js';
import { memoryGoogle } from '../src/memoryGoogle.js';
import { DAY_MS } from '../src/common.js';
import { auth, caller, clearFirestore, db, deps, fakePush, seedChurch, setNow } from './support.js';

const appUrl = 'https://app.example';
const now = new Date('2026-10-27T10:00:00+08:00');

beforeEach(async () => {
  await clearFirestore();
  setNow(now);
});

/** Everything in [uid]'s 通知列表, oldest first, without when. */
async function listOf(uid: string) {
  const q = await db.collection(`users/${uid}/notifications`).orderBy('at').get();
  return q.docs.map((d) => {
    const { at, ...rest } = d.data();
    assert.ok(at instanceof Timestamp, 'at is when it was sent');
    return rest;
  });
}

/** A notification already in [uid]'s list, from church [cid], sent [at]. */
const kept = (uid: string, cid: string, at: Date) =>
  db.collection(`users/${uid}/notifications`).add({
    cid,
    kind: 'reminder',
    title: 't',
    body: 'b',
    link: '/home',
    at: Timestamp.fromDate(at),
  });

const hoursAgo = (h: number) => new Date(Date.now() - h * 3_600_000);

describe('通知列表 (#89)', () => {
  test('every push is kept in its person’s list, with where it opens', async () => {
    await seedChurch('C1', { alice: 'admin' });
    await db.doc('users/alice').set({ fcm: { phone: 'tok' } });
    const { messaging } = fakePush();
    await notifyMembers({ db, messaging, appUrl }, 'C1', ['alice'], 'memberLeft', (w) => ({
      title: 'C1',
      body: w.memberLeft('小明'),
      link: '/me/members',
    }));
    await notifyMembers({ db, messaging, appUrl }, 'C1', ['alice'], 'reminder', () => ({ title: 't', body: 'b' }));
    assert.deepEqual(await listOf('alice'), [
      { cid: 'C1', kind: 'memberLeft', title: 'C1', body: '「小明」退出了教會', link: '/me/members' },
      { cid: 'C1', kind: 'reminder', title: 't', body: 'b', link: '/home' },
    ]);
  });

  test('a kind someone muted is kept all the same, only not pushed', async () => {
    await seedChurch('C1', { alice: 'admin' });
    await db.doc('churches/C1/members/alice').update({ 'notificationPrefs.muted': ['reminder'] });
    await db.doc('users/alice').set({ fcm: { phone: 'tok' } });
    const { messaging, sent } = fakePush();
    assert.equal(await notifyMembers({ db, messaging, appUrl }, 'C1', ['alice'], 'reminder', () => ({ title: 't', body: 'b' })), 0);
    assert.deepEqual(sent, []);
    assert.equal((await listOf('alice')).length, 1);
  });

  test('someone with no device to push to has it in their list', async () => {
    await seedChurch('C1', { alice: 'admin' });
    const { messaging } = fakePush();
    assert.equal(await notifyMembers({ db, messaging, appUrl }, 'C1', ['alice'], 'reminder', () => ({ title: 't', body: 'b' })), 0);
    assert.equal((await listOf('alice')).length, 1);
  });

  test('in their own language', async () => {
    await seedChurch('C1', { alice: 'admin', bob: 'admin' });
    await db.doc('users/bob').set({ appLocale: 'en' });
    const { messaging } = fakePush();
    await notifyMembers({ db, messaging, appUrl }, 'C1', ['alice', 'bob'], 'memberLeft', (w) => ({ title: 'C1', body: w.memberLeft(null) }));
    assert.equal((await listOf('alice'))[0].body, '有人退出了教會');
    assert.notEqual((await listOf('bob'))[0].body, '有人退出了教會');
  });

  test('nobody outside the church gets one', async () => {
    await seedChurch('C1', { alice: 'admin' });
    await seedChurch('C2', { eve: 'admin' });
    const { messaging } = fakePush();
    await notifyMembers({ db, messaging, appUrl }, 'C1', ['eve'], 'reminder', () => ({ title: 't', body: 'b' }));
    assert.deepEqual(await listOf('eve'), []);
  });

  test('the app icon’s number: what is unread in every church of theirs, this one included', async () => {
    await seedChurch('C1', { alice: 'admin' });
    await seedChurch('C2', { alice: 'staff' });
    await db.doc('users/alice').set({
      fcm: { phone: 'tok' },
      notificationsSeenAt: { C1: Timestamp.fromDate(hoursAgo(5)) },
    });
    await kept('alice', 'C1', hoursAgo(6)); // seen
    await kept('alice', 'C1', hoursAgo(4)); // since
    await kept('alice', 'C2', hoursAgo(30)); // C2's list never opened
    const { messaging, sent } = fakePush();
    await notifyMembers({ db, messaging, appUrl }, 'C1', ['alice'], 'reminder', () => ({ title: 't', body: 'b' }));
    assert.equal(sent[0].badge, 3);
  });

  test('each person gets their own number', async () => {
    await seedChurch('C1', { alice: 'admin', bob: 'admin' });
    await db.doc('users/alice').set({ fcm: { phone: 'tok-a' } });
    await db.doc('users/bob').set({ fcm: { phone: 'tok-b' } });
    await kept('bob', 'C1', hoursAgo(1));
    const { messaging, sent } = fakePush();
    await notifyMembers({ db, messaging, appUrl }, 'C1', ['alice', 'bob'], 'reminder', () => ({ title: 't', body: 'b' }));
    assert.deepEqual(
      sent.map((s) => [s.tokens, s.badge]).sort(),
      [
        [['tok-a'], 1],
        [['tok-b'], 2],
      ],
    );
  });

  test(`gone after ${NOTIFICATION_DAYS} days`, async () => {
    await kept('alice', 'C1', new Date(now.getTime() - NOTIFICATION_DAYS * DAY_MS));
    await kept('alice', 'C1', new Date(now.getTime() - NOTIFICATION_DAYS * DAY_MS + 60_000));
    assert.equal(await forgetOldNotifications(deps), 1);
    assert.equal((await listOf('alice')).length, 1);
  });

  test('someone leaving a church, or removed from it, loses its notifications and keeps the others', async () => {
    await seedChurch('C1', { alice: 'admin', bob: 'staff' });
    await seedChurch('C2', { bob: 'staff' });
    await kept('bob', 'C1', hoursAgo(1));
    await kept('bob', 'C2', hoursAgo(1));
    const bob = await db.doc('churches/C1/members/bob').get();
    await bob.ref.delete();
    const { google } = memoryGoogle();
    const { messaging } = fakePush();
    const cal = { ...deps, secretKey: '', google, config: { clientId: '', clientSecret: '', redirectUri: '', appUrl, tokenKey: '' } };
    await onMemberDeleted({ ...cal, messaging, appUrl }, 'C1', bob, 'alice');
    assert.deepEqual((await listOf('bob')).map((n) => n.cid), ['C2']);
  });

  test('deleting the account deletes the whole list', async () => {
    const user = await auth.createUser({ email: 'leaver@example.com', password: 'secret123' });
    await seedChurch('C1', { alice: 'admin', [user.uid]: 'staff' });
    await db.doc(`users/${user.uid}`).set({ name: '要走的人' });
    await kept(user.uid, 'C1', hoursAgo(1));
    await deleteAccount({ ...deps, auth }, caller(user.uid));
    assert.deepEqual(await listOf(user.uid), []);
  });
});
