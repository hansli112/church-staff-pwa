import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

import { Timestamp } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';

import { APP_SHELL, churchPage, clearTemplateCache, type PageDeps } from '../src/churchPage.js';
import { clearFirestore, db, deps, fakeFetch, seedChurch, setNow } from './support.js';

const APP = 'https://martha.example';
// The built web app's head, as Flutter writes it.
const SHELL = `<!DOCTYPE html>
<html lang="zh-Hant">
<head>
  <base href="/">
  <meta name="apple-mobile-web-app-title" content="馬大別忙">
  <link rel="apple-touch-icon" href="icons/Icon-192.png">
  <title>馬大別忙</title>
  <link rel="manifest" href="manifest.json">
</head>
<body>
  <div id="splash" role="status"><!--splash--><p class="title">馬大別忙</p><p class="note">載入中…</p><!--/splash--></div>
  <script src="flutter_bootstrap.js" async></script>
</body>
</html>`;

/** What the page shows before the app starts. */
const splashOf = (html: string) => /<!--splash-->([\s\S]*?)<!--\/splash-->/.exec(html)?.[1] ?? '';

async function seedInvite(code: string, cid: string, fields: Record<string, unknown> = {}) {
  await db.doc(`invites/${code}`).set({
    cid,
    churchName: 'old name',
    expiresAt: Timestamp.fromDate(new Date('2026-10-08T10:00:00+08:00')),
    revoked: false,
    ...fields,
  });
}

const bucket = getStorage().bucket('demo-martha.appspot.com');

function page(routes = {}) {
  const f = fakeFetch({ [`${APP}${APP_SHELL}`]: { body: SHELL }, ...routes });
  const d: PageDeps = { ...deps, fetch: f.fetch, bucket, appUrl: APP };
  return { get: (path: string) => churchPage(d, path), requests: f.requests };
}

const text = (body: string | Buffer) => body.toString();

beforeEach(async () => {
  await clearFirestore();
  clearTemplateCache();
  setNow(new Date('2026-10-01T10:00:00+08:00'));
});

