import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

import { sendAttendanceReminders } from '../src/attendance.js';
import { setGroupMember } from '../src/groupMembers.js';
import { editSmallGroup } from '../src/smallGroups.js';
import { caller, clearFirestore, db, deps, fakePush, rejectsWith, seedChurch } from './support.js';

const appUrl = 'https://app.example';

// Sunday 2026-10-18; 主日崇拜 meets on Sundays, 喜樂小組 on Fridays every
// other week from 10/2.
const sundayEvening = () => new Date('2026-10-18T21:00:00+08:00');

async function church(extra: Record<string, unknown> = { attendanceSince: '2026-10-01' }) {
  await seedChurch('C1', { pastor: 'admin', sundayLead: 'staff', joyLead: 'staff', mei: 'staff', youthLead: 'staff' }, extra);
  await db.doc('churches/C1/settings/services').set({
    services: [
      { id: 'sunday', name: '主日崇拜', weekday: 7, duties: ['司琴'] },
      { id: 'youth', name: '青年崇拜', weekday: 6, duties: [] },
    ],
    ids: ['sunday', 'youth'],
  });
  await db.doc('churches/C1/members/sundayLead').update({ leadTypes: ['sunday'], identities: [{ kind: 'lead', service: 'sunday' }] });
  await db.doc('churches/C1/members/youthLead').update({ leadTypes: ['youth'], identities: [{ kind: 'lead', service: 'youth' }] });
  for (const uid of ['sundayLead', 'joyLead', 'mei', 'pastor']) await db.doc(`users/${uid}`).set({ fcm: { phone: `tok-${uid}` } });
}

/** 喜樂小組, opened by 主日崇拜's 負責人, led by joyLead. */
async function joy() {
  const { id } = await editSmallGroup(deps, caller('sundayLead'), {
    churchId: 'C1', op: 'save', group: { name: '喜樂小組', service: 'sunday', weekday: 5, every: 2, startsOn: '2026-10-02' }, leads: ['joyLead'],
  });
  return id;
}

const roster = (day: string) => db.doc(`churches/C1/rosters/${day}_sunday`).set({ type: 'sunday', dateKey: day, duties: [] });

beforeEach(clearFirestore);

