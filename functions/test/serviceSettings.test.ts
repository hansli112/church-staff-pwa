import assert from 'node:assert/strict';
import { beforeEach, test } from 'node:test';

import { editService } from '../src/serviceSettings.js';
import { caller, clearFirestore, db, deps, rejectsWith, seedChurch } from './support.js';

const sunday = {
  id: 'sunday', name: '主日崇拜', weekday: 7, enabled: true,
  duties: ['司會', '司琴'], events: [{ name: '聖餐', color: 0 }],
};
const youth = { id: 'youth', name: '青年崇拜', weekday: 6, enabled: true, duties: ['敬拜'], events: [] };

async function church() {
  await seedChurch('C1', { admin: 'admin', staff: 'staff' });
  await seedChurch('C2', { other: 'admin' });
  await db.doc('churches/C1/settings/services').set({ services: [sunday, youth], ids: ['sunday', 'youth', 'historical'] });
}

beforeEach(clearFirestore);

test('stale service edits fail with conflict instead of overwriting the newer setting', async () => {
  await church();
  const current = { ...sunday, duties: ['司琴', '司會'] };
  await db.doc('churches/C1/settings/services').update({ services: [current, youth] });
  const error = await rejectsWith(editService(deps, caller('admin'), {
    churchId: 'C1', before: sunday, after: { ...sunday, name: '過期修改' },
  }), 'conflict') as { code: string };
  assert.equal(error.code, 'aborted');
  assert.deepEqual((await db.doc('churches/C1/settings/services').get()).get('services'), [current, youth]);
});

test('an explicit duty rename moves member and pending duties and staff order atomically, preserving unrelated data and rosters', async () => {
  await church();
  const zones = [
    { serviceType: 'sunday', duties: ['司會', '司琴'], smallGroups: ['喜樂'] },
    { serviceType: 'youth', duties: ['司會'], smallGroups: ['青年'] },
  ];
  await db.doc('churches/C1/members/staff').update({ zones, zoneTypes: ['sunday', 'youth'], notificationPrefs: { muted: ['reminder'] } });
  await db.doc('churches/C1/pendingMembers/legacy').set({ name: '待認領', zones: [zones[0]], notificationPrefs: { muted: ['memberLeft'] }, emailHash: 'keep' });
  await db.doc('churches/C2/members/other').update({ zones });
  await db.doc('churches/C1/staff_orders/sunday').set({ roles: { 司會: ['同工', '待認領'], 司琴: ['同工'] }, otherField: 'keep' });
  const roster = { type: 'sunday', dateKey: '2030-10-04', duties: [{ role: '司會', people: ['同工'], uids: { 同工: 'staff' } }] };
  await db.doc('churches/C1/rosters/2030-10-04_sunday').set(roster);
  const after = { ...sunday, duties: ['主持', '司琴'] };
  await editService(deps, caller('admin'), { churchId: 'C1', before: sunday, after, dutyRename: { from: '司會', to: '主持' } });
  const member = await db.doc('churches/C1/members/staff').get();
  const pending = await db.doc('churches/C1/pendingMembers/legacy').get();
  assert.deepEqual(member.get('zones'), [{ ...zones[0], duties: ['主持', '司琴'] }, zones[1]]);
  assert.deepEqual(pending.get('zones'), [{ ...zones[0], duties: ['主持', '司琴'] }]);
  assert.deepEqual(member.get('notificationPrefs'), { muted: ['reminder'] });
  assert.deepEqual(pending.get('notificationPrefs'), { muted: ['memberLeft'] });
  assert.equal(pending.get('emailHash'), 'keep');
  assert.deepEqual((await db.doc('churches/C1/staff_orders/sunday').get()).data(), { roles: { 主持: ['同工', '待認領'], 司琴: ['同工'] }, otherField: 'keep' });
  assert.deepEqual((await db.doc('churches/C2/members/other').get()).get('zones'), zones);
  assert.deepEqual((await db.doc('churches/C1/rosters/2030-10-04_sunday').get()).data(), roster, 'future changes require a separate previewed operation');
});

