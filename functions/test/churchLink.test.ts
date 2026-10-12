import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

import { Timestamp } from 'firebase-admin/firestore';

import { fetchDueLinks, fetchSource, nextFetchAt, parseContent, setLinkSource } from '../src/churchLink.js';
import { caller, clearFirestore, db, deps, fakeFetch, rejectsWith, seedChurch, setNow, type FakeResponse } from './support.js';

const SRC = 'https://feed.example/today.json';
const good = { date: '2026-10-04', title: '今日經文', body: '耶和華是我的牧者', link: 'https://feed.example/1004' };

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
  test('parseContent accepts only the required dated JSON contract with a real Gregorian date and HTTPS original link', () => {
    const valid = { date: '2026-10-04', title: '今日經文', body: '', link: 'https://feed.example/original' };
    assert.deepEqual(parseContent(valid), valid);
    assert.deepEqual(parseContent({ ...valid, date: '2024-02-29' }), { ...valid, date: '2024-02-29' });
    assert.deepEqual(parseContent({ ...valid, date: '2000-02-29' }), { ...valid, date: '2000-02-29' });
    for (const field of ['date', 'title', 'body', 'link']) {
      const missing = { ...valid } as Record<string, unknown>;
      delete missing[field];
      assert.equal(parseContent(missing), null, `missing ${field}`);
    }
    for (const date of ['2026-02-29', '1900-02-29', '2026-04-31', '2026-00-04', '2026-13-04', '0000-01-01', '2026-1-04', '2026-10-04T00:00:00Z']) {
      assert.equal(parseContent({ ...valid, date }), null, date);
    }
    for (const raw of [
      { ...valid, rawRange: 'legacy' }, { title: '舊格式', rawRange: '創世記' }, '<html>經文</html>',
      { ...valid, body: null }, { ...valid, title: ' ' },
      { ...valid, link: null }, { ...valid, link: 'http://feed.example/original' },
      { ...valid, link: 'javascript:alert(1)' },
    ]) assert.equal(parseContent(raw), null, JSON.stringify(raw));
  });
  test('a JSON {date, title, body, link} is cut to the church link limits', async () => {
    const { d } = withFetch({ [SRC]: { body: { ...good, title: '題'.repeat(40), body: '文'.repeat(200), link: 'https://x.example' } } });
    const r = await fetchSource(d, SRC, 'Asia/Taipei');
    assert.ok(r.ok);
    assert.equal([...r.content.title].length, 30);
    assert.equal([...r.content.body].length, 120);
    assert.equal(r.content.link, 'https://x.example');
  });

  test('the cut counts characters as a person does and never splits one', () => {
    const c = parseContent({ ...good, title: '👍🏽'.repeat(40), body: '🇹🇼'.repeat(200) })!;
    assert.equal(c.title, '👍🏽'.repeat(30));
    assert.equal(c.body, '🇹🇼'.repeat(120));
  });

  test('the request is a plain GET', async () => {
    const { d, requests } = withFetch({ [SRC]: { body: good } });
    await fetchSource(d, SRC, 'Asia/Taipei');
    assert.equal(requests[0].method, 'GET');
  });

  test('times out after 5 seconds', async () => {
    const { d } = withFetch({ [SRC]: { body: good, delayMs: 6000 } });
    const started = Date.now();
    assert.deepEqual(await fetchSource(d, SRC, 'Asia/Taipei'), { ok: false, error: 'timeout' });
    assert.ok(Date.now() - started < 5800);
  });

  test('refuses more than 64KB', async () => {
    const big = JSON.stringify({ title: 'x', body: 'y'.repeat(70 * 1024) });
    const { d } = withFetch({ [SRC]: { body: big } });
    assert.deepEqual(await fetchSource(d, SRC, 'Asia/Taipei'), { ok: false, error: 'tooLarge' });
  });

  test('wrong shapes are a format error', async () => {
    for (const body of ['<html>daily bible</html>', '[]', '{"body": "no title"}', '{"title": "  "}', '{"title": "x", "body": 3}']) {
      const { d } = withFetch({ [SRC]: { body } });
      assert.deepEqual(await fetchSource(d, SRC, 'Asia/Taipei'), { ok: false, error: 'badFormat' }, body);
    }
  });

  test('only https, also after a redirect', async () => {
    const { d } = withFetch({
      [SRC]: { redirect: 'http://plain.example/feed' },
      'https://moved.example/a': { redirect: 'https://moved.example/b' },
      'https://moved.example/b': { body: good },
    });
    assert.deepEqual(await fetchSource(d, 'http://feed.example/x', 'Asia/Taipei'), { ok: false, error: 'notHttps' });
    assert.deepEqual(await fetchSource(d, SRC, 'Asia/Taipei'), { ok: false, error: 'notHttps' });
    assert.ok((await fetchSource(d, 'https://moved.example/a', 'Asia/Taipei')).ok);
  });

  test('HTTP errors and dead hosts are reported, never thrown', async () => {
    const { d } = withFetch({ [SRC]: { status: 503 } });
    assert.deepEqual(await fetchSource(d, SRC, 'Asia/Taipei'), { ok: false, error: 'http', status: 503 });
    assert.deepEqual(await fetchSource(d, 'https://nowhere.example/', 'Asia/Taipei'), { ok: false, error: 'network' });
  });

  test('an invalid original link or missing summary is a format error, never a manual-link fallback', () => {
    assert.equal(parseContent({ ...good, link: 'javascript:alert(1)' }), null);
    assert.equal(parseContent({ date: good.date, title: 't', link: good.link }), null);
  });
});

