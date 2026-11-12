import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { beforeEach, describe, test } from 'node:test';

import { Timestamp } from 'firebase-admin/firestore';

import { answerSwap, askCover, askSwap, coverAsked, sendSwapPushes, stillHolds, undoSwap, voidStaleSwaps, withdrawSwap } from '../src/swaps.js';
import { caller, clearFirestore, db, deps, fakePush, rejectsWith, seedChurch, setNow, type SentPush } from './support.js';

/** The rows app/test/domain/swaps_test.dart runs too: both sides must agree. */
const rules = JSON.parse(readFileSync(new URL('../../testdata/swaps.json', import.meta.url), 'utf8'));

describe('coverAsked (testdata/swaps.json)', () => {
  for (const r of rules.coverAsked) {
    test(r.why, () => assert.deepEqual(coverAsked(r.members, r.service, r.dateKey, r.duties, r.duty, r.from, r.away), r.asked));
  }
});

describe('stillHolds (testdata/swaps.json)', () => {
  for (const r of rules.stillHolds) {
    test(r.why, () => assert.equal(stillHolds(r.kind, r.duty, r.from, r.to, r.duties, r.other), r.holds));
  }
});

const appUrl = 'https://app.example';
let push: ReturnType<typeof fakePush>;
let pushed: SentPush[];
const d = () => ({ ...deps, messaging: push.messaging, appUrl });

beforeEach(async () => {
  await clearFirestore();
  // Monday 2 November 2026, 10:00 in Taipei.
  setNow(new Date('2026-11-02T10:00:00+08:00'));
  push = fakePush();
  pushed = push.sent;
});

const UIDS: Record<string, string> = { 王小明: 'wang', 李美玉: 'mei', 陳志豪: 'hao', 林負責: 'lead' };
const duty = (role: string, people: string[]) => ({
  role,
  people,
  uids: Object.fromEntries(people.filter((p) => UIDS[p]).map((p) => [p, UIDS[p]])),
});

/**
 * 恩典堂's 主日崇拜: 王小明, 李美玉 and 陳志豪 play the piano; 林負責 leads it.
 * 王小明 plays on 11/15, 陳志豪 on 11/22.
 */
async function church() {
  await seedChurch('C1', { wang: 'staff', mei: 'staff', hao: 'staff', lead: 'staff', boss: 'admin' }, { name: '恩典堂' });
  await db.doc('churches/C1/settings/services').set({ services: [{ id: 'sunday', name: '主日崇拜' }], ids: ['sunday'] });
  const sunday = [{ serviceType: 'sunday', duties: ['司琴'] }];
  for (const [uid, name] of [['wang', '王小明'], ['mei', '李美玉'], ['hao', '陳志豪']]) {
    await db.doc(`churches/C1/members/${uid}`).update({ name, zones: sunday });
  }
  await db.doc('churches/C1/members/lead').update({ name: '林負責', leadTypes: ['sunday'] });
  for (const uid of ['wang', 'mei', 'hao', 'lead', 'boss']) await db.doc(`users/${uid}`).set({ fcm: { phone: `tok-${uid}` } });
  await day('2026-11-15', [duty('司琴', ['王小明'])]);
  await day('2026-11-22', [duty('司琴', ['陳志豪'])]);
}

const day = (dateKey: string, duties: ReturnType<typeof duty>[]) =>
  db.doc(`churches/C1/rosters/${dateKey}_sunday`).set({ type: 'sunday', dateKey, duties, events: [] });
const pianists = async (dateKey: string) =>
  (await db.doc(`churches/C1/rosters/${dateKey}_sunday`).get()).get('duties').find((x: { role: string }) => x.role === '司琴');
const request = async (id: string) => (await db.doc(`churches/C1/swapRequests/${id}`).get()).data()!;
const said = () => pushed.flatMap((p) => p.tokens.map((t) => [t, p.body, p.link])).sort();

const cover = (uid = 'wang') => askCover(d(), caller(uid), { churchId: 'C1', serviceId: 'sunday', dateKey: '2026-11-15', duty: '司琴' });
const swap = (uid = 'wang', extra: Record<string, unknown> = {}) =>
  askSwap(d(), caller(uid), { churchId: 'C1', serviceId: 'sunday', dateKey: '2026-11-15', duty: '司琴', with: 'hao', withDateKey: '2026-11-22', ...extra });
