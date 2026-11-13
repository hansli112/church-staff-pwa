import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

import { answerClaim, askClaim, claimCandidates } from '../src/claimAsks.js';
import { onPendingMemberDeleted } from '../src/pendingMembers.js';
import { caller, clearFirestore, db, deps, fakePush, rejectsWith, seedChurch } from './support.js';

const appUrl = 'https://app.example';

/** 恩典堂 with admin pastor, member ming (joined as 小明, in no service), and 王小明 without an account, on a Sunday. */
async function church() {
  await seedChurch('C1', { pastor: 'admin', ming: 'staff', mei: 'staff' });
  await db.doc('churches/C1').update({ name: '恩典堂' });
  await db.doc('churches/C1/members/ming').update({ name: '小明' });
  await db.doc('users/pastor').set({ fcm: { phone: 'tok-pastor' } });
  await db.doc('churches/C1/settings/services').set({ services: [{ id: 'sunday', name: '主日崇拜' }] });
  await db.doc('churches/C1/smallGroups/joy').set({ name: '喜樂小組', service: 'sunday' });
  await db.doc('churches/C1/pendingMembers/old-ming').set({
    name: '王小明',
    email: 'ming@example.com',
    emailHash: 'h',
    role: 'staff',
    groups: [],
    zones: [{ serviceType: 'sunday', duties: ['招待'], smallGroups: ['青年'] }],
    zoneTypes: ['sunday'],
    smallGroups: ['joy'],
    rosterIds: ['2026-10-04_sunday'],
  });
  await db.doc('churches/C1/rosters/2026-10-04_sunday').set({
    type: 'sunday',
    duties: [{ role: '招待', people: ['王小明'], uids: { 王小明: 'old-ming' } }],
  });
}

beforeEach(clearFirestore);

describe('認領申請', () => {
  test('a member sees the 同工 without an account: names, 小組 and duties, no emails', async () => {
    await church();
    const { candidates } = await claimCandidates(deps, caller('ming'), { churchId: 'C1' });
    assert.deepEqual(candidates, [
      { pendingId: 'old-ming', name: '王小明', smallGroups: ['喜樂小組', '青年'], serves: [{ dateKey: '2026-10-04', service: '主日崇拜', duty: '招待' }] },
    ]);
    await rejectsWith(claimCandidates(deps, caller('stranger'), { churchId: 'C1' }), 'permissionDenied');
  });

  test('asking tells the admins once; asking again replaces it; null takes it back', async () => {
    await church();
    const { messaging, sent } = fakePush();
    const pd = { ...deps, messaging, appUrl };
    assert.deepEqual(await askClaim(pd, caller('ming'), { churchId: 'C1', pendingId: 'old-ming' }), {});
    const ask = await db.doc('churches/C1/claimAsks/ming').get();
    assert.deepEqual(
      { uid: ask.get('uid'), name: ask.get('name'), pendingId: ask.get('pendingId'), pendingName: ask.get('pendingName') },
      { uid: 'ming', name: '小明', pendingId: 'old-ming', pendingName: '王小明' },
    );
    assert.deepEqual(sent.map((s) => [s.tokens, s.title, s.body, s.link]), [[['tok-pastor'], '恩典堂', '「小明」說自己是服事表上的「王小明」', '/c/C1?to=%2Fme%2Fmembers']]);
    await askClaim(pd, caller('ming'), { churchId: 'C1', pendingId: 'old-ming' });
    assert.equal(sent.length, 1, 'the same ask is not told twice');
    await rejectsWith(askClaim(pd, caller('ming'), { churchId: 'C1', pendingId: 'nobody' }), 'notFound');
    await askClaim(pd, caller('ming'), { churchId: 'C1', pendingId: null });
    assert.equal((await db.doc('churches/C1/claimAsks/ming').get()).exists, false);
  });

  test('an admin says yes: merged, the rosters theirs, the ask gone', async () => {
    await church();
    const pd = { ...deps, messaging: fakePush().messaging, appUrl };
    await askClaim(pd, caller('ming'), { churchId: 'C1', pendingId: 'old-ming' });
    await rejectsWith(answerClaim(deps, caller('mei'), { churchId: 'C1', uid: 'ming', allow: true }), 'permissionDenied');
    assert.deepEqual(await answerClaim(deps, caller('pastor'), { churchId: 'C1', uid: 'ming', allow: true }), {});
    const ming = await db.doc('churches/C1/members/ming').get();
    assert.deepEqual(ming.get('zoneTypes'), ['sunday']);
    assert.deepEqual((await db.doc('churches/C1/rosters/2026-10-04_sunday').get()).get('duties')[0].uids, { 王小明: 'ming' });
    assert.equal((await db.doc('churches/C1/pendingMembers/old-ming').get()).exists, false);
    assert.equal((await db.doc('churches/C1/claimAsks/ming').get()).exists, false);
    await rejectsWith(answerClaim(deps, caller('pastor'), { churchId: 'C1', uid: 'ming', allow: true }), 'notFound');
  });

  test('an admin says no: the ask goes, nothing else changes', async () => {
    await church();
    const pd = { ...deps, messaging: fakePush().messaging, appUrl };
    await askClaim(pd, caller('ming'), { churchId: 'C1', pendingId: 'old-ming' });
    await answerClaim(deps, caller('pastor'), { churchId: 'C1', uid: 'ming', allow: false });
    assert.equal((await db.doc('churches/C1/claimAsks/ming').get()).exists, false);
    assert.ok((await db.doc('churches/C1/pendingMembers/old-ming').get()).exists);
    assert.deepEqual((await db.doc('churches/C1/members/ming').get()).get('zones'), []);
  });

  test('asks naming a pending member go with it', async () => {
    await church();
    const pd = { ...deps, messaging: fakePush().messaging, appUrl };
    await askClaim(pd, caller('ming'), { churchId: 'C1', pendingId: 'old-ming' });
    await askClaim(pd, caller('mei'), { churchId: 'C1', pendingId: 'old-ming' });
    const ref = db.doc('churches/C1/pendingMembers/old-ming');
    const snap = await ref.get();
    await ref.delete();
    await onPendingMemberDeleted(deps, 'C1', snap);
    assert.equal((await db.collection('churches/C1/claimAsks').get()).size, 0);
  });
});