describe('when sources run', () => {
  test('today at the time if still ahead and not run yet, else tomorrow', () => {
    const at3 = new Date('2026-10-04T03:00:00+08:00');
    assert.equal(nextFetchAt(at3, 270, false, 'Asia/Taipei').toISOString(), new Date('2026-10-04T04:30:00+08:00').toISOString());
    assert.equal(nextFetchAt(at3, 270, true, 'Asia/Taipei').toISOString(), new Date('2026-10-05T04:30:00+08:00').toISOString());
    assert.equal(nextFetchAt(at3, 120, false, 'Asia/Taipei').toISOString(), new Date('2026-10-05T02:00:00+08:00').toISOString());
  });

  test("at the time on the church's clock, summer time or not", () => {
    const la = 'America/Los_Angeles';
    // 3:00 on 31 October in Los Angeles; the clocks go back the next night.
    const at3 = new Date('2026-10-31T03:00:00-07:00');
    assert.equal(nextFetchAt(at3, 270, false, la).toISOString(), new Date('2026-10-31T04:30:00-07:00').toISOString());
    assert.equal(nextFetchAt(new Date('2026-10-31T05:00:00-07:00'), 270, false, la).toISOString(), new Date('2026-11-01T04:30:00-08:00').toISOString());
    // Late the night before each change: the next day, not two on or the same.
    assert.equal(nextFetchAt(new Date('2026-03-07T23:30:00-08:00'), 23 * 60 + 15, true, la).toISOString(), new Date('2026-03-08T23:15:00-07:00').toISOString());
    assert.equal(nextFetchAt(new Date('2026-10-31T23:30:00-07:00'), 23 * 60 + 15, true, la).toISOString(), new Date('2026-11-01T23:15:00-08:00').toISOString());
  });

  test("a source's date is the church's today", async () => {
    const d = { now: () => new Date('2026-10-03T16:30:00Z'), fetch: fakeFetch({ [SRC]: { body: { ...good, date: '2026-10-03' } } }).fetch };
    assert.equal((await fetchSource(d, SRC, 'Asia/Taipei')).ok, false, 'already the 4th in Taipei');
    assert.equal((await fetchSource(d, SRC, 'America/New_York')).ok, true);
  });
});

