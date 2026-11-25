import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

import { Timestamp } from 'firebase-admin/firestore';

import { logClientError } from '../src/logging.js';
import {
  adminChurchMembers,
  adminRenameChurch,
  adminRevokeAdmin,
  adminSearchChurches,
  adminSetStatus,
  adminStats,
  adminTransferAdmin,
} from '../src/operator.js';
import { writeDailyStats } from '../src/stats.js';
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
    await rejectsWith(adminRevokeAdmin(deps, admin, { churchId: 'C1', uid: 'alice' }), 'permissionDenied');
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

  test('rename may give a church the name another one has', async () => {
    await seedChurch('C1', { alice: 'admin' }, { name: '甲' });
    await seedChurch('C2', { bob: 'admin' }, { name: '乙' });

    await adminRenameChurch(deps, op, { churchId: 'C2', name: ' 甲 ' });
    assert.equal((await db.doc('churches/C2').get()).get('name'), '甲');
    assert.equal((await db.doc('churches/C1').get()).get('name'), '甲');
    await rejectsWith(adminRenameChurch(deps, op, { churchId: 'C9', name: '丙' }), 'unknown');
  });

  test('transfer makes 管理員 of someone with a 身分, keeping it', async () => {
    await seedChurch('C1', { alice: 'admin', bob: 'staff' });
    await db.doc('churches/C1/members/bob').update({ identities: [{ kind: 'lead', service: 'sunday' }], leadTypes: ['sunday'] });
    await adminTransferAdmin(deps, op, { churchId: 'C1', uid: 'bob' });
    const bob = await db.doc('churches/C1/members/bob').get();
    assert.equal(bob.get('role'), 'admin');
    assert.deepEqual(bob.get('identities'), [{ kind: 'admin' }, { kind: 'lead', service: 'sunday' }]);
    assert.deepEqual(bob.get('leadTypes'), ['sunday']);
  });

  test('revoke takes away what makes them admin, keeping their other 身分; never the last admin', async () => {
    await seedChurch('C1', { alice: 'admin', bob: 'staff' });
    await db.doc('churches/C1/members/bob').update({ identities: [{ kind: 'lead', service: 'sunday' }], leadTypes: ['sunday'] });
    await adminTransferAdmin(deps, op, { churchId: 'C1', uid: 'bob' });
    await adminRevokeAdmin(deps, op, { churchId: 'C1', uid: 'bob' });
    const bob = await db.doc('churches/C1/members/bob').get();
    assert.equal(bob.get('role'), 'staff');
    assert.deepEqual(bob.get('identities'), [{ kind: 'lead', service: 'sunday' }]);
    assert.deepEqual(bob.get('leadTypes'), ['sunday']);

    await db.doc('churches/C1/members/bob').update({ role: 'admin', identities: [{ kind: 'pastor' }, { kind: 'office' }], leadTypes: [] });
    const { removed } = await adminRevokeAdmin(deps, op, { churchId: 'C1', uid: 'bob' });
    assert.equal((await db.doc('churches/C1/members/bob').get()).get('role'), 'staff', 'a whole church\'s 牧者 is an admin too');
    assert.deepEqual(removed, [{ kind: 'pastor' }]);
    // 復原 gives back what was taken, not 管理員 in its place.
    await adminTransferAdmin(deps, op, { churchId: 'C1', uid: 'bob', identities: removed });
    const back = await db.doc('churches/C1/members/bob').get();
    assert.equal(back.get('role'), 'admin');
    assert.deepEqual(back.get('identities'), [{ kind: 'pastor' }, { kind: 'office' }]);
    await rejectsWith(
      adminTransferAdmin(deps, op, { churchId: 'C1', uid: 'bob', identities: [{ kind: 'office' }] }),
      'unknown',
    );

    await adminRevokeAdmin(deps, op, { churchId: 'C1', uid: 'bob' });
    await rejectsWith(adminRevokeAdmin(deps, op, { churchId: 'C1', uid: 'alice' }), 'lastAdmin');
    assert.equal((await db.doc('churches/C1/members/alice').get()).get('role'), 'admin');
    await rejectsWith(adminRevokeAdmin(deps, op, { churchId: 'C1', uid: 'nobody' }), 'unknown');
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
    await db.doc('churches/C1').update({ status: 'deleted' });
    await rejectsWith(adminSetStatus(deps, op, { churchId: 'C1', status: 'active' }), 'churchClosed');
  });
});

