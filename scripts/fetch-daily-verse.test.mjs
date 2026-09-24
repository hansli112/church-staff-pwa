import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { devotionalFetchSettings, fetchDailyVerse, parseDailyBibleHtml, validateDailyVerse } from './fetch-daily-verse.mjs';

const example = JSON.parse(readFileSync(new URL('../config/church.example.json', import.meta.url), 'utf8'));

const options = { timeZone: 'Asia/Taipei', now: new Date('2026-09-24T16:30:00Z') };
const data = { date: '2026-09-25', rawRange: '約翰福音 1:1-5' };

test('fetch settings come only from shared ChurchConfig, with safe defaults', () => {
  assert.deepEqual(devotionalFetchSettings(undefined), { enabled: false });
  assert.equal(devotionalFetchSettings(JSON.stringify(example)).enabled, false);
  const config = structuredClone(example);
  config.devotional = {
    enabled: true, sourceName: '測試來源', dataUrl: 'https://example.invalid/daily-verse.json',
    linkUrl: 'https://example.invalid/daily', fetchUrl: '',
  };
  assert.equal(devotionalFetchSettings(JSON.stringify(config)).enabled, false);
  config.devotional.fetchUrl = 'https://example.invalid/source';
  config.devotional.fetchFormat = 'dailyBibleHtml';
  config.timeZone = 'America/New_York';
  assert.deepEqual(devotionalFetchSettings(JSON.stringify(config)), {
    enabled: true, url: 'https://example.invalid/source', format: 'dailyBibleHtml', timeZone: 'America/New_York',
  });
  config.devotional.fetchFormat = 'unknown';
  assert.throws(() => devotionalFetchSettings(JSON.stringify(config)), /fetchFormat/);
  config.devotional.fetchFormat = 'json';
  config.devotional.fetchUrl = 'http://example.invalid/insecure';
  assert.throws(() => devotionalFetchSettings(JSON.stringify(config)), /HTTPS/);
});

test('dailyBibleHtml adapter preserves the old date/span/range structure with synthetic content', async () => {
  const html = '<!doctype html><h1>測試資料</h1><div>2026-09-25 <span>|</span> <span> 約翰福音 1:1-5 </span></div>';
  assert.deepEqual(parseDailyBibleHtml(html), data);
  const parsed = await fetchDailyVerse('https://example.invalid/source', {
    ...options, format: 'dailyBibleHtml', fetchImpl: async (_url, init) => {
      assert.equal(init.headers.Accept, 'text/html');
      assert.equal(init.redirect, 'error');
      return new Response(html);
    },
  });
  assert.deepEqual(parsed, validateDailyVerse(data, options));
  assert.throws(() => parseDailyBibleHtml('<div>2026-09-25 任意其他版型</div>'), /既定/);
  await assert.rejects(fetchDailyVerse('https://example.invalid/source', {
    ...options, fetchImpl: async () => new Response(html),
  }), SyntaxError, '沒有明確選 HTML adapter 時不得猜測格式');
});

test('preserves the existing JSON contract and respects configured time zone', () => {
  assert.deepEqual(validateDailyVerse(data, options), { ...data, fetchedAt: '2026-09-24T16:30:00.000Z' });
  assert.throws(() => validateDailyVerse(data, { ...options, timeZone: 'America/New_York' }), /晚於/);
  assert.throws(() => validateDailyVerse(data, { ...options, timeZone: 'invalid' }));
});

test('rejects invalid dates, HTML, control characters and missing ranges', () => {
  for (const invalid of [
    null, '<html>source</html>', [], { ...data, date: '2026-02-30' }, { ...data, date: '2026-09-26' },
    { ...data, rawRange: '' }, { ...data, rawRange: '<script>' }, { ...data, rawRange: 'a\nb' }, { ...data, rawRange: 'a'.repeat(121) },
  ]) assert.throws(() => validateDailyVerse(invalid, options));
});

test('fetch requires HTTPS, no credentials and disallows redirects', async () => {
  const fetchImpl = async (url, init) => {
    assert.equal(url.href, 'https://example.invalid/feed.json');
    assert.equal(init.redirect, 'error');
    return new Response(JSON.stringify(data));
  };
  await assert.rejects(fetchDailyVerse('http://example.invalid/feed.json', { fetchImpl }), /HTTPS/);
  await assert.rejects(fetchDailyVerse('https://user:secret@example.invalid/feed.json', { fetchImpl }), /帳密/);
  assert.deepEqual(await fetchDailyVerse('https://example.invalid/feed.json', { fetchImpl, ...options }), validateDailyVerse(data, options));
});

test('fetch fails closed for bad HTTP status, HTML and oversized feeds', async () => {
  for (const response of [new Response('error', { status: 503 }), new Response('<html></html>'), new Response('x'.repeat(65_537))]) {
    await assert.rejects(fetchDailyVerse('https://example.invalid/feed.json', { fetchImpl: async () => response, ...options }));
  }
});
