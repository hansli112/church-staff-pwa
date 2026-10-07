import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

import { Timestamp } from 'firebase-admin/firestore';

import { churchPreview, createChurch, deleteChurch, purgeDeletedChurches, restoreChurch } from '../src/church.js';
import { nameKey } from '../src/text.js';
import { caller, clearFirestore, db, deps, rejectsWith, seedChurch, setNow } from './support.js';

beforeEach(async () => {
  await clearFirestore();
  setNow(new Date('2026-10-01T10:00:00+08:00'));
});

describe('nameKey', () => {
  test('treats spacing, width and case differences as the same name', () => {
    assert.equal(nameKey('台北 靈糧堂'), nameKey('台北靈糧堂'));
    assert.equal(nameKey('ＴＡＩＰＥＩ'), nameKey('taipei'));
    assert.notEqual(nameKey('台北靈糧堂'), nameKey('台中靈糧堂'));
  });
});

describe('createChurch', () => {
  test('creates the church, its admin and default services in one go', async () => {
    await db.doc('users/alice').set({ name: '愛麗絲' });
    const { churchId } = await createChurch(deps, caller('alice'), { name: ' 恩典堂 ' });

    const church = await db.doc(`churches/${churchId}`).get();
    assert.equal(church.get('name'), '恩典堂');
    assert.equal(church.get('status'), 'active');
    const member = await db.doc(`churches/${churchId}/members/alice`).get();
    assert.equal(member.get('role'), 'admin');
    assert.equal(member.get('name'), '愛麗絲');
    assert.equal(member.get('uid'), 'alice');
    const services = await db.doc(`churches/${churchId}/settings/services`).get();
    assert.deepEqual(services.get('ids'), ['sunday']);
  });

  test('rejects an unverified email', async () => {
    await rejectsWith(
      createChurch(deps, caller('bob', { emailVerified: false }), { name: '恩典堂' }),
      'unverifiedEmail',
    );
    assert.equal((await db.collection('churches').get()).size, 0);
  });

  test('rejects a signed-out caller', async () => {
    await rejectsWith(createChurch(deps, null, { name: '恩典堂' }), 'permissionDenied');
  });

  test('rejects names that only differ by spaces, width or case', async () => {
    await createChurch(deps, caller('alice'), { name: '台北 靈糧堂' });
    await rejectsWith(createChurch(deps, caller('bob'), { name: '台北靈糧堂' }), 'duplicateName');
    await createChurch(deps, caller('alice'), { name: 'Taipei Grace' });
    await rejectsWith(
      createChurch(deps, caller('bob'), { name: 'ＴＡＩＰＥＩ　ＧＲＡＣＥ' }),
      'duplicateName',
    );
  });

  test('two people creating the same name at once: only one succeeds', async () => {
    const results = await Promise.allSettled([
      createChurch(deps, caller('alice'), { name: '同名教會' }),
      createChurch(deps, caller('bob'), { name: '同名 教會' }),
      createChurch(deps, caller('carol'), { name: '同名教會 ' }),
    ]);
    assert.equal(results.filter((r) => r.status === 'fulfilled').length, 1);
    assert.equal((await db.collection('churches').get()).size, 1);
  });

  test('rejects empty and overlong names', async () => {
    await rejectsWith(createChurch(deps, caller('alice'), { name: '   ' }), 'unknown');
    await rejectsWith(createChurch(deps, caller('alice'), { name: 'x'.repeat(61) }), 'unknown');
  });
});

