import assert from 'node:assert/strict';
import { beforeEach, test } from 'node:test';

import { applyUidBackfillPlan, createUidBackfillPlan } from '../scripts/backfill-roster-uids.js';
import { clearFirestore, db, seedChurch } from './support.js';

beforeEach(clearFirestore);

async function church() {
  await seedChurch('C1', { mei: 'staff', twin1: 'staff', twin2: 'staff' });
  await db.doc('churches/C1/members/mei').update({ name: '李美玉', email: 'PRIVATE-EMAIL@example.com' });
  await db.doc('churches/C1/members/twin1').update({ name: '志豪' });
  await db.doc('churches/C1/members/twin2').update({ name: '志豪' });
  await seedChurch('C2', { other: 'staff' });
  await db.doc('churches/C2/members/other').update({ name: '李美玉' });
}

const legacy = {
  type: 'sunday', dateKey: '2026-10-04', duties: [
    { role: '司琴', people: ['李美玉', '志豪', '美玉', '外賓'] },
    { role: '敬拜', people: ['李美玉'], uids: {} },
    { role: '音控', people: ['李美玉'], uids: { 李美玉: 'unknown-explicit' } },
  ],
};

test('applying a UID backfill plan binds only eligible exact identities and marks the repair as a quiet import', async () => {
  await church();
  await db.doc('churches/C1/rosters/legacy').set({ ...legacy, otherField: 'preserved', via: 'app' });
  await db.doc('churches/C2/rosters/foreign').set(legacy);
  const plan = await createUidBackfillPlan(db, 'C1');
  const result = await applyUidBackfillPlan(db, plan);
  assert.equal(result.appliedRosters, 1);
  assert.equal(result.conflicts, 0);
  const repaired = await db.doc('churches/C1/rosters/legacy').get();
  assert.deepEqual(repaired.get('duties'), [
    { ...legacy.duties[0], uids: { 李美玉: 'mei' } }, legacy.duties[1], legacy.duties[2],
  ]);
  assert.equal(repaired.get('otherField'), 'preserved');
  assert.equal(repaired.get('via'), 'import', 'existing import semantics suppress misleading repair pushes');
  assert.ok(repaired.get('updatedAt'));
  assert.deepEqual((await db.doc('churches/C2/rosters/foreign').get()).data(), legacy);
  assert.equal((await createUidBackfillPlan(db, 'C1')).summary.rostersToChange, 0, 'the one-time conversion is idempotent');
});

test('backfill CAS refuses a roster changed since preview, especially a newly explicit same-name guest', async () => {
  await church();
  const ref = db.doc('churches/C1/rosters/legacy');
  await ref.set(legacy);
  const plan = await createUidBackfillPlan(db, 'C1');
  const edited = { type: 'sunday', dateKey: '2026-10-04', title: '新的安排', via: 'app', duties: [{ role: '司琴', people: ['李美玉'], uids: {} }] };
  await ref.set(edited);
  assert.deepEqual(await applyUidBackfillPlan(db, plan), { appliedRosters: 0, conflicts: 1, conflictRosterIds: ['legacy'] });
  assert.deepEqual((await ref.get()).data(), edited, 'CAS never overwrites newer guest intent');
});

test('backfill rechecks identity uniqueness and church existence in its apply transaction', async () => {
  for (const change of ['duplicateMember', 'duplicatePending', 'renamed', 'removedMember', 'purgedChurch']) {
    await clearFirestore();
    await church();
    const ref = db.doc('churches/C1/rosters/legacy');
    await ref.set(legacy);
    const plan = await createUidBackfillPlan(db, 'C1');
    if (change === 'duplicateMember') await db.doc('churches/C1/members/new-mei').set({ uid: 'new-mei', name: '李美玉', role: 'staff' });
    else if (change === 'duplicatePending') await db.doc('churches/C1/pendingMembers/old-mei').set({ name: '李美玉' });
    else if (change === 'renamed') await db.doc('churches/C1/members/mei').update({ name: '新名字' });
    else if (change === 'removedMember') await db.doc('churches/C1/members/mei').delete();
    else await db.doc('churches/C1').delete();
    assert.deepEqual(await applyUidBackfillPlan(db, plan), { appliedRosters: 0, conflicts: 1, conflictRosterIds: ['legacy'] }, change);
    assert.deepEqual((await ref.get()).data(), legacy, change);
  }
});

