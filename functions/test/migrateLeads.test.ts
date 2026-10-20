import assert from 'node:assert/strict';
import { beforeEach, test } from 'node:test';

import { applyLeads, planLeads } from '../scripts/migrate-leads.js';
import { clearFirestore, db, seedChurch } from './support.js';

beforeEach(clearFirestore);

test('a roster editor of their 牧區 becomes its 負責人; a calendar editor 行政; admins stay as they are', async () => {
  await seedChurch('C1', { pastor: 'admin', ed: 'staff', cal: 'staff', both: 'staff', done: 'staff' });
  await db.doc('churches/C1/members/ed').update({ groups: ['roster-editors'], zoneTypes: ['sunday', 'youth'] });
  await db.doc('churches/C1/members/cal').update({ groups: ['calendar-editors'] });
  await db.doc('churches/C1/members/both').update({ groups: ['roster-editors', 'calendar-editors'], zoneTypes: ['sunday'] });
  await db.doc('churches/C1/members/done').update({ groups: ['roster-editors'], identities: [{ kind: 'office' }] });
  const plan = await planLeads(db);
  assert.deepEqual(plan.map((c) => c.path).sort(), ['churches/C1/members/both', 'churches/C1/members/cal', 'churches/C1/members/ed']);
  await applyLeads(db, plan);
  const ed = await db.doc('churches/C1/members/ed').get();
  assert.deepEqual(ed.get('groups'), []);
  assert.deepEqual(ed.get('leadTypes'), ['sunday', 'youth']);
  assert.deepEqual(ed.get('identities'), [{ kind: 'lead', service: 'sunday' }, { kind: 'lead', service: 'youth' }]);
  for (const uid of ['cal', 'both']) {
    const m = await db.doc(`churches/C1/members/${uid}`).get();
    assert.deepEqual(m.get('identities'), [{ kind: 'office' }], uid);
    assert.deepEqual(m.get('groups'), ['roster-editors', 'calendar-editors'], uid);
  }
  assert.deepEqual(await planLeads(db), [], 'once');
});
