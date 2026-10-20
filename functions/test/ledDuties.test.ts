import assert from 'node:assert/strict';
import { beforeEach, test } from 'node:test';

import { editLedDuties } from '../src/ledDuties.js';
import { caller, clearFirestore, db, deps, rejectsWith, seedChurch } from './support.js';

// 事工負責人 (#82): 敬拜團 leads 司琴 and 敬拜 in 主日崇拜, and 敬拜 in 青年崇拜.
const worship = {
  id: 'worship',
  name: '敬拜團',
  duties: [{ service: 'sunday', duty: '司琴' }, { service: 'sunday', duty: '敬拜' }, { service: 'youth', duty: '敬拜' }],
};

const duty = (role: string, people: string[] = [], uids: Record<string, string> = {}) => ({ role, people, uids });
const day = (duties: ReturnType<typeof duty>[], events: unknown[] = []) => ({ type: 'sunday', dateKey: '2030-10-06', duties, events });
const ID = '2030-10-06_sunday';

async function church() {
  await seedChurch('C1', { admin: 'admin', lead: 'staff', staff: 'staff' });
  await db.doc('churches/C1/settings/services').set({ services: [], ids: ['sunday', 'youth'] });
  await db.doc('churches/C1/settings/ministries').set({ ministries: [worship], ids: ['worship'] });
  await db.doc('churches/C1/members/lead').update({ leadMinistries: ['worship'], identities: [{ kind: 'lead', ministry: 'worship' }] });
}

beforeEach(clearFirestore);

test("a 事工's 負責人 arranges the duties it leads, and only those", async () => {
  await church();
  const before = day([duty('司會', ['老王'], { 老王: 'admin' }), duty('司琴')]);
  await db.doc(`churches/C1/rosters/${ID}`).set(before);
  const after = day([duty('司會', ['老王'], { 老王: 'admin' }), duty('司琴', ['美玉'], { 美玉: 'staff' })]);
  await editLedDuties(deps, caller('lead'), { churchId: 'C1', before: { [ID]: before }, after: { [ID]: after }, via: 'app' });
  const saved = await db.doc(`churches/C1/rosters/${ID}`).get();
  assert.deepEqual(saved.get('duties'), after.duties);
  assert.equal(saved.get('via'), 'app');

  const other = day([duty('司會', ['美玉'], { 美玉: 'staff' }), duty('司琴', ['美玉'], { 美玉: 'staff' })]);
  await rejectsWith(
    editLedDuties(deps, caller('lead'), { churchId: 'C1', before: { [ID]: after }, after: { [ID]: other }, via: 'app' }),
    'permissionDenied',
  );
  assert.deepEqual((await db.doc(`churches/C1/rosters/${ID}`).get()).get('duties'), after.duties);
});

test('a day changed meanwhile is refused with conflict, not overwritten', async () => {
  await church();
  const shown = day([duty('司琴')]);
  const newer = day([duty('司琴', ['老王'], { 老王: 'admin' })]);
  await db.doc(`churches/C1/rosters/${ID}`).set(newer);
  await rejectsWith(
    editLedDuties(deps, caller('lead'), {
      churchId: 'C1', before: { [ID]: shown }, after: { [ID]: day([duty('司琴', ['美玉'], { 美玉: 'staff' })]) }, via: 'app',
    }),
    'conflict',
  );
  assert.deepEqual((await db.doc(`churches/C1/rosters/${ID}`).get()).get('duties'), newer.duties);
});

test('nor the day itself: its 特別活動 stay as they are, and it is not deleted', async () => {
  await church();
  const before = day([duty('司琴')]);
  await db.doc(`churches/C1/rosters/${ID}`).set(before);
  const tagged = day([duty('司琴')], [{ name: '聖餐', color: 0 }]);
  await rejectsWith(
    editLedDuties(deps, caller('lead'), { churchId: 'C1', before: { [ID]: before }, after: { [ID]: tagged }, via: 'app' }),
    'permissionDenied',
  );
  await rejectsWith(
    editLedDuties(deps, caller('lead'), { churchId: 'C1', before: { [ID]: before }, after: { [ID]: null }, via: 'app' }),
    'permissionDenied',
  );
});