test('only an explicit confirmed mapping repairs a canonical empty map or selects an ambiguous/abbreviated identity', async () => {
  await church();
  const ref = db.doc('churches/C1/rosters/guest');
  await ref.set({ type: 'sunday', dateKey: '2026-10-04', duties: [{ role: '司琴', people: ['志豪', '美玉'], uids: {} }] });
  assert.equal((await createUidBackfillPlan(db, 'C1')).summary.rostersToChange, 0);
  const plan = await createUidBackfillPlan(db, 'C1', {
    format: 'martha-roster-uid-backfill', version: 1, bindings: [
      { rosterId: 'guest', dutyIndex: 0, name: '志豪', uid: 'twin2' },
      { rosterId: 'guest', dutyIndex: 0, name: '美玉', uid: 'mei' },
    ],
  });
  assert.equal(plan.summary.automaticBindings, 0);
  assert.equal(plan.summary.confirmedBindings, 2);
  assert.equal(plan.summary.rostersToChange, 1);
  await applyUidBackfillPlan(db, plan);
  assert.deepEqual((await ref.get()).get('duties'), [{ role: '司琴', people: ['志豪', '美玉'], uids: { 志豪: 'twin2', 美玉: 'mei' } }]);
});

test('pending identities block same-name member inference, and a reused pending ID cannot impersonate a current member', async () => {
  await church();
  await db.doc('churches/C1/pendingMembers/old-mei').set({ name: '李美玉' });
  await db.doc('churches/C1/pendingMembers/mei').set({ name: '其他人' });
  await db.doc('churches/C1/rosters/legacy').set({ type: 'sunday', dateKey: '2026-10-04', duties: [{ role: '司琴', people: ['李美玉', '其他人'] }] });
  const plan = await createUidBackfillPlan(db, 'C1');
  assert.equal(plan.summary.automaticBindings, 0);
  assert.equal(plan.summary.ambiguousNames, 1);
  assert.equal(plan.summary.unknownNames, 1);
});

test('the one-time UID backfill preview is read-only, CID-scoped and preserves explicit guest maps', async () => {
  await church();
  await db.doc('churches/C1/rosters/legacy').set(legacy);
  await db.doc('churches/C1/rosters/guest').set({ type: 'sunday', dateKey: '2026-10-11', duties: [{ role: '司琴', people: ['李美玉'], uids: {} }] });
  await db.doc('churches/C2/rosters/foreign').set(legacy);
  const plan = await createUidBackfillPlan(db, 'C1');
  assert.equal(plan.summary.scannedRosters, 2);
  assert.equal(plan.summary.rostersToChange, 1);
  assert.equal(plan.summary.normalizedUidMaps, 1);
  assert.equal(plan.summary.automaticBindings, 1);
  assert.equal(plan.summary.ambiguousNames, 1);
  assert.equal(plan.summary.unknownNames, 2);
  assert.deepEqual(plan.summary.rosterIds, ['legacy']);
  assert.deepEqual((await db.doc('churches/C1/rosters/legacy').get()).data(), legacy);
  assert.deepEqual((await db.doc('churches/C2/rosters/foreign').get()).data(), legacy);
  const output = JSON.stringify(plan.summary);
  for (const privateValue of ['李美玉', '志豪', '美玉', '外賓', 'PRIVATE-EMAIL', 'unknown-explicit']) assert.equal(output.includes(privateValue), false);
});

test('a confirmation never replaces a binding, names someone off the duty, or binds a non-member', async () => {
  await church();
  await db.doc('churches/C1/pendingMembers/old-hao').set({ name: '舊名單' });
  await db.doc('churches/C1/rosters/bound').set({
    type: 'sunday', dateKey: '2026-10-04', duties: [{ role: '司琴', people: ['李美玉', '外賓'], uids: { 李美玉: 'mei' } }],
  });
  const confirm = (binding: { name: string; uid: string; rosterId?: string; dutyIndex?: number }) =>
    createUidBackfillPlan(db, 'C1', {
      format: 'martha-roster-uid-backfill', version: 1,
      bindings: [{ rosterId: 'bound', dutyIndex: 0, ...binding }],
    });
  await assert.rejects(confirm({ name: '李美玉', uid: 'twin1' }), /confirmationRejected/, 'replacing a binding');
  await assert.rejects(confirm({ name: '不在這項', uid: 'twin1' }), /confirmationRejected/, 'a name not on the duty');
  await assert.rejects(confirm({ name: '外賓', uid: 'old-hao' }), /confirmationRejected/, 'a pending person is not a member');
  await assert.rejects(confirm({ name: '外賓', uid: 'mei', rosterId: 'missing' }), /confirmedRosterMissing/);
  await assert.rejects(
    createUidBackfillPlan(db, 'C1', { format: 'other', version: 1, bindings: [] } as never),
    /invalidConfirmations/,
  );
  assert.deepEqual((await db.doc('churches/C1/rosters/bound').get()).get('duties')[0].uids, { 李美玉: 'mei' });
});