describe('小組 (#85)', () => {
  test("a service's 負責人 opens one in it and names its 小組長, who gets the 身分", async () => {
    await church();
    const id = await joy();
    const g = await db.doc(`churches/C1/smallGroups/${id}`).get();
    assert.deepEqual(g.data(), { name: '喜樂小組', service: 'sunday', weekday: 5, every: 2, startsOn: '2026-10-02' });
    assert.deepEqual((await db.doc('churches/C1/settings/smallGroups').get()).get('ids'), [id]);
    const lead = await db.doc('churches/C1/members/joyLead').get();
    assert.deepEqual(lead.get('identities'), [{ kind: 'lead', smallGroup: id }]);
    assert.deepEqual(lead.get('leadSmallGroups'), [id]);
  });

  test('another 小組長 named takes the place; an admin keeps 管理員 when named', async () => {
    await church();
    const id = await joy();
    await editSmallGroup(deps, caller('pastor'), {
      churchId: 'C1', op: 'save', group: { id, name: '喜樂', service: 'sunday' }, leads: ['pastor'],
    });
    assert.deepEqual((await db.doc('churches/C1/members/joyLead').get()).get('identities'), []);
    assert.deepEqual((await db.doc('churches/C1/members/joyLead').get()).get('leadSmallGroups'), []);
    assert.deepEqual((await db.doc('churches/C1/members/pastor').get()).get('identities'), [{ kind: 'admin' }, { kind: 'lead', smallGroup: id }]);
    assert.deepEqual((await db.doc(`churches/C1/smallGroups/${id}`).get()).data(), { name: '喜樂', service: 'sunday' });
  });

  test('a change saying what it was made over is refused once that changed: an undo overwrites no one', async () => {
    await church();
    const id = await joy();
    const shown = { id, name: '喜樂小組', service: 'sunday', weekday: 5, every: 2, startsOn: '2026-10-02' };
    const save = (group: object, more: object = {}) =>
      editSmallGroup(deps, caller('sundayLead'), { churchId: 'C1', op: 'save', group, ...more });
    await save({ ...shown, name: '喜樂' }, { before: shown });
    await rejectsWith(save({ ...shown, weekday: 6, startsOn: '2026-10-03' }, { before: shown }), 'conflict');
    await rejectsWith(save({ ...shown, name: '喜樂' }, { leads: [], leadsBefore: ['someoneElse'] }), 'conflict');
    await save({ ...shown, name: '喜樂' }, { leads: [], leadsBefore: ['joyLead'] });
    assert.deepEqual((await db.doc('churches/C1/members/joyLead').get()).get('leadSmallGroups'), []);
  });

  test("not in another service, nor by its 小組長 or anyone leading nothing", async () => {
    await church();
    const id = await joy();
    const save = (who: string, service = 'sunday') =>
      editSmallGroup(deps, caller(who), { churchId: 'C1', op: 'save', group: { id, name: '喜樂', service } });
    await rejectsWith(save('youthLead'), 'permissionDenied');
    await rejectsWith(save('sundayLead', 'youth'), 'permissionDenied');
    await rejectsWith(save('joyLead'), 'permissionDenied');
    await rejectsWith(
      editSmallGroup(deps, caller('mei'), { churchId: 'C1', op: 'save', group: { name: '平安', service: 'sunday' } }),
      'permissionDenied',
    );
    await rejectsWith(
      editSmallGroup(deps, caller('pastor'), { churchId: 'C1', op: 'save', group: { name: '平安', service: 'gone' } }),
      'unknown',
    );
    // It starts on a day it meets.
    await rejectsWith(
      editSmallGroup(deps, caller('pastor'), {
        churchId: 'C1', op: 'save', group: { name: '平安', service: 'sunday', weekday: 5, startsOn: '2026-10-04' },
      }),
      'unknown',
    );
  });

  test('its 小組長 sets when it meets, and nothing else', async () => {
    await church();
    const id = await joy();
    await editSmallGroup(deps, caller('joyLead'), {
      churchId: 'C1', op: 'save', group: { id, name: '喜樂小組', service: 'sunday', weekday: 3, every: 1 },
    });
    assert.equal((await db.doc(`churches/C1/smallGroups/${id}`).get()).get('weekday'), 3);
    await rejectsWith(
      editSmallGroup(deps, caller('joyLead'), { churchId: 'C1', op: 'save', group: { id, name: '大喜樂', service: 'sunday' } }),
      'permissionDenied',
    );
    await rejectsWith(
      editSmallGroup(deps, caller('joyLead'), { churchId: 'C1', op: 'save', group: { id, name: '喜樂小組', service: 'sunday' }, leads: ['mei'] }),
      'permissionDenied',
    );
  });

  test('its 小組長 adds and takes out a 同工; closing it takes it off everyone, its 人數 kept', async () => {
    await church();
    const id = await joy();
    await setGroupMember(deps, caller('joyLead'), { churchId: 'C1', uid: 'mei', smallGroup: id, member: true });
    assert.deepEqual((await db.doc('churches/C1/members/mei').get()).get('smallGroups'), [id]);
    await rejectsWith(
      setGroupMember(deps, caller('youthLead'), { churchId: 'C1', uid: 'mei', smallGroup: id, member: false }),
      'permissionDenied',
    );
    await db.doc(`churches/C1/attendance/small:${id}/days/2026-10-16`).set({ count: 8 });
    await editSmallGroup(deps, caller('sundayLead'), { churchId: 'C1', op: 'delete', id });
    assert.equal((await db.doc(`churches/C1/smallGroups/${id}`).get()).exists, false);
    assert.deepEqual((await db.doc('churches/C1/members/mei').get()).get('smallGroups'), []);
    assert.deepEqual((await db.doc('churches/C1/members/joyLead').get()).get('leadSmallGroups'), []);
    assert.equal((await db.doc(`churches/C1/attendance/small:${id}/days/2026-10-16`).get()).get('count'), 8);
    await rejectsWith(
      setGroupMember(deps, caller('joyLead'), { churchId: 'C1', uid: 'mei', smallGroup: id, member: true }),
      'permissionDenied',
    );
  });
});