test('service edits reject noncanonical input, identity changes and ambiguous duty renames without writing', async () => {
  await church();
  const valid = { churchId: 'C1', before: sunday, after: sunday };
  const invalid: Record<string, unknown>[] = [
    { ...valid, memberPatches: [{ uid: 'staff', role: 'admin' }] },
    { ...valid, after: { ...sunday, id: 'changed' } },
    { ...valid, after: { ...sunday, name: ' ' } },
    { ...valid, after: { ...sunday, weekday: 8 } },
    { ...valid, after: { ...sunday, weekday: 1.5 } },
    { ...valid, after: { ...sunday, enabled: 'yes' } },
    { ...valid, after: { ...sunday, duties: ['司會', '司會'] } },
    { ...valid, after: { ...sunday, duties: [' '] } },
    { ...valid, after: { ...sunday, events: [{ name: '聖餐', color: 6 }] } },
    { ...valid, after: { ...sunday, events: [{ name: '聖餐', color: 0.5 }] } },
    { ...valid, after: { ...sunday, events: [{ name: '聖餐', color: 0 }, { name: '聖餐', color: 1 }] } },
    { ...valid, after: { ...sunday, events: [{ name: '聖餐', color: 0, legacyColor: 123 }] } },
    { ...valid, after: { ...sunday, extra: true } },
    { ...valid, before: { ...sunday, extra: true } },
    { ...valid, dutyRename: { from: '司會', to: '司會' } },
    { ...valid, dutyRename: { from: '司會', to: '司琴' } },
    { ...valid, dutyRename: { from: '沒有', to: '主持' } },
    { ...valid, after: { ...sunday, duties: ['主持'] }, dutyRename: { from: '司會', to: '主持' } },
    { ...valid, after: { ...sunday, duties: ['主持', '司琴'] }, dutyRename: { from: '司會', to: '主持', members: [] } },
  ];
  for (const input of invalid) {
    const error = await rejectsWith(editService(deps, caller('admin'), input), 'unknown') as { code: string };
    assert.equal(error.code, 'invalid-argument', JSON.stringify(input));
    assert.deepEqual((await db.doc('churches/C1/settings/services').get()).get('services'), [sunday, youth]);
  }
});

test('a duty rename refuses a saved staff-order name collision rather than overwriting its ranking', async () => {
  await church();
  const roles = { 司會: ['原本排序'], 主持: ['保留排序'] };
  await db.doc('churches/C1/staff_orders/sunday').set({ roles });
  await db.doc('churches/C1/members/staff').update({ zones: [{ serviceType: 'sunday', duties: ['司會'], smallGroups: ['喜樂'] }] });
  const error = await rejectsWith(editService(deps, caller('admin'), {
    churchId: 'C1', before: sunday, after: { ...sunday, duties: ['主持', '司琴'] }, dutyRename: { from: '司會', to: '主持' },
  }), 'conflict') as { code: string };
  assert.equal(error.code, 'aborted');
  assert.deepEqual((await db.doc('churches/C1/settings/services').get()).get('services'), [sunday, youth]);
  assert.deepEqual((await db.doc('churches/C1/staff_orders/sunday').get()).get('roles'), roles);
  assert.deepEqual((await db.doc('churches/C1/members/staff').get()).get('zones'), [{ serviceType: 'sunday', duties: ['司會'], smallGroups: ['喜樂'] }]);
});

test('a duty rename exceeding 500 total writes refuses the whole change instead of splitting it', async () => {
  await church();
  const writer = db.bulkWriter();
  const writes: Promise<unknown>[] = [];
  for (let i = 0; i < 499; i++) {
    writes.push(writer.set(db.doc(`churches/C1/members/m${i}`), { uid: `m${i}`, role: 'staff', zones: [{ serviceType: 'sunday', duties: ['司會'], smallGroups: [] }] }));
  }
  writes.push(writer.set(db.doc('churches/C1/pendingMembers/legacy'), { zones: [{ serviceType: 'sunday', duties: ['司會'], smallGroups: ['喜樂'] }] }));
  writes.push(writer.set(db.doc('churches/C1/staff_orders/sunday'), { roles: { 司會: ['同工'] } }));
  await writer.close();
  await Promise.all(writes);
  const error = await rejectsWith(editService(deps, caller('admin'), {
    churchId: 'C1', before: sunday, after: { ...sunday, duties: ['主持', '司琴'] }, dutyRename: { from: '司會', to: '主持' },
  }), 'quotaExceeded') as { code: string; details: { detail: string } };
  assert.equal(error.code, 'resource-exhausted');
  assert.equal(error.details.detail, 'tooManyChanges');
  assert.deepEqual((await db.doc('churches/C1/settings/services').get()).get('services'), [sunday, youth]);
  assert.deepEqual((await db.doc('churches/C1/members/m0').get()).get('zones'), [{ serviceType: 'sunday', duties: ['司會'], smallGroups: [] }]);
  assert.deepEqual((await db.doc('churches/C1/pendingMembers/legacy').get()).get('zones'), [{ serviceType: 'sunday', duties: ['司會'], smallGroups: ['喜樂'] }]);
  assert.deepEqual((await db.doc('churches/C1/staff_orders/sunday').get()).get('roles'), { 司會: ['同工'] });
});

