import assert from 'node:assert/strict';
import { beforeEach, test } from 'node:test';

import { applyDutyLeads, planDutyLeads } from '../scripts/migrate-duty-leads.js';
import { clearFirestore, db, seedChurch } from './support.js';

beforeEach(clearFirestore);

test("a 事工's 負責人 lead the duties it linked; the 事工 stays, linking none", async () => {
  await seedChurch('C1', { admin: 'admin', mei: 'staff', hao: 'staff' });
  await db.doc('churches/C1/settings/services').set({
    services: [{ id: 'sunday', name: '主日崇拜', duties: ['司琴', '攝影'] }, { id: 'youth', name: '青年崇拜', duties: ['攝影'] }],
    ids: ['sunday', 'youth'],
  });
  await db.doc('churches/C1/settings/ministries').set({
    ministries: [
      {
        id: 'media',
        name: '多媒體',
        duties: [
          { service: 'sunday', duty: '攝影' },
          { service: 'youth', duty: '攝影' },
          { service: 'sunday', duty: '燈光' }, // no longer a duty there
          { service: null, duty: '攝影' }, // events'
        ],
      },
      { id: 'care', name: '關懷', duties: [], addedIn: 'sunday' },
    ],
    ids: ['media', 'care'],
  });
  await db.doc('churches/C1/members/mei').update({ identities: [{ kind: 'lead', ministry: 'media' }], leadMinistries: ['media'] });
  // From before 身分: what the rules read.
  await db.doc('churches/C1/members/hao').update({ leadMinistries: ['media', 'care'] });

  const changes = await planDutyLeads(db);
  await applyDutyLeads(db, changes);

  const mei = (await db.doc('churches/C1/members/mei').get()).data()!;
  assert.deepEqual(mei.identities, [
    { kind: 'lead', ministry: 'media' },
    { kind: 'dutyLead', service: 'sunday', duty: '攝影' },
    { kind: 'dutyLead', service: 'youth', duty: '攝影' },
  ]);
  assert.deepEqual(mei.leadDuties, ['sunday/攝影', 'youth/攝影']);
  assert.deepEqual(mei.leadTypes, [], 'not the services’ 負責人');
  assert.deepEqual(mei.leadMinistries, ['media'], 'still the 事工’s');
  const hao = (await db.doc('churches/C1/members/hao').get()).data()!;
  assert.deepEqual(hao.leadDuties, ['sunday/攝影', 'youth/攝影']);
  assert.deepEqual(hao.leadMinistries, ['media', 'care']);
  assert.deepEqual((await db.doc('churches/C1/settings/ministries').get()).get('ministries'), [
    { id: 'media', name: '多媒體' },
    { id: 'care', name: '關懷' },
  ]);

  assert.deepEqual(await planDutyLeads(db), [], 'once is enough');
});
