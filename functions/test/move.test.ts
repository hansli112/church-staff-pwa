import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

import { Timestamp } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';

import { purgeDeletedChurches } from '../src/church.js';
import { emailHash } from '../src/claim.js';
import { MOVE_LIMITS, moveCommit, movePreview, type MoveDeps } from '../src/move.js';
import { caller, clearFirestore, db, deps, purgeDeps, rejectsWith } from './support.js';

const bucket = getStorage().bucket('demo-martha.appspot.com');
const d: MoveDeps = { ...deps, bucket };
const PATH = 'moves/newadmin/f1.json';

/** A small self-host church, as the move command writes it. */
function moveFile(extra: Record<string, unknown> = {}) {
  return {
    format: 'church-staff-pwa-move',
    version: 1,
    project: 'grace-selfhost',
    exportedAt: '2026-10-04T00:00:00Z',
    users: [
      { id: 'old-pastor', data: { name: '王牧師', email: 'Pastor@Example.com', role: 'admin', zones: [{ serviceType: 'sunday', ministries: ['司會'] }] } },
      { id: 'old-mei', data: { name: '李美玉', email: 'mei@example.com', role: 'staff', groups: ['roster-editors'], zones: [{ serviceType: 'sunday', ministries: ['司琴'] }] } },
      { id: 'old-hao', data: { name: '陳志豪', email: '', role: 'staff' } },
    ],
    settings: [
      { id: 'services', data: { services: [{ id: 'sunday', name: '主日崇拜', weekday: 7 }], ids: ['sunday'] } },
      { id: 'roster_templates', data: { sunday: ['司會', '司琴'] } },
    ],
    rosters: [
      {
        id: '20261004_sunday',
        data: {
          type: 'sunday',
          date: { __time__: '2026-10-03T16:00:00Z' },
          duties: [
            { role: '司會', people: ['王牧師'], personIdsByName: { 王牧師: 'old-pastor' } },
            { role: '司琴', people: ['李美玉'], personIdsByName: { 李美玉: 'old-mei' } },
          ],
        },
      },
      { id: 'x', data: { type: 'sunday', date: { _seconds: 1760889600, _nanoseconds: 0 }, duties: [] } },
    ],
    staffOrders: [{ id: 'sunday', data: { roles: { 司琴: ['李美玉'] } } }],
    ...extra,
  };
}

async function upload(content: unknown, path = PATH) {
  await bucket.file(path).save(Buffer.from(typeof content === 'string' ? content : JSON.stringify(content)), { contentType: 'application/json' });
}

const me = caller('newadmin', { email: 'someone.else@gmail.com' });

beforeEach(async () => {
  await clearFirestore();
  await bucket.deleteFiles({ prefix: 'moves/' });
});

