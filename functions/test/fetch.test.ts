import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import { fetchSource } from '../src/churchLink.js';
import { deps, fakeFetch } from './support.js';

test('source dates must match today in UTC+8, not UTC or a stale/future provider day', async () => {
  const source = 'https://feed.example/today.json';
  for (const date of ['2026-10-03', '2026-10-05', '2026-10-04']) {
    const content = { date, title: '今日經文', body: '摘要', link: 'https://feed.example/original' };
    const { fetch } = fakeFetch({ [source]: { body: content } });
    const result = await fetchSource({ fetch, now: () => new Date('2026-10-03T16:30:00Z') }, source, 'Asia/Taipei');
    assert.deepEqual(result, date === '2026-10-04' ? { ok: true, content } : { ok: false, error: 'notToday' });
  }
});

describe('fake fetch', () => {
  test('answers with the status, body and headers given, and records the request', async () => {
    const { fetch, requests } = fakeFetch({
      'https://a.example/x': { status: 201, body: { ok: true }, headers: { 'content-type': 'application/json' } },
    });
    const res = await fetch('https://a.example/x', { method: 'post', headers: { 'X-Test': '1' }, body: 'hi' });
    assert.equal(res.status, 201);
    assert.deepEqual(await res.json(), { ok: true });
    assert.deepEqual(requests, [{ url: 'https://a.example/x', method: 'POST', headers: { 'x-test': '1' }, body: 'hi' }]);
  });

  test('redirects, delays until aborted, and fails unknown URLs', async () => {
    const { fetch } = fakeFetch({
      'https://a.example/moved': { redirect: 'http://b.example/' },
      'https://a.example/slow': { delayMs: 10_000 },
    });
    const moved = await fetch('https://a.example/moved', { redirect: 'manual' });
    assert.equal(moved.status, 302);
    assert.equal(moved.headers.get('location'), 'http://b.example/');
    await assert.rejects(fetch('https://a.example/slow', { signal: AbortSignal.timeout(20) }));
    await assert.rejects(fetch('https://a.example/unknown'));
  });

  test('the shared deps never reach the network', async () => {
    await assert.rejects(deps.fetch('https://example.com/'));
  });
});
