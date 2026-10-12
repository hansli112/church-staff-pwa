import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

import { sendReminders, type ReminderTiming } from '../src/notifications.js';
import { clearFirestore, db, fakePush, seedChurch } from './support.js';

const appUrl = 'https://app.example';

const now = () => new Date('2026-10-03T19:00:00+08:00'); // Saturday evening

async function church() {
  await seedChurch('C1', { pastor: 'admin', mei: 'staff', hao: 'staff' });
  await db.doc('churches/C1/settings/services').set({
    services: [{ id: 'sunday', name: '主日崇拜' }],
    ids: ['sunday'],
  });
  await db.doc('users/mei').set({ fcm: { phone: 'tok-mei', tablet: 'tok-mei-2' } });
  await db.doc('users/hao').set({ fcm: { phone: 'tok-hao' } });
}

const remindAt = (uid: string, reminderTiming: ReminderTiming) =>
  db.doc(`churches/C1/members/${uid}`).update({ 'notificationPrefs.reminderTiming': reminderTiming });

/** The day-before reminder, which these tests are about, for both staff. */
async function dayBeforeChurch() {
  await church();
  await remindAt('mei', 'dayBefore');
  await remindAt('hao', 'dayBefore');
}

const duties = (piano: string[], usher: string[]) => [
  { role: '司琴', people: piano, uids: Object.fromEntries(piano.map((n) => [n, n === '美玉' ? 'mei' : 'hao'])) },
  { role: '招待', people: usher, uids: Object.fromEntries(usher.map((n) => [n, n === '美玉' ? 'mei' : 'hao'])) },
];

beforeEach(clearFirestore);

describe('reminders', () => {
  test('an explicit same-name guest or missing UID binding never notifies the member with that name', async () => {
    await dayBeforeChurch();
    await db.doc('churches/C1/members/mei').update({ name: '美玉' });
    await db.doc('churches/C1/rosters/2026-10-04_sunday').set({
      type: 'sunday', dateKey: '2026-10-04', duties: [
        { role: '司琴', people: ['美玉'], uids: {} },
        { role: '敬拜', people: ['美玉'] },
        { role: '招待', people: ['志豪'], uids: { 志豪: 'hao' } },
      ],
    });
    const { sent, messaging } = fakePush();
    assert.equal(await sendReminders({ db, messaging, now, appUrl }), 1);
    assert.deepEqual(sent.map(({ tokens, body }) => ({ tokens, body })), [{ tokens: ['tok-hao'], body: '主日崇拜 招待' }]);
  });
  test('non-map UID fields cannot authorize a reminder recipient', async () => {
    await dayBeforeChurch();
    await db.doc('churches/C1/members/mei').update({ name: '0' });
    await db.doc('churches/C1/members/m').set({ uid: 'm', name: '0', role: 'staff' });
    await db.doc('users/m').set({ fcm: { phone: 'tok-m' } });
    await db.doc('churches/C1/rosters/2026-10-04_sunday').set({
      type: 'sunday', dateKey: '2026-10-04', duties: [
        { role: '司琴', people: ['0'], uids: ['mei'] },
        { role: '招待', people: ['0'], uids: 'm' },
      ],
    });
    const { sent, messaging } = fakePush();
    assert.equal(await sendReminders({ db, messaging, now, appUrl }), 0);
    assert.deepEqual(sent, []);
  });

  test('empty or path-shaped UID values are not identities and do not stop valid recipients', async () => {
    await dayBeforeChurch();
    await db.doc('churches/C1/rosters/2026-10-04_sunday').set({
      type: 'sunday', dateKey: '2026-10-04', duties: [
        { role: '司琴', people: ['美玉'], uids: { 美玉: '' } },
        { role: '敬拜', people: ['美玉'], uids: { 美玉: '/' } },
        { role: '招待', people: ['志豪'], uids: { 志豪: 'hao' } },
      ],
    });
    const { sent, messaging } = fakePush();
    assert.equal(await sendReminders({ db, messaging, now, appUrl }), 1);
    assert.deepEqual(sent.map(({ tokens, body }) => ({ tokens, body })), [{ tokens: ['tok-hao'], body: '主日崇拜 招待' }]);
  });

  test('one message per person for tomorrow, listing their duties', async () => {
    await dayBeforeChurch();
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
    const { sent, messaging } = fakePush();

    await sendReminders({ db, messaging, now, appUrl });

    assert.equal(sent.length, 2);
    const mei = sent.find((s) => s.tokens.includes('tok-mei'))!;
    assert.equal(mei.body, '主日崇拜 司琴、招待');
  });

  test('an event’s roster is reminded of the day before it starts, by its title; a cancelled one is not', async () => {
    await dayBeforeChurch();
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
    const { sent, messaging } = fakePush();
    await sendReminders({ db, messaging, now, appUrl });
    assert.deepEqual(sent.map((s) => s.body), ['秋季退修會 司琴']);
  });

  test('suspended churches send no reminders', async () => {
    await dayBeforeChurch();
    await db.doc('churches/C1').update({ status: 'suspended' });
    await db.doc('churches/C1/rosters/2026-10-04_sunday').set({
      type: 'sunday',
      dateKey: '2026-10-04',
      duties: duties(['美玉'], []),
    });
    const { sent, messaging } = fakePush();
    await sendReminders({ db, messaging, now, appUrl });
    assert.equal(sent.length, 0);
  });

  test("at 7 in the evening on each church's clock, summer time or not", async () => {
    await dayBeforeChurch();
    await db.doc('churches/C1').update({ timeZone: 'America/Los_Angeles' });
    await seedChurch('C2', { pastor: 'admin', mei: 'staff' });
    await db.doc('churches/C2/settings/services').set({ services: [{ id: 'sunday', name: '主日' }], ids: ['sunday'] });
    await db.doc('churches/C2/members/mei').update({ 'notificationPrefs.reminderTiming': 'dayBefore' });
    for (const day of ['2026-10-04', '2026-11-08']) {
      for (const cid of ['C1', 'C2']) {
        await db.doc(`churches/${cid}/rosters/${day}_sunday`).set({ type: 'sunday', dateKey: day, duties: duties(['美玉'], []) });
      }
    }
    const at = async (time: string) => {
      const { sent, messaging } = fakePush();
      await sendReminders({ db, messaging, now: () => new Date(time), appUrl });
      return sent.map((s) => `${s.title} ${s.body}`);
    };
    // Taipei's evening is Los Angeles' early morning: only C2, the church
    // in Taipei (the one without a time zone).
    assert.deepEqual(await at('2026-10-03T19:00:00+08:00'), ['明天的服事（10/4） 主日 司琴']);
    assert.deepEqual(await at('2026-10-03T19:00:00-07:00'), ['明天的服事（10/4） 主日崇拜 司琴']);
    assert.deepEqual(await at('2026-10-03T20:00:00-07:00'), []);
    // The clocks went back on 1 November: 7 is an hour later in UTC.
    assert.deepEqual(await at('2026-11-07T19:00:00-07:00'), []);
    assert.deepEqual(await at('2026-11-07T19:00:00-08:00'), ['明天的服事（11/8） 主日崇拜 司琴']);
  });
});

