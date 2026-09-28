// Tests for GET /api/devotional/today, the same-day fallback the home page uses
// while the scheduled data-branch update is still hours late.
import assert from 'node:assert/strict';
import { afterEach, describe, test } from 'node:test';

import { onRequestGet } from '../functions/api/devotional/today.js';
import { dateKeyInZone, TEST_CHURCH_CONFIG } from '../worker/church_config.js';
import { ENABLED_CONFIG, MEMBER_UID, fakeFetch, idToken, muteConsoleError, request, testEnv, withFetch } from './helpers.js';

const SOURCE = 'https://source.example/daily-bible/';
const CONFIG = {
  ...ENABLED_CONFIG,
  devotional: {
    enabled: true, dataUrl: 'https://data.example/daily-verse.json', linkUrl: SOURCE,
    sourceName: '每日靈糧', fetchUrl: SOURCE, fetchFormat: 'dailyBibleHtml',
  },
};
const today = () => dateKeyInZone(new Date(), CONFIG.timeZone);
const page = (date) => `<html><div>${date} <span>|</span> <span>  哥林多後書一：12-一：24  </span></div></html>`;

function withSource(html, { status = 200 } = {}) {
  const base = fakeFetch();
  const sourceCalls = [];
  const impl = async (url, init = {}) => {
    if (String(url) === SOURCE) {
      sourceCalls.push(init);
      return new Response(html, { status });
    }
    return base(url, init);
  };
  impl.sourceCalls = sourceCalls;
  return impl;
}

async function get(env, fetchImpl, { token = idToken(MEMBER_UID) } = {}) {
  return withFetch(fetchImpl, () => onRequestGet({ request: request('GET', { token, path: '/api/devotional/today' }), env }));
}

afterEach(() => { delete globalThis.caches; });

describe('GET /api/devotional/today', () => {
  test('a signed-in member gets today\'s range from the configured source', async () => {
    const fetchImpl = withSource(page(today()));
    const response = await get(await testEnv({ [TEST_CHURCH_CONFIG]: CONFIG }), fetchImpl);
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { date: today(), rawRange: '哥林多後書一：12-一：24' });
    assert.equal(fetchImpl.sourceCalls.length, 1);
    assert.equal(fetchImpl.sourceCalls[0].redirect, 'error');
  });

  test('without a sign-in the source is never contacted', async () => {
    const fetchImpl = withSource(page(today()));
    const response = await get(await testEnv({ [TEST_CHURCH_CONFIG]: CONFIG }), fetchImpl, { token: null });
    assert.equal(response.status, 401);
    assert.equal(fetchImpl.sourceCalls.length, 0);
  });

  test('a source still on yesterday is reported, not passed off as today', async () => {
    const yesterday = dateKeyInZone(new Date(Date.now() - 86_400_000), CONFIG.timeZone);
    const response = await get(await testEnv({ [TEST_CHURCH_CONFIG]: CONFIG }), withSource(page(yesterday)));
    assert.equal(response.status, 404);
  });

  test('a church without a devotional source gets 404 and nothing is fetched', async () => {
    const fetchImpl = withSource(page(today()));
    const disabled = { ...CONFIG, devotional: { ...CONFIG.devotional, enabled: false } };
    const response = await get(await testEnv({ [TEST_CHURCH_CONFIG]: disabled }), fetchImpl);
    assert.equal(response.status, 404);
    assert.equal(fetchImpl.sourceCalls.length, 0);
  });

  test('a broken source is a 502, with nothing about it sent to the client', async () => {
    const restore = muteConsoleError();
    try {
      const response = await get(await testEnv({ [TEST_CHURCH_CONFIG]: CONFIG }), withSource('down', { status: 503 }));
      assert.equal(response.status, 502);
      assert.deepEqual(await response.json(), { error: '暫時無法讀取今日經文' });
    } finally {
      restore();
    }
  });

  test('the day\'s answer is cached at the edge, keyed by the church date', async () => {
    const stored = new Map();
    globalThis.caches = { default: {
      match: async (key) => stored.get(key.url)?.clone(),
      put: async (key, response) => { stored.set(key.url, response); },
    } };
    const env = await testEnv({ [TEST_CHURCH_CONFIG]: CONFIG });
    const fetchImpl = withSource(page(today()));
    await get(env, fetchImpl);
    const again = await get(env, fetchImpl);
    assert.equal(again.status, 200);
    assert.deepEqual(await again.json(), { date: today(), rawRange: '哥林多後書一：12-一：24' });
    assert.equal(fetchImpl.sourceCalls.length, 1);
    assert.deepEqual([...stored.keys()], [`https://app.example/api/devotional/today?d=${today()}`]);
  });
});