describe('delete and restore', () => {
  test('an admin deletes and restores within 30 days', async () => {
    await seedChurch('C1', { alice: 'admin', bob: 'staff' });
    await deleteChurch(deps, caller('alice'), { churchId: 'C1' });
    assert.equal((await db.doc('churches/C1').get()).get('status'), 'deleted');

    setNow(new Date('2026-10-20T10:00:00+08:00'));
    await restoreChurch(deps, caller('alice'), { churchId: 'C1' });
    const church = await db.doc('churches/C1').get();
    assert.equal(church.get('status'), 'active');
    assert.equal(church.get('deletedAt'), null);
    assert.ok((await db.doc('churches/C1/members/bob').get()).exists, 'data is intact');
  });

  test('a non-admin, or an admin of another church, cannot delete', async () => {
    await seedChurch('C1', { alice: 'admin', bob: 'staff' });
    await seedChurch('C2', { eve: 'admin' });
    await rejectsWith(deleteChurch(deps, caller('bob'), { churchId: 'C1' }), 'permissionDenied');
    await rejectsWith(deleteChurch(deps, caller('eve'), { churchId: 'C1' }), 'permissionDenied');
    assert.equal((await db.doc('churches/C1').get()).get('status'), 'active');
  });

  test('purge removes churches deleted over 30 days ago, and only those', async () => {
    await seedChurch('Old', { alice: 'admin' });
    await seedChurch('Recent', { bob: 'admin' });
    await seedChurch('Live', { carol: 'admin' });
    await db.doc('churches/Old/rosters/r1').set({ type: 'sunday', dateKey: '2026-08-02' });
    await db.doc('invites/ABCDEFGH').set({ cid: 'Old' });
    await db.doc('linkSources/Old').set({ source: 'https://x.example' });
    await db.doc('churches/Old').update({
      status: 'deleted',
      deletedAt: Timestamp.fromDate(new Date('2026-08-25T00:00:00Z')),
    });
    await db.doc('churches/Recent').update({
      status: 'deleted',
      deletedAt: Timestamp.fromDate(new Date('2026-09-20T00:00:00Z')),
    });

    const purged = await purgeDeletedChurches(deps);

    assert.deepEqual(purged, ['Old']);
    assert.equal((await db.doc('churches/Old').get()).exists, false);
    assert.equal((await db.doc('churches/Old/rosters/r1').get()).exists, false);
    assert.equal((await db.doc('churches/Old/members/alice').get()).exists, false);
    assert.equal((await db.doc('churchNames/old').get()).exists, false);
    assert.equal((await db.doc('invites/ABCDEFGH').get()).exists, false);
    assert.equal((await db.doc('linkSources/Old').get()).exists, false);
    assert.ok((await db.doc('churches/Recent').get()).exists);
    assert.ok((await db.doc('churches/Live').get()).exists);
  });

  test('restore fails after 30 days', async () => {
    await seedChurch('C1', { alice: 'admin' });
    await deleteChurch(deps, caller('alice'), { churchId: 'C1' });
    setNow(new Date('2026-11-05T10:00:00+08:00'));
    await rejectsWith(restoreChurch(deps, caller('alice'), { churchId: 'C1' }), 'churchClosed');
  });
});

describe('suspension', () => {
  test('an admin cannot delete-and-restore their way out of a suspension', async () => {
    await seedChurch('C1', { alice: 'admin' }, { status: 'suspended' });
    await rejectsWith(deleteChurch(deps, caller('alice'), { churchId: 'C1' }), 'churchClosed');
    await rejectsWith(restoreChurch(deps, caller('alice'), { churchId: 'C1' }), 'churchClosed');
    assert.equal((await db.doc('churches/C1').get()).get('status'), 'suspended');
  });
});

describe('purge hooks', () => {
  test('purge calls the hook before deleting, e.g. to revoke the calendar grant', async () => {
    await seedChurch('Old', { alice: 'admin' });
    await db.doc('churches/Old').update({ status: 'deleted', deletedAt: Timestamp.fromDate(new Date('2026-08-01T00:00:00Z')) });
    const seen: string[] = [];
    await purgeDeletedChurches(deps, undefined, async (cid) => seen.push(cid));
    assert.deepEqual(seen, ['Old']);
  });
});

describe('churchPreview', () => {
  test('anyone, even signed out, gets an active church’s name and logo', async () => {
    await seedChurch('Grace', { pastor: 'admin' }, { name: '恩典堂', logoVersion: '17' });
    assert.deepEqual(await churchPreview(deps, null, { churchId: 'Grace' }), {
      churchId: 'Grace',
      name: '恩典堂',
      logoPath: '/c/Grace/icons/17/logo.png',
    });
    await seedChurch('Plain', {});
    assert.equal((await churchPreview(deps, caller('x'), { churchId: 'Plain' })).logoPath, null);
  });

  test('a suspended, deleted or unknown church is not found', async () => {
    await seedChurch('Closed', {}, { status: 'suspended' });
    await seedChurch('Gone', {}, { status: 'deleted' });
    for (const churchId of ['Closed', 'Gone', 'Nope']) {
      await rejectsWith(churchPreview(deps, caller('x'), { churchId }), 'notFound');
    }
    await rejectsWith(churchPreview(deps, null, { churchId: '../x' }), 'unknown');
  });
});
