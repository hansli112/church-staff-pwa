import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

import { getStorage } from 'firebase-admin/storage';

import { claimPending, mergePending, onPendingMemberDeleted, pendingClaims } from '../src/claim.js';
import { emailHash, moveCommit, type MoveDeps } from '../src/move.js';
import { caller, clearFirestore, db, deps, rejectsWith } from './support.js';

const bucket = getStorage().bucket('demo-martha.appspot.com');
const d: MoveDeps = { ...deps, bucket };

/** A church moved from self-host by 'mover', with 美玉 and 志豪 pending. */
async function moved(name = '恩典堂', mover = 'mover') {
  const path = `moves/${mover}/f.json`;
  await bucket.file(path).save(
    JSON.stringify({
      format: 'church-staff-pwa-move',
      version: 1,
      users: [
        { id: 'old-mei', data: { name: '李美玉', email: 'Mei@Example.com', role: 'leader', groups: ['roster-editors'], zones: [{ serviceType: 'sunday', ministries: ['司琴'] }] } },
        { id: 'old-hao', data: { name: '陳志豪', email: 'hao@example.com', role: 'staff', zones: [{ serviceType: 'sunday', ministries: ['招待'] }] } },
      ],
      settings: [{ id: 'services', data: { services: [{ id: 'sunday', name: '主日崇拜' }], ids: ['sunday'] } }],
      rosters: [
        { id: '20261004_sunday', data: { type: 'sunday', duties: [{ role: '司琴', people: ['李美玉'], personIdsByName: { 李美玉: 'old-mei' } }, { role: '招待', people: ['陳志豪'], personIdsByName: { 陳志豪: 'old-hao' } }] } },
        { id: '20261011_sunday', data: { type: 'sunday', duties: [{ role: '司琴', people: ['李美玉'], personIdsByName: { 李美玉: 'old-mei' } }] } },
      ],
    }),
  );
  return (await moveCommit(d, caller(mover), { path, churchName: name })).churchId;
}

const mei = (extra = {}) => caller('new-mei', { email: 'mei@example.com', ...extra });
const uidsOn = async (cid: string, day: string) =>
  ((await db.doc(`churches/${cid}/rosters/${day}_sunday`).get()).get('duties') as { uids: Record<string, string> }[]).map((x) => x.uids);

beforeEach(async () => {
  await clearFirestore();
  await bucket.deleteFiles({ prefix: 'moves/' });
});

describe('claiming', () => {
  test('a verified email finds its pending member; an unverified one finds nothing', async () => {
    const cid = await moved();
    assert.deepEqual(await pendingClaims(deps, mei()), { claims: [{ churchId: cid, churchName: '恩典堂', pendingId: 'old-mei', name: '李美玉' }] });
    assert.deepEqual(await pendingClaims(deps, mei({ emailVerified: false })), { claims: [] });
    assert.deepEqual(await pendingClaims(deps, caller('x', { email: 'nobody@example.com' })), { claims: [] });
  });

  test('joining moves the member under the uid and rewrites that church’s rosters', async () => {
    const cid = await moved();
    assert.deepEqual(await claimPending(deps, mei(), { churchId: cid, pendingId: 'old-mei' }), { churchId: cid });
    const m = await db.doc(`churches/${cid}/members/new-mei`).get();
    assert.equal(m.get('name'), '李美玉');
    assert.equal(m.get('email'), 'mei@example.com');
    assert.equal(m.get('role'), 'leader');
    assert.deepEqual(m.get('groups'), ['roster-editors']);
    assert.deepEqual(m.get('zones'), [{ serviceType: 'sunday', duties: ['司琴'] }]);
    assert.deepEqual(await uidsOn(cid, '2026-10-04'), [{ 李美玉: 'new-mei' }, { 陳志豪: 'old-hao' }]);
    assert.deepEqual(await uidsOn(cid, '2026-10-11'), [{ 李美玉: 'new-mei' }]);
    assert.equal((await db.doc(`churches/${cid}/pendingMembers/old-mei`).get()).exists, false);
    assert.equal((await db.doc(`pendingIndex/${emailHash('mei@example.com')}`).get()).get(`churches.${cid}`), undefined);
    assert.deepEqual((await pendingClaims(deps, mei())).claims, []);
  });

  test('claiming twice is fine', async () => {
    const cid = await moved();
    await claimPending(deps, mei(), { churchId: cid, pendingId: 'old-mei' });
    assert.deepEqual(await claimPending(deps, mei(), { churchId: cid, pendingId: 'old-mei' }), { churchId: cid });
  });

  test('not claiming adds nobody; someone else’s email or an unverified one cannot claim', async () => {
    const cid = await moved();
    await pendingClaims(deps, mei());
    assert.equal((await db.doc(`churches/${cid}/members/new-mei`).get()).exists, false, 'never automatic');
    await rejectsWith(claimPending(deps, caller('stranger', { email: 'x@example.com' }), { churchId: cid, pendingId: 'old-mei' }), 'permissionDenied');
    await rejectsWith(claimPending(deps, mei({ emailVerified: false }), { churchId: cid, pendingId: 'old-mei' }), 'unverifiedEmail');
    assert.ok((await db.doc(`churches/${cid}/pendingMembers/old-mei`).get()).exists);
  });

  test('someone who joined by invite first keeps their role and gains the rest', async () => {
    const cid = await moved();
    await db.doc(`churches/${cid}/members/new-mei`).set({ uid: 'new-mei', name: '美玉', email: 'mei@example.com', role: 'staff', groups: [], zones: [{ serviceType: 'sunday', duties: ['招待'] }], zoneTypes: ['sunday'] });
    await claimPending(deps, mei(), { churchId: cid, pendingId: 'old-mei' });
    const m = await db.doc(`churches/${cid}/members/new-mei`).get();
    assert.equal(m.get('role'), 'staff');
    assert.deepEqual(m.get('groups'), ['roster-editors']);
    assert.deepEqual(m.get('zones'), [{ serviceType: 'sunday', duties: ['招待', '司琴'] }]);
  });

  test('a suspended church cannot be claimed into', async () => {
    const cid = await moved();
    await db.doc(`churches/${cid}`).update({ status: 'suspended' });
    assert.deepEqual((await pendingClaims(deps, mei())).claims, []);
    await rejectsWith(claimPending(deps, mei(), { churchId: cid, pendingId: 'old-mei' }), 'permissionDenied');
  });
});

