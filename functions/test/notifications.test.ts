import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

import { onRosterWritten, rosterChange, sendReminders } from '../src/notifications.js';
import { clearFirestore, db, seedChurch } from './support.js';

const now = () => new Date('2026-10-03T19:00:00+08:00'); // Saturday evening

function fakeMessaging() {
  const sent: { tokens: string[]; body: string }[] = [];
  return {
    sent,
    messaging: {
      sendEachForMulticast: async (m: { tokens: string[]; notification: { body: string } }) => {
        sent.push({ tokens: m.tokens, body: m.notification.body });
        return { successCount: m.tokens.length, failureCount: 0, responses: m.tokens.map(() => ({ success: true })) };
      },
    } as never,
  };
}

async function church() {
  await seedChurch('C1', { pastor: 'admin', mei: 'staff', hao: 'staff' });
  await db.doc('churches/C1/settings/services').set({
    services: [{ id: 'sunday', name: '主日崇拜' }],
    ids: ['sunday'],
  });
  await db.doc('users/mei').set({ fcm: { phone: 'tok-mei', tablet: 'tok-mei-2' } });
  await db.doc('users/hao').set({ fcm: { phone: 'tok-hao' } });
}

const duties = (piano: string[], usher: string[]) => [
  { role: '司琴', people: piano, uids: Object.fromEntries(piano.map((n) => [n, n === '美玉' ? 'mei' : 'hao'])) },
  { role: '招待', people: usher, uids: Object.fromEntries(usher.map((n) => [n, n === '美玉' ? 'mei' : 'hao'])) },
];

beforeEach(clearFirestore);

describe('rosterChange', () => {
  test('lists who was added to and removed from which duty', () => {
    const c = rosterChange(duties(['美玉'], []), duties(['志豪'], ['美玉']));
    assert.deepEqual([...c.added], [['hao', ['司琴']], ['mei', ['招待']]]);
    assert.deepEqual([...c.removed], [['mei', ['司琴']]]);
  });

  test('ignores uids whose name is no longer listed', () => {
    const c = rosterChange([], [{ role: '司琴', people: [], uids: { 美玉: 'mei' } }]);
    assert.equal(c.added.size, 0);
  });
});

describe('roster change notifications', () => {
  test('both of a member’s devices hear about it; the editor does not', async () => {
    await church();
    const ref = db.doc('churches/C1/rosters/2026-10-04_sunday');
    await ref.set({ type: 'sunday', dateKey: '2026-10-04', duties: duties([], []) });
    const before = await ref.get();
    await ref.set({ type: 'sunday', dateKey: '2026-10-04', duties: duties(['美玉'], ['志豪']) });
    const after = await ref.get();
    const { sent, messaging } = fakeMessaging();

    await onRosterWritten({ db, messaging, now }, 'C1', before, after, 'hao');

    assert.equal(sent.length, 1);
    assert.deepEqual(sent[0].tokens, ['tok-mei', 'tok-mei-2']);
    assert.match(sent[0].body, /10\/4 主日崇拜：司琴/);
  });

  test('muted members and past days get nothing', async () => {
    await church();
    await db.doc('churches/C1/members/mei').update({ 'notificationPrefs.muted': ['rosterChange'] });
    const ref = db.doc('churches/C1/rosters/2026-10-04_sunday');
    await ref.set({ type: 'sunday', dateKey: '2026-10-04', duties: duties(['美玉'], []) });
    const { sent, messaging } = fakeMessaging();
    await onRosterWritten({ db, messaging, now }, 'C1', undefined, await ref.get(), 'pastor');
    assert.equal(sent.length, 0);

    const past = db.doc('churches/C1/rosters/2026-09-27_sunday');
    await past.set({ type: 'sunday', dateKey: '2026-09-27', duties: duties(['志豪'], []) });
    await onRosterWritten({ db, messaging, now }, 'C1', undefined, await past.get(), 'pastor');
    assert.equal(sent.length, 0);
  });
});

describe('reminders', () => {
  test('one message per person for tomorrow, listing their duties', async () => {
    await church();
    await db.doc('churches/C1/rosters/2026-10-04_sunday').set({
      type: 'sunday',
      dateKey: '2026-10-04',
      duties: duties(['美玉'], ['美玉', '志豪']),
    });
    await db.doc('churches/C1/rosters/2026-10-11_sunday').set({
      type: 'sunday',
      dateKey: '2026-10-11',
      duties: duties(['志豪'], []),
    });
    const { sent, messaging } = fakeMessaging();

    await sendReminders({ db, messaging, now });

    assert.equal(sent.length, 2);
    const mei = sent.find((s) => s.tokens.includes('tok-mei'))!;
    assert.equal(mei.body, '主日崇拜 司琴、招待');
  });

  test('suspended churches send no reminders', async () => {
    await church();
    await db.doc('churches/C1').update({ status: 'suspended' });
    await db.doc('churches/C1/rosters/2026-10-04_sunday').set({
      type: 'sunday',
      dateKey: '2026-10-04',
      duties: duties(['美玉'], []),
    });
    const { sent, messaging } = fakeMessaging();
    await sendReminders({ db, messaging, now });
    assert.equal(sent.length, 0);
  });
});

describe('imports', () => {
  test('a roster written by the import sends no per-day push', async () => {
    await church();
    const ref = db.doc('churches/C1/rosters/2026-10-04_sunday');
    await ref.set({ type: 'sunday', dateKey: '2026-10-04', duties: duties(['美玉'], []), via: 'import' });
    const { sent, messaging } = fakeMessaging();
    await onRosterWritten({ db, messaging, now }, 'C1', undefined, await ref.get(), 'pastor');
    assert.equal(sent.length, 0);
  });
});