describe('setLinkSource', () => {
  test('an admin explicitly retries the stored source without resaving static fields or accepting a client source override', async () => {
    await church();
    const failed = withFetch({ [SRC]: { status: 503 } });
    assert.deepEqual(await setLinkSource(failed.d, caller('pastor'), { churchId: 'C1', source: SRC, fetchMinute: 270 }), { ok: false, error: 'http', status: 503 });
    assert.equal((await schedule())!.lastDay, undefined);
    assert.equal((await schedule())!.lastAttemptDay, '2026-10-04');
    const before = (await db.doc('churches/C1/settings/link').get()).data();
    const { d, requests } = withFetch({ [SRC]: { body: good } });
    assert.deepEqual(await setLinkSource(d, caller('pastor'), { churchId: 'C1', refresh: true }), { ok: true, content: { ...good, source: SRC, fetchedAt: Date.parse('2026-10-04T03:00:00+08:00') } });
    assert.equal(requests.length, 1, 'explicit retry is allowed on the same day');
    assert.equal(requests[0].url, SRC, 'the current server source is authoritative');
    assert.deepEqual((await db.doc('churches/C1/settings/link').get()).data(), before, 'static fields and source/time are not rewritten');
    assert.equal((await schedule())!.lastDay, '2026-10-04');
    assert.equal((await content())!.error, null);
    for (const extra of [{ source: 'https://arbitrary.example/' }, { fetchMinute: 900 }, { title: '改名' }, { url: 'https://arbitrary.example/' }]) {
      await rejectsWith(setLinkSource(d, caller('pastor'), { churchId: 'C1', refresh: true, ...extra }), 'unknown');
    }
    await rejectsWith(setLinkSource(d, caller('mei'), { churchId: 'C1', refresh: true }), 'permissionDenied');
    assert.equal(requests.length, 1, 'refused requests do not fetch');
  });
  test('a pending admin fetch cannot refill content or overwrite schedules after its source, settings or authorization epoch changes', async () => {
    for (const change of ['source', 'clear', 'sourceABA', 'time', 'removedLink', 'suspended', 'deleted', 'demoted', 'removedMember']) {
      await clearFirestore();
      await church();
      const other = 'https://other.example/today.json';
      let entered!: () => void;
      let release!: () => void;
      const fetching = new Promise<void>((resolve) => { entered = resolve; });
      const gate = new Promise<void>((resolve) => { release = resolve; });
      const { fetch: ready } = fakeFetch({
        [SRC]: { body: { ...good, title: '最新 A' } },
        [other]: { body: { ...good, title: '最新 B' } },
      });
      const requests: string[] = [];
      const d = { ...deps, fetch: async (url: string, init?: RequestInit) => {
        requests.push(url);
        if (requests.length === 1) { entered(); await gate; return Response.json({ ...good, title: '慢舊內容' }); }
        return ready(url, init);
      } };
      const pending = setLinkSource(d, caller('pastor'), { churchId: 'C1', source: SRC, fetchMinute: 270 });
      await fetching;
      let reason = 'conflict';
      if (change === 'source' || change === 'sourceABA') {
        await setLinkSource(d, caller('pastor'), { churchId: 'C1', source: other, fetchMinute: 270 });
        if (change === 'sourceABA') await setLinkSource(d, caller('pastor'), { churchId: 'C1', source: SRC, fetchMinute: 270 });
      } else if (change === 'clear') await setLinkSource(d, caller('pastor'), { churchId: 'C1', source: null });
      else if (change === 'time') {
        assert.deepEqual(await setLinkSource(d, caller('pastor'), { churchId: 'C1', source: SRC, fetchMinute: 600 }), { ok: true, content: null, unchanged: true });
        assert.equal(requests.length, 1, 'a time-only edit never starts another download');
      } else if (change === 'removedLink') await db.doc('churches/C1/settings/link').delete();
      else if (change === 'demoted') { await db.doc('churches/C1/members/pastor').update({ role: 'staff' }); reason = 'permissionDenied'; }
      else if (change === 'removedMember') { await db.doc('churches/C1/members/pastor').delete(); reason = 'permissionDenied'; }
      else { await db.doc('churches/C1').update({ status: change }); reason = 'churchClosed'; }
      const currentContent = await content();
      const currentSchedule = await schedule();
      const currentLink = (await db.doc('churches/C1/settings/link').get()).data();
      release();
      const error = await rejectsWith(pending, reason) as { code: string };
      if (reason === 'conflict') assert.equal(error.code, 'aborted', change);
      assert.deepEqual(await content(), currentContent, `${change}: no late content write`);
      assert.deepEqual(await schedule(), currentSchedule, `${change}: no schedule revival or overwrite`);
      assert.deepEqual((await db.doc('churches/C1/settings/link').get()).data(), currentLink, change);
    }
  });

  test('refresh replies identify the server source and actual fetched time so clients need not guess either', async () => {
    await church();
    const { d } = withFetch({ [SRC]: { body: good } });
    await setLinkSource(d, caller('pastor'), { churchId: 'C1', source: SRC, fetchMinute: 270 });
    setNow(new Date('2026-10-04T03:15:00+08:00'));
    assert.deepEqual(await setLinkSource(d, caller('pastor'), { churchId: 'C1', refresh: true }), {
      ok: true,
      content: { ...good, source: SRC, fetchedAt: Date.parse('2026-10-04T03:15:00+08:00') },
    });
    assert.equal((await content())!.fetchedAt.toMillis(), Date.parse('2026-10-04T03:15:00+08:00'));
  });

  test('a newer manual retry can publish an error without a slower earlier retry restoring successful-looking content', async () => {
    await church();
    const initial = withFetch({ [SRC]: { body: good } });
    await setLinkSource(initial.d, caller('pastor'), { churchId: 'C1', source: SRC, fetchMinute: 270 });
    let entered!: () => void;
    let release!: () => void;
    const fetching = new Promise<void>((resolve) => { entered = resolve; });
    const gate = new Promise<void>((resolve) => { release = resolve; });
    let requests = 0;
    const d = { ...deps, fetch: async () => {
      if (++requests === 1) { entered(); await gate; return Response.json(good); }
      return new Response('not JSON');
    } };
    const slow = setLinkSource(d, caller('pastor'), { churchId: 'C1', refresh: true });
    await fetching;
    assert.deepEqual(await setLinkSource(d, caller('pastor'), { churchId: 'C1', refresh: true }), { ok: false, error: 'badFormat', status: null });
    const current = await content();
    const currentSchedule = await schedule();
    release();
    await rejectsWith(slow, 'conflict');
    assert.deepEqual(await content(), current);
    assert.deepEqual(Object.keys(current!).sort(), ['error', 'errorAt', 'errorStatus', 'source']);
    assert.deepEqual(await schedule(), currentSchedule);
  });

  test('saving a source fetches it at once and returns the result', async () => {
    await church();
    const { d } = withFetch({ [SRC]: { body: good } });
    const r = await setLinkSource(d, caller('pastor'), { churchId: 'C1', source: SRC, fetchMinute: 300 });
    assert.deepEqual(r, { ok: true, content: { ...good, source: SRC, fetchedAt: Date.parse('2026-10-04T03:00:00+08:00') } });
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

  test('the same source on a link removed and set again is fetched again', async () => {
    await church();
    const { d, requests } = withFetch({ [SRC]: { body: good } });
    await setLinkSource(d, caller('pastor'), { churchId: 'C1', source: SRC, fetchMinute: 270 });
    // Removed by the app (the doc goes; the schedule stays until the next run), then set again.
    await db.doc('churches/C1/settings/link').delete();
    await db.doc('churches/C1/settings/link').set({ title: '官網', body: '', url: 'https://grace.example' });
    const r = await setLinkSource(d, caller('pastor'), { churchId: 'C1', source: SRC, fetchMinute: 270 });
    assert.deepEqual(r, { ok: true, content: { ...good, source: SRC, fetchedAt: Date.parse('2026-10-04T03:00:00+08:00') } });
    assert.equal(requests.length, 2);
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
      nextAt: Timestamp.fromDate(nextFetchAt(new Date('2026-10-03T23:00:00+08:00'), fetchMinute, false, 'Asia/Taipei')),
      ...extra,
    });
  }

  test('fetches only once its time has come, and once a day', async () => {
    await church();
    await scheduled('C1', 270);
    const todayContent = { ...good };
    const { d, requests } = withFetch({ [SRC]: { body: todayContent } });
    setNow(new Date('2026-10-04T04:15:00+08:00'));
    assert.equal(await fetchDueLinks(d), 0, 'not yet');
    setNow(new Date('2026-10-04T04:30:00+08:00'));
    assert.equal(await fetchDueLinks(d), 1);
    setNow(new Date('2026-10-04T04:45:00+08:00'));
    assert.equal(await fetchDueLinks(d), 0, 'not twice the same day');
    assert.equal(requests.length, 1);
    assert.equal((await content())!.title, '今日經文');
    setNow(new Date('2026-10-05T04:30:00+08:00'));
    todayContent.date = '2026-10-05';
    assert.equal(await fetchDueLinks(d), 1, 'again the next day');
    assert.equal((await content())!.date, '2026-10-05');
    assert.equal((await content())!.error, null);
  });

  test('scheduled fetches cannot publish or reschedule after source/settings changes, clear, closure or schedule removal', async () => {
    for (const change of ['source', 'clear', 'sourceABA', 'time', 'removedLink', 'suspended', 'deleted', 'removedSchedule']) {
      await clearFirestore();
      await church();
      await scheduled('C1', 270);
      setNow(new Date('2026-10-04T04:30:00+08:00'));
      let entered!: () => void;
      let release!: () => void;
      const fetching = new Promise<void>((resolve) => { entered = resolve; });
      const gate = new Promise<void>((resolve) => { release = resolve; });
      const other = 'https://other.example/today.json';
      const { fetch: ready } = fakeFetch({ [SRC]: { body: { ...good, title: '最新 A' } }, [other]: { body: { ...good, title: '最新 B' } } });
      let requests = 0;
      const d = { ...deps, fetch: async (url: string, init?: RequestInit) => {
        if (++requests === 1) { entered(); await gate; return Response.json({ ...good, title: '慢舊內容' }); }
        return ready(url, init);
      } };
      const pending = fetchDueLinks(d);
      await fetching;
      if (change === 'source' || change === 'sourceABA') {
        await setLinkSource(d, caller('pastor'), { churchId: 'C1', source: other, fetchMinute: 600 });
        if (change === 'sourceABA') await setLinkSource(d, caller('pastor'), { churchId: 'C1', source: SRC, fetchMinute: 600 });
      } else if (change === 'clear') await setLinkSource(d, caller('pastor'), { churchId: 'C1', source: null });
      else if (change === 'time') await setLinkSource(d, caller('pastor'), { churchId: 'C1', source: SRC, fetchMinute: 600 });
      else if (change === 'removedLink') await db.doc('churches/C1/settings/link').delete();
      else if (change === 'removedSchedule') await db.doc('linkSources/C1').delete();
      else await db.doc('churches/C1').update({ status: change });
      const latest = await content();
      const latestSchedule = await schedule();
      release();
      assert.equal(await pending, 0, change);
      assert.deepEqual(await content(), latest, `${change}: no stale content`);
      assert.deepEqual(await schedule(), latestSchedule, `${change}: no stale schedule`);
    }
  });

  test('editing the fixed title while today’s fetch runs keeps the fetched content', async () => {
    await church();
    await scheduled('C1', 270);
    setNow(new Date('2026-10-04T04:30:00+08:00'));
    let entered!: () => void;
    let release!: () => void;
    const fetching = new Promise<void>((resolve) => { entered = resolve; });
    const gate = new Promise<void>((resolve) => { release = resolve; });
    const d = { ...deps, fetch: async () => { entered(); await gate; return Response.json(good); } };
    const pending = fetchDueLinks(d);
    await fetching;
    await db.doc('churches/C1/settings/link').update({ title: '新的固定標題' });
    release();
    assert.equal(await pending, 1);
    assert.equal((await content())!.title, good.title);
    assert.equal((await schedule())!.lastDay, '2026-10-04');
  });

  test('simultaneous scheduled jobs reserve one daily attempt, while explicit admin retry can still run that day', async () => {
    await church();
    await scheduled('C1', 270);
    setNow(new Date('2026-10-04T04:30:00+08:00'));
    let entered!: () => void;
    let release!: () => void;
    const fetching = new Promise<void>((resolve) => { entered = resolve; });
    const gate = new Promise<void>((resolve) => { release = resolve; });
    let requests = 0;
    const d = { ...deps, fetch: async () => {
      if (++requests === 1) { entered(); await gate; return new Response('not JSON'); }
      return Response.json(good);
    } };
    const first = fetchDueLinks(d);
    await fetching;
    assert.equal(await fetchDueLinks(d), 0);
    assert.equal(requests, 1);
    release();
    assert.equal(await first, 1);
    assert.equal((await content())!.error, 'badFormat');
    assert.equal((await schedule())!.lastDay, '2026-10-03');
    setNow(new Date('2026-10-04T06:00:00+08:00'));
    await setLinkSource(d, caller('pastor'), { churchId: 'C1', source: SRC, fetchMinute: 600 });
    setNow(new Date('2026-10-04T10:00:00+08:00'));
    assert.equal(await fetchDueLinks(d), 0, 'moving the time does not create automatic retries');
    await setLinkSource(d, caller('pastor'), { churchId: 'C1', refresh: true });
    assert.equal(requests, 2, 'only an explicit manual retry fetches again today');
    assert.equal((await content())!.error, null);
    assert.equal((await schedule())!.lastDay, '2026-10-04');
  });

  test('a failed daily fetch stores only the error, never stale content or a successful lastDay', async () => {
    await church();
    await scheduled('C1', 270);
    await db.doc('churches/C1/settings/linkContent').set({ ...good, source: SRC, fetchedAt: Timestamp.now(), error: null });
    const { d } = withFetch({ [SRC]: { delayMs: 6000 } });
    setNow(new Date('2026-10-04T04:30:00+08:00'));
    await fetchDueLinks(d);
    const c = await content();
    assert.deepEqual(Object.keys(c!).sort(), ['error', 'errorAt', 'errorStatus', 'source']);
    assert.equal(c!.error, 'timeout');
    const next = await schedule();
    assert.equal(next!.lastDay, '2026-10-03', 'lastDay means success, not an attempted fetch');
    assert.equal(next!.lastAttemptDay, '2026-10-04');
    assert.equal(next!.nextAt.toDate().toISOString(), new Date('2026-10-05T04:30:00+08:00').toISOString());
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
    assert.equal((await schedule('Closed'))!.lastDay, '2026-10-03', 'skipping a closed church is not a successful fetch');
    assert.equal((await schedule('Closed'))!.nextAt.toDate().toISOString(), new Date('2026-10-05T04:30:00+08:00').toISOString());
  });
});
