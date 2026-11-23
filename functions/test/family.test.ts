import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

import { claimPending, renamePending } from '../src/claim.js';
import { addFamily, answerFamily, familyCandidates, removeFamily } from '../src/family.js';
import { sendReminders } from '../src/notifications.js';
import { onPendingMemberDeleted } from '../src/pendingMembers.js';
import { notifyPlanned, onRosterWritten, sendHeldPushes } from '../src/rosterChange.js';
import { onMemberDeleted } from '../src/triggers.js';
import { memoryGoogle } from '../src/memoryGoogle.js';
import { auth, caller, clearFirestore, db, deps, fakePush, rejectsWith, seedChurch, setNow } from './support.js';

const appUrl = 'https://app.example';

beforeEach(async () => {
  await clearFirestore();
  setNow(new Date('2026-11-20T10:00:00+08:00')); // Friday
});

/**
 * 恩典堂: 陳志玲 (mom) and 林豪佳 (dad) have accounts, as has 美玉 (mei);
 * 林小恩 (kid1) and 林小安 (kid2) do not.
 */
async function church() {
  await seedChurch('C1', { pastor: 'admin', mom: 'staff', dad: 'staff', mei: 'staff' }, { name: '恩典堂' });
  await db.doc('churches/C1/members/mom').update({ name: '陳志玲' });
  await db.doc('churches/C1/members/dad').update({ name: '林豪佳' });
  await db.doc('churches/C1/members/mei').update({ name: '美玉' });
  await db.doc('churches/C1/pendingMembers/kid1').set({ name: '林小恩', email: null, emailHash: null, zones: [] });
  await db.doc('churches/C1/pendingMembers/kid2').set({ name: '林小安', email: null, emailHash: null, zones: [] });
  await db.doc('churches/C1/settings/services').set({ services: [{ id: 'sunday', name: '主日崇拜' }], ids: ['sunday'] });
  for (const uid of ['mom', 'dad', 'mei']) await db.doc(`users/${uid}`).set({ fcm: { phone: `tok-${uid}` } });
}

const pushDeps = (messaging: ReturnType<typeof fakePush>['messaging']) => ({ ...deps, messaging, appUrl });

/** The households of C1, each as its people and those asked, sorted. */
async function households() {
  const q = await db.collection('churches/C1/households').get();
  return q.docs
    .map((d) => ({
      people: [...(d.get('people') as string[])].sort(),
      invited: [...((d.get('invited') as string[] | undefined) ?? [])].sort(),
    }))
    .sort((a, b) => a.people[0].localeCompare(b.people[0]));
}

const add = (who: string, id: string, messaging = fakePush().messaging) =>
  addFamily(pushDeps(messaging), caller(who), { churchId: 'C1', id });

async function householdOf(uid: string) {
  const q = await db.collection('churches/C1/households').where('people', 'array-contains', uid).get();
  return q.docs[0];
}

describe('加入家人', () => {
  test('someone without an account is family at once, named, marked as without one', async () => {
    await church();
    await add('mom', 'kid1');
    assert.deepEqual(await households(), [{ people: ['kid1', 'mom'], invited: [] }]);
    const h = await householdOf('mom');
    assert.deepEqual(h.get('noAccount'), ['kid1']);
    assert.deepEqual(h.get('names'), { mom: '陳志玲', kid1: '林小恩' });
    await add('mom', 'kid2');
    assert.deepEqual(await households(), [{ people: ['kid1', 'kid2', 'mom'], invited: [] }], 'the same family');
  });

  test('someone with an account is asked, with a push, and is family once they accept', async () => {
    await church();
    const { messaging, sent } = fakePush();
    await add('mom', 'dad', messaging);
    assert.deepEqual(await households(), [{ people: ['mom'], invited: ['dad'] }]);
    assert.deepEqual(sent.map((p) => [p.tokens, p.body]), [[['tok-dad'], '「陳志玲」想加你為家人']]);
    const h = await householdOf('mom');
    await answerFamily(deps, caller('dad'), { churchId: 'C1', householdId: h.id, yes: true });
    assert.deepEqual(await households(), [{ people: ['dad', 'mom'], invited: [] }]);
  });

  test('accepting brings the family they had: one family for both', async () => {
    await church();
    await add('dad', 'kid1');
    await add('mom', 'kid2');
    await add('mom', 'dad');
    const h = await householdOf('mom');
    await answerFamily(deps, caller('dad'), { churchId: 'C1', householdId: h.id, yes: true });
    assert.deepEqual(await households(), [{ people: ['dad', 'kid1', 'kid2', 'mom'], invited: [] }]);
    assert.deepEqual([...(await householdOf('dad')).get('noAccount')].sort(), ['kid1', 'kid2']);
  });

  test('saying no leaves nothing of a family of one', async () => {
    await church();
    await add('mom', 'dad');
    const h = await householdOf('mom');
    await answerFamily(deps, caller('dad'), { churchId: 'C1', householdId: h.id, yes: false });
    assert.deepEqual(await households(), []);
  });

  test('only the one asked answers; nobody adds themself or a stranger', async () => {
    await church();
    await add('mom', 'dad');
    const h = await householdOf('mom');
    await rejectsWith(answerFamily(deps, caller('mei'), { churchId: 'C1', householdId: h.id, yes: true }), 'notFound');
    await rejectsWith(add('mom', 'mom'), 'unknown');
    await rejectsWith(add('mom', 'nobody'), 'notFound');
  });

  test('移出 and 收回: the family is as before, and one of one is gone', async () => {
    await church();
    await add('mom', 'kid1');
    await add('mom', 'dad');
    await removeFamily(deps, caller('mom'), { churchId: 'C1', id: 'dad' });
    assert.deepEqual(await households(), [{ people: ['kid1', 'mom'], invited: [] }]);
    await removeFamily(deps, caller('mom'), { churchId: 'C1', id: 'kid1' });
    assert.deepEqual(await households(), []);
  });

  test('the church\'s people to pick from: names, and whether each has an account, without the caller', async () => {
    await church();
    const r = await familyCandidates(deps, caller('mom'), { churchId: 'C1' });
    assert.deepEqual(
      [...r.people].sort((a, b) => a.id.localeCompare(b.id)),
      [
        { id: 'dad', name: '林豪佳', account: true },
        { id: 'kid1', name: '林小恩', account: false },
        { id: 'kid2', name: '林小安', account: false },
        { id: 'mei', name: '美玉', account: true },
        { id: 'pastor', name: 'pastor', account: true },
      ],
    );
  });
});

