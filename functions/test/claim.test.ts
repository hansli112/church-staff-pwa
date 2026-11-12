import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

import { getStorage } from 'firebase-admin/storage';

import { claimPending, mergePending, pendingClaims } from '../src/claim.js';
import { moveCommit, type MoveDeps } from '../src/move.js';
import { callerKey, onPendingMemberDeleted, waitingFor } from '../src/pendingMembers.js';
import { auth, caller, clearFirestore, db, deps, rejectsWith } from './support.js';

const bucket = getStorage().bucket('demo-martha.appspot.com');
const d: MoveDeps = { ...deps, bucket };
/** Claims look up the caller's linked sign-ins too. */
const cd = { ...deps, auth };

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
/** The churches the index says wait for [email]. */
const indexed = async (email: string) => (await waitingFor(deps, callerKey(caller('x', { email }))!)).map(([cid]) => cid);
const uidsOn = async (cid: string, day: string) =>
  ((await db.doc(`churches/${cid}/rosters/${day}_sunday`).get()).get('duties') as { uids: Record<string, string> }[]).map((x) => x.uids);

beforeEach(async () => {
  await clearFirestore();
  await bucket.deleteFiles({ prefix: 'moves/' });
});

describe('claiming', () => {
  test('a verified email finds its pending member; an unverified one finds nothing', async () => {
    const cid = await moved();
    assert.deepEqual(await pendingClaims(cd, mei()), {
      claims: [{
        churchId: cid,
        churchName: '恩典堂',
        pendingId: 'old-mei',
        name: '李美玉',
        serves: [
          { dateKey: '2026-10-04', service: '主日崇拜', duty: '司琴' },
          { dateKey: '2026-10-11', service: '主日崇拜', duty: '司琴' },
        ],
      }],
    });
    assert.deepEqual(await pendingClaims(cd, mei({ emailVerified: false })), { claims: [] });
    assert.deepEqual(await pendingClaims(cd, caller('x', { email: 'nobody@example.com' })), { claims: [] });
  });

  test('joining moves the member under the uid and rewrites that church’s rosters', async () => {
    const cid = await moved();
    assert.deepEqual(await claimPending(cd, mei(), { churchId: cid, pendingId: 'old-mei' }), { churchId: cid });
    const m = await db.doc(`churches/${cid}/members/new-mei`).get();
    assert.equal(m.get('name'), '李美玉');
    assert.equal(m.get('email'), 'mei@example.com');
    assert.equal(m.get('role'), 'leader');
    assert.deepEqual(m.get('groups'), []);
    assert.deepEqual(m.get('leadTypes'), ['sunday']);
    assert.deepEqual(m.get('zones'), [{ serviceType: 'sunday', duties: ['司琴'], smallGroups: [] }]);
    assert.deepEqual(await uidsOn(cid, '2026-10-04'), [{ 李美玉: 'new-mei' }, { 陳志豪: 'old-hao' }]);
    assert.deepEqual(await uidsOn(cid, '2026-10-11'), [{ 李美玉: 'new-mei' }]);
    assert.equal((await db.doc(`churches/${cid}/pendingMembers/old-mei`).get()).exists, false);
    assert.deepEqual(await indexed('mei@example.com'), []);
    assert.deepEqual((await pendingClaims(cd, mei())).claims, []);
  });

  test('claiming a new identity preserves migrated small groups and reminder opt-out', async () => {
    const cid = await moved();
    await db.doc(`churches/${cid}/pendingMembers/old-mei`).update({
      zones: [{ serviceType: 'sunday', duties: ['司琴'], smallGroups: ['喜樂'] }],
      notificationPrefs: { muted: ['reminder'] },
    });
    await claimPending(cd, mei(), { churchId: cid, pendingId: 'old-mei' });
    const m = await db.doc(`churches/${cid}/members/new-mei`).get();
    assert.deepEqual(m.get('notificationPrefs'), { muted: ['reminder'] });
    assert.deepEqual(m.get('zones'), [{ serviceType: 'sunday', duties: ['司琴'], smallGroups: ['喜樂'] }]);
    // A self-host roster editor edited their 牧區's rosters: its 負責人 now (#82).
    assert.deepEqual(m.get('groups'), []);
    assert.deepEqual(m.get('leadTypes'), ['sunday']);
    assert.deepEqual(m.get('identities'), [{ kind: 'lead', service: 'sunday' }]);
    assert.deepEqual(await uidsOn(cid, '2026-10-04'), [{ 李美玉: 'new-mei' }, { 陳志豪: 'old-hao' }]);
    assert.equal((await db.doc(`churches/${cid}/pendingMembers/old-mei`).get()).exists, false);
  });

  test('a day they were put on since the move, and a 小組 they were put in, are theirs once claimed', async () => {
    const cid = await moved();
    await db.doc(`churches/${cid}/smallGroups/joy`).set({ name: '喜樂', service: 'sunday' });
    await db.doc(`churches/${cid}/pendingMembers/old-mei`).update({ smallGroups: ['joy'] });
    await db.doc(`churches/${cid}/rosters/2026-10-18_sunday`).set({
      type: 'sunday',
      duties: [{ role: '司琴', people: ['李美玉'], uids: { 李美玉: 'old-mei' } }],
    });
    await claimPending(cd, mei(), { churchId: cid, pendingId: 'old-mei' });
    assert.deepEqual((await db.doc(`churches/${cid}/members/new-mei`).get()).get('smallGroups'), ['joy']);
    assert.deepEqual(await uidsOn(cid, '2026-10-18'), [{ 李美玉: 'new-mei' }]);
  });

  test('a claim made, its rosters still being pointed at them, is not asked again', async () => {
    const cid = await moved();
    // Where claimPending is between making the member and dropping the
    // pending one; their app, seeing the new church, asks again meanwhile.
    await db.doc(`churches/${cid}/members/new-mei`).set({ uid: 'new-mei', name: '李美玉', role: 'leader', claimedFrom: 'old-mei' });
    assert.deepEqual((await pendingClaims(cd, mei())).claims, []);
  });

  test('someone who joined by invite first is asked, and after saying yes is not asked again', async () => {
    const cid = await moved();
    await db.doc(`churches/${cid}/members/new-mei`).set({ uid: 'new-mei', name: '美玉', email: 'mei@example.com', role: 'staff', groups: [], zones: [], zoneTypes: [] });
    assert.equal((await pendingClaims(cd, mei())).claims.length, 1);
    await claimPending(cd, mei(), { churchId: cid, pendingId: 'old-mei' });
    assert.equal((await db.doc(`churches/${cid}/members/new-mei`).get()).get('claimedFrom'), 'old-mei');
  });

  test('claiming twice is fine', async () => {
    const cid = await moved();
    await claimPending(cd, mei(), { churchId: cid, pendingId: 'old-mei' });
    assert.deepEqual(await claimPending(cd, mei(), { churchId: cid, pendingId: 'old-mei' }), { churchId: cid });
  });

  test('not claiming adds nobody; someone else’s email or an unverified one cannot claim', async () => {
    const cid = await moved();
    await pendingClaims(cd, mei());
    assert.equal((await db.doc(`churches/${cid}/members/new-mei`).get()).exists, false, 'never automatic');
    await rejectsWith(claimPending(cd, caller('stranger', { email: 'x@example.com' }), { churchId: cid, pendingId: 'old-mei' }), 'permissionDenied');
    await rejectsWith(claimPending(cd, mei({ emailVerified: false }), { churchId: cid, pendingId: 'old-mei' }), 'unverifiedEmail');
    assert.ok((await db.doc(`churches/${cid}/pendingMembers/old-mei`).get()).exists);
  });

  test('someone who joined by invite first keeps their role and gains the rest', async () => {
    const cid = await moved();
    await db.doc(`churches/${cid}/members/new-mei`).set({ uid: 'new-mei', name: '美玉', email: 'mei@example.com', role: 'staff', groups: [], zones: [{ serviceType: 'sunday', duties: ['招待'] }], zoneTypes: ['sunday'] });
    await claimPending(cd, mei(), { churchId: cid, pendingId: 'old-mei' });
    const m = await db.doc(`churches/${cid}/members/new-mei`).get();
    assert.equal(m.get('role'), 'staff');
    assert.deepEqual(m.get('groups'), []);
    assert.deepEqual(m.get('leadTypes'), ['sunday']);
    assert.deepEqual(m.get('zones'), [{ serviceType: 'sunday', duties: ['招待', '司琴'], smallGroups: [] }]);
  });

  test('a suspended church cannot be claimed into', async () => {
    const cid = await moved();
    await db.doc(`churches/${cid}`).update({ status: 'suspended' });
    assert.deepEqual((await pendingClaims(cd, mei())).claims, []);
    await rejectsWith(claimPending(cd, mei(), { churchId: cid, pendingId: 'old-mei' }), 'churchClosed');
  });
});