describe('weekly reminders', () => {
  const monday = () => new Date('2026-10-12T19:00:00+08:00');
  const saturday = () => new Date('2026-10-17T19:00:00+08:00');

  async function week() {
    await church();
    await db.doc('churches/C1/settings/services').set({
      services: [{ id: 'sunday', name: '主日崇拜' }, { id: 'prayer', name: '禱告會' }],
      ids: ['sunday', 'prayer'],
    });
    await db.doc('churches/C1/members/mei').update({ name: '美玉' });
    await db.doc('churches/C1/rosters/2026-10-12_prayer').set({
      type: 'prayer', dateKey: '2026-10-12', duties: duties(['美玉'], []),
    });
    await db.doc('churches/C1/rosters/2026-10-13_prayer').set({
      type: 'prayer', dateKey: '2026-10-13', duties: duties([], ['志豪']),
    });
    await db.doc('churches/C1/rosters/2026-10-18_sunday').set({
      type: 'sunday', dateKey: '2026-10-18', duties: duties(['美玉'], ['美玉', '志豪']),
    });
    await db.doc('churches/C1/rosters/2026-10-19_prayer').set({
      type: 'prayer', dateKey: '2026-10-19', duties: duties(['美玉'], []),
    });
  }

  test('by default, Monday evening lists each person’s duties from that Monday to Sunday', async () => {
    await week();
    const { sent, messaging } = fakePush();
    await sendReminders({ db, messaging, now: monday, appUrl });
    assert.deepEqual(new Set(sent.map((s) => s.title)), new Set(['這週的服事（10/12–10/18）']));
    const mei = sent.find((s) => s.tokens.includes('tok-mei'))!;
    assert.equal(mei.body, '10/12（週一）禱告會 司琴；10/18（週日）主日崇拜 司琴、招待');
    const hao = sent.find((s) => s.tokens.includes('tok-hao'))!;
    assert.equal(hao.body, '10/13（週二）禱告會 招待；10/18（週日）主日崇拜 招待');
    assert.equal(sent.length, 2);
  });

  test('in the language each one’s app shows', async () => {
    await week();
    await db.doc('users/hao').update({ appLocale: 'en' });
    await remindAt('mei', 'dayBefore');
    const mon = fakePush();
    await sendReminders({ db, messaging: mon.messaging, now: monday, appUrl });
    assert.deepEqual(mon.sent.map((s) => [s.tokens, s.title, s.body]), [
      [['tok-hao'], 'Serving this week (Oct 12–Oct 18)', 'Oct 13 (Tue) 禱告會: 招待; Oct 18 (Sun) 主日崇拜: 招待'],
    ]);
    await remindAt('hao', 'dayBefore');
    const sat = fakePush();
    await sendReminders({ db, messaging: sat.messaging, now: saturday, appUrl });
    assert.deepEqual(sat.sent.map((s) => [s.tokens, s.title, s.body]), [
      [['tok-mei', 'tok-mei-2'], '明天的服事（10/18）', '主日崇拜 司琴、招待'],
      [['tok-hao'], 'Serving tomorrow (Oct 18)', '主日崇拜: 招待'],
    ]);
  });

  test("Monday is the church's Monday", async () => {
    await week();
    await db.doc('churches/C1').update({ timeZone: 'America/New_York' });
    const { sent, messaging } = fakePush();
    // Monday evening in New York, Tuesday morning in Taipei.
    await sendReminders({ db, messaging, now: () => new Date('2026-10-12T19:00:00-04:00'), appUrl });
    assert.deepEqual(new Set(sent.map((s) => s.title)), new Set(['這週的服事（10/12–10/18）']));
  });

  test('by default, no other evening reminds anyone', async () => {
    await week();
    const { sent, messaging } = fakePush();
    assert.equal(await sendReminders({ db, messaging, now: saturday, appUrl }), 0);
    assert.deepEqual(sent, []);
  });

  test('the day before only: no weekly list on Monday, tomorrow’s duties every evening', async () => {
    await week();
    await remindAt('hao', 'dayBefore');
    const monday1 = fakePush();
    await sendReminders({ db, messaging: monday1.messaging, now: monday, appUrl });
    const hao = monday1.sent.filter((s) => s.tokens.includes('tok-hao'));
    assert.deepEqual(hao.map((s) => [s.title, s.body]), [['明天的服事（10/13）', '禱告會 招待']]);
    const sat = fakePush();
    await sendReminders({ db, messaging: sat.messaging, now: saturday, appUrl });
    assert.deepEqual(sat.sent.map(({ tokens, body }) => ({ tokens, body })), [{ tokens: ['tok-hao'], body: '主日崇拜 招待' }]);
  });

  test('both: on Monday only the weekly list, which has tomorrow; the day before every other evening', async () => {
    await week();
    await remindAt('hao', 'both');
    const mon = fakePush();
    await sendReminders({ db, messaging: mon.messaging, now: monday, appUrl });
    const hao = mon.sent.filter((s) => s.tokens.includes('tok-hao'));
    assert.deepEqual(hao.map((s) => [s.title, s.body]), [
      ['這週的服事（10/12–10/18）', '10/13（週二）禱告會 招待；10/18（週日）主日崇拜 招待'],
    ]);
    const sat = fakePush();
    await sendReminders({ db, messaging: sat.messaging, now: saturday, appUrl });
    assert.deepEqual(sat.sent.map((s) => [s.tokens, s.title, s.body]), [[['tok-hao'], '明天的服事（10/18）', '主日崇拜 招待']]);
  });

  test('an event is listed in the week it starts, by its title; a cancelled one is not', async () => {
    await church();
    await db.doc('churches/C1/rosters/ev_x1').set({
      kind: 'event', eventId: 'x1', title: '秋季退修會', dateKey: '2026-10-17', endDateKey: '2026-10-18',
      duties: duties(['美玉'], []),
    });
    await db.doc('churches/C1/rosters/ev_x2').set({
      kind: 'event', eventId: 'x2', title: '取消的活動', dateKey: '2026-10-14', endDateKey: '2026-10-14',
      duties: duties([], ['志豪']), cancelledAt: new Date(),
    });
    const { sent, messaging } = fakePush();
    await sendReminders({ db, messaging, now: monday, appUrl });
    assert.deepEqual(sent.map((s) => s.body), ['10/17（週六）秋季退修會 司琴']);
  });

  test('those who turned reminders off get no weekly list', async () => {
    await week();
    await db.doc('churches/C1/members/mei').update({ 'notificationPrefs.muted': ['reminder'] });
    const { sent, messaging } = fakePush();
    await sendReminders({ db, messaging, now: monday, appUrl });
    assert.deepEqual(sent.map((s) => s.tokens), [['tok-hao']]);
  });
});