const answer = (id: string, uid: string, yes: boolean) => answerSwap(d(), caller(uid), { churchId: 'C1', id, yes });

describe('請人代 (askCover)', () => {
  test('asks everyone on the list free that day; the first to say 我來 takes it, and who asked and the lead hear', async () => {
    await church();
    const { id, asked } = await cover();
    assert.equal(asked, 2);
    assert.deepEqual(said(), [
      ['tok-hao', '「王小明」想請你代 11/15（週日）主日崇拜 司琴', `/c/C1?to=%2Frosters%2Frequest%2F${id}`],
      ['tok-mei', '「王小明」想請你代 11/15（週日）主日崇拜 司琴', `/c/C1?to=%2Frosters%2Frequest%2F${id}`],
    ]);
    pushed.length = 0;

    await answer(id, 'mei', true);
    assert.deepEqual(await pianists('2026-11-15'), duty('司琴', ['李美玉']));
    assert.equal((await db.doc('churches/C1/rosters/2026-11-15_sunday').get()).get('via'), 'swap');
    assert.deepEqual([(await request(id)).status, (await request(id)).taker], ['taken', 'mei']);
    assert.deepEqual(said(), [
      ['tok-lead', '11/15（週日）主日崇拜 司琴：「王小明」→「李美玉」', '/c/C1?to=%2Frosters%2Fsunday%2F2026-11-15'],
      ['tok-wang', '「李美玉」接手了你 11/15（週日）主日崇拜 司琴', '/c/C1?to=%2Frosters%2Fsunday%2F2026-11-15'],
    ]);
    await rejectsWith(answer(id, 'hao', true), 'unknown');
  });

  test('不方便 tells nobody and leaves it to the others; only those asked answer', async () => {
    await church();
    const { id } = await cover();
    pushed.length = 0;
    await answer(id, 'hao', false);
    assert.deepEqual(pushed, []);
    assert.deepEqual([(await request(id)).status, (await request(id)).passed], ['open', ['hao']]);
    await rejectsWith(answer(id, 'lead', true), 'permissionDenied');
  });

  test('only for one of your own days still to come, once at a time, and not with nobody to ask', async () => {
    await church();
    await rejectsWith(cover('mei'), 'unknown');
    await cover();
    await rejectsWith(cover(), 'unknown');
    await day('2026-11-08', [duty('司琴', ['王小明'])]);
    await db.doc('churches/C1/unavailable/mei').set({ spans: [{ from: '2026-11-08', to: '2026-11-08', note: '' }] });
    await db.doc('churches/C1/unavailable/hao').set({ spans: [{ from: '2026-11-01', to: '2026-11-30', note: '' }] });
    const nobody = askCover(d(), caller('wang'), { churchId: 'C1', serviceId: 'sunday', dateKey: '2026-11-08', duty: '司琴' });
    await assert.rejects(nobody, (e: { details?: { detail?: string } }) => e.details?.detail === 'nobodyToAsk');
    setNow(new Date('2026-11-16T10:00:00+08:00'));
    await rejectsWith(askCover(d(), caller('wang'), { churchId: 'C1', serviceId: 'sunday', dateKey: '2026-11-15', duty: '司琴' }), 'unknown');
  });

  test('asked in the night, it goes out at 7:00', async () => {
    await church();
    setNow(new Date('2026-11-02T23:30:00+08:00'));
    const { id } = await cover();
    assert.deepEqual(pushed, []);
    setNow(new Date('2026-11-03T06:00:00+08:00'));
    await sendSwapPushes(d());
    assert.deepEqual(pushed, []);
    setNow(new Date('2026-11-03T07:00:00+08:00'));
    await sendSwapPushes(d());
    assert.equal(said().length, 2);
    assert.equal((await request(id)).sendAt, null);
  });

  test('three days before, at 19:00, the lead hears nobody took it, once', async () => {
    await church();
    await cover();
    setNow(new Date('2026-11-12T18:00:00+08:00'));
    pushed.length = 0;
    await sendSwapPushes(d());
    assert.deepEqual(pushed, []);
    setNow(new Date('2026-11-12T19:00:00+08:00'));
    await sendSwapPushes(d());
    assert.deepEqual(said(), [['tok-lead', '11/15（週日）主日崇拜 司琴還沒人代', '/c/C1?to=%2Frosters%2Fsunday%2F2026-11-15']]);
    await sendSwapPushes(d());
    assert.equal(pushed.length, 1);
  });

  test('taken in the night: who asked hears at once, the lead at 7:00', async () => {
    await church();
    const { id } = await cover();
    setNow(new Date('2026-11-02T23:00:00+08:00'));
    pushed.length = 0;
    await answer(id, 'mei', true);
    assert.deepEqual(said().map(([t]) => t), ['tok-wang']);
    setNow(new Date('2026-11-03T07:00:00+08:00'));
    await sendSwapPushes(d());
    assert.deepEqual(said().map(([t]) => t), ['tok-lead', 'tok-wang']);
  });

  test('only someone still on the list and free that day takes it', async () => {
    await church();
    const { id } = await cover();
    await db.doc('churches/C1/unavailable/mei').set({ spans: [{ from: '2026-11-15', to: '2026-11-15', note: '' }] });
    await rejectsWith(answer(id, 'mei', true), 'unknown');
    await db.doc('churches/C1/members/hao').update({ zones: [] });
    await rejectsWith(answer(id, 'hao', true), 'unknown');
    assert.equal((await request(id)).status, 'open');
  });

  test('with no lead of the service, 行政 and the admins hear', async () => {
    await church();
    await db.doc('churches/C1/members/lead').update({ leadTypes: [] });
    const { id } = await cover();
    pushed.length = 0;
    await answer(id, 'hao', true);
    assert.deepEqual(said().map(([t]) => t), ['tok-boss', 'tok-wang']);
  });

  test('復原 puts it back and opens it again, and who asked hears; not once the roster moved on', async () => {
    await church();
    const { id } = await cover();
    await answer(id, 'mei', true);
    pushed.length = 0;
    await undoSwap(d(), caller('mei'), { churchId: 'C1', id });
    assert.deepEqual(await pianists('2026-11-15'), duty('司琴', ['王小明']));
    assert.equal((await request(id)).status, 'open');
    assert.ok(said().some(([t, body]) => t === 'tok-wang' && body === '「李美玉」取消了接手 11/15（週日）主日崇拜 司琴，還在找人'));
    assert.ok(said().some(([t, body]) => t === 'tok-lead' && body.includes('取消了接手')), 'the lead had heard it was taken');
    assert.deepEqual(said().filter(([, body]) => body.includes('想請你代')).map(([t]) => t), ['tok-hao'], 'asked again, but not who gave it back');

    await answer(id, 'hao', true);
    await rejectsWith(undoSwap(d(), caller('mei'), { churchId: 'C1', id }), 'permissionDenied');
    setNow(new Date('2026-11-02T10:11:00+08:00'));
    await assert.rejects(undoSwap(d(), caller('hao'), { churchId: 'C1', id }), (e: { details?: { detail?: string } }) => e.details?.detail === 'swapClosed', 'ten minutes on');
  });

  test('收回 by who asked; then nobody can answer', async () => {
    await church();
    const { id } = await cover();
    await rejectsWith(withdrawSwap(deps, caller('mei'), { churchId: 'C1', id }), 'permissionDenied');
    await withdrawSwap(deps, caller('wang'), { churchId: 'C1', id });
    assert.equal((await request(id)).status, 'withdrawn');
    await assert.rejects(answer(id, 'mei', true), (e: { details?: { detail?: string } }) => e.details?.detail === 'swapClosed');
  });

  test('the roster changed so that who asked is off it: void', async () => {
    await church();
    const { id } = await cover();
    await day('2026-11-15', [duty('司琴', ['李美玉'])]);
    assert.equal(await voidStaleSwaps(deps, 'C1', '2026-11-15_sunday'), 1);
    assert.equal((await request(id)).status, 'voided');
  });

  test('once its day has gone by, void', async () => {
    await church();
    const { id } = await cover();
    setNow(new Date('2026-11-17T10:00:00+08:00'));
    await sendSwapPushes(d());
    assert.equal((await request(id)).status, 'voided');
  });
});