describe('claiming by name, a pending member with no email', () => {
  /** 黃鎮台, no email on the list, and his day; [joined] has joined by invite under [name]. */
  async function noEmail(joined = 'huang', name = '黃鎮台') {
    const cid = await moved();
    await db.doc(`churches/${cid}/pendingMembers/old-huang`).set({
      name: '黃鎮台',
      email: null,
      emailHash: null,
      role: 'staff',
      zones: [{ serviceType: 'sunday', duties: ['招待'], smallGroups: [] }],
      zoneTypes: ['sunday'],
      rosterIds: ['2026-10-11_sunday'],
    });
    await db.doc(`churches/${cid}/rosters/2026-10-11_sunday`).update({ duties: [{ role: '招待', people: ['黃鎮台'], uids: { 黃鎮台: 'old-huang' } }] });
    await db.doc(`churches/${cid}/members/${joined}`).set({ uid: joined, name, email: `${joined}@example.com`, role: 'staff', groups: [], zones: [], zoneTypes: [] });
    return cid;
  }

  test('someone in the church under the same name is asked, and saying yes takes it', async () => {
    const cid = await noEmail();
    const huang = caller('huang');
    assert.deepEqual((await pendingClaims(cd, huang)).claims, [
      { churchId: cid, churchName: '恩典堂', pendingId: 'old-huang', name: '黃鎮台', byName: true, serves: [{ dateKey: '2026-10-11', service: '主日崇拜', duty: '招待' }] },
    ]);
    await claimPending(cd, huang, { churchId: cid, pendingId: 'old-huang' });
    const m = await db.doc(`churches/${cid}/members/huang`).get();
    assert.equal(m.get('role'), 'staff', 'the role is not taken over, as an admin merging');
    assert.deepEqual(m.get('zones'), [{ serviceType: 'sunday', duties: ['招待'], smallGroups: [] }]);
    assert.deepEqual(await uidsOn(cid, '2026-10-11'), [{ 黃鎮台: 'huang' }]);
    assert.equal((await db.doc(`churches/${cid}/pendingMembers/old-huang`).get()).exists, false);
    assert.deepEqual((await pendingClaims(cd, huang)).claims, []);
  });

  test('even with no verified email: the church let them in', async () => {
    await noEmail();
    assert.equal((await pendingClaims(cd, caller('huang', { emailVerified: false }))).claims.length, 1);
  });

  test('another name, or someone not in the church, is not asked and cannot take it', async () => {
    const cid = await noEmail('wang', '王小明');
    assert.deepEqual((await pendingClaims(cd, caller('wang'))).claims, []);
    await rejectsWith(claimPending(cd, caller('wang'), { churchId: cid, pendingId: 'old-huang' }), 'permissionDenied');
    assert.deepEqual((await pendingClaims(cd, caller('stranger', { name: '黃鎮台' }))).claims, []);
    await rejectsWith(claimPending(cd, caller('stranger', { name: '黃鎮台' }), { churchId: cid, pendingId: 'old-huang' }), 'permissionDenied');
  });

  test('a pending member with an email waits for that email, not the name', async () => {
    const cid = await noEmail();
    await db.doc(`churches/${cid}/members/mei-2`).set({ uid: 'mei-2', name: '李美玉', role: 'staff', groups: [], zones: [], zoneTypes: [] });
    assert.deepEqual((await pendingClaims(cd, caller('mei-2'))).claims, []);
    await rejectsWith(claimPending(cd, caller('mei-2'), { churchId: cid, pendingId: 'old-mei' }), 'permissionDenied');
  });

  test('asked with a few of their days to know them by: the next ones, or the last; or what they serve', async () => {
    const cid = await noEmail();
    const days = ['2026-09-20', '2026-09-27', '2026-10-11', '2026-10-18', '2026-10-25', '2026-11-01'];
    for (const day of days) {
      await db.doc(`churches/${cid}/rosters/${day}_sunday`).set({ type: 'sunday', duties: [{ role: '招待', people: ['黃鎮台'], uids: { 黃鎮台: 'old-huang' } }] });
    }
    // Someone else took 10/18 since.
    await db.doc(`churches/${cid}/rosters/2026-10-18_sunday`).update({ duties: [{ role: '招待', people: ['王小明'], uids: { 王小明: 'wang' } }] });
    const pending = db.doc(`churches/${cid}/pendingMembers/old-huang`);
    await pending.update({ rosterIds: days.map((day) => `${day}_sunday`) });
    const serves = async () => (await pendingClaims(cd, caller('huang'))).claims[0].serves.map((s) => s.dateKey ?? `${s.service}・${s.duty}`);
    assert.deepEqual(await serves(), ['2026-10-11', '2026-10-25', '2026-11-01']);
    await pending.update({ rosterIds: ['2026-09-20_sunday', '2026-09-27_sunday'] });
    assert.deepEqual(await serves(), ['2026-09-27', '2026-09-20']);
    await pending.update({ rosterIds: [] });
    assert.deepEqual(await serves(), ['主日崇拜・招待']);
  });

  test('two with no email under the name: nobody is asked, the admin merges', async () => {
    const cid = await noEmail();
    await db.doc(`churches/${cid}/pendingMembers/old-huang-2`).set({ name: '黃鎮台', email: null, emailHash: null, role: 'staff', zones: [], rosterIds: [] });
    assert.deepEqual((await pendingClaims(cd, caller('huang'))).claims, []);
  });
});

