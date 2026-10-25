import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

import { Timestamp } from 'firebase-admin/firestore';

import { deleteAccount } from '../src/account.js';
import { churchPreview } from '../src/church.js';
import {
  answerJoinRequest,
  forgetOldJoinRequests,
  requestToJoin,
  withdrawJoinRequest,
} from '../src/joinRequests.js';
import { auth, caller, clearFirestore, db, deps, fakePush, rejectsWith, seedChurch, setNow } from './support.js';

const appUrl = 'https://app.example';
const DAY = 24 * 60 * 60 * 1000;

beforeEach(async () => {
  await clearFirestore();
  setNow(new Date('2026-10-01T10:00:00+08:00'));
});

/** Church C1 with admin alice and member bob, both with a device; carol is new. */
async function seed(extra: Record<string, unknown> = {}) {
  await seedChurch('C1', { alice: 'admin', bob: 'staff' }, extra);
  await db.doc('users/alice').set({ name: 'alice', fcm: { phone: 'tok-alice' } });
  await db.doc('users/bob').set({ name: 'bob', fcm: { phone: 'tok-bob' } });
  await db.doc('users/carol').set({ name: '新朋友', fcm: { phone: 'tok-carol' } });
}

const pushDeps = () => {
  const push = fakePush();
  return { ...push, deps: { ...deps, messaging: push.messaging, appUrl } };
};