describe('和別週交換 (askSwap)', () => {
  test('not with one of the 同工 without an account, who could never answer', async () => {
    await church();
    await day('2026-11-22', [{ role: '司琴', people: ['黃鎮台'], uids: { 黃鎮台: 'old-huang' } }]);
    await rejectsWith(swap('wang', { with: 'old-huang' }), 'notFound');
    assert.deepEqual(said(), []);
  });

  test('asks the one person; 接受 trades the two days, and who asked and the lead hear', async () => {
    await church();
    const { id } = await swap();
    assert.deepEqual(said(), [['tok-hao', '「王小明」想用 11/15（週日）和你交換 11/22（週日）主日崇拜 司琴', `/c/C1?to=%2Frosters%2Frequest%2F${id}`]]);
    pushed.length = 0;
    await rejectsWith(answer(id, 'mei', true), 'permissionDenied');
    await answer(id, 'hao', true);
    assert.deepEqual(await pianists('2026-11-15'), duty('司琴', ['陳志豪']));
    assert.deepEqual(await pianists('2026-11-22'), duty('司琴', ['王小明']));
    assert.deepEqual(said(), [
      ['tok-lead', '主日崇拜 司琴：「王小明」11/15（週日）和「陳志豪」11/22（週日）交換了', '/c/C1?to=%2Frosters%2Fsunday%2F2026-11-15'],
      ['tok-wang', '「陳志豪」和你交換了，你改成 11/22（週日）主日崇拜 司琴', '/c/C1?to=%2Frosters%2Fsunday%2F2026-11-22'],
    ]);
    pushed.length = 0;
    await undoSwap(d(), caller('hao'), { churchId: 'C1', id });
    assert.deepEqual(await pianists('2026-11-15'), duty('司琴', ['王小明']));
    assert.deepEqual(await pianists('2026-11-22'), duty('司琴', ['陳志豪']));
    assert.equal((await request(id)).status, 'declined', 'as if they had said 不方便');
    assert.ok(said().some(([t, body]) => t === 'tok-wang' && body === '「陳志豪」取消了交換，11/15（週日）主日崇拜 司琴還是你'));

    // Not once a roster has moved on since.
    const again = (await swap()).id;
    await answer(again, 'hao', true);
    await day('2026-11-22', [duty('司琴', ['李美玉'])]);
    await rejectsWith(undoSwap(d(), caller('hao'), { churchId: 'C1', id: again }), 'conflict');
  });

  test('不方便 tells who asked and closes it', async () => {
    await church();
    const { id } = await swap();
    pushed.length = 0;
    await answer(id, 'hao', false);
    assert.equal((await request(id)).status, 'declined');
    assert.deepEqual(said(), [['tok-wang', '「陳志豪」不方便和你交換 11/15（週日）主日崇拜 司琴', '/c/C1?to=%2Frosters%2Fsunday%2F2026-11-15']]);
  });

  test('only with someone on the duty on another day from tomorrow; void once they are not', async () => {
    await church();
    await rejectsWith(swap('wang', { with: 'mei' }), 'unknown');
    await rejectsWith(swap('wang', { withDateKey: '2026-11-15' }), 'unknown');
    await day('2026-11-02', [duty('司琴', ['陳志豪'])]);
    await rejectsWith(swap('wang', { withDateKey: '2026-11-02' }), 'unknown');
    const { id } = await swap();
    await day('2026-11-22', [duty('司琴', ['李美玉'])]);
    assert.equal(await voidStaleSwaps(deps, 'C1', '2026-11-22_sunday'), 1);
    assert.equal((await request(id)).status, 'voided');
    await assert.rejects(answer(id, 'hao', true), (e: { details?: { detail?: string } }) => e.details?.detail === 'swapClosed');
  });
});

test('a request is kept for its day', async () => {
  await church();
  const { id } = await cover();
  const r = await request(id);
  assert.deepEqual([r.kind, r.rosterId, r.dateKey, r.duty, r.from, r.fromName, r.asked], ['cover', '2026-11-15_sunday', '2026-11-15', '司琴', 'wang', '王小明', ['hao', 'mei']]);
  assert.ok(r.createdAt instanceof Timestamp);
});
