import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

import { Timestamp } from 'firebase-admin/firestore';

import { fetchDueLinks, fetchSource, nextFetchAt, parseContent, setLinkSource } from '../src/churchLink.js';
import { caller, clearFirestore, db, deps, fakeFetch, rejectsWith, seedChurch, setNow, type FakeResponse } from './support.js';

const SRC = 'https://feed.example/today.json';
const good = { title: '今日經文', body: '耶和華是我的牧者', link: 'https://feed.example/1004' };

function withFetch(routes: Record<string, FakeResponse>) {
  const f = fakeFetch(routes);
  return { d: { ...deps, fetch: f.fetch }, requests: f.requests };
}

async function church(cid = 'C1', extra: Record<string, unknown> = {}) {
  await seedChurch(cid, { pastor: 'admin', mei: 'staff' }, extra);
  await db.doc(`churches/${cid}/settings/link`).set({ title: '教會官網', body: '', url: 'https://grace.example' });
}

const content = async (cid = 'C1') => (await db.doc(`churches/${cid}/settings/linkContent`).get()).data();
const schedule = async (cid = 'C1') => (await db.doc(`linkSources/${cid}`).get()).data();

beforeEach(async () => {
  await clearFirestore();
  setNow(new Date('2026-10-04T03:00:00+08:00'));
});

describe('fetching a content source', () => {
  test('a JSON {title, body, link} is cut to the church link limits', async () => {
    const { d } = withFetch({ [SRC]: { body: { title: '題'.repeat(40), body: '文'.repeat(200), link: 'https://x.example' } } });
    const r = await fetchSource(d, SRC);
    assert.ok(r.ok);
    assert.equal([...r.content.title].length, 30);
    assert.equal([...r.content.body].length, 120);
    assert.equal(r.content.link, 'https://x.example');
  });

  test('the cut counts characters as a person does and never splits one', () => {
    const c = parseContent({ title: '👍🏽'.repeat(40), body: '🇹🇼'.repeat(200) })!;
    assert.equal(c.title, '👍🏽'.repeat(30));
    assert.equal(c.body, '🇹🇼'.repeat(120));
  });

  test('the request is a plain GET', async () => {
    const { d, requests } = withFetch({ [SRC]: { body: good } });
    await fetchSource(d, SRC);
    assert.equal(requests[0].method, 'GET');
  });

  test('times out after 5 seconds', async () => {
    const { d } = withFetch({ [SRC]: { body: good, delayMs: 6000 } });
    const started = Date.now();
    assert.deepEqual(await fetchSource(d, SRC), { ok: false, error: 'timeout' });
    assert.ok(Date.now() - started < 5800);
  });

  test('refuses more than 64KB', async () => {
    const big = JSON.stringify({ title: 'x', body: 'y'.repeat(70 * 1024) });
    const { d } = withFetch({ [SRC]: { body: big } });
    assert.deepEqual(await fetchSource(d, SRC), { ok: false, error: 'tooLarge' });
  });

  test('wrong shapes are a format error', async () => {
    for (const body of ['<html>daily bible</html>', '[]', '{"body": "no title"}', '{"title": "  "}', '{"title": "x", "body": 3}']) {
      const { d } = withFetch({ [SRC]: { body } });
      assert.deepEqual(await fetchSource(d, SRC), { ok: false, error: 'badFormat' }, body);
    }
  });

  test('only https, also after a redirect', async () => {
    const { d } = withFetch({
      [SRC]: { redirect: 'http://plain.example/feed' },
      'https://moved.example/a': { redirect: 'https://moved.example/b' },
      'https://moved.example/b': { body: good },
    });
    assert.deepEqual(await fetchSource(d, 'http://feed.example/x'), { ok: false, error: 'notHttps' });
    assert.deepEqual(await fetchSource(d, SRC), { ok: false, error: 'notHttps' });
    assert.ok((await fetchSource(d, 'https://moved.example/a')).ok);
  });

  test('HTTP errors and dead hosts are reported, never thrown', async () => {
    const { d } = withFetch({ [SRC]: { status: 503 } });
    assert.deepEqual(await fetchSource(d, SRC), { ok: false, error: 'http', status: 503 });
    assert.deepEqual(await fetchSource(d, 'https://nowhere.example/'), { ok: false, error: 'network' });
  });

  test('a link that is not https is dropped', () => {
    assert.equal(parseContent({ title: 't', link: 'javascript:alert(1)' })!.link, null);
    assert.equal(parseContent({ title: 't' })!.body, '');
  });
});

describe('when sources run', () => {
  test('today at the time if still ahead and not run yet, else tomorrow', () => {
    const at3 = new Date('2026-10-04T03:00:00+08:00');
    assert.equal(nextFetchAt(at3, 270, false).toISOString(), new Date('2026-10-04T04:30:00+08:00').toISOString());
    assert.equal(nextFetchAt(at3, 270, true).toISOString(), new Date('2026-10-05T04:30:00+08:00').toISOString());
    assert.equal(nextFetchAt(at3, 120, false).toISOString(), new Date('2026-10-05T02:00:00+08:00').toISOString());
  });
});