describe('daily stats', () => {
  test('writes yesterday (UTC+8) with its counts', async () => {
    await seedChurch('C1', { alice: 'admin', bob: 'staff' });
    await seedChurch('C2', { carol: 'admin' }, { status: 'suspended' });
    await db.doc('users/alice').set({ name: 'a' });
    await db.doc('churches/C1/rosters/r1').set({ type: 'sunday', dateKey: '2026-10-04' });

    const s = await writeDailyStats(deps);

    assert.equal(s.date, '2026-10-01');
    const doc = await db.doc('stats/2026-10-01').get();
    assert.equal(doc.get('users'), 1);
    assert.equal(doc.get('churches_active'), 1);
    assert.equal(doc.get('churches_suspended'), 1);
    assert.equal(doc.get('members'), 3);
    assert.equal(doc.get('rosters'), 1);
  });

  test('who opened the app in the 7 days to the day, and the churches whose rosters changed in them', async () => {
    // The day counted is 2026-10-01 (UTC+8): from 09-25 on.
    for (const [uid, seenOn] of [['a', '2026-10-01'], ['b', '2026-09-25'], ['c', '2026-09-24'], ['d', undefined]] as const) {
      await db.doc(`users/${uid}`).set(seenOn ? { name: uid, seenOn } : { name: uid });
    }
    const at = (iso: string) => Timestamp.fromDate(new Date(iso));
    await db.doc('churches/C1/rosters/r1').set({ dateKey: '2026-10-04', updatedAt: at('2026-09-25T00:30:00+08:00') });
    await db.doc('churches/C1/rosters/r2').set({ dateKey: '2026-10-11', updatedAt: at('2026-10-01T23:00:00+08:00') });
    await db.doc('churches/C2/rosters/r1').set({ dateKey: '2026-10-04', updatedAt: at('2026-09-24T23:59:00+08:00') });
    await db.doc('churches/C3/rosters/r1').set({ dateKey: '2026-10-04', updatedAt: at('2026-10-02T00:10:00+08:00') });
    await db.doc('churches/C4/rosters/ev_x').set({ dateKey: '2026-10-04', via: 'calendar', updatedAt: at('2026-09-30T12:00:00+08:00') });
    const s = await writeDailyStats(deps);
    assert.equal(s.users_active_7d, 2);
    assert.equal(s.churches_editing_7d, 1, 'C1 twice; C2 before, C3 after, C4 only Google Calendar');
  });

  test('running twice for the same day replaces, never doubles', async () => {
    await seedChurch('C1', { alice: 'admin' });
    await writeDailyStats(deps);
    await writeDailyStats(deps);
    const all = await db.collection('stats').get();
    assert.equal(all.size, 1);
    assert.equal(all.docs[0].get('members'), 1);
  });

  test('adminStats returns newest first, at most the asked number', async () => {
    for (const d of ['2026-09-29', '2026-09-30', '2026-10-01']) {
      await db.doc(`stats/${d}`).set({ date: d, users: 1 });
    }
    const { days } = await adminStats(deps, op, { days: 2 });
    assert.deepEqual(days.map((d) => d.date), ['2026-10-01', '2026-09-30']);
  });
});

describe('client error log', () => {
  test('limits size; signed out too, as an error can come before signing in', () => {
    assert.deepEqual(logClientError(null, { message: 'x', stack: '' }), {});
    assert.throws(() => logClientError(caller('a'), { message: 'x'.repeat(1001), stack: '' }), /unknown/);
    assert.throws(() => logClientError(caller('a'), { message: 'x', stack: 'y'.repeat(8001) }), /unknown/);
    assert.deepEqual(logClientError(caller('a'), { message: 'boom', stack: 'at main.dart' }), {});
  });

  test('where it happened goes along as fields, not in the message; what is not as sent is left out', (t) => {
    // The Functions logger writes through the console it kept at load time.
    const lines: string[] = [];
    for (const out of [process.stdout, process.stderr]) {
      t.mock.method(out, 'write', (s: unknown) => (lines.push(String(s)), true));
    }
    const logged = (data: Record<string, unknown>) => {
      lines.length = 0;
      logClientError(caller('a'), { message: 'boom', stack: 'at main.dart', ...data });
      return JSON.parse(lines.find((l) => l.includes('boom'))!) as Record<string, unknown>;
    };

    const entry = logged({ screen: '/rosters/:id', during: 'while dispatching a pointer event', library: 'gestures library', fatal: true });
    assert.equal(entry.message, 'boom\nat main.dart');
    assert.equal(entry.screen, '/rosters/:id');
    assert.equal(entry.during, 'while dispatching a pointer event');
    assert.equal(entry.library, 'gestures library');
    assert.equal(entry.fatal, true);

    const old = logged({});
    assert.equal(old.screen, null);
    assert.equal(old.fatal, null);
    const odd = logged({ screen: 42, during: 'x'.repeat(201), library: '', fatal: 'yes' });
    assert.deepEqual([odd.screen, odd.during, odd.library, odd.fatal], [null, null, null, null]);
    assert.equal(logged({ during: 'building a@example.com' }).during, 'building <email>');
    const agent = 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';
    assert.equal(logged({ agent }).agent, agent, 'which browser, for errors of its engine');
    assert.equal(logged({ agent: 'x'.repeat(301) }).agent, null);
    const trail = '/rosters 41s → /rosters/event/:id 0.3s';
    assert.equal(logged({ trail }).trail, trail, 'the pages before it');
    assert.equal(logged({ trail: 'x'.repeat(201) }).trail, null);
    assert.equal(logged({ memory: 'skwasm 64 MB, heap 120 MB' }).memory, 'skwasm 64 MB, heap 120 MB');
    assert.equal(logged({ memory: 7 }).memory, null);
  });

  test('signed out, the entry has no user', (t) => {
    const lines: string[] = [];
    for (const out of [process.stdout, process.stderr]) {
      t.mock.method(out, 'write', (s: unknown) => (lines.push(String(s)), true));
    }
    logClientError(null, { message: 'before sign-in', stack: '', screen: '/loading' });
    const entry = JSON.parse(lines.find((l) => l.includes('before sign-in'))!) as Record<string, unknown>;
    assert.equal(entry.uid, null);
    assert.equal(entry.context, undefined);
    assert.equal(entry.screen, '/loading');
  });
});
