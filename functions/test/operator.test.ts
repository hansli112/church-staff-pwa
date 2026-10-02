import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

import { logClientError, scrub } from '../src/logging.js';
import {
  adminChurchMembers,
  adminRenameChurch,
  adminSearchChurches,
  adminSetStatus,
  adminStats,
  adminTransferAdmin,
} from '../src/operator.js';
import { estimateCostUsd, writeDailyStats } from '../src/stats.js';
import { caller, clearFirestore, db, deps, rejectsWith, seedChurch, setNow } from './support.js';

const op = caller('hans', { operator: true });

beforeEach(async () => {
  await clearFirestore();
  setNow(new Date('2026-10-02T09:00:00+08:00'));
});

describe('operator back office', () => {
  test('everything is refused without the operator claim', async () => {
    await seedChurch('C1', { alice: 'admin' });
    const admin = caller('alice'); // admin of a church, not the platform
    await rejectsWith(adminSearchChurches(deps, admin, { query: '' }), 'permissionDenied');
    await rejectsWith(adminRenameChurch(deps, admin, { churchId: 'C1', name: 'x' }), 'permissionDenied');
    await rejectsWith(adminTransferAdmin(deps, admin, { churchId: 'C1', uid: 'alice' }), 'permissionDenied');
    await rejectsWith(adminSetStatus(deps, admin, { churchId: 'C1', status: 'suspended' }), 'permissionDenied');
    await rejectsWith(adminStats(deps, admin, {}), 'permissionDenied');
    await rejectsWith(adminStats(deps, null, {}), 'permissionDenied');
    await rejectsWith(adminChurchMembers(deps, admin, { churchId: 'C1' }), 'permissionDenied');
  });

  test('search finds part of a name, any width or case, with admins and count', async () => {
    await seedChurch('C1', { alice: 'admin', bob: 'staff' }, { name: 'Grace Church 恩典' });
    await seedChurch('C2', { carol: 'admin' }, { name: '靈糧堂' });
    const { churches } = await adminSearchChurches(deps, op, { query: 'ＧＲＡＣＥ' });
    assert.equal(churches.length, 1);
    assert.equal(churches[0].id, 'C1');
    assert.equal(churches[0].memberCount, 2);
    assert.deepEqual(churches[0].admins.map((a) => a.uid), ['alice']);
  });

  test('rename still goes through the duplicate-name check', async () => {
    await seedChurch('C1', { alice: 'admin' }, { name: '甲', nameKey: '甲' });
    await db.doc('churchNames/甲').set({ cid: 'C1' });
    await seedChurch('C2', { bob: 'admin' }, { name: '乙', nameKey: '乙' });
    await db.doc('churchNames/乙').set({ cid: 'C2' });

    await rejectsWith(adminRenameChurch(deps, op, { churchId: 'C2', name: ' 甲 ' }), 'duplicateName');
    await adminRenameChurch(deps, op, { churchId: 'C2', name: '丙' });
    const c2 = await db.doc('churches/C2').get();
    assert.equal(c2.get('name'), '丙');
    assert.equal((await db.doc('churchNames/乙').get()).exists, false, 'old name released');
    assert.equal((await db.doc('churchNames/丙').get()).get('cid'), 'C2');
  });

  test('transfer makes a member admin; suspend and reopen', async () => {
    await seedChurch('C1', { alice: 'admin', bob: 'staff' });
    const { members } = await adminChurchMembers(deps, op, { churchId: 'C1' });
    assert.deepEqual(members.map((m) => m.uid), ['alice', 'bob']);
    await adminTransferAdmin(deps, op, { churchId: 'C1', uid: 'bob' });
    assert.equal((await db.doc('churches/C1/members/bob').get()).get('role'), 'admin');
    await rejectsWith(adminTransferAdmin(deps, op, { churchId: 'C1', uid: 'nobody' }), 'unknown');

    await adminSetStatus(deps, op, { churchId: 'C1', status: 'suspended' });
    assert.equal((await db.doc('churches/C1').get()).get('status'), 'suspended');
    await adminSetStatus(deps, op, { churchId: 'C1', status: 'active' });
    assert.equal((await db.doc('churches/C1').get()).get('status'), 'active');
    await rejectsWith(adminSetStatus(deps, op, { churchId: 'C1', status: 'deleted' }), 'unknown');
  });
});

describe('daily stats', () => {
  const usage = async () => ({
    firestoreReads: 150_000,
    firestoreWrites: 1_000,
    firestoreDeletes: 0,
    storageBytes: 1_500_000,
    functionCalls: 42,
  });

  test('writes yesterday (UTC+8) with counts and usage', async () => {
    await seedChurch('C1', { alice: 'admin', bob: 'staff' });
    await seedChurch('C2', { carol: 'admin' }, { status: 'suspended' });
    await db.doc('users/alice').set({ name: 'a' });
    await db.doc('churches/C1/rosters/r1').set({ type: 'sunday', dateKey: '2026-10-04' });

    const s = await writeDailyStats(deps, usage);

    assert.equal(s.date, '2026-10-01');
    const doc = await db.doc('stats/2026-10-01').get();
    assert.equal(doc.get('users'), 1);
    assert.equal(doc.get('churches_active'), 1);
    assert.equal(doc.get('churches_suspended'), 1);
    assert.equal(doc.get('members'), 3);
    assert.equal(doc.get('rosters'), 1);
    assert.equal(doc.get('firestore_reads'), 150_000);
    assert.ok(doc.get('cost_usd') > 0);
  });

  test('running twice for the same day replaces, never doubles', async () => {
    await seedChurch('C1', { alice: 'admin' });
    await writeDailyStats(deps, usage);
    await writeDailyStats(deps, usage);
    const all = await db.collection('stats').get();
    assert.equal(all.size, 1);
    assert.equal(all.docs[0].get('members'), 1);
  });

  test('a monitoring failure still records the counts', async () => {
    await writeDailyStats(deps, async () => {
      throw new Error('monitoring down');
    });
    const doc = await db.doc('stats/2026-10-01').get();
    assert.equal(doc.get('churches_active'), 0);
    assert.equal(doc.get('firestore_reads'), undefined);
  });

  test('adminStats returns newest first, at most the asked number', async () => {
    for (const d of ['2026-09-29', '2026-09-30', '2026-10-01']) {
      await db.doc(`stats/${d}`).set({ date: d, users: 1 });
    }
    const { days } = await adminStats(deps, op, { days: 2 });
    assert.deepEqual(days.map((d) => d.date), ['2026-10-01', '2026-09-30']);
  });

  test('cost is zero inside the free tier', () => {
    assert.equal(
      estimateCostUsd({ firestoreReads: 1000, firestoreWrites: 10, firestoreDeletes: 0, storageBytes: 1e6, functionCalls: 1 }),
      0,
    );
  });
});

describe('client error log', () => {
  test('requires sign-in and limits size', () => {
    assert.throws(() => logClientError(null, { message: 'x', stack: '' }), /permissionDenied/);
    assert.throws(() => logClientError(caller('a'), { message: 'x'.repeat(1001), stack: '' }), /unknown/);
    assert.throws(() => logClientError(caller('a'), { message: 'x', stack: 'y'.repeat(8001) }), /unknown/);
    assert.deepEqual(logClientError(caller('a'), { message: 'boom', stack: 'at main.dart' }), {});
  });

  test('scrubs emails and phone numbers', () => {
    assert.equal(scrub('user john@example.com failed'), 'user <email> failed');
    assert.equal(scrub('call 0912 345 678'), 'call <number>');
  });
});