describe('setLinkSource', () => {
  test('saving a source fetches it at once and returns the result', async () => {
    await church();
    const { d } = withFetch({ [SRC]: { body: good } });
    const r = await setLinkSource(d, caller('pastor'), { churchId: 'C1', source: SRC, fetchMinute: 300 });
    assert.deepEqual(r, { ok: true, content: good });
    const c = await content();
    assert.equal(c!.title, '今日經文');
    assert.equal(c!.source, SRC);
    assert.equal(c!.error, null);
    const link = (await db.doc('churches/C1/settings/link').get()).data()!;
    assert.equal(link.source, SRC);
    assert.equal(link.fetchMinute, 300);
    assert.equal((await schedule())!.nextAt.toDate().toISOString(), new Date('2026-10-05T05:00:00+08:00').toISOString());
  });

  test('a failed first fetch is returned with its reason and recorded', async () => {
    await church();
    const { d } = withFetch({ [SRC]: { body: 'not json' } });
    const r = await setLinkSource(d, caller('pastor'), { churchId: 'C1', source: SRC, fetchMinute: 270 });
    assert.deepEqual(r, { ok: false, error: 'badFormat', status: null });
    assert.equal((await content())!.error, 'badFormat');
  });

  test('a new source that fails does not show the old source’s content', async () => {
    await church();
    const OTHER = 'https://other.example/feed.json';
    const { d } = withFetch({ [SRC]: { body: good }, [OTHER]: { status: 404 } });
    await setLinkSource(d, caller('pastor'), { churchId: 'C1', source: SRC, fetchMinute: 270 });
    await setLinkSource(d, caller('pastor'), { churchId: 'C1', source: OTHER, fetchMinute: 270 });
    const c = await content();
    assert.equal(c!.source, OTHER);
    assert.equal(c!.title, undefined);
    assert.equal(c!.error, 'http');
    assert.equal(c!.errorStatus, 404);
  });

  test('changing only the time fetches nothing and moves the next run', async () => {
    await church();
    const { d, requests } = withFetch({ [SRC]: { body: good } });
    await setLinkSource(d, caller('pastor'), { churchId: 'C1', source: SRC, fetchMinute: 270 });
    await setLinkSource(d, caller('pastor'), { churchId: 'C1', source: SRC, fetchMinute: 600 });
    assert.equal(requests.length, 1);
    assert.equal((await schedule())!.nextAt.toDate().toISOString(), new Date('2026-10-05T10:00:00+08:00').toISOString(), 'it ran today');
  });

  test('clearing the source stops it and drops the content', async () => {
    await church();
    const { d } = withFetch({ [SRC]: { body: good } });
    await setLinkSource(d, caller('pastor'), { churchId: 'C1', source: SRC, fetchMinute: 270 });
    await setLinkSource(d, caller('pastor'), { churchId: 'C1', source: null });
    assert.equal(await content(), undefined);
    assert.equal(await schedule(), undefined);
    assert.equal((await db.doc('churches/C1/settings/link').get()).get('source'), undefined);
  });

  test('admins of that church only; https only; times on the quarter hour', async () => {
    await church();
    await seedChurch('C2', { other: 'admin' });
    const { d } = withFetch({ [SRC]: { body: good } });
    await rejectsWith(setLinkSource(d, caller('mei'), { churchId: 'C1', source: SRC }), 'permissionDenied');
    await rejectsWith(setLinkSource(d, caller('other'), { churchId: 'C1', source: SRC }), 'permissionDenied');
    await rejectsWith(setLinkSource(d, caller('pastor'), { churchId: 'C1', source: 'http://feed.example' }), 'unknown');
    await rejectsWith(setLinkSource(d, caller('pastor'), { churchId: 'C1', source: SRC, fetchMinute: 280 }), 'unknown');
  });
});

describe('the 15-minute schedule', () => {
  async function scheduled(cid: string, fetchMinute: number, extra: Record<string, unknown> = {}) {
    await db.doc(`churches/${cid}/settings/link`).update({ source: SRC, fetchMinute });
    await db.doc(`linkSources/${cid}`).set({
      source: SRC,
      fetchMinute,
      lastDay: '2026-10-03',
      nextAt: Timestamp.fromDate(nextFetchAt(new Date('2026-10-03T23:00:00+08:00'), fetchMinute, false)),
      ...extra,
    });
  }

  test('fetches only once its time has come, and once a day', async () => {
    await church();
    await scheduled('C1', 270);
    const { d, requests } = withFetch({ [SRC]: { body: good } });
    setNow(new Date('2026-10-04T04:15:00+08:00'));
    assert.equal(await fetchDueLinks(d), 0, 'not yet');
    setNow(new Date('2026-10-04T04:30:00+08:00'));
    assert.equal(await fetchDueLinks(d), 1);
    setNow(new Date('2026-10-04T04:45:00+08:00'));
    assert.equal(await fetchDueLinks(d), 0, 'not twice the same day');
    assert.equal(requests.length, 1);
    assert.equal((await content())!.title, '今日經文');
    setNow(new Date('2026-10-05T04:30:00+08:00'));
    assert.equal(await fetchDueLinks(d), 1, 'again the next day');
  });

  test('a failure keeps the last content and records why', async () => {
    await church();
    await scheduled('C1', 270);
    await db.doc('churches/C1/settings/linkContent').set({ ...good, source: SRC, fetchedAt: Timestamp.now(), error: null });
    const { d } = withFetch({ [SRC]: { delayMs: 6000 } });
    setNow(new Date('2026-10-04T04:30:00+08:00'));
    await fetchDueLinks(d);
    const c = await content();
    assert.equal(c!.title, '今日經文');
    assert.equal(c!.error, 'timeout');
  });

  test('suspended churches are skipped; removed links are dropped', async () => {
    await church('Closed', { status: 'suspended' });
    await scheduled('Closed', 270);
    await church('Gone');
    await scheduled('Gone', 270);
    await db.doc('churches/Gone/settings/link').delete();
    const { d, requests } = withFetch({ [SRC]: { body: good } });
    setNow(new Date('2026-10-04T05:00:00+08:00'));
    assert.equal(await fetchDueLinks(d), 0);
    assert.equal(requests.length, 0);
    assert.equal(await schedule('Gone'), undefined);
    assert.equal((await schedule('Closed'))!.lastDay, '2026-10-04', 'waits for tomorrow');
  });
});