const kidOn = (role: string, kid = 'kid1', name = '林小恩') => ({ role, people: [name], uids: { [name]: kid } });

let n = 0;
async function write(day: string, duties: unknown[], editedBy = 'pastor', messaging = fakePush().messaging) {
  const ref = db.doc(`churches/C1/rosters/${day}_sunday`);
  const before = await ref.get();
  await ref.set({ type: 'sunday', dateKey: day, duties });
  return onRosterWritten({ ...deps, messaging, appUrl }, 'C1', before, await ref.get(), editedBy, `ev${++n}`);
}

describe('家人 hear of those without an account', () => {
  test('put on and taken off: everyone with an account in the family, by name', async () => {
    await church();
    await add('mom', 'kid1');
    await add('mom', 'dad');
    await answerFamily(deps, caller('dad'), { churchId: 'C1', householdId: (await householdOf('mom')).id, yes: true });
    const { messaging, sent } = fakePush();
    await write('2026-11-29', [kidOn('兒主小幫手')], 'pastor', messaging);
    await write('2026-11-29', [], 'pastor', messaging);
    assert.deepEqual(sent.map((p) => [p.tokens[0], p.body]).sort(), [
      ['tok-dad', '「林小恩」被排進 11/29 主日崇拜：兒主小幫手'],
      ['tok-dad', '「林小恩」被移出 11/29 主日崇拜：兒主小幫手'],
      ['tok-mom', '「林小恩」被排進 11/29 主日崇拜：兒主小幫手'],
      ['tok-mom', '「林小恩」被移出 11/29 主日崇拜：兒主小幫手'],
    ]);
  });

  test('not the one who put them on, nor anyone of another family', async () => {
    await church();
    await add('mom', 'kid1');
    await add('mei', 'kid2');
    const { messaging, sent } = fakePush();
    await write('2026-11-29', [kidOn('兒主小幫手')], 'mom', messaging);
    assert.deepEqual(sent, []);
  });

  test('at night, at 7:00', async () => {
    await church();
    await add('mom', 'kid1');
    setNow(new Date('2026-11-20T23:00:00+08:00'));
    const { messaging, sent } = fakePush();
    await write('2026-11-29', [kidOn('兒主小幫手')], 'pastor', messaging);
    assert.deepEqual(sent, []);
    setNow(new Date('2026-11-21T07:00:00+08:00'));
    await sendHeldPushes({ ...deps, messaging, appUrl });
    assert.deepEqual(sent.map((p) => [p.tokens[0], p.body]), [['tok-mom', '「林小恩」被排進 11/29 主日崇拜：兒主小幫手']]);
  });

  test('安排服事: when 通知同工 is pressed', async () => {
    await church();
    await db.doc('churches/C1/members/pastor').update({ leadTypes: ['sunday'] });
    await add('mom', 'kid1');
    const { messaging, sent } = fakePush();
    const ref = db.doc('churches/C1/rosters/2026-11-29_sunday');
    const before = await ref.get();
    await ref.set({ type: 'sunday', dateKey: '2026-11-29', duties: [kidOn('獻詩')], via: 'plan' });
    await onRosterWritten({ ...deps, messaging, appUrl }, 'C1', before, await ref.get(), 'pastor', 'plan1');
    assert.deepEqual(sent, []);
    await notifyPlanned({ ...deps, messaging, appUrl }, caller('pastor'), { churchId: 'C1', serviceId: 'sunday' });
    assert.deepEqual(sent.map((p) => [p.tokens[0], p.body]), [['tok-mom', '「林小恩」的主日崇拜服事排好了\n排進 11/29 獻詩']]);
  });

  test('安排服事: not the parent who pressed 通知同工, even after quiet hours', async () => {
    await church();
    await db.doc('churches/C1/members/mom').update({ leadTypes: ['sunday'] });
    await add('mom', 'kid1');
    await add('mom', 'dad');
    await answerFamily(deps, caller('dad'), { churchId: 'C1', householdId: (await householdOf('mom')).id, yes: true });
    const { messaging, sent } = fakePush();
    const ref = db.doc('churches/C1/rosters/2026-11-29_sunday');
    const before = await ref.get();
    await ref.set({ type: 'sunday', dateKey: '2026-11-29', duties: [kidOn('獻詩')], via: 'plan' });
    await onRosterWritten({ ...deps, messaging, appUrl }, 'C1', before, await ref.get(), 'mom', 'plan2');
    setNow(new Date('2026-11-20T23:00:00+08:00'));
    await notifyPlanned({ ...deps, messaging, appUrl }, caller('mom'), { churchId: 'C1', serviceId: 'sunday' });
    setNow(new Date('2026-11-21T07:00:00+08:00'));
    const { sendPlannedPushes } = await import('../src/rosterChange.js');
    await sendPlannedPushes({ ...deps, messaging, appUrl });
    assert.deepEqual(sent.map((p) => p.tokens[0]), ['tok-dad']);
  });

  test('the week\'s reminder lists theirs under their name, after one\'s own', async () => {
    await church();
    await add('mom', 'kid1');
    await db.doc('churches/C1/rosters/2026-11-29_sunday').set({
      type: 'sunday',
      dateKey: '2026-11-29',
      duties: [kidOn('兒主小幫手'), { role: '司會', people: ['陳志玲'], uids: { 陳志玲: 'mom' } }],
    });
    await db.doc('churches/C1/rosters/2026-11-24_sunday').set({ type: 'sunday', dateKey: '2026-11-24', duties: [kidOn('獻詩')] });
    const { messaging, sent } = fakePush();
    await sendReminders({ db, messaging, appUrl, now: () => new Date('2026-11-23T19:00:00+08:00') }); // Monday
    assert.deepEqual(sent.map((p) => [p.tokens[0], p.title, p.body]), [
      ['tok-mom', '平安 陳志玲，這週的服事', '林小恩：11/24（週二）主日崇拜 獻詩\n11/29（週日）主日崇拜 司會\n林小恩：11/29（週日）主日崇拜 兒主小幫手'],
    ]);
  });
});

