import assert from 'node:assert/strict';
import { beforeEach, test } from 'node:test';

import { setGroupMember } from '../src/groupMembers.js';
import { caller, clearFirestore, db, deps, rejectsWith, seedChurch } from './support.js';

// 加為同工, 移出 (#82): a group's 負責人 adds or takes out a 同工 who is
// already in the church; giving anyone a 身分 stays the admin's.
async function church() {
  await seedChurch('C1', { admin: 'admin', sundayLead: 'staff', worshipLead: 'staff', mei: 'staff' });
  await seedChurch('C2', { stranger: 'staff' });
  await db.doc('churches/C1/settings/services').set({
    services: [{ id: 'sunday', name: '主日崇拜', duties: ['司琴', '招待'] }, { id: 'youth', name: '青年崇拜', duties: ['敬拜'] }],
    ids: ['sunday', 'youth'],
  });
  await db.doc('churches/C1/settings/ministries').set({ ministries: [{ id: 'worship', name: '敬拜團', duties: [] }], ids: ['worship'] });
  await db.doc('churches/C1/members/sundayLead').update({ leadTypes: ['sunday'], identities: [{ kind: 'lead', service: 'sunday' }] });
  await db.doc('churches/C1/members/worshipLead').update({ leadMinistries: ['worship'], identities: [{ kind: 'lead', ministry: 'worship' }] });
  await db.doc('churches/C1/members/mei').update({ zones: [{ serviceType: 'youth', duties: ['敬拜'], smallGroups: [] }], zoneTypes: ['youth'] });
}

const mei = () => db.doc('churches/C1/members/mei').get();

beforeEach(clearFirestore);

test("a service's 負責人 adds a 同工 to it, with the duties they served, and takes them out again", async () => {
  await church();
  await setGroupMember(deps, caller('sundayLead'), { churchId: 'C1', uid: 'mei', service: 'sunday', member: true, duties: ['司琴'] });
  assert.deepEqual((await mei()).get('zones'), [
    { serviceType: 'youth', duties: ['敬拜'], smallGroups: [] },
    { serviceType: 'sunday', duties: ['司琴'], smallGroups: [] },
  ]);
  assert.deepEqual((await mei()).get('zoneTypes'), ['youth', 'sunday']);

  await setGroupMember(deps, caller('sundayLead'), { churchId: 'C1', uid: 'mei', service: 'sunday', member: false });
  assert.deepEqual((await mei()).get('zones'), [{ serviceType: 'youth', duties: ['敬拜'], smallGroups: [] }]);
  assert.deepEqual((await mei()).get('zoneTypes'), ['youth']);
});

test("but not another service's, nor a 事工 they do not lead", async () => {
  await church();
  await rejectsWith(
    setGroupMember(deps, caller('sundayLead'), { churchId: 'C1', uid: 'mei', service: 'youth', member: false }),
    'permissionDenied',
  );
  await rejectsWith(
    setGroupMember(deps, caller('sundayLead'), { churchId: 'C1', uid: 'mei', ministry: 'worship', member: true }),
    'permissionDenied',
  );
  await rejectsWith(
    setGroupMember(deps, caller('mei'), { churchId: 'C1', uid: 'mei', service: 'sunday', member: true, duties: [] }),
    'permissionDenied',
  );
  assert.deepEqual((await mei()).get('zoneTypes'), ['youth']);
});

test("a 事工's 負責人 adds and takes out its 同工; an admin may for any group", async () => {
  await church();
  await setGroupMember(deps, caller('worshipLead'), { churchId: 'C1', uid: 'mei', ministry: 'worship', member: true });
  assert.deepEqual((await mei()).get('ministries'), ['worship']);
  await setGroupMember(deps, caller('worshipLead'), { churchId: 'C1', uid: 'mei', ministry: 'worship', member: true });
  assert.deepEqual((await mei()).get('ministries'), ['worship'], 'once');
  await setGroupMember(deps, caller('admin'), { churchId: 'C1', uid: 'mei', ministry: 'worship', member: false });
  assert.deepEqual((await mei()).get('ministries'), []);
  await setGroupMember(deps, caller('admin'), { churchId: 'C1', uid: 'mei', service: 'sunday', member: true, duties: [] });
  assert.deepEqual((await mei()).get('zoneTypes'), ['youth', 'sunday']);
});

test('only people already in the church, and only duties the service has', async () => {
  await church();
  await rejectsWith(
    setGroupMember(deps, caller('sundayLead'), { churchId: 'C1', uid: 'stranger', service: 'sunday', member: true, duties: [] }),
    'notFound',
  );
  await rejectsWith(
    setGroupMember(deps, caller('sundayLead'), { churchId: 'C1', uid: 'mei', service: 'sunday', member: true, duties: ['講員'] }),
    'unknown',
  );
  await rejectsWith(
    setGroupMember(deps, caller('worshipLead'), { churchId: 'C1', uid: 'mei', ministry: 'band', member: true }),
    'permissionDenied',
  );
});
