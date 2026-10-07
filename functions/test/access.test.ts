import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

import { churchAccess, churchId, isChurchId, type Level } from '../src/access.js';
import { caller, clearFirestore, db, deps, rejectsWith, seedChurch } from './support.js';

/**
 * C1 has Sunday and youth services: pastor its admin, editor a roster
 * editor for Sunday, mei on staff. eve belongs to C2 only.
 */
async function church(status = 'active') {
  await seedChurch('C1', { pastor: 'admin', editor: 'staff', mei: 'staff' }, { status });
  await seedChurch('C2', { eve: 'admin' });
  await db.doc('churches/C1/members/editor').update({ groups: ['roster-editors'], zoneTypes: ['sunday'] });
  await db.doc('churches/C1/settings/services').set({ services: [{ id: 'sunday' }, { id: 'youth' }], ids: ['sunday', 'youth'] });
}

const access = (uid: string, level: Level, opts?: { closed?: 'allow' }) =>
  churchAccess(deps, caller(uid), { churchId: 'C1' }, level, opts);

/** What each person gets at each level in an active church. */
const levels: [string, Level][] = [
  ['member', 'member'],
  ['admin', 'admin'],
  ['roster editor', { rosterEditor: 'sunday' }],
  ['calendar editor', { group: 'calendar-editors' }],
  ['anyone', 'anyone'],
];
const allowed: Record<string, string[]> = {
  pastor: ['member', 'admin', 'roster editor', 'calendar editor', 'anyone'],
  editor: ['member', 'roster editor', 'anyone'],
  mei: ['member', 'anyone'],
  eve: ['anyone'],
};

beforeEach(clearFirestore);

describe('church access', () => {
  test('an active church: each level lets in whom firestore.rules does', async () => {
    await church();
    for (const [uid, names] of Object.entries(allowed)) {
      for (const [name, level] of levels) {
        if (names.includes(name)) {
          const a = await access(uid, level);
          assert.equal(a.cid, 'C1');
          assert.equal(a.open, true);
          assert.equal(a.admin, uid === 'pastor', `${uid} admin`);
        } else {
          await rejectsWith(access(uid, level), 'permissionDenied');
        }
      }
    }
  });

  for (const status of ['suspended', 'deleted']) {
    test(`a ${status} church: members are told it is closed, strangers are refused`, async () => {
      await church(status);
      for (const uid of ['pastor', 'editor', 'mei']) {
        for (const [, level] of levels) {
          const err = await rejectsWith(access(uid, level), 'churchClosed');
          assert.equal((err as { code: string }).code, 'failed-precondition');
        }
      }
      for (const [, level] of levels) {
        await rejectsWith(access('eve', level), level === 'anyone' ? 'churchClosed' : 'permissionDenied');
      }
    });

    test(`a ${status} church lets its admin in where closed churches are allowed`, async () => {
      await church(status);
      const a = await access('pastor', 'admin', { closed: 'allow' });
      assert.equal(a.open, false);
      await rejectsWith(access('mei', 'admin', { closed: 'allow' }), 'permissionDenied');
      await rejectsWith(access('eve', 'admin', { closed: 'allow' }), 'permissionDenied');
    });
  }

  test('a roster editor edits only their zones, and only services the church has had', async () => {
    await church();
    await db.doc('churches/C1/members/editor').update({ zoneTypes: ['sunday', 'retreat'] });
    await rejectsWith(access('editor', { rosterEditor: 'youth' }), 'permissionDenied');
    await rejectsWith(access('editor', { rosterEditor: 'retreat' }), 'permissionDenied');
    await rejectsWith(access('pastor', { rosterEditor: 'retreat' }), 'permissionDenied');
    await access('pastor', { rosterEditor: 'youth' });
    // A service taken off the list keeps its ID: rosters for it stay editable.
    await db.doc('churches/C1/settings/services').update({ services: [{ id: 'youth' }] });
    await access('editor', { rosterEditor: 'sunday' });
    // A zone without the group is not enough.
    await db.doc('churches/C1/members/mei').update({ zoneTypes: ['sunday'] });
    await rejectsWith(access('mei', { rosterEditor: 'sunday' }), 'permissionDenied');
  });

  test('a group: its members and admins', async () => {
    await church();
    await db.doc('churches/C1/members/mei').update({ groups: ['calendar-editors'] });
    assert.ok((await access('mei', { group: 'calendar-editors' })).inGroup('calendar-editors'));
    await rejectsWith(access('mei', { group: 'roster-editors' }), 'permissionDenied');
  });

  test('signed out, an unknown church, a bad ID', async () => {
    await church();
    await rejectsWith(churchAccess(deps, null, { churchId: 'C1' }, 'member'), 'permissionDenied');
    await rejectsWith(churchAccess(deps, caller('mei'), { churchId: 'Nope' }, 'member'), 'permissionDenied');
    await rejectsWith(churchAccess(deps, caller('mei'), { churchId: 'Nope' }, 'anyone'), 'notFound');
    for (const bad of [undefined, '', 'C-1', 'a/b', 'x'.repeat(65), 7]) {
      await rejectsWith(churchAccess(deps, caller('mei'), { churchId: bad }, 'member'), 'unknown');
    }
  });
});

describe('church IDs', () => {
  test('letters and digits, 1 to 64', () => {
    assert.equal(churchId('AbC123'), 'AbC123');
    assert.ok(isChurchId('x'.repeat(64)));
    for (const bad of ['', 'C_1', 'C-1', 'a/b', 'x'.repeat(65), null, 1]) {
      assert.equal(isChurchId(bad), false, String(bad));
      assert.throws(() => churchId(bad), /unknown/);
    }
  });
});