describe('回報人數 reminders (#85)', () => {
  test("at 21:00 the 負責人 of a service that met today are asked, once", async () => {
    await church();
    await roster('2026-10-18');
    const { sent, messaging } = fakePush();
    assert.equal(await sendAttendanceReminders({ db, messaging, now: sundayEvening, appUrl }), 1);
    assert.deepEqual(sent.map((s) => [s.tokens, s.title, s.body]), [
      [['tok-sundayLead'], '填寫人數', '「主日崇拜」10/18（週日）的聚會有幾個人？'],
    ]);
    // An hour later, nobody again.
    assert.equal(await sendAttendanceReminders({ db, messaging, now: () => new Date('2026-10-18T22:00:00+08:00'), appUrl }), 0);
  });

  test("not its 牧者, who only sees them", async () => {
    await church();
    await db.doc('churches/C1/members/mei').update({ leadTypes: ['sunday'], identities: [{ kind: 'pastor', services: ['sunday'] }] });
    await roster('2026-10-18');
    const { sent, messaging } = fakePush();
    await sendAttendanceReminders({ db, messaging, now: sundayEvening, appUrl });
    assert.deepEqual(sent.map((s) => s.tokens), [['tok-sundayLead']]);
  });

  test('a 小組 on its week is asked of its 小組長; not on the weeks between', async () => {
    await church();
    await joy();
    const { sent, messaging } = fakePush();
    await sendAttendanceReminders({ db, messaging, now: () => new Date('2026-10-16T21:00:00+08:00'), appUrl });
    assert.deepEqual(sent.map((s) => s.tokens), [['tok-joyLead']]);
    await sendAttendanceReminders({ db, messaging, now: () => new Date('2026-10-09T21:00:00+08:00'), appUrl });
    assert.equal(sent.length, 1);
  });

  test('nobody is asked once someone filled it in, marked 這次沒聚會, or paused it', async () => {
    await church();
    await roster('2026-10-18');
    const { sent, messaging } = fakePush();
    await db.doc('churches/C1/attendance/service:sunday/days/2026-10-18').set({ count: 120 });
    await sendAttendanceReminders({ db, messaging, now: sundayEvening, appUrl });
    await db.doc('churches/C1/attendance/service:sunday/days/2026-10-18').set({ none: true });
    await sendAttendanceReminders({ db, messaging, now: sundayEvening, appUrl });
    await db.doc('churches/C1/attendance/service:sunday/days/2026-10-18').delete();
    await db.doc('churches/C1/attendance/service:sunday').set({ pauses: [{ from: '2026-10-10', until: '2026-11-01' }] });
    await sendAttendanceReminders({ db, messaging, now: sundayEvening, appUrl });
    assert.equal(sent.length, 0);
  });

  test('not with 回報人數 off, without a roster that day, nor to someone who muted it', async () => {
    await church({});
    await roster('2026-10-18');
    const { sent, messaging } = fakePush();
    await sendAttendanceReminders({ db, messaging, now: sundayEvening, appUrl });
    assert.equal(sent.length, 0, 'off');

    await db.doc('churches/C1').update({ attendanceSince: '2026-10-01' });
    await db.doc('churches/C1/rosters/2026-10-18_sunday').delete();
    await sendAttendanceReminders({ db, messaging, now: sundayEvening, appUrl });
    assert.equal(sent.length, 0, 'no roster');

    await roster('2026-10-18');
    await db.doc('churches/C1/members/sundayLead').update({ 'notificationPrefs.muted': ['attendance'] });
    await sendAttendanceReminders({ db, messaging, now: sundayEvening, appUrl });
    assert.equal(sent.length, 0, 'muted');
  });
});