describe('church page', () => {
  test('the church URL and the pages under it carry the church’s name and logo', async () => {
    await seedChurch('Grace', {}, { name: '恩典堂 <台北>', logoVersion: '42' });
    const { get } = page();
    for (const path of ['/c/Grace', '/c/Grace/join/ABCDEFGH']) {
      const r = await get(path);
      assert.equal(r.status, 200);
      assert.equal(r.headers['cache-control'], path === '/c/Grace' ? 'public, max-age=300' : 'private, no-cache');
      const html = text(r.body);
      assert.match(html, /<title>恩典堂 &lt;台北&gt;<\/title>/);
      assert.match(html, /<meta name="apple-mobile-web-app-title" content="恩典堂 &lt;台北&gt;">/);
      assert.match(html, /<link rel="apple-touch-icon" href="\/c\/Grace\/icons\/42\/logo.png">/);
      assert.match(html, /<link rel="manifest" href="\/c\/Grace\/manifest.json">/);
      assert.match(html, /<meta property="og:title" content="恩典堂 &lt;台北&gt;">/);
      assert.match(html, /<meta property="og:image" content="https:\/\/martha.example\/c\/Grace\/icons\/42\/logo.png">/);
      assert.match(html, /flutter_bootstrap\.js/, 'still the app');
    }
  });

  test('before the app starts, the church page shows the church, loading', async () => {
    await seedChurch('Grace', {}, { name: '恩典堂 <台北>', logoVersion: '42' });
    const shown = splashOf(text((await page().get('/c/Grace')).body));
    assert.match(shown, /<img src="\/c\/Grace\/icons\/42\/logo.png" alt="">/);
    assert.match(shown, /<p class="title">恩典堂 &lt;台北&gt;<\/p>/);
    assert.match(shown, /載入中…/);
    assert.match(shown, /class="spin"/);
  });

  test('an invite link shows whom it joins straight away, and fresh', async () => {
    await seedChurch('Grace', {}, { name: '恩典堂' });
    await seedInvite('ABCDEFGH', 'Grace');
    const r = await page().get('/c/Grace/join/abcdefgh');
    assert.equal(r.status, 200);
    assert.equal(r.headers['cache-control'], 'private, no-cache');
    const html = text(r.body);
    assert.match(html, /<title>恩典堂<\/title>/, 'still the church’s page');
    const shown = splashOf(html);
    assert.match(shown, /<p class="title">加入〈恩典堂〉<\/p>/, 'the church’s name now, not the invite’s');
    assert.match(shown, /載入中…/);
    assert.match(shown, /class="spin"/);
  });

  test('an invite link that cannot be used says why, before the app starts', async () => {
    await seedChurch('Grace', {}, { name: '恩典堂' });
    await seedChurch('Closed', {}, { name: '關閉堂', status: 'suspended' });
    await seedInvite('EXPIRED1', 'Grace', { expiresAt: Timestamp.fromDate(new Date('2026-10-01T09:00:00+08:00')) });
    await seedInvite('REVOKED1', 'Grace', { revoked: true });
    await seedInvite('CLOSED01', 'Closed');
    const { get } = page();
    const shown = async (path: string) => splashOf(text((await get(path)).body));

    assert.match(await shown('/c/Grace/join/EXPIRED1'), /這個邀請過期了，請向管理員要新的邀請/);
    for (const path of ['/c/Grace/join/REVOKED1', '/c/Grace/join/NOSUCH01', '/c/Closed/join/CLOSED01']) {
      const s = await shown(path);
      assert.match(s, /找不到這個邀請，請確認邀請碼，或向管理員要新的邀請/, path);
      assert.doesNotMatch(s, /class="spin"/, path);
      assert.doesNotMatch(s, /關閉堂/, 'a closed church stays unnamed');
    }
  });

  test('a shell without the loading screen is left as it is', async () => {
    await seedChurch('Grace', {}, { name: '恩典堂' });
    await seedInvite('ABCDEFGH', 'Grace');
    const bare = SHELL.replace(/\s*<div id="splash"[^\n]*/, '');
    const html = text((await page({ [`${APP}${APP_SHELL}`]: { body: bare } }).get('/c/Grace/join/ABCDEFGH')).body);
    assert.match(html, /<title>恩典堂<\/title>/);
    assert.doesNotMatch(html, /splash/);
  });

  test('a church name with $ in it is written as it is', async () => {
    await seedChurch('Cash', {}, { name: "$& $' 堂" });
    const html = text((await page().get('/c/Cash')).body);
    assert.match(html, /<title>\$&amp; \$' 堂<\/title>/);
    assert.match(splashOf(html), /<p class="title">\$&amp; \$' 堂<\/p>/);
  });

  test('the manifest names the church and starts at its URL', async () => {
    await seedChurch('Grace', {}, { name: '恩典堂', logoVersion: '42' });
    const r = await page().get('/c/Grace/manifest.json');
    assert.equal(r.status, 200);
    assert.match(r.headers['content-type'], /application\/manifest\+json/);
    const m = JSON.parse(text(r.body));
    assert.equal(m.name, '恩典堂');
    assert.equal(m.short_name, '恩典堂');
    assert.equal(m.id, '/c/Grace');
    assert.equal(m.start_url, '/c/Grace');
    assert.equal(m.scope, '/');
    assert.deepEqual(m.icons, [{ src: '/c/Grace/icons/42/logo.png', sizes: '512x512', type: 'image/png' }]);
  });

  test('the home-screen name goes under the icon; the title keeps the full name', async () => {
    await seedChurch('Long', {}, { name: '台北靈糧堂民生分堂', homeName: '民生靈糧堂' });
    const { get } = page();
    const m = JSON.parse(text((await get('/c/Long/manifest.json')).body));
    assert.equal(m.name, '台北靈糧堂民生分堂');
    assert.equal(m.short_name, '民生靈糧堂');
    const html = text((await get('/c/Long')).body);
    assert.match(html, /<title>台北靈糧堂民生分堂<\/title>/);
    assert.match(html, /<meta name="apple-mobile-web-app-title" content="民生靈糧堂">/);
  });

  test('without a logo the default icons are used', async () => {
    await seedChurch('Plain', {}, { name: '平安堂' });
    const { get } = page();
    const m = JSON.parse(text((await get('/c/Plain/manifest.json')).body));
    assert.equal(m.icons[0].src, '/icons/Icon-192.png');
    assert.ok(m.icons.some((i: { purpose?: string }) => i.purpose === 'maskable'));
    const html = text((await get('/c/Plain')).body);
    assert.match(html, /<link rel="apple-touch-icon" href="\/icons\/Icon-192.png">/);
    assert.match(html, /og:image" content="https:\/\/martha.example\/icons\/Icon-512.png"/);
  });

  test('an unknown church is a 404 with the plain page', async () => {
    const { get } = page();
    const r = await get('/c/Nope');
    assert.equal(r.status, 404);
    assert.equal(text(r.body), SHELL);
    assert.equal((await get('/c/Nope/manifest.json')).status, 404);
    assert.equal((await get('/c/bad.id')).status, 404);
  });

  test('a suspended or deleted church shows neither name nor logo', async () => {
    await seedChurch('Closed', {}, { name: '關閉堂', status: 'suspended', logoVersion: '1' });
    await seedChurch('Gone', {}, { name: '刪除堂', status: 'deleted' });
    const { get } = page();
    for (const cid of ['Closed', 'Gone']) {
      const r = await get(`/c/${cid}`);
      assert.equal(r.status, 200);
      assert.equal(text(r.body), SHELL);
      const m = JSON.parse(text((await get(`/c/${cid}/manifest.json`)).body));
      assert.equal(m.name, '馬大別忙');
      assert.equal(m.icons[0].src, '/icons/Icon-192.png');
    }
    assert.equal((await get('/c/Closed/icons/1/logo.png')).status, 404);
  });

  test('the app shell is fetched from the hosting origin once every few minutes', async () => {
    await seedChurch('Grace', {}, { name: '恩典堂' });
    const { get, requests } = page();
    await get('/c/Grace');
    await get('/c/Grace');
    assert.equal(requests.length, 1);
    setNow(new Date('2026-10-01T10:06:00+08:00'));
    await get('/c/Grace');
    assert.equal(requests.length, 2);
  });

  test('a page that is not the app (the landing page, say) never gets a church’s name', async () => {
    await seedChurch('Grace', {}, { name: '恩典堂' });
    const landing = { body: '<html><head><title>馬大別忙｜教會同工的服事表</title></head></html>' };
    assert.equal((await page({ [`${APP}${APP_SHELL}`]: landing }).get('/c/Grace')).status, 503);
  });

  test('when the template cannot be fetched, a stale copy is used, else 503', async () => {
    await seedChurch('Grace', {}, { name: '恩典堂' });
    assert.equal((await page({ [`${APP}${APP_SHELL}`]: { status: 500 } }).get('/c/Grace')).status, 503);
    await page().get('/c/Grace');
    setNow(new Date('2026-10-01T11:00:00+08:00'));
    const r = await page({ [`${APP}${APP_SHELL}`]: { status: 500 } }).get('/c/Grace');
    assert.equal(r.status, 200);
    assert.match(text(r.body), /<title>恩典堂<\/title>/);
  });

  test('the logo is served under its version, never another church’s', async () => {
    await seedChurch('Grace', {}, { name: '恩典堂', logoVersion: '42' });
    await seedChurch('Other', {}, { name: '別堂', logoVersion: '7' });
    const png = Buffer.from([0x89, 0x50, 0x4e, 0x47, 1, 2, 3]);
    await bucket.file('churches/Grace/logo.png').save(png, { contentType: 'image/png' });
    const { get } = page();
    const r = await get('/c/Grace/icons/42/logo.png');
    assert.equal(r.status, 200);
    assert.equal(r.headers['content-type'], 'image/png');
    assert.match(r.headers['cache-control'], /immutable/);
    assert.deepEqual(r.body, png);
    assert.equal((await get('/c/Grace/icons/41/logo.png')).status, 404, 'old version');
    assert.equal((await get('/c/Other/icons/7/logo.png')).status, 404, 'no file for that church');
  });
});
