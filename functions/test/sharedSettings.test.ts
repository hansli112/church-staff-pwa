import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

import { copySharedSettings } from '../src/sharedSettings.js';
import { clearFirestore, db, deps, seedChurch } from './support.js';

const shared = async () => (await db.doc('churches/C1/settings/shared').get()).data();

beforeEach(async () => {
  await clearFirestore();
  await seedChurch('C1', { admin: 'admin' }, { name: '恩典堂' });
});

describe('settings/shared, the copy the app reads on opening', () => {
  test('holds what the app reads of the settings, a missing one as null', async () => {
    await db.doc('churches/C1/settings/services').set({ services: [{ id: 'sunday', name: '主日' }], ids: ['sunday'] });
    await db.doc('churches/C1/settings/link').set({ title: '奉獻', url: 'https://example.com' });
    await db.doc('churches/C1/settings/webhook').set({ url: 'https://hook.example.com/?token=secret' });

    assert.equal(await copySharedSettings(deps, 'C1'), true);

    assert.deepEqual(await shared(), {
      services: { services: [{ id: 'sunday', name: '主日' }], ids: ['sunday'] },
      ministries: null,
      calendar: null,
      link: { title: '奉獻', url: 'https://example.com' },
      linkContent: null,
    });
  });

  test('follows a change and a deletion, and writes nothing when it already matches', async () => {
    await db.doc('churches/C1/settings/link').set({ title: '奉獻', url: 'https://example.com' });
    await copySharedSettings(deps, 'C1');
    await db.doc('churches/C1/settings/link').delete();
    await db.doc('churches/C1/settings/calendar').set({ calendarId: 'c@group', calendarName: '教會' });

    assert.equal(await copySharedSettings(deps, 'C1'), true);
    assert.equal((await shared())?.link, null);
    assert.deepEqual((await shared())?.calendar, { calendarId: 'c@group', calendarName: '教會' });

    const written = (await db.doc('churches/C1/settings/shared').get()).updateTime;
    assert.equal(await copySharedSettings(deps, 'C1'), false);
    assert.deepEqual((await db.doc('churches/C1/settings/shared').get()).updateTime, written);
  });

  test('leaves a deleted church, and one that is gone, without it', async () => {
    await db.doc('churches/C1').update({ status: 'deleted' });
    assert.equal(await copySharedSettings(deps, 'C1'), false);
    assert.equal(await copySharedSettings(deps, 'nowhere'), false);
    assert.equal(await shared(), undefined);
    assert.equal((await db.doc('churches/nowhere/settings/shared').get()).exists, false);
  });
});