describe('a family as people come and go', () => {
  test('one without an account who signs in is still family, with an account', async () => {
    await church();
    await add('mom', 'kid1');
    await db.doc('churches/C1/pendingMembers/kid1').update({ email: 'en@example.com', emailHash: (await import('../src/pendingMembers.js')).emailKey('en@example.com') });
    const user = await auth.createUser({ email: 'en@example.com', emailVerified: true }).catch(() => auth.getUserByEmail('en@example.com'));
    await claimPending({ ...deps, auth }, caller(user.uid, { email: 'en@example.com', emailVerified: true }), { churchId: 'C1', pendingId: 'kid1' });
    const h = await householdOf('mom');
    assert.deepEqual([...h.get('people')].sort(), [user.uid, 'mom'].sort());
    assert.deepEqual(h.get('noAccount'), []);
    await auth.deleteUser(user.uid);
  });

  test('deleted, or left: out of the family', async () => {
    await church();
    await add('mom', 'kid1');
    await add('mom', 'kid2');
    const kid = await db.doc('churches/C1/pendingMembers/kid1').get();
    await kid.ref.delete();
    await onPendingMemberDeleted(deps, 'C1', kid);
    assert.deepEqual(await households(), [{ people: ['kid2', 'mom'], invited: [] }]);
    const mom = await db.doc('churches/C1/members/mom').get();
    await mom.ref.delete();
    const { messaging } = fakePush();
    const cal = { ...deps, secretKey: '', google: memoryGoogle().google, config: { clientId: '', clientSecret: '', redirectUri: '', appUrl, tokenKey: '' } };
    await onMemberDeleted({ ...cal, messaging, appUrl }, 'C1', mom, 'mom');
    assert.deepEqual(await households(), [], 'nobody with an account to tell');
  });

  test('who asked leaves: the ask goes with them', async () => {
    await church();
    await add('mom', 'kid1');
    await add('mei', 'kid1');
    await add('mom', 'dad');
    await add('mom', 'mei');
    await answerFamily(deps, caller('mei'), { churchId: 'C1', householdId: (await householdOf('mom')).id, yes: true });
    await removeFamily(deps, caller('mom'), { churchId: 'C1', id: 'mom' });
    assert.deepEqual(await households(), [{ people: ['kid1', 'mei'], invited: [] }], 'nobody asks dad any more');
  });

  test('a new name reaches the family', async () => {
    await church();
    await add('mom', 'kid1');
    await renamePending(deps, caller('pastor'), { churchId: 'C1', pendingId: 'kid1', name: '林恩恩' });
    assert.equal((await householdOf('mom')).get('names.kid1'), '林恩恩');
  });
});
