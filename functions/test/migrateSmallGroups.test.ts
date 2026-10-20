import assert from 'node:assert/strict';
import { beforeEach, test } from 'node:test';

import { applySmallGroups, planSmallGroups } from '../scripts/migrate-small-groups.js';
import { clearFirestore, db, seedChurch } from './support.js';

beforeEach(clearFirestore);

test('the 小組 names members kept become 小組; they are in them, a 小組長 leads them; once', async () => {
  await seedChurch('C1', { mei: 'leader', hao: 'staff', pastor: 'admin' });
  await db.doc('churches/C1/settings/services').set({ services: [{ id: 'sunday', name: '主日崇拜' }], ids: ['sunday'] });
  await db.doc('churches/C1/members/mei').update({ zones: [{ serviceType: 'sunday', duties: [], smallGroups: ['喜樂小組'] }] });
  await db.doc('churches/C1/members/hao').update({ zones: [{ serviceType: 'sunday', duties: [], smallGroups: ['喜樂小組', '平安小組'] }, { serviceType: 'gone', duties: [], smallGroups: ['舊小組'] }] });
  await db.doc('churches/C1/pendingMembers/old').set({ name: '老同工', zones: [{ serviceType: 'sunday', duties: [], smallGroups: ['恩典小組'] }] });
  await applySmallGroups(db, await planSmallGroups(db));

  const groups = (await db.collection('churches/C1/smallGroups').get()).docs;
  const id = (name: string) => groups.find((g) => g.get('name') === name)!.id;
  assert.deepEqual(groups.map((g) => g.get('name')).sort(), ['喜樂小組', '平安小組', '恩典小組'], "a service no longer there makes none");
  assert.deepEqual(((await db.doc('churches/C1/settings/smallGroups').get()).get('ids') as string[]).sort(), groups.map((g) => g.id).sort());
  const mei = await db.doc('churches/C1/members/mei').get();
  assert.deepEqual(mei.get('smallGroups'), [id('喜樂小組')]);
  assert.deepEqual(mei.get('leadSmallGroups'), [id('喜樂小組')]);
  assert.deepEqual(mei.get('identities'), [{ kind: 'lead', smallGroup: id('喜樂小組') }]);
  const hao = await db.doc('churches/C1/members/hao').get();
  assert.deepEqual(hao.get('smallGroups'), [id('喜樂小組'), id('平安小組')]);
  assert.equal(hao.get('leadSmallGroups'), undefined);
  assert.deepEqual(await planSmallGroups(db), [], 'once');
});