test('service edits preserve the existing service-count and historical-ID limits', async () => {
  await church();
  const ref = db.doc('churches/C1/settings/services');
  const settings = [
    { services: [sunday, youth, ...Array.from({ length: 19 }, (_, i) => ({ ...sunday, id: `s${i}` }))], ids: ['sunday', 'youth', ...Array.from({ length: 19 }, (_, i) => `s${i}`)] },
    { services: [sunday, youth], ids: ['sunday', 'youth', ...Array.from({ length: 99 }, (_, i) => `past${i}`)] },
  ];
  for (const invalid of settings) {
    await ref.set(invalid);
    const error = await rejectsWith(editService(deps, caller('admin'), { churchId: 'C1', before: sunday, after: { ...sunday, enabled: false } }), 'unknown') as { code: string };
    assert.equal(error.code, 'failed-precondition');
    assert.deepEqual((await ref.get()).data(), invalid);
  }
});

test('service edits require active admin membership in the specified church', async () => {
  await church();
  const input = { churchId: 'C1', before: sunday, after: { ...sunday, name: '改名' } };
  await rejectsWith(editService(deps, null, input), 'permissionDenied');
  await rejectsWith(editService(deps, caller('staff'), input), 'permissionDenied');
  await rejectsWith(editService(deps, caller('other'), input), 'permissionDenied');
  await db.doc('churches/C1/members/staff').update({ groups: ['roster-editors', 'calendar-editors'] });
  await rejectsWith(editService(deps, caller('staff'), input), 'permissionDenied');
  for (const status of ['suspended', 'deleted']) {
    await db.doc('churches/C1').update({ status });
    await rejectsWith(editService(deps, caller('admin'), input), 'churchClosed');
  }
  await db.doc('churches/C1').update({ status: 'active' });
  await db.doc('churches/C1/members/admin').delete();
  await rejectsWith(editService(deps, caller('admin'), input), 'permissionDenied');
  assert.deepEqual((await db.doc('churches/C1/settings/services').get()).get('services'), [sunday, youth]);
});

test('concurrent edits of the same service allow one winner and report a conflict to the other', async () => {
  await church();
  const results = await Promise.allSettled(['第一份', '第二份'].map((name) => editService(deps, caller('admin'), {
    churchId: 'C1', before: sunday, after: { ...sunday, name },
  })));
  assert.equal(results.filter((r) => r.status === 'fulfilled').length, 1);
  const loser = results.find((r) => r.status === 'rejected') as PromiseRejectedResult;
  assert.equal(loser.reason.code, 'aborted');
  assert.equal(loser.reason.details.reason, 'conflict');
});

test('editing one service compares only that service and merges the current unrelated service list', async () => {
  await church();
  const currentYouth = { ...youth, name: '另一位管理員的新名稱' };
  await db.doc('churches/C1/settings/services').update({ services: [currentYouth, sunday] });
  const after = { ...sunday, weekday: 6 };
  await editService(deps, caller('admin'), { churchId: 'C1', before: sunday, after });
  assert.deepEqual((await db.doc('churches/C1/settings/services').get()).get('services'), [currentYouth, after]);
});

test('an admin edits only the compared service, keeping unrelated services, history and existing assignments', async () => {
  await church();
  const assigned = { type: 'sunday', dateKey: '2026-10-04', duties: [{ role: '司琴', people: ['同工'], uids: { 同工: 'staff' } }], events: [{ name: '聖餐', color: 0 }] };
  await db.doc('churches/C1/rosters/2026-10-04_sunday').set(assigned);
  const after = { ...sunday, name: '主日聚會', duties: ['司會'], events: [{ name: '聖餐', color: 5 }] };
  assert.deepEqual(await editService(deps, caller('admin'), { churchId: 'C1', before: sunday, after }), {});
  const settings = await db.doc('churches/C1/settings/services').get();
  assert.deepEqual(settings.get('services'), [after, youth]);
  assert.deepEqual(settings.get('ids'), ['sunday', 'youth', 'historical']);
  assert.deepEqual((await db.doc('churches/C1/rosters/2026-10-04_sunday').get()).data(), assigned, 'configured option deletion never changes saved assignments');
});

test('a duty rename moves the 事工 that link it too (#82)', async () => {
  await church();
  const ministries = [
    { id: 'worship', name: '敬拜團', duties: [{ service: 'sunday', duty: '司會' }, { service: 'youth', duty: '司會' }] },
    { id: 'care', name: '關懷', duties: [] },
  ];
  await db.doc('churches/C1/settings/ministries').set({ ministries, ids: ['worship', 'care'] });
  await editService(deps, caller('admin'), {
    churchId: 'C1', before: sunday, after: { ...sunday, duties: ['主持', '司琴'] }, dutyRename: { from: '司會', to: '主持' },
  });
  assert.deepEqual((await db.doc('churches/C1/settings/ministries').get()).get('ministries'), [
    { id: 'worship', name: '敬拜團', duties: [{ service: 'sunday', duty: '主持' }, { service: 'youth', duty: '司會' }] },
    { id: 'care', name: '關懷', duties: [] },
  ]);
});