test("on an event's roster, in no service, the duties it leads by name", async () => {
  await church();
  const ev = { kind: 'event', eventId: 'xmas', title: '聖誕晚會', dateKey: '2030-12-24', endDateKey: '2030-12-24', events: [] };
  const before = { ...ev, duties: [duty('敬拜'), duty('招待')] };
  await db.doc('churches/C1/rosters/ev_xmas').set(before);
  const after = { ...ev, duties: [duty('敬拜', ['美玉'], { 美玉: 'staff' }), duty('招待')] };
  await editLedDuties(deps, caller('lead'), { churchId: 'C1', before: { ev_xmas: before }, after: { ev_xmas: after }, via: 'app' });
  assert.deepEqual((await db.doc('churches/C1/rosters/ev_xmas').get()).get('duties'), after.duties);

  await db.doc('churches/C1/rosters/ev_xmas').update({ cancelledAt: new Date() });
  await rejectsWith(
    editLedDuties(deps, caller('lead'), { churchId: 'C1', before: { ev_xmas: after }, after: { ev_xmas: before }, via: 'app' }),
    'permissionDenied',
  );
});

test('someone who leads no 事工 arranges nothing here', async () => {
  await church();
  const before = day([duty('司琴')]);
  await db.doc(`churches/C1/rosters/${ID}`).set(before);
  const after = day([duty('司琴', ['美玉'], { 美玉: 'staff' })]);
  await rejectsWith(
    editLedDuties(deps, caller('staff'), { churchId: 'C1', before: { [ID]: before }, after: { [ID]: after }, via: 'app' }),
    'permissionDenied',
  );
  // A 事工 that no longer links the duty leads it no more.
  await db.doc('churches/C1/settings/ministries').set({ ministries: [{ ...worship, duties: [] }], ids: ['worship'] });
  await rejectsWith(
    editLedDuties(deps, caller('lead'), { churchId: 'C1', before: { [ID]: before }, after: { [ID]: after }, via: 'app' }),
    'permissionDenied',
  );
});

test('a day not made yet: one with only the duties it leads', async () => {
  await church();
  const mine = day([duty('司琴', ['美玉'], { 美玉: 'staff' })]);
  await editLedDuties(deps, caller('lead'), { churchId: 'C1', before: { [ID]: null }, after: { [ID]: mine }, via: 'app' });
  const saved = await db.doc(`churches/C1/rosters/${ID}`).get();
  assert.deepEqual(saved.get('duties'), mine.duties);
  assert.equal(saved.get('type'), 'sunday');

  const other = '2030-10-13_sunday';
  await rejectsWith(
    editLedDuties(deps, caller('lead'), {
      churchId: 'C1',
      before: { [other]: null },
      after: { [other]: { ...day([duty('司會', ['美玉'], { 美玉: 'staff' })]), dateKey: '2030-10-13' } },
      via: 'app',
    }),
    'permissionDenied',
  );
  await rejectsWith(
    editLedDuties(deps, caller('lead'), {
      churchId: 'C1', before: { '2030-10-13_youth': null }, after: { '2030-10-13_youth': mine }, via: 'app',
    }),
    'unknown',
  );
});

test("a day as an older version stored it compares equal to the app's copy", async () => {
  await church();
  // No events, and a uid left behind by a name taken off.
  await db.doc(`churches/C1/rosters/${ID}`).set({ type: 'sunday', dateKey: '2030-10-06', duties: [{ role: '司琴', people: [], uids: { 老王: 'admin' } }] });
  const after = day([duty('司琴', ['美玉'], { 美玉: 'staff' })]);
  await editLedDuties(deps, caller('lead'), { churchId: 'C1', before: { [ID]: day([duty('司琴')]) }, after: { [ID]: after }, via: 'app' });
  assert.deepEqual((await db.doc(`churches/C1/rosters/${ID}`).get()).get('duties'), after.duties);
});
