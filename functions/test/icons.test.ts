import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

import { getStorage } from 'firebase-admin/storage';
import sharp from 'sharp';

import { churchPage, clearTemplateCache } from '../src/churchPage.js';
import { makeIcons } from '../src/icons.js';
import { onLogoUploaded } from '../src/triggers.js';
import { clearFirestore, db, deps, fakeFetch, seedChurch } from './support.js';

const bucket = getStorage().bucket('demo-martha.appspot.com');
const logoDeps = { ...deps, bucket };

/** A 512px logo: a red square on a transparent background. */
async function logo(color = { r: 220, g: 38, b: 38, alpha: 1 }) {
  const square = await sharp({ create: { width: 256, height: 256, channels: 4, background: color } }).png().toBuffer();
  return sharp({ create: { width: 512, height: 512, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } } })
    .composite([{ input: square, gravity: 'center' }])
    .png()
    .toBuffer();
}

async function pixel(png: Buffer, x: number, y: number) {
  const { data, info } = await sharp(png).raw().toBuffer({ resolveWithObject: true });
  const i = (y * info.width + x) * info.channels;
  return [...data.subarray(i, i + info.channels)];
}

const files = async (cid: string) =>
  (await bucket.getFiles({ prefix: `churches/${cid}/` }))[0].map((f) => f.name).sort();

beforeEach(async () => {
  await clearFirestore();
  clearTemplateCache();
  await bucket.deleteFiles({ prefix: 'churches/' });
});

describe('home-screen icons', () => {
  test('sizes, and an opaque white background where platforms need one', async () => {
    const icons = await makeIcons(await logo());
    const meta = async (f: keyof typeof icons) => sharp(icons[f]).metadata();
    assert.deepEqual([(await meta('icon-192.png')).width, (await meta('icon-192.png')).height], [192, 192]);
    assert.equal((await meta('icon-512.png')).width, 512);
    assert.equal((await meta('maskable-512.png')).width, 512);
    assert.equal((await meta('apple-touch-180.png')).width, 180);

    for (const f of ['maskable-512.png', 'apple-touch-180.png'] as const) {
      assert.equal((await meta(f)).hasAlpha, false, `${f} is opaque`);
      assert.deepEqual(await pixel(icons[f], 0, 0), [255, 255, 255], `${f} corner is white, not black`);
    }
    assert.equal((await pixel(icons['icon-512.png'], 0, 0))[3], 0, 'the plain icon keeps its transparency');

    // Maskable: the logo stays inside the safe zone (a circle 80% across).
    const m = icons['maskable-512.png'];
    assert.deepEqual(await pixel(m, 256, 256), [220, 38, 38]);
    assert.deepEqual(await pixel(m, 256, 256 - Math.round(512 * 0.4) + 2), [255, 255, 255], 'top of the safe zone is white');
  });

  test('an upload makes the icons, links them, and serves them', async () => {
    await seedChurch('C1', {}, { name: '恩典堂' });
    await bucket.file('churches/C1/logo.png').save(await logo(), { contentType: 'image/png' });
    assert.equal(await onLogoUploaded(logoDeps, 'churches/C1/logo.png', '200'), true);
    assert.deepEqual(await files('C1'), [
      'churches/C1/logo-200-apple-touch-180.png',
      'churches/C1/logo-200-icon-192.png',
      'churches/C1/logo-200-icon-512.png',
      'churches/C1/logo-200-maskable-512.png',
      'churches/C1/logo.png',
    ]);
    const church = await db.doc('churches/C1').get();
    assert.equal(church.get('logoVersion'), '200');
    assert.equal(church.get('logoIcons'), '200');

    const f = fakeFetch({ 'https://app.example/index.html': { body: '<head><link rel="apple-touch-icon" href="x"></head>' } });
    const get = (path: string) => churchPage({ ...deps, fetch: f.fetch, bucket, appUrl: 'https://app.example' }, path);
    const m = JSON.parse((await get('/c/C1/manifest.json')).body.toString());
    assert.deepEqual(
      m.icons.map((i: { src: string; purpose?: string }) => [i.src, i.purpose ?? 'any']),
      [
        ['/c/C1/icons/200/icon-192.png', 'any'],
        ['/c/C1/icons/200/icon-512.png', 'any'],
        ['/c/C1/icons/200/maskable-512.png', 'maskable'],
      ],
    );
    assert.match((await get('/c/C1')).body.toString(), /apple-touch-icon" href="\/c\/C1\/icons\/200\/apple-touch-180.png"/);
    const served = await get('/c/C1/icons/200/apple-touch-180.png');
    assert.equal(served.status, 200);
    assert.equal((await sharp(served.body as Buffer).metadata()).width, 180);
  });

  test('a new logo replaces the old icons; a late, older upload does not win', async () => {
    await seedChurch('C1', {});
    await bucket.file('churches/C1/logo.png').save(await logo(), { contentType: 'image/png' });
    await onLogoUploaded(logoDeps, 'churches/C1/logo.png', '200');
    await onLogoUploaded(logoDeps, 'churches/C1/logo.png', '300');
    assert.ok((await files('C1')).every((n) => !n.includes('logo-200-')), 'old icons removed');
    await onLogoUploaded(logoDeps, 'churches/C1/logo.png', '250');
    assert.equal((await db.doc('churches/C1').get()).get('logoVersion'), '300');
    assert.ok((await files('C1')).some((n) => n.includes('logo-300-')), 'current icons kept');
  });

  test('a logo that cannot be read still gets its version, and the page uses the logo itself', async () => {
    await seedChurch('C1', {});
    await bucket.file('churches/C1/logo.png').save(Buffer.from('not an image'), { contentType: 'image/png' });
    await onLogoUploaded(logoDeps, 'churches/C1/logo.png', '5');
    const church = await db.doc('churches/C1').get();
    assert.equal(church.get('logoVersion'), '5');
    assert.equal(church.get('logoIcons'), undefined);
    const f = fakeFetch();
    const m = JSON.parse(
      (await churchPage({ ...deps, fetch: f.fetch, bucket, appUrl: 'https://a' }, '/c/C1/manifest.json')).body.toString(),
    );
    assert.deepEqual(m.icons, [{ src: '/c/C1/icons/5/logo.png', sizes: '512x512', type: 'image/png' }]);
  });
});