describe('requestToJoin', () => {
  test('asks with a note and tells the admins, not the others', async () => {
    await seed();
    const { deps: d, sent } = pushDeps();
    await requestToJoin(d, caller('carol'), { churchId: 'C1', note: '  我是敬拜團的小明 ' });

    const request = await db.doc('churches/C1/joinRequests/carol').get();
    assert.equal(request.get('name'), '新朋友');
    assert.equal(request.get('email'), 'carol@example.com');
    assert.equal(request.get('note'), '我是敬拜團的小明');
    assert.equal(request.get('uid'), 'carol');
    assert.deepEqual(sent.map((s) => s.tokens), [['tok-alice']]);
    assert.equal(sent[0].body, '「新朋友」申請加入教會');
    assert.equal(sent[0].link, '/c/C1?to=%2Fme%2Fmembers');

    const preview = await churchPreview(deps, caller('carol'), { churchId: 'C1' });
    assert.equal(preview.takesRequests, true);
    assert.equal(preview.request, 'pending');
  });

  test('asking again while waiting changes nothing and tells nobody', async () => {
    await seed();
    const { deps: d, sent } = pushDeps();
    await requestToJoin(d, caller('carol'), { churchId: 'C1' });
    setNow(new Date('2026-10-02T10:00:00+08:00'));
    await requestToJoin(d, caller('carol'), { churchId: 'C1', note: 'again' });
    const request = await db.doc('churches/C1/joinRequests/carol').get();
    assert.equal(request.get('note'), undefined);
    assert.equal(sent.length, 1);
  });

  test('an unverified email, a long note, a closed church or one taking none are refused', async () => {
    await seed();
    const { deps: d } = pushDeps();
    await rejectsWith(requestToJoin(d, caller('carol', { emailVerified: false }), { churchId: 'C1' }), 'unverifiedEmail');
    await rejectsWith(requestToJoin(d, caller('carol'), { churchId: 'C1', note: '字'.repeat(101) }), 'unknown');
    await requestToJoin(d, caller('carol'), { churchId: 'C1', note: '字'.repeat(100) });
    await db.doc('churches/C1/joinRequests/carol').delete();

    await db.doc('churches/C1').update({ joinRequestsClosed: true });
    const closed = await rejectsWith(requestToJoin(d, caller('carol'), { churchId: 'C1' }), 'unknown');
    assert.equal((closed as { details: { detail: string } }).details.detail, 'requestsClosed');
    assert.equal((await churchPreview(deps, caller('carol'), { churchId: 'C1' })).takesRequests, false);

    await db.doc('churches/C1').update({ status: 'suspended' });
    await rejectsWith(requestToJoin(d, caller('carol'), { churchId: 'C1' }), 'notFound');
    assert.equal((await db.doc('churches/C1/joinRequests/carol').get()).exists, false);
  });

  test('a member has nothing to ask', async () => {
    await seed();
    const { deps: d, sent } = pushDeps();
    await requestToJoin(d, caller('bob'), { churchId: 'C1' });
    assert.equal((await db.doc('churches/C1/joinRequests/bob').get()).exists, false);
    assert.equal(sent.length, 0);
  });

  test('asking, taking it back and asking again tells the admins once a day', async () => {
    await seed();
    const { deps: d, sent } = pushDeps();
    for (let i = 0; i < 3; i++) {
      await requestToJoin(d, caller('carol'), { churchId: 'C1' });
      await withdrawJoinRequest(deps, caller('carol'), { churchId: 'C1' });
    }
    await requestToJoin(d, caller('dave'), { churchId: 'C1' });
    assert.equal(sent.length, 2, 'carol once, and dave');

    setNow(new Date(Date.parse('2026-10-01T10:00:00+08:00') + DAY));
    await requestToJoin(d, caller('carol'), { churchId: 'C1' });
    assert.equal(sent.length, 3, 'a day on, again');
  });

  test('each admin is told in their own language; with no name, someone asked', async () => {
    await seed();
    await db.doc('users/alice').update({ appLocale: 'en' });
    const { deps: d, sent } = pushDeps();
    await requestToJoin(d, caller('dave', { name: undefined }), { churchId: 'C1' });
    assert.equal(sent[0].body, 'Someone asked to join the church');
    assert.equal((await db.doc('churches/C1/joinRequests/dave').get()).get('name'), '');
  });

  test('without a profile, the name they signed in with', async () => {
    await seed();
    const { deps: d } = pushDeps();
    await requestToJoin(d, caller('dave', { name: '大衛' }), { churchId: 'C1' });
    assert.equal((await db.doc('churches/C1/joinRequests/dave').get()).get('name'), '大衛');
  });

  test('a request is to one church: another church knows nothing of it', async () => {
    await seed();
    await seedChurch('C2', { erin: 'admin' });
    const { deps: d } = pushDeps();
    await requestToJoin(d, caller('carol'), { churchId: 'C1' });
    assert.equal((await churchPreview(deps, caller('carol'), { churchId: 'C2' })).request, null);
    await rejectsWith(answerJoinRequest(d, caller('erin'), { churchId: 'C2', uid: 'carol', allow: true }), 'unknown');
    await rejectsWith(answerJoinRequest(d, caller('erin'), { churchId: 'C1', uid: 'carol', allow: true }), 'permissionDenied');
    assert.equal((await db.doc('churches/C2/members/carol').get()).exists, false);
    assert.equal((await db.doc('churches/C1/members/carol').get()).exists, false);
  });

  test('signed out, the preview says whether one may ask, and of no request', async () => {
    await seed();
    const { deps: d } = pushDeps();
    await requestToJoin(d, caller('carol'), { churchId: 'C1' });
    const preview = await churchPreview(deps, null, { churchId: 'C1' });
    assert.deepEqual([preview.takesRequests, preview.request], [true, null]);
  });

  test('a bad church ID, note or uid is refused', async () => {
    await seed();
    const { deps: d } = pushDeps();
    await rejectsWith(requestToJoin(d, caller('carol'), { churchId: '../C1' }), 'unknown');
    await rejectsWith(requestToJoin(d, caller('carol'), { churchId: 'C1', note: 3 }), 'unknown');
    await rejectsWith(requestToJoin(d, null, { churchId: 'C1' }), 'permissionDenied');
    await rejectsWith(withdrawJoinRequest(deps, null, { churchId: 'C1' }), 'permissionDenied');
    for (const uid of [undefined, '', 'a/b', 'x'.repeat(129)]) {
      await rejectsWith(answerJoinRequest(d, caller('alice'), { churchId: 'C1', uid, allow: true }), 'unknown');
    }
  });

  test('taken back, there is none', async () => {
    await seed();
    const { deps: d } = pushDeps();
    await requestToJoin(d, caller('carol'), { churchId: 'C1' });
    await withdrawJoinRequest(deps, caller('carol'), { churchId: 'C1' });
    assert.equal((await db.doc('churches/C1/joinRequests/carol').get()).exists, false);
    assert.equal((await churchPreview(deps, caller('carol'), { churchId: 'C1' })).request, null);
  });
});

