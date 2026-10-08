import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

import { sendReminders } from '../src/notifications.js';
import { clearFirestore, db, seedChurch } from './support.js';

const appUrl = 'https://app.example';

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

    await sendReminders({ db, messaging, now, appUrl });

    assert.equal(sent.length, 2);
    const mei = sent.find((s) => s.tokens.includes('tok-mei'))!;
    assert.equal(mei.body, '主日崇拜 司琴、招待');
  });

  test('an event’s roster is reminded of the day before it starts, by its title; a cancelled one is not', async () => {
    await church();
    await db.doc('churches/C1/rosters/ev_x1').set({
      kind: 'event',
      eventId: 'x1',
      title: '秋季退修會',
      dateKey: '2026-10-04',
      endDateKey: '2026-10-05',
      duties: duties(['美玉'], []),
    });
    await db.doc('churches/C1/rosters/ev_x2').set({
      kind: 'event',
      eventId: 'x2',
      title: '取消的活動',
      dateKey: '2026-10-04',
      endDateKey: '2026-10-04',
      duties: duties([], ['志豪']),
      cancelledAt: new Date(),
    });
    const { sent, messaging } = fakeMessaging();
    await sendReminders({ db, messaging, now, appUrl });
    assert.deepEqual(sent.map((s) => s.body), ['秋季退修會 司琴']);
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
    await sendReminders({ db, messaging, now, appUrl });
    assert.equal(sent.length, 0);
  });
});