describe('claiming with a linked Google or Apple account', () => {
  /** Signed up with an old yahoo address, never verified, then linked [provider] under mei's email. */
  async function linked(providerId = 'google.com', email = 'mei@example.com') {
    await auth.deleteUser('yahoo-mei').catch(() => {});
    await auth.createUser({ uid: 'yahoo-mei', email: 'mei.old@yahoo.com', emailVerified: false });
    await auth.updateUser('yahoo-mei', { providerToLink: { providerId, uid: `${providerId}-mei`, email } });
    return caller('yahoo-mei', { email: 'mei.old@yahoo.com', emailVerified: false });
  }

  test('the linked email finds its pending member, and claims it', async () => {
    const cid = await moved();
    const c = await linked();
    assert.deepEqual((await pendingClaims(cd, c)).claims.map((x) => [x.churchId, x.pendingId]), [[cid, 'old-mei']]);
    await claimPending(cd, c, { churchId: cid, pendingId: 'old-mei' });
    const m = await db.doc(`churches/${cid}/members/yahoo-mei`).get();
    assert.equal(m.get('role'), 'leader');
    assert.equal(m.get('email'), 'mei.old@yahoo.com', 'the account’s own email stays');
    assert.deepEqual(await uidsOn(cid, '2026-10-11'), [{ 李美玉: 'yahoo-mei' }]);
  });

  test('so does an Apple one', async () => {
    const cid = await moved();
    const c = await linked('apple.com');
    assert.equal((await pendingClaims(cd, c)).claims.length, 1);
    await claimPending(cd, c, { churchId: cid, pendingId: 'old-mei' });
  });

  test('a linked email under nobody’s pending member finds nothing', async () => {
    const cid = await moved();
    const c = await linked('google.com', 'someone@gmail.com');
    assert.deepEqual((await pendingClaims(cd, c)).claims, []);
    await rejectsWith(claimPending(cd, c, { churchId: cid, pendingId: 'old-mei' }), 'permissionDenied');
  });
});

