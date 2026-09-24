import assert from 'node:assert/strict';
import { mkdir, mkdtemp, readFile, rm, symlink, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import { prepareDeployment, renderRules, validateChurchConfig } from '../scripts/prepare-deployment.mjs';
import defaults from '../worker/generated_config.js';
import { churchConfig, dateKeyInZone, TEST_CHURCH_CONFIG } from '../worker/church_config.js';
import { quotaResetText, callGemini } from '../worker/gemini.js';
import { notifyN8n, notifyPayload } from '../worker/line_notify.js';
import { authorize } from '../worker/authorize.js';
import { onRequestPost as calendarPost } from '../functions/api/calendar/events.js';
import { onRequestPatch, onRequestDelete } from '../functions/api/calendar/events/[id].js';
import { onRequestPost as importPost } from '../functions/api/roster/import-image.js';
import { ENABLED_CONFIG, ADMIN_UID, ROSTER_EDITOR_UID, fakeFetch, request, testEnv, withFetch } from './helpers.js';

const fixture = () => ({
  ...structuredClone(ENABLED_CONFIG),
  appName: 'Example Community', shortName: 'Community', timeZone: 'America/New_York',
  services: [...structuredClone(defaults.services), { id: 'midweek', label: '週中', name: '週中聚會', weekday: 3, enabled: true }],
});

const root = path.resolve(import.meta.dirname, '..');

test('tracked Worker defaults match the canonical example exactly', async () => {
  assert.deepEqual(defaults, JSON.parse(await readFile(path.join(root, 'config/church.example.json'), 'utf8')));
  assert.equal(churchConfig().features.calendar, false);
  assert.equal(churchConfig().features.photoImport, false);
});

test('CI emits a deployable Worker directory, not the deprecated multipart outfile', async () => {
  const workflow = await readFile(path.join(root, '.github/workflows/deploy-flutter-pwa.yml'), 'utf8');
  assert.match(workflow, /pages functions build .*--outdir=build\/web\/_worker\.js/);
  assert.doesNotMatch(workflow, /--outfile=build\/web\/_worker\.js/);
});

test('schema rejects invalid IDs, duplicate IDs, flags, URLs, paths and timezones', () => {
  for (const change of [
    (c) => { c.services[0].id = "bad'); allow write: if true; //"; },
    (c) => { c.services[1].id = c.services[0].id; },
    (c) => { c.services[0].id = 'constructor'; },
    (c) => { c.services[0].weekday = 0; },
    (c) => { c.services[0].weekday = 8; },
    (c) => { c.services[0].weekday = 1.5; },
    (c) => { c.services[0].enabled = 'false'; },
    (c) => { c.features.calendar = 'false'; },
    (c) => { c.features.photoImport = null; },
    (c) => { c.timeZone = 'Invalid/Zone'; },
    (c) => { c.timeZone = '+08:00'; },
    (c) => { c.icons.favicon = '../private.png'; },
    (c) => { c.icons.favicon = 'https://example.com/icon.png'; },
    (c) => { c.devotional.dataUrl = 'http://example.com/data.json'; },
    (c) => { c.devotional.linkUrl = 'https://username:password@example.com'; },
    (c) => { c.devotional.enabled = true; c.devotional.dataUrl = ''; },
    (c) => { c.services = []; },
    (c) => { c.services = Array.from({ length: 21 }, (_, i) => ({ ...c.services[0], id: `service${i}` })); },
    (c) => { c.features.secret = 'not-public'; },
    (c) => { c.GEMINI_API_KEY = 'not-public'; },
    (c) => { c.schemaVersion = 2; },
  ]) {
    const config = fixture();
    change(config);
    assert.throws(() => validateChurchConfig(config));
  }
  assert.equal(validateChurchConfig(fixture()).services[3].id, 'midweek');
});

test('generator stages one config for Flutter, Worker and rules without modifying sources', async () => {
  const dir = await mkdtemp(path.join(os.tmpdir(), 'church-deployment-test-'));
  try {
    const configPath = path.join(dir, 'config.json');
    const outDir = path.join(dir, 'out');
    const config = fixture();
    config.services[1].enabled = false;
    config.appName = 'Example <Community> & "Friends"';
    config.shortName = 'Example & Friends';
    const trackedBefore = await readFile(path.join(root, 'worker/generated_config.js'), 'utf8');
    await writeFile(configPath, JSON.stringify(config));
    await prepareDeployment({ configPath, outDir });
    const defines = JSON.parse(await readFile(path.join(outDir, 'dart-defines.json'), 'utf8'));
    assert.deepEqual(JSON.parse(defines.CHURCH_CONFIG_JSON), config);
    const index = await readFile(path.join(outDir, 'web/index.html'), 'utf8');
    assert.match(index, /<title>Example &lt;Community&gt; &amp; &quot;Friends&quot;<\/title>/);
    assert.match(index, /<base href="\/">/);
    assert.doesNotMatch(index, /\$FLUTTER_BASE_HREF/);
    const manifest = JSON.parse(await readFile(path.join(outDir, 'web/manifest.json'), 'utf8'));
    assert.equal(manifest.name, config.appName);
    assert.equal(manifest.short_name, config.shortName);
    assert.equal(manifest.icons[0].src, config.icons.icon192);
    const messagingWorker = await readFile(path.join(outDir, 'web/firebase-messaging-sw.js'), 'utf8');
    assert.ok(messagingWorker.includes(JSON.stringify(config.appName)));
    assert.ok(messagingWorker.includes(JSON.stringify('/' + config.icons.icon192)));
    assert.match(messagingWorker, /__FIREBASE_API_KEY__/); // Firebase injection happens after staging.
    const generated = await readFile(path.join(outDir, 'worker/generated_config.js'), 'utf8');
    assert.deepEqual(JSON.parse(generated.match(/export default ([\s\S]*);/)[1]), config);
    const rules = await readFile(path.join(outDir, 'firestore.rules'), 'utf8');
    assert.match(rules, /"midweek"/);
    assert.match(rules, /"youth"/); // disabled ID remains authorized by its original grants
    assert.match(await readFile(path.join(outDir, 'functions/api/calendar/events.js'), 'utf8'), /requireFeature/);
    assert.equal(await readFile(path.join(root, 'worker/generated_config.js'), 'utf8'), trackedBefore);
    await writeFile(path.join(outDir, 'functions/obsolete.js'), 'old route');
    await prepareDeployment({ configPath, outDir }); // repeatable staging
    await assert.rejects(() => readFile(path.join(outDir, 'functions/obsolete.js')), { code: 'ENOENT' });
    await assert.rejects(() => prepareDeployment({ configPath, outDir: path.join(root, 'worker') }), /tracked source/);
    await assert.rejects(() => prepareDeployment({ configPath, outDir: dir }), /must be empty/);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('private assets are staged without modifying web/ and never escape the selected asset root', async () => {
  const dir = await mkdtemp(path.join(os.tmpdir(), 'church-assets-test-'));
  try {
    const assetsDir = path.join(dir, 'private-assets');
    await mkdir(path.join(assetsDir, 'original'), { recursive: true });
    const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aTpkAAAAASUVORK5CYII=', 'base64');
    await writeFile(path.join(assetsDir, 'original/brand.png'), png);
    await writeFile(path.join(assetsDir, 'not-selected.txt'), 'must not be copied');
    const config = fixture();
    for (const key of Object.keys(config.icons)) config.icons[key] = 'original/brand.png';
    const configPath = path.join(dir, 'config.json');
    const outDir = path.join(dir, 'out');
    await writeFile(configPath, JSON.stringify(config));
    await prepareDeployment({ configPath, outDir, assetsDir });
    assert.deepEqual(await readFile(path.join(outDir, 'web/original/brand.png')), png);
    await assert.rejects(() => readFile(path.join(outDir, 'web/not-selected.txt')), { code: 'ENOENT' });
    await assert.rejects(() => readFile(path.join(root, 'web/original/brand.png')), { code: 'ENOENT' });
    config.icons.favicon = 'missing.png';
    await writeFile(configPath, JSON.stringify(config));
    await assert.rejects(() => prepareDeployment({ configPath, outDir, assetsDir }), { code: 'ENOENT' });
    await writeFile(path.join(dir, 'outside.png'), png);
    await symlink(path.join(dir, 'outside.png'), path.join(assetsDir, 'escape.png'));
    config.icons.favicon = 'escape.png';
    await writeFile(configPath, JSON.stringify(config));
    await assert.rejects(() => prepareDeployment({ configPath, outDir, assetsDir }), /within the assets directory/);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('all services may be disabled for a historical deployment without losing IDs', () => {
  const config = fixture();
  config.services.forEach((service) => { service.enabled = false; });
  assert.equal(validateChurchConfig(config).services.length, 4);
});

test('runtime configuration cannot diverge from any generated deployment setting', () => {
  const original = console.error;
  console.error = () => {};
  try {
    for (const changed of [fixture(), { ...defaults, timeZone: 'America/New_York' }, ENABLED_CONFIG, { ...defaults, appName: 'Different app' }]) {
      assert.throws(() => churchConfig({ CHURCH_CONFIG_JSON: JSON.stringify(changed) }), { status: 500 });
    }
    assert.deepEqual(churchConfig({ [TEST_CHURCH_CONFIG]: fixture() }).services, fixture().services);
  } finally {
    console.error = original;
  }
});

test('equivalent runtime config accepts reordered JSON keys and optional fetch defaults', () => {
  const reverseKeys = (value) => {
    if (Array.isArray(value)) return value.map(reverseKeys);
    if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).reverse().map(([key, entry]) => [key, reverseKeys(entry)]));
    return value;
  };
  const reordered = reverseKeys(defaults);
  assert.deepEqual(churchConfig({ CHURCH_CONFIG_JSON: JSON.stringify(reordered) }), defaults);
  delete reordered.devotional.fetchUrl;
  delete reordered.devotional.fetchFormat;
  assert.equal(churchConfig({ CHURCH_CONFIG_JSON: JSON.stringify(reordered) }).timeZone, defaults.timeZone);
});

test('rule rendering fails closed when its insertion marker is absent', () => {
  assert.throws(() => renderRules('allow write: if false;', fixture()), /exactly one/);
});

test('disabled APIs reject before auth/body parsing and perform no network requests', async () => {
  let calls = 0;
  const noFetch = () => { calls += 1; throw new Error('unexpected network request'); };
  for (const handler of [calendarPost, onRequestPatch, onRequestDelete, importPost]) {
    const response = await withFetch(noFetch, () => handler({
      request: request('POST', { body: { CHURCH_CONFIG_JSON: JSON.stringify(fixture()) } }), env: {}, params: { id: 'id' },
    }));
    assert.equal(response.status, 403);
    assert.match((await response.json()).error, /尚未啟用/);
  }
  await assert.rejects(() => callGemini({}, { images: [], prompt: 'x', fetchImpl: noFetch }), { status: 403 });
  await notifyN8n({ NOTIFY_WEBHOOK_URL: 'https://example.com', NOTIFY_WEBHOOK_SECRET: 'test' }, {}, noFetch);
  assert.equal(calls, 0);
});

test('enabled calendar uses deployment timezone, never a timezone supplied in the body', async () => {
  const config = fixture();
  const env = await testEnv({ [TEST_CHURCH_CONFIG]: config });
  let event;
  const fetchImpl = fakeFetch({ calendar: (_url, init) => { event = JSON.parse(init.body); return Response.json({ id: 'x' }); } });
  const response = await withFetch(fetchImpl, () => calendarPost({ env, request: request('POST', {
    body: { title: 'Meeting', allDay: false, start: '2026-11-03T19:00', end: '2026-11-03T20:00', timeZone: 'Asia/Taipei' },
  }) }));
  assert.equal(response.status, 201);
  assert.equal(event.start.timeZone, 'America/New_York');
  assert.equal(notifyPayload('created', event, {}, config.timeZone).timeZone, 'America/New_York');
});

test('custom fourth service uses admin/group plus its own zone; unknown IDs always fail', async () => {
  const config = fixture();
  config.services[3].enabled = false;
  const env = await testEnv({ [TEST_CHURCH_CONFIG]: config });
  for (const [uid, user, allowed] of [
    [ADMIN_UID, { role: 'admin' }, true],
    [ROSTER_EDITOR_UID, { role: 'staff', groups: ['roster-editors'], zoneTypes: ['midweek'] }, true],
    [ROSTER_EDITOR_UID, { role: 'staff', groups: ['roster-editors'], zoneTypes: ['youth'] }, false],
  ]) {
    const impl = fakeFetch({ users: { [uid]: user } });
    const { idToken } = await import('./helpers.js');
    const permit = await authorize(request('POST', { token: idToken(uid) }), env, { edit: 'roster' }, impl);
    if (allowed) assert.ok(permit.forRosterType('midweek'));
    else assert.throws(() => permit.forRosterType('midweek'), { status: 403 });
    assert.throws(() => permit.forRosterType('unknown'), { status: 400 });
  }
});

test('prompt dates are church-local and quota reset stays Los Angeles midnight across DST', () => {
  assert.equal(dateKeyInZone(new Date('2026-01-01T01:00:00Z'), 'America/New_York'), '2025-12-31');
  assert.equal(dateKeyInZone(new Date('2026-01-01T01:00:00Z'), 'Asia/Taipei'), '2026-01-01');
  assert.equal(quotaResetText(Date.parse('2026-09-24T02:15:00Z'), 'America/New_York'), '2026-09-24 03:00（America/New_York）');
  assert.equal(quotaResetText(Date.parse('2026-11-02T02:00:00Z'), 'Europe/London'), '今天 08:00（Europe/London）');
  assert.equal(quotaResetText(Date.parse('2026-03-08T07:30:00Z'), 'UTC'), '今天 08:00（UTC）');
});