describe('dropping pending data', () => {
  test('when an admin deletes a pending member, its index entry goes too', async () => {
    const cid = await moved();
    const ref = db.doc(`churches/${cid}/pendingMembers/old-hao`);
    const snap = await ref.get();
    await ref.delete();
    assert.equal(await onPendingMemberDeleted(deps, cid, snap), true);
    assert.equal((await db.doc(`pendingIndex/${emailHash('hao@example.com')}`).get()).get(`churches.${cid}`), undefined);
    assert.equal(await onPendingMemberDeleted(deps, cid, snap), false, 'nothing left to do');
  });
});

describe('merging', () => {
  test('an admin merges a pending member into someone who joined with another email', async () => {
    const cid = await moved();
    await db.doc(`churches/${cid}/members/hao-google`).set({ uid: 'hao-google', name: '志豪', email: 'hao@gmail.com', role: 'staff', groups: [], zones: [], zoneTypes: [] });
    assert.deepEqual(await mergePending(deps, caller('mover'), { churchId: cid, pendingId: 'old-hao', uid: 'hao-google' }), {});
    const m = await db.doc(`churches/${cid}/members/hao-google`).get();
    assert.deepEqual(m.get('zones'), [{ serviceType: 'sunday', duties: ['招待'] }]);
    assert.deepEqual(m.get('zoneTypes'), ['sunday']);
    assert.deepEqual(await uidsOn(cid, '2026-10-04'), [{ 李美玉: 'old-mei' }, { 陳志豪: 'hao-google' }]);
    assert.equal((await db.doc(`churches/${cid}/pendingMembers/old-hao`).get()).exists, false);
    assert.equal((await db.doc(`pendingIndex/${emailHash('hao@example.com')}`).get()).get(`churches.${cid}`), undefined);
  });

  test('only that church’s admin, and only within that church', async () => {
    const cid = await moved();
    const other = await moved('活水堂', 'other');
    await db.doc(`churches/${cid}/members/hao-google`).set({ uid: 'hao-google', name: '志豪', role: 'staff', groups: [], zones: [], zoneTypes: [] });
    await db.doc(`churches/${cid}/members/staffer`).set({ uid: 'staffer', name: '同工', role: 'staff' });
    await rejectsWith(mergePending(deps, caller('staffer'), { churchId: cid, pendingId: 'old-hao', uid: 'hao-google' }), 'permissionDenied');
    await rejectsWith(mergePending(deps, caller('other'), { churchId: cid, pendingId: 'old-hao', uid: 'hao-google' }), 'permissionDenied');
    // The other church's admin, in their own church, cannot reach this church's member.
    await rejectsWith(mergePending(deps, caller('other'), { churchId: other, pendingId: 'old-hao', uid: 'hao-google' }), 'notFound');
    assert.ok((await db.doc(`churches/${cid}/pendingMembers/old-hao`).get()).exists);
    assert.ok((await db.doc(`churches/${other}/pendingMembers/old-hao`).get()).exists);
  });
});