describe('answerJoinRequest', () => {
  test('let in, they join as an invite would and are told', async () => {
    await seed();
    const { deps: d, sent } = pushDeps();
    await requestToJoin(d, caller('carol'), { churchId: 'C1' });
    await answerJoinRequest(d, caller('alice'), { churchId: 'C1', uid: 'carol', allow: true });

    const member = await db.doc('churches/C1/members/carol').get();
    assert.equal(member.get('role'), 'staff');
    assert.equal(member.get('name'), '新朋友');
    assert.deepEqual(member.get('zoneTypes'), []);
    assert.equal((await db.doc('churches/C1/joinRequests/carol').get()).exists, false);
    assert.deepEqual(sent.at(-1)?.tokens, ['tok-carol']);
    assert.equal(sent.at(-1)?.body, '管理員允許你加入了，歡迎！');
  });

  test('turned down, they see so and may ask again', async () => {
    await seed();
    const { deps: d, sent } = pushDeps();
    await requestToJoin(d, caller('carol'), { churchId: 'C1' });
    await answerJoinRequest(d, caller('alice'), { churchId: 'C1', uid: 'carol', allow: false });
    assert.equal((await db.doc('churches/C1/members/carol').get()).exists, false);
    assert.equal(sent.length, 1, 'only the admin, when asked');
    assert.equal((await churchPreview(deps, caller('carol'), { churchId: 'C1' })).request, 'rejected');
    await rejectsWith(answerJoinRequest(d, caller('alice'), { churchId: 'C1', uid: 'carol', allow: true }), 'unknown');

    await requestToJoin(d, caller('carol'), { churchId: 'C1' });
    assert.equal((await churchPreview(deps, caller('carol'), { churchId: 'C1' })).request, 'pending');
    assert.equal(sent.length, 1, 'told of carol today already');
  });

  test('someone who joined meanwhile: letting them in only clears the request', async () => {
    await seed();
    const { deps: d, sent } = pushDeps();
    await requestToJoin(d, caller('carol'), { churchId: 'C1' });
    await db.doc('churches/C1/members/carol').set({ uid: 'carol', name: '小明', role: 'staff', zoneTypes: ['sunday'] });
    await answerJoinRequest(d, caller('alice'), { churchId: 'C1', uid: 'carol', allow: true });
    assert.deepEqual((await db.doc('churches/C1/members/carol').get()).get('zoneTypes'), ['sunday'], 'kept as they joined');
    assert.equal((await db.doc('churches/C1/joinRequests/carol').get()).exists, false);
    assert.equal(sent.length, 1, 'only the admin, when asked');
  });

  test('turning down someone who never asked changes nothing', async () => {
    await seed();
    const { deps: d } = pushDeps();
    await answerJoinRequest(d, caller('alice'), { churchId: 'C1', uid: 'nobody', allow: false });
    assert.equal((await db.doc('churches/C1/joinRequests/nobody').get()).exists, false);
  });

  test('only an admin answers', async () => {
    await seed();
    const { deps: d } = pushDeps();
    await requestToJoin(d, caller('carol'), { churchId: 'C1' });
    await rejectsWith(answerJoinRequest(d, caller('bob'), { churchId: 'C1', uid: 'carol', allow: true }), 'permissionDenied');
    await rejectsWith(answerJoinRequest(d, caller('carol'), { churchId: 'C1', uid: 'carol', allow: true }), 'permissionDenied');
    assert.equal((await db.doc('churches/C1/members/carol').get()).exists, false);
  });

  test('a church that stopped taking requests lets none in', async () => {
    await seed();
    const { deps: d } = pushDeps();
    await requestToJoin(d, caller('carol'), { churchId: 'C1' });
    await db.doc('churches/C1').update({ joinRequestsClosed: true });
    await rejectsWith(answerJoinRequest(d, caller('alice'), { churchId: 'C1', uid: 'carol', allow: true }), 'unknown');
    assert.equal((await db.doc('churches/C1/members/carol').get()).exists, false);
  });

  test('a request 30 days old is gone: not let in, and the daily purge deletes it', async () => {
    await seed();
    const { deps: d } = pushDeps();
    await requestToJoin(d, caller('carol'), { churchId: 'C1' });
    setNow(new Date(Date.parse('2026-10-01T10:00:00+08:00') + 30 * DAY));
    assert.equal((await churchPreview(deps, caller('carol'), { churchId: 'C1' })).request, null);
    await rejectsWith(answerJoinRequest(d, caller('alice'), { churchId: 'C1', uid: 'carol', allow: true }), 'unknown');

    await db.doc('churches/C1/joinRequests/dave').set({ uid: 'dave', name: 'd', createdAt: Timestamp.fromDate(deps.now()) });
    await db.doc('churches/C1/joinRequestPushes/dave').set({ uid: 'dave', at: Timestamp.fromDate(deps.now()) });
    assert.equal(await forgetOldJoinRequests(deps), 1);
    assert.equal((await db.doc('churches/C1/joinRequests/carol').get()).exists, false);
    assert.equal((await db.doc('churches/C1/joinRequestPushes/carol').get()).exists, false, 'told over a day ago');
    assert.equal((await db.doc('churches/C1/joinRequests/dave').get()).exists, true);
    assert.equal((await db.doc('churches/C1/joinRequestPushes/dave').get()).exists, true);
  });
});

test('deleting the account takes its requests with it', async () => {
  await seed();
  await seedChurch('C2', { erin: 'admin' });
  const { deps: d } = pushDeps();
  await auth.createUser({ uid: 'carol' }).catch(() => undefined);
  await requestToJoin(d, caller('carol'), { churchId: 'C1' });
  await requestToJoin(d, caller('carol'), { churchId: 'C2' });
  await deleteAccount({ ...deps, auth }, caller('carol'));
  assert.equal((await db.collectionGroup('joinRequests').where('uid', '==', 'carol').get()).size, 0);
  assert.equal((await db.collectionGroup('joinRequestPushes').where('uid', '==', 'carol').get()).size, 0);
});
