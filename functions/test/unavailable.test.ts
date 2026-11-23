import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

import { onMemberDeleted } from '../src/triggers.js';
import { askUnavailable, remindUnavailable, saveUnavailableDays, sendUnavailableDays } from '../src/unavailable.js';
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

describe('通知同工填 (askUnavailable)', () => {
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
    assert.deepEqual([...asked.get('told')].sort(), ['hao', 'mei']);
    assert.ok(asked.get('at'));
    const mei = await db.doc('churches/C1/unavailable/mei').get();
    assert.deepEqual([mei.get('asked.from'), mei.get('asked.to')], ['2026-12', '2027-01'], 'told in their own');
    assert.equal(mei.get('asked.at').toMillis(), asked.get('at').toMillis());
  });

  test('asked again before sending, the months stretch over both; once sent, only the new', async () => {
    await church();
    await db.doc('churches/C1/members/lead').update({ leadTypes: ['sunday', 'youth'] });
    await db.doc('churches/C1/members/mei').update({ zones: [{ serviceType: 'sunday', duties: ['司琴'] }, { serviceType: 'youth', duties: ['司琴'] }] });
    const { messaging } = fakePush();
    const ask = (serviceId: string, from: string, to: string) =>
      askUnavailable({ ...deps, messaging, appUrl }, caller('lead'), { churchId: 'C1', serviceId, from, to });
    const asked = async () => {
      const d = await db.doc('churches/C1/unavailable/mei').get();
      return [d.get('asked.from'), d.get('asked.to')];
    };
    await ask('sunday', '2026-12', '2027-01');
    await ask('youth', '2027-01', '2027-03');
    assert.deepEqual(await asked(), ['2026-12', '2027-03']);
    await sendUnavailableDays(deps, caller('mei'), { churchId: 'C1' });
    await ask('youth', '2027-04', '2027-04');
    assert.deepEqual(await asked(), ['2027-04', '2027-04']);
  });

  test('stretched from this month on: months gone by are not asked again', async () => {
    await church();
    const { messaging } = fakePush();
    const ask = (from: string, to: string) =>
      askUnavailable({ ...deps, messaging, appUrl }, caller('lead'), { churchId: 'C1', serviceId: 'sunday', from, to });
    const asked = async () => {
      const d = await db.doc('churches/C1/unavailable/mei').get();
      return [d.get('asked.from'), d.get('asked.to')];
    };
    await ask('2026-11', '2027-01');
    setNow(new Date('2026-12-15T10:00:00+08:00'));
    await ask('2027-02', '2027-02');
    assert.deepEqual(await asked(), ['2026-12', '2027-02'], 'November is gone by');
    setNow(new Date('2027-03-15T10:00:00+08:00'));
    await ask('2027-04', '2027-04');
    assert.deepEqual(await asked(), ['2027-04', '2027-04'], 'all of the last is gone by');
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

describe('再通知 (remindUnavailable)', () => {
  test('one push again to those told who are still here and have not sent since', async () => {
    await church();
    await seedChurch('C1', { yu: 'staff' }, { name: '恩典堂' });
    await db.doc('churches/C1/members/yu').update({ zones: [{ serviceType: 'sunday', duties: ['招待'] }] });
    await db.doc('users/yu').set({ fcm: { phone: 'tok-yu' } });
    const first = fakePush();
    await askUnavailable({ ...deps, messaging: first.messaging, appUrl }, caller('lead'), { churchId: 'C1', serviceId: 'sunday', from: '2026-12', to: '2027-01' });
    await sendUnavailableDays(deps, caller('mei'), { churchId: 'C1' });
    await db.doc('churches/C1/members/yu').delete();
    const { messaging, sent } = fakePush();
    const r = await remindUnavailable({ ...deps, messaging, appUrl }, caller('lead'), { churchId: 'C1', serviceId: 'sunday' });
    assert.deepEqual(r, { people: 1 });
    assert.deepEqual(sent.flatMap((p) => p.tokens.map((t) => [t, p.body])), [['tok-hao', '請填 12 月到 1 月不能服事的日子']]);
  });

  test('only who arranges the service, and only once asked', async () => {
    await church();
    const { messaging } = fakePush();
    const remind = (uid: string, data: Record<string, unknown> = {}) =>
      remindUnavailable({ ...deps, messaging, appUrl }, caller(uid), { churchId: 'C1', serviceId: 'sunday', ...data });
    await rejectsWith(remind('lead'), 'unknown');
    await askUnavailable({ ...deps, messaging, appUrl }, caller('lead'), { churchId: 'C1', serviceId: 'sunday', from: '2026-12', to: '2026-12' });
    await rejectsWith(remind('mei'), 'permissionDenied');
    await rejectsWith(remind('lead', { serviceId: 'youth' }), 'permissionDenied');
    await rejectsWith(remind('lead', { extra: 1 }), 'unknown');
  });

  test('an ask from before whom it told was kept has nobody to tell again', async () => {
    await church();
    const { messaging, sent } = fakePush();
    await db.doc('churches/C1/unavailableAsks/sunday').set({ at: new Date(), by: 'lead', from: '2026-12', to: '2026-12' });
    await rejectsWith(
      remindUnavailable({ ...deps, messaging, appUrl }, caller('lead'), { churchId: 'C1', serviceId: 'sunday' }),
      'unknown',
    );
    assert.deepEqual(sent, []);
  });
});

describe('送出 (sendUnavailableDays)', () => {
  test('says when, keeping the days and what was asked; saving the days keeps when too', async () => {
    await church();
    const { messaging } = fakePush();
    await saveUnavailableDays(deps, caller('mei'), { churchId: 'C1', spans: [{ from: '2026-12-20', to: '2026-12-20', note: '' }] });
    await askUnavailable({ ...deps, messaging, appUrl }, caller('lead'), { churchId: 'C1', serviceId: 'sunday', from: '2026-12', to: '2026-12' });
    await sendUnavailableDays(deps, caller('mei'), { churchId: 'C1' });
    await saveUnavailableDays(deps, caller('mei'), { churchId: 'C1', spans: [] });
    const mei = await db.doc('churches/C1/unavailable/mei').get();
    assert.ok(mei.get('sentAt'));
    assert.equal(mei.get('asked.from'), '2026-12');
    assert.deepEqual(mei.get('spans'), []);
    await rejectsWith(sendUnavailableDays(deps, caller('mei'), { churchId: 'C1', extra: 1 }), 'unknown');
    await rejectsWith(sendUnavailableDays(deps, caller('stranger'), { churchId: 'C1' }), 'permissionDenied');
  });
});

describe('saveUnavailableDays', () => {
  const save = (spans: unknown, uid = 'mei') => saveUnavailableDays(deps, caller(uid), { churchId: 'C1', spans });

  test("a member's own, in order, each reason trimmed", async () => {
    await church();
    await save([{ from: '2026-12-20', to: '2026-12-27', note: ' 出國 ' }, { from: '2026-11-15', to: '2026-11-15', note: '' }]);
    assert.deepEqual((await db.doc('churches/C1/unavailable/mei').get()).get('spans'), [
      { from: '2026-11-15', to: '2026-11-15', note: '' },
      { from: '2026-12-20', to: '2026-12-27', note: '出國' },
    ]);
  });

  test('refuses what the page never sends: a stretch backwards, a long reason, too many, a stranger', async () => {
    await church();
    const day = { from: '2026-11-15', to: '2026-11-15', note: '' };
    await rejectsWith(save([{ ...day, to: '2026-11-14' }]), 'unknown');
    await rejectsWith(save([{ ...day, from: '2026-11-31x' }]), 'unknown');
    await rejectsWith(save([{ ...day, note: '一'.repeat(31) }]), 'unknown');
    await rejectsWith(save([{ ...day, extra: 1 }]), 'unknown');
    await rejectsWith(save(Array(101).fill(day)), 'unknown');
    await save([{ ...day, note: '一'.repeat(30) }]);
    await rejectsWith(save([day], 'stranger'), 'permissionDenied');
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
