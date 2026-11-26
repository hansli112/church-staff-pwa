import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

import { editLedDuties } from '../src/ledDuties.js';
import { sendReminders } from '../src/notifications.js';
import { notifyPlanned, onRosterWritten } from '../src/rosterChange.js';
import { dutiesByUid } from '../src/rosters.js';
import { editSmallGroup } from '../src/smallGroups.js';
import { caller, clearFirestore, db, deps, fakePush, seedChurch, setNow, type SentPush } from './support.js';

/**
 * 服事交給小組: a duty on a day given to a 小組 (`groups`, name → its id).
 * Everyone in it holds the duty, as told by reminders and roster changes.
 */

const appUrl = 'https://app.example';
let push: ReturnType<typeof fakePush>;
let pushed: SentPush[];
const triggerDeps = () => ({ ...deps, messaging: push.messaging, appUrl });

/** 喜樂小組 (joy) has 美玉 (mei) and 志豪 (hao); 林弟兄 (lin) has no account, in it too. */
async function church() {
  await seedChurch('C1', { pastor: 'admin', mei: 'staff', hao: 'staff', other: 'staff' }, { name: '恩典堂' });
  await db.doc('churches/C1/settings/services').set({ services: [{ id: 'sunday', name: '主日崇拜' }], ids: ['sunday'] });
  await db.doc('churches/C1/smallGroups/joy').set({ name: '喜樂小組', service: 'sunday' });
  await db.doc('churches/C1/members/mei').update({ name: '美玉', smallGroups: ['joy'] });
  await db.doc('churches/C1/members/hao').update({ name: '志豪', smallGroups: ['joy'] });
  await db.doc('churches/C1/pendingMembers/lin').set({ name: '林弟兄', smallGroups: ['joy'] });
  await db.doc('users/mei').set({ fcm: { phone: 'tok-mei' } });
  await db.doc('users/hao').set({ fcm: { phone: 'tok-hao' } });
  await db.doc('users/other').set({ fcm: { phone: 'tok-other' } });
}

const usher = (people: string[], groups: Record<string, string> = {}) => ({ role: '招待', people, uids: {}, groups });

let n = 0;
async function write(day: string, duties: unknown[], opts: { via?: string; editedBy?: string } = {}) {
  const ref = db.doc(`churches/C1/rosters/${day}_sunday`);
  const before = await ref.get();
  await ref.set({ type: 'sunday', dateKey: day, duties, ...(opts.via ? { via: opts.via } : {}) });
  return onRosterWritten(triggerDeps(), 'C1', before, await ref.get(), opts.editedBy ?? 'pastor', `g${++n}`);
}

beforeEach(async () => {
  await clearFirestore();
  setNow(new Date('2026-10-03T19:00:00+08:00')); // Saturday evening
  push = fakePush();
  pushed = push.sent;
});

describe('who holds a duty given to a 小組', () => {
  const joy = new Map([['joy', ['mei', 'hao']]]);

  test('everyone in it, the duty said with the 小組', () => {
    const held = dutiesByUid([usher(['喜樂小組'], { 喜樂小組: 'joy' })], joy);
    assert.deepEqual([...held.keys()].sort(), ['hao', 'mei']);
    assert.equal(held.get('mei')!.length, 1);
  });

  test('not once its name is off the duty, nor a 小組 the day does not name', () => {
    assert.equal(dutiesByUid([usher([], { 喜樂小組: 'joy' })], joy).size, 0);
    assert.equal(dutiesByUid([usher(['喜樂小組'])], joy).size, 0);
  });

  test('someone on it by name as well holds it once', () => {
    const held = dutiesByUid([{ ...usher(['美玉', '喜樂小組'], { 喜樂小組: 'joy' }), uids: { 美玉: 'mei' } }], joy);
    assert.deepEqual(held.get('mei'), ['招待']);
  });
});

describe('reminders', () => {
  test('everyone in the 小組 is reminded, the duty said with it', async () => {
    await church();
    for (const uid of ['mei', 'hao', 'other']) {
      await db.doc(`churches/C1/members/${uid}`).update({ 'notificationPrefs.reminderTiming': 'dayBefore' });
    }
    await db.doc('churches/C1/rosters/2026-10-04_sunday').set({
      type: 'sunday', dateKey: '2026-10-04', duties: [usher(['喜樂小組'], { 喜樂小組: 'joy' })],
    });
    await sendReminders({ db, messaging: push.messaging, now: () => new Date('2026-10-03T19:00:00+08:00'), appUrl });
    assert.deepEqual(pushed.map((p) => [p.tokens[0], p.body]).sort(), [
      ['tok-hao', '主日崇拜 招待（喜樂小組）'],
      ['tok-mei', '主日崇拜 招待（喜樂小組）'],
    ]);
  });
});

