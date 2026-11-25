import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

import { Timestamp } from 'firebase-admin/firestore';

import { collectWeeklyReport, lastSunday, sendWeeklyReport, weeklyMail, type Analytics } from '../src/weeklyReport.js';
import { clearFirestore, db, deps, fakeFetch, seedChurch, setNow, type SeenRequest } from './support.js';

const ts = (iso: string) => Timestamp.fromDate(new Date(iso));
const READER = 'reader@demo.iam.gserviceaccount.com';
const analytics: Analytics = {
  accessToken: async () => 'runtime-token',
  reader: READER,
  ga4Property: '42',
  gscSite: 'sc-domain:example.com',
  project: 'demo-martha',
};

// Monday 23 November: the week is 16–22 November, the one before 9–15.
beforeEach(async () => {
  await clearFirestore();
  setNow(new Date('2026-11-23T09:00:00+08:00'));
  for (const [uid, at] of Object.entries({
    old: '2026-10-01T10:00:00+08:00',
    lastWeek: '2026-11-10T10:00:00+08:00',
    mon: '2026-11-16T00:30:00+08:00',
    fri1: '2026-11-20T12:00:00+08:00',
    fri2: '2026-11-20T23:59:00+08:00',
    today: '2026-11-23T08:00:00+08:00', // after the week: not counted
  })) await db.doc(`users/${uid}`).set({ name: uid, createdAt: ts(at) });

  await seedChurch('new', { mon: 'admin', fri1: 'member' }, { name: '新的教會', createdAt: ts('2026-11-17T10:00:00+08:00') });
  await seedChurch('quiet', { old: 'admin' }, { name: '停下來的教會', createdAt: ts('2026-10-01T10:00:00+08:00') });
  await seedChurch('synced', { lastWeek: 'admin' }, { name: '只有同步', createdAt: ts('2026-10-01T10:00:00+08:00') });
  await seedChurch('later', { today: 'admin' }, { name: '這週一才建', createdAt: ts('2026-11-23T08:30:00+08:00') });
  await seedChurch('gone', { fri2: 'admin' }, { name: '刪掉的', status: 'deleted', createdAt: ts('2026-11-18T10:00:00+08:00') });
  const roster = (cid: string, id: string, at: string, via: string) =>
    db.doc(`churches/${cid}/rosters/${id}`).set({ updatedAt: ts(at), via });
  await roster('new', 'r1', '2026-11-18T10:00:00+08:00', 'app');
  await roster('new', 'r2', '2026-11-22T23:00:00+08:00', 'plan');
  await roster('quiet', 'r1', '2026-11-12T10:00:00+08:00', 'app');
  await roster('synced', 'r1', '2026-11-19T10:00:00+08:00', 'calendar');
  await roster('new', 'r3', '2026-11-23T08:00:00+08:00', 'app'); // after the week

  await db.doc('stats/2026-11-22').set({ date: '2026-11-22', users_active_7d: 5 });
  await db.doc('stats/2026-11-15').set({ date: '2026-11-15', users_active_7d: 2 });
  await db.doc('ecpayOrders/20261119aaaa').set({ status: 'paid', amount: 300, paidAt: ts('2026-11-19T10:00:00+08:00') });
  await db.doc('ecpayOrders/20261110bbbb').set({ status: 'paid', amount: 100, paidAt: ts('2026-11-10T10:00:00+08:00') });
  await db.doc('ecpayOrders/20261120cccc').set({ status: 'pending', amount: 500, createdAt: ts('2026-11-20T10:00:00+08:00') });
});

