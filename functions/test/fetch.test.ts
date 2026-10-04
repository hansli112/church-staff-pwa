import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import { deps, fakeFetch } from './support.js';

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