describe('self-serve move', () => {
  test('the preview counts members, roster days and services, and lists the people', async () => {
    await upload(moveFile());
    assert.deepEqual(await movePreview(d, me, { path: PATH }), {
      members: 3,
      rosters: 2,
      skippedRosters: 0,
      services: [{ id: 'sunday', name: '主日崇拜' }],
      people: [
        { id: 'old-pastor', name: '王牧師', email: 'Pastor@Example.com' },
        { id: 'old-mei', name: '李美玉', email: 'mei@example.com' },
        { id: 'old-hao', name: '陳志豪', email: '' },
      ],
    });
  });

  test('the uploader becomes admin whatever their email; the others wait to be claimed', async () => {
    await upload(moveFile());
    const { churchId } = await moveCommit(d, me, { path: PATH, churchName: '恩典堂' });
    const church = await db.doc(`churches/${churchId}`).get();
    assert.equal(church.get('name'), '恩典堂');
    assert.equal(church.get('movedFrom'), 'grace-selfhost');
    const admin = await db.doc(`churches/${churchId}/members/newadmin`).get();
    assert.equal(admin.get('role'), 'admin');
    assert.equal(admin.get('email'), 'someone.else@gmail.com');
    const pending = await db.collection(`churches/${churchId}/pendingMembers`).get();
    assert.deepEqual(pending.docs.map((p) => p.id).sort(), ['old-hao', 'old-mei', 'old-pastor']);
    const mei = await db.doc(`churches/${churchId}/pendingMembers/old-mei`).get();
    assert.deepEqual(mei.get('groups'), ['roster-editors']);
    assert.deepEqual(mei.get('zoneTypes'), ['sunday']);

    const roster = await db.doc(`churches/${churchId}/rosters/2026-10-04_sunday`).get();
    assert.deepEqual(roster.get('duties')[1].uids, { 李美玉: 'old-mei' }, 'points at the pending member');
    assert.equal((await db.doc(`churches/${churchId}/rosters/2025-10-20_sunday`).get()).exists, true, 'seconds timestamps read in UTC+8');
    assert.deepEqual((await db.doc(`churches/${churchId}/staff_orders/sunday`).get()).get('roles'), { 司琴: ['李美玉'] });
    assert.deepEqual((await db.doc(`churches/${churchId}/settings/services`).get()).get('ids'), ['sunday']);
    assert.equal((await bucket.file(PATH).exists())[0], false, 'the file is deleted');
  });

  test('「這位是我」 takes over that member: zones, groups and their roster days', async () => {
    await upload(moveFile());
    const { churchId } = await moveCommit(d, me, { path: PATH, churchName: '恩典堂', me: 'old-pastor' });
    const admin = await db.doc(`churches/${churchId}/members/newadmin`).get();
    assert.equal(admin.get('name'), '王牧師');
    assert.equal(admin.get('role'), 'admin');
    assert.deepEqual(admin.get('zoneTypes'), ['sunday']);
    assert.equal((await db.doc(`churches/${churchId}/pendingMembers/old-pastor`).get()).exists, false);
    const roster = await db.doc(`churches/${churchId}/rosters/2026-10-04_sunday`).get();
    assert.deepEqual(roster.get('duties')[0].uids, { 王牧師: 'newadmin' });
    assert.equal((await db.doc(`pendingIndex/${emailHash('pastor@example.com')}`).get()).exists, false);
  });

  test('the pending index is keyed by the email hash, never the email', async () => {
    await upload(moveFile());
    const { churchId } = await moveCommit(d, me, { path: PATH, churchName: '恩典堂' });
    const index = await db.collection('pendingIndex').get();
    assert.deepEqual(
      index.docs.map((x) => x.id).sort(),
      [emailHash('mei@example.com'), emailHash('pastor@example.com')].sort(),
    );
    assert.equal(emailHash(' Pastor@Example.COM '), emailHash('pastor@example.com'));
    for (const x of index.docs) {
      assert.match(x.id, /^[0-9a-f]{64}$/);
      assert.equal(JSON.stringify(x.data()).includes('@'), false);
    }
    assert.equal((await db.doc(`pendingIndex/${emailHash('mei@example.com')}`).get()).get(`churches.${churchId}`), 'old-mei');
  });

  test('password hashes in the file are ignored', async () => {
    const file = moveFile({ accounts: [{ localId: 'old-mei', email: 'mei@example.com', passwordHash: 'SECRET-HASH', salt: 'SALT' }] });
    (file.users[1].data as Record<string, unknown>).passwordHash = 'SECRET-HASH';
    await upload(file);
    const { churchId } = await moveCommit(d, me, { path: PATH, churchName: '恩典堂' });
    const all = [
      ...(await db.collection(`churches/${churchId}/pendingMembers`).get()).docs,
      ...(await db.collection(`churches/${churchId}/members`).get()).docs,
      ...(await db.collection('pendingIndex').get()).docs,
    ];
    for (const doc of all) assert.equal(JSON.stringify(doc.data()).includes('SECRET-HASH'), false, doc.ref.path);
    assert.equal((await db.collection('users').get()).size, 0, 'no accounts or profiles are made');
  });

  test('over the limits it is refused with the counts', async () => {
    const many = Array.from({ length: MOVE_LIMITS.members + 1 }, (_, i) => ({ id: `u${i}`, data: { name: `同工${i}` } }));
    await upload(moveFile({ users: many }));
    const e = (await rejectsWith(movePreview(d, me, { path: PATH }), 'moveTooLarge')) as { details: { detail: { members: number } } };
    assert.equal(e.details.detail.members, 2001);
    await rejectsWith(moveCommit(d, me, { path: PATH, churchName: '恩典堂' }), 'moveTooLarge');
    const days = Array.from({ length: MOVE_LIMITS.rosters + 1 }, (_, i) => ({ id: `r${i}`, data: {} }));
    await upload(moveFile({ rosters: days }));
    await rejectsWith(movePreview(d, me, { path: PATH }), 'moveTooLarge');
  });

  test('not a move file, someone else’s file, or unverified email', async () => {
    await upload('{"hello": 1}');
    await rejectsWith(movePreview(d, me, { path: PATH }), 'moveInvalid');
    await upload('not json');
    await rejectsWith(movePreview(d, me, { path: PATH }), 'moveInvalid');
    await upload(moveFile(), 'moves/victim/f1.json');
    await rejectsWith(movePreview(d, me, { path: 'moves/victim/f1.json' }), 'permissionDenied');
    await rejectsWith(movePreview(d, me, { path: '../x' }), 'permissionDenied');
    await upload(moveFile());
    await rejectsWith(moveCommit(d, caller('newadmin', { emailVerified: false }), { path: PATH, churchName: '恩典堂' }), 'unverifiedEmail');
  });

  test('purging the church drops its pending index entries', async () => {
    await upload(moveFile());
    const { churchId } = await moveCommit(d, me, { path: PATH, churchName: '恩典堂' });
    await db.doc(`churches/${churchId}`).update({ status: 'deleted', deletedAt: Timestamp.fromDate(new Date('2026-08-01T00:00:00Z')) });
    await purgeDeletedChurches(purgeDeps);
    const index = await db.doc(`pendingIndex/${emailHash('mei@example.com')}`).get();
    assert.deepEqual(index.get('churches'), {});
  });

  test('the church name must be free', async () => {
    await upload(moveFile());
    await moveCommit(d, me, { path: PATH, churchName: '恩典堂' });
    await upload(moveFile());
    const before = (await db.collectionGroup('pendingMembers').get()).size;
    await rejectsWith(moveCommit(d, me, { path: PATH, churchName: '恩典 堂' }), 'duplicateName');
    assert.equal((await db.collectionGroup('pendingMembers').get()).size, before, 'nothing written for a taken name');
  });
});