/** GA4 rows: [dimension values..., date range] -> metric values. */
function gaRows(rows: [string[], number[]][]) {
  return { rows: rows.map(([dims, values]) => ({ dimensionValues: dims.map((value) => ({ value })), metricValues: values.map((v) => ({ value: String(v) })) })) };
}
function googleRoutes() {
  return {
    [`https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${READER}:generateAccessToken`]: { body: { accessToken: 'reader-token' } },
    'https://analyticsdata.googleapis.com/v1beta/properties/42:runReport': (req: SeenRequest) => {
      const dim = JSON.parse(req.body).dimensions[0]?.name;
      if (!dim) return { body: gaRows([[['date_range_0'], [120]], [['date_range_1'], [40]]]) };
      if (dim === 'platform') return { body: gaRows([[['iOS', 'date_range_0'], [70, 30]], [['web', 'date_range_0'], [50, 20]], [['iOS', 'date_range_1'], [30, 5]]]) };
      if (dim === 'eventName') return { body: gaRows([[['church_create', 'date_range_0'], [9]], [['church_create', 'date_range_1'], [2]]]) };
      if (dim === 'languageCode') {
        assert.deepEqual(JSON.parse(req.body).dateRanges[1], { startDate: '2026-10-26', endDate: '2026-11-22' }, 'the last 4 weeks');
        return { body: gaRows([
          [['zh-tw', 'date_range_0'], [20]], [['zh-hant-hk', 'date_range_0'], [5]], [['zh-tw', 'date_range_1'], [60]],
          [['zh-cn', 'date_range_1'], [30]], [['en-us', 'date_range_0'], [3]], [['en-gb', 'date_range_1'], [8]],
          [['it-it', 'date_range_0'], [1]], [['it-it', 'date_range_1'], [4]], [['ja-jp', 'date_range_1'], [2]],
          [['(not set)', 'date_range_1'], [1]],
        ]) };
      }
      if (dim === 'countryId') return { body: gaRows([[['TW', 'date_range_0'], [30]], [['HK', 'date_range_0'], [12]], [['(not set)', 'date_range_0'], [1]]]) };
      return { body: gaRows([[['(direct)', 'date_range_0'], [40]], [['m.facebook.com', 'date_range_0'], [3]], [['facebook.com', 'date_range_0'], [2]]]) };
    },
    'https://searchconsole.googleapis.com/webmasters/v3/sites/sc-domain%3Aexample.com/searchAnalytics/query': (req: SeenRequest) => {
      const q = JSON.parse(req.body);
      if (q.dimensions.length) return { body: { rows: [{ keys: ['馬大別忙'], clicks: 20, impressions: 25, ctr: 0.8, position: 1.2 }] } };
      return { body: { rows: [q.startDate === '2026-11-16' ? { clicks: 80, impressions: 130, ctr: 0.62, position: 2.9 } : { clicks: 1, impressions: 10, ctr: 0.1, position: 13 }] } };
    },
  };
}

