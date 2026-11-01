import assert from 'node:assert/strict';
import { beforeEach, test } from 'node:test';

import { setDuty, setGroupMember } from '../src/groupMembers.js';
import { caller, clearFirestore, db, deps, rejectsWith, seedChurch } from './support.js';

// 加為同工, 移出 (#82): a group's 負責人 adds or takes out a 同工 who is
// already in the church; giving anyone a 身分 stays the admin's. Who is on
// a duty's list (#94): whoever leads it puts anyone on it.
async function church() {
  await seedChurch('C1', { admin: 'admin', sundayLead: 'staff', worshipLead: 'staff', mei: 'staff' });
  await seedChurch('C2', { stranger: 'staff' });
  await db.doc('churches/C1/settings/services').set({
    services: [{ id: 'sunday', name: '主日崇拜', duties: ['司琴', '招待'] }, { id: 'youth', name: '青年崇拜', duties: ['敬拜'] }],
    ids: ['sunday', 'youth'],
  });
  await db.doc('churches/C1/settings/ministries').set({
    ministries: [{ id: 'worship', name: '敬拜團', duties: [{ service: 'sunday', duty: '司琴' }] }],
    ids: ['worship'],
  });
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

test("but not another service's, and a 事工 has no 同工 of its own (#94)", async () => {
  await church();
  await rejectsWith(
    setGroupMember(deps, caller('sundayLead'), { churchId: 'C1', uid: 'mei', service: 'youth', member: false }),
    'permissionDenied',
  );
  await rejectsWith(
    setGroupMember(deps, caller('admin'), { churchId: 'C1', uid: 'mei', ministry: 'worship', member: true }),
    'unknown',
  );
  await rejectsWith(
    setGroupMember(deps, caller('mei'), { churchId: 'C1', uid: 'mei', service: 'sunday', member: true, duties: [] }),
    'permissionDenied',
  );
  assert.deepEqual((await mei()).get('zoneTypes'), ['youth']);
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
});

test('a lead moves only plain 同工; a service keeps its 小組 when one comes back', async () => {
  await church();
  await rejectsWith(
    setGroupMember(deps, caller('sundayLead'), { churchId: 'C1', uid: 'worshipLead', service: 'sunday', member: true }),
    'permissionDenied',
  );
  await setGroupMember(deps, caller('admin'), { churchId: 'C1', uid: 'mei', service: 'youth', member: false });
  await setGroupMember(deps, caller('admin'), {
    churchId: 'C1', uid: 'mei', service: 'youth', member: true, duties: ['敬拜'], smallGroups: ['喜樂'],
  });
  assert.deepEqual((await mei()).get('zones'), [{ serviceType: 'youth', duties: ['敬拜'], smallGroups: ['喜樂'] }]);
});

test("a 事工's 負責人 puts anyone on its duty's list, who becomes a 同工 of the service, and takes them off again", async () => {
  await church();
  await setDuty(deps, caller('worshipLead'), { churchId: 'C1', uid: 'mei', service: 'sunday', duty: '司琴', on: true });
  assert.deepEqual((await mei()).get('zones'), [
    { serviceType: 'youth', duties: ['敬拜'], smallGroups: [] },
    { serviceType: 'sunday', duties: ['司琴'], smallGroups: [] },
  ]);
  assert.deepEqual((await mei()).get('zoneTypes'), ['youth', 'sunday']);
  await setDuty(deps, caller('worshipLead'), { churchId: 'C1', uid: 'mei', service: 'sunday', duty: '司琴', on: true });
  assert.deepEqual((await mei()).get('zones')[1].duties, ['司琴'], 'once');

  // Someone with a 身分 too: a list gives nothing.
  await setDuty(deps, caller('worshipLead'), { churchId: 'C1', uid: 'sundayLead', service: 'sunday', duty: '司琴', on: true });
  assert.deepEqual((await db.doc('churches/C1/members/sundayLead').get()).get('zoneTypes'), ['sunday']);

  await setDuty(deps, caller('worshipLead'), { churchId: 'C1', uid: 'mei', service: 'sunday', duty: '司琴', on: false });
  assert.deepEqual((await mei()).get('zones')[1], { serviceType: 'sunday', duties: [], smallGroups: [] }, 'still a 同工');
  assert.deepEqual((await mei()).get('zoneTypes'), ['youth', 'sunday']);
});

test('only the duties they lead, and only those the service has', async () => {
  await church();
  await rejectsWith(
    setDuty(deps, caller('worshipLead'), { churchId: 'C1', uid: 'mei', service: 'sunday', duty: '招待', on: true }),
    'permissionDenied',
  );
  await rejectsWith(
    setDuty(deps, caller('mei'), { churchId: 'C1', uid: 'mei', service: 'youth', duty: '敬拜', on: false }),
    'permissionDenied',
  );
  await rejectsWith(
    setDuty(deps, caller('sundayLead'), { churchId: 'C1', uid: 'mei', service: 'youth', duty: '敬拜', on: false }),
    'permissionDenied',
  );
  await rejectsWith(
    setDuty(deps, caller('sundayLead'), { churchId: 'C1', uid: 'mei', service: 'sunday', duty: '講員', on: true }),
    'unknown',
  );
  await rejectsWith(
    setDuty(deps, caller('admin'), { churchId: 'C1', uid: 'stranger', service: 'sunday', duty: '司琴', on: true }),
    'notFound',
  );
  // A duty gone from the service still comes off.
  await setDuty(deps, caller('admin'), { churchId: 'C1', uid: 'mei', service: 'youth', duty: '舊的', on: false });
  await db.doc('churches/C1/members/mei').update({ zones: [{ serviceType: 'youth', duties: ['敬拜', '舊的'], smallGroups: [] }] });
  await setDuty(deps, caller('admin'), { churchId: 'C1', uid: 'mei', service: 'youth', duty: '舊的', on: false });
  assert.deepEqual((await mei()).get('zones'), [{ serviceType: 'youth', duties: ['敬拜'], smallGroups: [] }]);
});
