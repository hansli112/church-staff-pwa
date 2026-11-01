import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

import { onMemberDeleted } from '../src/triggers.js';
import { askUnavailable } from '../src/unavailable.js';
import { memoryGoogle } from '../src/memoryGoogle.js';
import { caller, clearFirestore, db, deps, fakePush, rejectsWith, seedChurch, setNow } from './support.js';

const appUrl = 'https://app.example';

beforeEach(async () => {
  await clearFirestore();
  setNow(new Date('2026-11-01T10:00:00+08:00'));
});

/** 恩典堂: 陳負責人 leads 主日崇拜; 美玉 plays there, 志豪 ushers, 小林 is in 青年崇拜. */
async function church() {
  await seedChurch('C1', { lead: 'staff', mei: 'staff', hao: 'staff', lin: 'staff' }, { name: '恩典堂' });
  await db.doc('churches/C1/settings/services').set({ services: [], ids: ['sunday', 'youth'] });
  await db.doc('churches/C1/members/lead').update({ leadTypes: ['sunday'], zones: [{ serviceType: 'sunday', duties: ['司琴'] }] });
  await db.doc('churches/C1/members/mei').update({ zones: [{ serviceType: 'sunday', duties: ['司琴'] }] });
  await db.doc('churches/C1/members/hao').update({ zones: [{ serviceType: 'sunday', duties: ['招待'] }] });
  await db.doc('churches/C1/members/lin').update({ zones: [{ serviceType: 'youth', duties: ['司琴'] }] });
  for (const uid of ['lead', 'mei', 'hao', 'lin']) await db.doc(`users/${uid}`).set({ fcm: { phone: `tok-${uid}` } });
}

describe('請同工填 (askUnavailable)', () => {
  test('one push to each on the lists of what they arrange, opening the page to fill in', async () => {
    await church();
    const { messaging, sent } = fakePush();
    const r = await askUnavailable({ ...deps, messaging, appUrl }, caller('lead'), { churchId: 'C1', serviceId: 'sunday', from: '2026-12', to: '2027-01' });
    assert.deepEqual(r, { people: 2 });
    assert.deepEqual(sent.flatMap((p) => p.tokens.map((t) => [t, p.title, p.body, p.link])).sort(), [
      ['tok-hao', '恩典堂', '請填 12 月到 1 月不能服事的日子', '/c/C1?to=%2Fme%2Funavailable'],
      ['tok-mei', '恩典堂', '請填 12 月到 1 月不能服事的日子', '/c/C1?to=%2Fme%2Funavailable'],
    ]);
    const asked = await db.doc('churches/C1/unavailableAsks/sunday').get();
    assert.deepEqual([asked.get('by'), asked.get('from'), asked.get('to')], ['lead', '2026-12', '2027-01']);
    assert.ok(asked.get('at'));
  });

  test('one month is said once, in their language', async () => {
    await church();
    await db.doc('users/mei').update({ appLocale: 'en' });
    const { messaging, sent } = fakePush();
    await askUnavailable({ ...deps, messaging, appUrl }, caller('lead'), { churchId: 'C1', serviceId: 'sunday', from: '2026-12', to: '2026-12' });
    assert.deepEqual(sent.map((p) => p.body).sort(), ['Please mark the days you can\'t serve in December', '請填 12 月不能服事的日子']);
  });

  test('only who arranges the service asks, and only for months in order', async () => {
    await church();
    const { messaging } = fakePush();
    const ask = (uid: string, data: Record<string, unknown>) =>
      askUnavailable({ ...deps, messaging, appUrl }, caller(uid), { churchId: 'C1', serviceId: 'sunday', from: '2026-12', to: '2027-01', ...data });
    await rejectsWith(ask('mei', {}), 'permissionDenied');
    await rejectsWith(ask('lead', { serviceId: 'youth' }), 'permissionDenied');
    await rejectsWith(ask('lead', { from: '2027-02' }), 'unknown');
    await rejectsWith(ask('lead', { to: '2027-13' }), 'unknown');
    await rejectsWith(ask('lead', { extra: 1 }), 'unknown');
  });
});

test('leaving the church takes their 不能服事的日子 with them', async () => {
  await church();
  await db.doc('churches/C1/unavailable/mei').set({ spans: [{ from: '2026-12-20', to: '2026-12-27', note: '出國' }] });
  const mei = await db.doc('churches/C1/members/mei').get();
  await mei.ref.delete();
  const { messaging } = fakePush();
  const cal = { ...deps, secretKey: '', google: memoryGoogle().google, config: { clientId: '', clientSecret: '', redirectUri: '', appUrl, tokenKey: '' } };
  await onMemberDeleted({ ...cal, messaging, appUrl }, 'C1', mei, 'mei');
  assert.equal((await db.doc('churches/C1/unavailable/mei').get()).exists, false);
});