describe('週報', () => {
  test('the week is the last full Monday to Sunday in Taipei', () => {
    assert.equal(lastSunday(new Date('2026-11-23T09:00:00+08:00')), '2026-11-22');
    assert.equal(lastSunday(new Date('2026-11-22T23:00:00+08:00')), '2026-11-15'); // Sunday itself is not over
    assert.equal(lastSunday(new Date('2026-11-25T12:00:00+08:00')), '2026-11-22');
  });

  test('counts the week from Firestore against the week before', async () => {
    const r = await collectWeeklyReport({ ...deps, analytics: null });
    assert.deepEqual(r.now, { from: '2026-11-16', to: '2026-11-22' });
    assert.deepEqual(r.newUsers, [3, 1]);
    assert.deepEqual(r.newUsersByDay.slice(7), [1, 0, 0, 0, 2, 0, 0]);
    assert.deepEqual(r.users, [5, 2]);
    assert.deepEqual(r.churches, [3, 2], 'active churches by the end of each week; not the deleted one or one made after');
    assert.deepEqual(r.openedApp, [5, 2]);
    assert.deepEqual(r.editing, [1, 1], 'the calendar following Google does not count');
    assert.equal(r.fresh.count, 1);
    assert.deepEqual([r.fresh.invited, r.fresh.planned, r.fresh.tenPlus], [1, 1, 0]);
    assert.deepEqual(r.busiest, [{ name: '新的教會', members: 2, edits: 2, editsBefore: 0 }]);
    assert.deepEqual(r.quiet.map((c) => c.name), ['停下來的教會']);
    assert.deepEqual(r.paid, { count: 1, amount: 300 });
    assert.equal(r.ga, null);
    assert.equal(r.gsc, null);
  });

  test('reads GA4 and Search Console as the reader, with a token of its own', async () => {
    const f = fakeFetch(googleRoutes());
    const r = await collectWeeklyReport({ ...deps, fetch: f.fetch, analytics });
    const iam = f.requests.find((q) => q.url.includes('generateAccessToken'))!;
    assert.equal(iam.headers.authorization, 'Bearer runtime-token');
    assert.deepEqual(JSON.parse(iam.body).scope, ['https://www.googleapis.com/auth/analytics.readonly', 'https://www.googleapis.com/auth/webmasters.readonly']);
    for (const q of f.requests.filter((q) => !q.url.includes('generateAccessToken'))) {
      assert.equal(q.headers.authorization, 'Bearer reader-token');
      assert.equal(q.headers['x-goog-user-project'], 'demo-martha');
    }
    assert.deepEqual(r.ga!.active, [120, 40]);
    assert.deepEqual(r.ga!.platforms, [
      { label: 'iOS', active: [70, 30], fresh: [30, 5] },
      { label: 'Android', active: [0, 0], fresh: [0, 0] },
      { label: '網頁', active: [50, 0], fresh: [20, 0] },
    ]);
    assert.deepEqual(r.ga!.events[0], { label: '建立教會', count: [9, 2] });
    assert.deepEqual(r.ga!.countries, [{ name: '台灣', n: 30 }, { name: '香港', n: 12 }, { name: '其他', n: 1 }]);
    assert.deepEqual(r.ga!.sources, [{ name: '直接開啟', n: 40 }, { name: 'Facebook', n: 5 }]);
    assert.deepEqual(r.ga!.languages, [
      { name: '繁體中文', supported: true, n: [25, 60] },
      { name: '簡體中文', supported: true, n: [0, 30] },
      { name: '英文', supported: true, n: [3, 8] },
      { name: '義大利文', supported: false, n: [1, 4] },
      { name: '日文', supported: true, n: [0, 2] },
      { name: '其他', supported: true, n: [0, 1] },
    ]);
    assert.match(weeklyMail(r).html, /義大利文<span[^>]*>App 沒有/);
    assert.deepEqual(r.gsc!.now, { clicks: 80, impressions: 130, ctr: 0.62, position: 2.9 });
    assert.equal(r.gsc!.before.clicks, 1);
    assert.deepEqual(r.gsc!.queries, [{ query: '馬大別忙', clicks: 20, impressions: 25, position: 1.2 }]);
  });

  test('the mail leads with the new users and keeps names escaped', async () => {
    await db.doc('churches/new').update({ name: '<b>新的</b>教會' });
    const mail = weeklyMail(await collectWeeklyReport({ ...deps, analytics: null }));
    assert.equal(mail.subject, '馬大別忙週報 11月16日 – 22日：3 位新使用者');
    assert.match(mail.html, /&lt;b&gt;新的&lt;\/b&gt;教會/);
    assert.doesNotMatch(mail.html, /<svg|display:\s*(flex|grid)/, 'Gmail shows neither');
    assert.doesNotMatch(mail.html, /Google 搜尋|App 與網站/, 'no GA4 or Search Console where they are not read');
    assert.match(mail.text, /停下來的教會/);
  });

  test('sends one mail through Resend', async () => {
    let sent: SeenRequest | undefined;
    const f = fakeFetch({
      'https://api.resend.com/emails': (req) => {
        sent = req;
        return { body: { id: 'm1' } };
      },
    });
    await sendWeeklyReport({ ...deps, fetch: f.fetch, analytics: null, resend: { apiKey: 'k', from: 'r@example.com', to: 'me@example.com' } });
    assert.equal(sent!.headers.authorization, 'Bearer k');
    const body = JSON.parse(sent!.body);
    assert.deepEqual(body.to, ['me@example.com']);
    assert.equal(body.subject, '馬大別忙週報 11月16日 – 22日：3 位新使用者');
    assert.match(body.html, /新教會 1 間/);
  });

  test('a mail Resend refuses fails the run', async () => {
    const f = fakeFetch({ 'https://api.resend.com/emails': { status: 403, body: { message: 'domain not verified' } } });
    await assert.rejects(
      sendWeeklyReport({ ...deps, fetch: f.fetch, analytics: null, resend: { apiKey: 'k', from: 'r@example.com', to: 'me@example.com' } }),
      /Resend: 403/,
    );
  });
});