describe('dropping pending data', () => {
  test('when an admin deletes a pending member, its index entry goes too', async () => {
    const cid = await moved();
    const ref = db.doc(`churches/${cid}/pendingMembers/old-hao`);
    const snap = await ref.get();
    await ref.delete();
    assert.equal(await onPendingMemberDeleted(deps, cid, snap), true);
    assert.deepEqual(await indexed('hao@example.com'), []);
    assert.equal(await onPendingMemberDeleted(deps, cid, snap), false, 'nothing left to do');
  });
});

describe('merging', () => {
  test('an admin merges a pending member into someone who joined with another email', async () => {
    const cid = await moved();
    await db.doc(`churches/${cid}/members/hao-google`).set({ uid: 'hao-google', name: '志豪', email: 'hao@gmail.com', role: 'staff', groups: [], zones: [], zoneTypes: [] });
    assert.deepEqual(await mergePending(deps, caller('mover'), { churchId: cid, pendingId: 'old-hao', uid: 'hao-google' }), {});
    const m = await db.doc(`churches/${cid}/members/hao-google`).get();
    assert.deepEqual(m.get('zones'), [{ serviceType: 'sunday', duties: ['招待'], smallGroups: [] }]);
    assert.deepEqual(m.get('zoneTypes'), ['sunday']);
    assert.deepEqual(await uidsOn(cid, '2026-10-04'), [{ 李美玉: 'old-mei' }, { 陳志豪: 'hao-google' }]);
    assert.equal((await db.doc(`churches/${cid}/pendingMembers/old-hao`).get()).exists, false);
    assert.deepEqual(await indexed('hao@example.com'), []);
  });

  test('claim and admin merge union small groups and opt-outs without overwriting current preferences with stale pending defaults', async () => {
    for (const mode of ['claim', 'merge']) for (const muted of [['reminder'], []]) {
      await clearFirestore();
      const cid = await moved();
      await db.doc(`churches/${cid}/pendingMembers/old-mei`).update({
        zones: [{ serviceType: 'sunday', duties: ['司琴'], smallGroups: ['共同', '遷入'] }],
        notificationPrefs: { muted },
      });
      const memberRef = db.doc(`churches/${cid}/members/new-mei`);
      await memberRef.set({
        uid: 'new-mei', name: '美玉', role: 'staff', groups: ['calendar-editors'],
        zones: [
          { serviceType: 'sunday', duties: ['招待'], smallGroups: ['現有', '共同'] },
          { serviceType: 'youth', duties: [], smallGroups: ['青年'] },
        ], zoneTypes: ['sunday', 'youth'],
        notificationPrefs: { muted: ['memberLeft'], otherPreference: 'preserved' },
      });
      if (mode === 'claim') await claimPending(cd, mei(), { churchId: cid, pendingId: 'old-mei' });
      else await mergePending(deps, caller('mover'), { churchId: cid, pendingId: 'old-mei', uid: 'new-mei' });
      const member = await memberRef.get();
      assert.deepEqual(member.get('zones'), [
        { serviceType: 'sunday', duties: ['招待', '司琴'], smallGroups: ['現有', '共同', '遷入'] },
        { serviceType: 'youth', duties: [], smallGroups: ['青年'] },
      ], mode);
      assert.deepEqual(member.get('notificationPrefs'), { muted: ['memberLeft', ...muted], otherPreference: 'preserved' }, mode);
      // Their calendar-editors was 行政, now held as a 身分 with both groups.
      assert.deepEqual(member.get('identities'), [{ kind: 'office' }, { kind: 'lead', service: 'sunday' }], mode);
      assert.deepEqual(member.get('groups'), ['roster-editors', 'calendar-editors'], mode);
      assert.deepEqual(member.get('leadTypes'), ['sunday'], 'the old roster editor leads their 牧區 (#82)');
      assert.equal(member.get('role'), 'staff');
      assert.equal((await db.doc(`churches/${cid}/pendingMembers/old-mei`).get()).exists, false);
      assert.deepEqual(await uidsOn(cid, '2026-10-11'), [{ 李美玉: 'new-mei' }]);
    }
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