describe('roster changes', () => {
  test('the 小組 put on: everyone in it is told, with the 小組; taken off, told too', async () => {
    await church();
    await write('2026-10-04', [usher(['喜樂小組'], { 喜樂小組: 'joy' })]);
    assert.deepEqual(pushed.map((p) => [p.tokens[0], p.body]).sort(), [
      ['tok-hao', '你被排進 10/4 主日崇拜：招待（喜樂小組）'],
      ['tok-mei', '你被排進 10/4 主日崇拜：招待（喜樂小組）'],
    ]);
    pushed.length = 0;
    await write('2026-10-04', [usher([])]);
    assert.deepEqual(pushed.map((p) => [p.tokens[0], p.body]).sort(), [
      ['tok-hao', '你被移出 10/4 主日崇拜：招待（喜樂小組）'],
      ['tok-mei', '你被移出 10/4 主日崇拜：招待（喜樂小組）'],
    ]);
  });

  test('in another language, said its way', async () => {
    await church();
    await db.doc('users/hao').update({ appLocale: 'en' });
    await write('2026-10-04', [usher(['喜樂小組'], { 喜樂小組: 'joy' })]);
    assert.equal(pushed.find((p) => p.tokens[0] === 'tok-hao')!.body, 'You’re on Oct 4 主日崇拜: 招待 (喜樂小組)');
  });

  test('the same name typed, not the 小組, tells nobody', async () => {
    await church();
    await write('2026-10-04', [usher(['喜樂小組'])]);
    assert.deepEqual(pushed, []);
  });

  test('the editor in the 小組 is not told of their own change', async () => {
    await church();
    await write('2026-10-04', [usher(['喜樂小組'], { 喜樂小組: 'joy' })], { editedBy: 'mei' });
    assert.deepEqual(pushed.map((p) => p.tokens[0]), ['tok-hao']);
  });

  test('安排服事: 通知同工 tells everyone in the 小組', async () => {
    await church();
    await write('2026-10-11', [usher(['喜樂小組'], { 喜樂小組: 'joy' })], { via: 'plan' });
    assert.deepEqual(pushed, []);
    assert.deepEqual(await notifyPlanned(triggerDeps(), caller('pastor'), { churchId: 'C1', serviceId: 'sunday' }), {
      people: 2,
      later: false,
    });
    assert.deepEqual(pushed.map((p) => p.body), [
      '主日崇拜的服事排好了\n排進 10/11 招待（喜樂小組）',
      '主日崇拜的服事排好了\n排進 10/11 招待（喜樂小組）',
    ]);
  });
});

describe('a duty’s 負責人 keeps the 小組', () => {
  test('saving the duties they lead leaves another duty’s 小組 as it was, and compares it', async () => {
    await seedChurch('C1', { admin: 'admin', lead: 'staff' });
    await db.doc('churches/C1/settings/services').set({ services: [], ids: ['sunday'] });
    await db.doc('churches/C1/members/lead').update({
      leadDuties: ['sunday/司琴'],
      identities: [{ kind: 'dutyLead', service: 'sunday', duty: '司琴' }],
    });
    const id = '2030-10-06_sunday';
    const day = (piano: string[]) => ({
      type: 'sunday',
      dateKey: '2030-10-06',
      events: [],
      duties: [{ role: '司琴', people: piano, uids: {} }, usher(['喜樂小組'], { 喜樂小組: 'joy' })],
    });
    await db.doc(`churches/C1/rosters/${id}`).set(day([]));
    await editLedDuties(deps, caller('lead'), { churchId: 'C1', before: { [id]: day([]) }, after: { [id]: day(['老王']) }, via: 'app' });
    assert.deepEqual((await db.doc(`churches/C1/rosters/${id}`).get()).get('duties')[1].groups, { 喜樂小組: 'joy' });
    // Shown without the 小組: changed meanwhile.
    const without = { ...day(['老王']), duties: [{ role: '司琴', people: ['老王'], uids: {} }, usher(['喜樂小組'])] };
    await assert.rejects(
      editLedDuties(deps, caller('lead'), { churchId: 'C1', before: { [id]: without }, after: { [id]: without }, via: 'app' }),
    );
  });
});

describe('renaming a 小組', () => {
  test('the days that give it a duty call it by its new name; a name typed alike stays', async () => {
    await church();
    await db.doc('churches/C1/rosters/2026-10-11_sunday').set({
      type: 'sunday',
      dateKey: '2026-10-11',
      duties: [usher(['美玉', '喜樂小組'], { 喜樂小組: 'joy' }), { role: '司會', people: ['喜樂小組'], uids: {} }],
    });
    await editSmallGroup(deps, caller('pastor'), { churchId: 'C1', op: 'save', group: { id: 'joy', name: '喜樂團契', service: 'sunday' } });
    const duties = (await db.doc('churches/C1/rosters/2026-10-11_sunday').get()).get('duties');
    assert.deepEqual(duties[0].people, ['美玉', '喜樂團契']);
    assert.deepEqual(duties[0].groups, { 喜樂團契: 'joy' });
    assert.deepEqual(duties[1].people, ['喜樂小組']);
  });
});
