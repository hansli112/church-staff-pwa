import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { createInstallationManager, UPDATE_STEPS } from './installer/core.mjs';
import { createDemoProviders } from './install-core.mjs';

async function fixture(t, { config } = {}) {
  const rootDir = await mkdtemp(path.join(os.tmpdir(), 'installer-update-'));
  t.after(() => rm(rootDir, { recursive: true, force: true }));
  const calls = [];
  const providers = createDemoProviders({ delayMs: 0 });
  const update = providers.google.update;
  providers.google.update = async (step, context) => { calls.push(step); return update(step, context); };
  const publish = providers.cloudflare.publishUpdate;
  providers.cloudflare.publishUpdate = async (context) => { calls.push('publish'); return publish(context); };
  const build = providers.build;
  providers.build = async (context) => { calls.push(['build', context.liveBuildVersion, context.plan.churchConfig.appName]); return build(context); };
  if (config !== undefined) {
    const fetchSite = providers.fetchSite;
    providers.fetchSite = async (url, options) => url.endsWith('/church-config.json') ? config : fetchSite(url, options);
  }
  const manager = createInstallationManager({ rootDir, ...providers, demo: true, sourceRevision: 'test-v1', release: { version: '2026.10.1', notes: ['新功能'] } });
  t.after(() => manager.dispose());
  return { manager, calls, rootDir };
}
const settle = async (manager) => { while (manager.snapshot().busy) await new Promise((resolve) => setImmediate(resolve)); };

test('update finds the installed site, rebuilds it from its own config and publishes it', async (t) => {
  const { manager, calls } = await fixture(t);
  await assert.rejects(manager.findInstalls(), /請先連接/);
  await manager.connectGoogle();
  await manager.connectCloudflare();
  await manager.findInstalls();
  const [site] = manager.snapshot().installs;
  assert.deepEqual(site, { accountId: '0123456789abcdef0123456789abcdef', accountName: '離線示範帳號', pagesProject: 'grace-church-staff',
    website: 'https://grace-church-staff.pages.dev/', appName: '恩典教會同工助手', readable: true, currentRelease: '2026.9.1' });

  await assert.rejects(manager.planUpdate({ pagesProject: 'someone-else', accountId: site.accountId }), /尋找已安裝的網站/);
  await manager.planUpdate({ pagesProject: site.pagesProject, accountId: site.accountId });
  assert.equal(manager.snapshot().update.status, 'ready');
  assert.equal(manager.snapshot().update.release, '2026.10.1');

  await assert.rejects(manager.applyUpdate({ confirm: 'wrong' }), /勾選確認/);
  assert.deepEqual(calls, []);
  await manager.applyUpdate({ confirm: 'grace-church-staff' });
  const { update } = manager.snapshot();
  assert.equal(update.status, 'complete');
  assert.deepEqual(update.steps.map((step) => step.id), UPDATE_STEPS.map((step) => step.id).filter((id) => id !== 'domain'));
  assert.ok(update.steps.every((step) => step.status === 'complete'));
  // The build gets the live build version (to skip identical rebuilds) and the site's own config.
  assert.deepEqual(calls, ['inspect', ['build', 'installer-demo-old', '恩典教會同工助手'], 'rules', 'publish']);
  // An update is not an installation: nothing to resume, no install record.
  assert.deepEqual(await manager.listRuns(), []);
  assert.equal(manager.snapshot().plan, undefined);
});

test('a site whose config cannot be read is listed but cannot be updated', async (t) => {
  const { manager, calls } = await fixture(t, { config: null });
  await manager.connectGoogle();
  await manager.connectCloudflare();
  await manager.findInstalls();
  const [site] = manager.snapshot().installs;
  assert.equal(site.readable, false);
  await assert.rejects(manager.planUpdate({ pagesProject: site.pagesProject, accountId: site.accountId }), /讀不到教會設定/);
  assert.deepEqual(calls, []);
});

test('a malformed config (e.g. an injected feature) is treated as unreadable, never built', async (t) => {
  const { manager } = await fixture(t, { config: { schemaVersion: 1, appName: 'x', shortName: 'x', timeZone: 'Not/AZone', services: [] } });
  await manager.connectGoogle();
  await manager.connectCloudflare();
  await manager.findInstalls();
  assert.equal(manager.snapshot().installs[0].readable, false);
});

test('an update over the HTTP API runs in the background like an install', async (t) => {
  const { manager } = await fixture(t);
  await manager.connectGoogle();
  await manager.connectCloudflare();
  await manager.findInstalls();
  const [site] = manager.snapshot().installs;
  await manager.planUpdate({ pagesProject: site.pagesProject, accountId: site.accountId });
  const running = manager.applyUpdate({ confirm: site.pagesProject });
  assert.equal(manager.snapshot().busy, true);
  await running;
  await settle(manager);
  assert.equal(manager.snapshot().update.status, 'complete');
});

// A valid PNG header of the given size: enough for the size check, not an image.
function png(size) {
  const bytes = Buffer.alloc(64);
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).copy(bytes);
  bytes.writeUInt32BE(13, 8);
  bytes.write('IHDR', 12, 'latin1');
  bytes.writeUInt32BE(size, 16);
  bytes.writeUInt32BE(size, 20);
  return bytes;
}
const SIZES = { 'favicon.png': 32, 'icons/Icon-192.png': 192, 'icons/Icon-512.png': 512, 'icons/Icon-maskable-192.png': 192, 'icons/Icon-maskable-512.png': 512 };
const encodedIcons = (sizes = SIZES) => Object.fromEntries(Object.entries(sizes).map(([name, size]) => [name, png(size).toString('base64')]));

async function planned(t, options) {
  const env = await fixture(t, options);
  await env.manager.connectGoogle();
  await env.manager.connectCloudflare();
  await env.manager.findInstalls();
  const [site] = env.manager.snapshot().installs;
  await env.manager.planUpdate({ pagesProject: site.pagesProject, accountId: site.accountId });
  return { ...env, site };
}

test('a new logo is checked, then handed to the build as five PNGs of the right sizes', async (t) => {
  const { manager } = await planned(t);
  assert.equal(manager.snapshot().update.iconSource, 'neutral');
  await assert.rejects(manager.setUpdateIcons({ icons: encodedIcons({ ...SIZES, 'icons/Icon-512.png': 256 }) }), /Logo 圖片轉換失敗/);
  await assert.rejects(manager.setUpdateIcons({ icons: { ...encodedIcons(), 'favicon.png': 'not base64!' } }), /Logo 圖片轉換失敗/);
  await manager.setUpdateIcons({ icons: encodedIcons() });
  assert.equal(manager.snapshot().update.iconSource, 'new');
  await manager.setUpdateIcons({ reset: true });
  assert.equal(manager.snapshot().update.iconSource, 'neutral');
});

test('the build gets the new logo, else the icons the site already serves', async (t) => {
  const received = [];
  const liveIcons = Object.fromEntries(Object.entries(SIZES).map(([name, size]) => [name, png(size)]));
  const providers = createDemoProviders({ delayMs: 0 });
  const build = providers.build;
  providers.build = async (context) => { received.push(context.icons); return build(context); };
  providers.fetchAsset = async (url) => liveIcons[Object.keys(SIZES).find((name) => url.endsWith(`/${name}`))] ?? null;
  const rootDir = await mkdtemp(path.join(os.tmpdir(), 'installer-update-icons-'));
  t.after(() => rm(rootDir, { recursive: true, force: true }));
  const second = createInstallationManager({ rootDir, ...providers, demo: true, sourceRevision: 'test-v1', release: { version: '2026.10.1', notes: [] } });
  t.after(() => second.dispose());
  await second.connectGoogle();
  await second.connectCloudflare();
  await second.findInstalls();
  const [site] = second.snapshot().installs;
  await second.planUpdate({ pagesProject: site.pagesProject, accountId: site.accountId });
  assert.equal(second.snapshot().update.iconSource, 'live', 'a logo set earlier is kept');
  await second.applyUpdate({ confirm: site.pagesProject });
  assert.deepEqual(Object.keys(received[0]).sort(), Object.keys(SIZES).sort());
  assert.ok(received[0]['icons/Icon-512.png'].equals(liveIcons['icons/Icon-512.png']));
  await second.setUpdateIcons({ icons: encodedIcons() });
  await second.applyUpdate({ confirm: site.pagesProject });
  assert.ok(received[1]['icons/Icon-512.png'].equals(png(512)));
});

test('a custom domain must be a subdomain, and adds the domain step with DNS instructions', async (t) => {
  const { manager, calls, site } = await planned(t);
  for (const bad of ['hope-church.org', 'grace.pages.dev', 'staff..hope.org', 'staff.hope-church.org/admin', '10.0.0.1']) {
    await assert.rejects(manager.applyUpdate({ confirm: site.pagesProject, customDomain: bad }), /子網域/, bad);
  }
  assert.deepEqual(calls, []);
  await manager.applyUpdate({ confirm: site.pagesProject, customDomain: ' Staff.Hope-Church.org ' });
  const { update } = manager.snapshot();
  assert.equal(update.customDomain, 'staff.hope-church.org');
  assert.equal(update.steps.at(-1).id, 'domain');
  assert.equal(update.steps.at(-1).status, 'complete');
  assert.deepEqual(update.domain, { status: 'pending', cname: { name: 'staff', fullName: 'staff.hope-church.org', target: 'grace-church-staff.pages.dev' } });
  assert.ok(calls.includes('domain'), 'Firebase Auth also learns the domain');
});

test('without a custom domain the domain step is not shown or run', async (t) => {
  const { manager, calls, site } = await planned(t);
  await manager.applyUpdate({ confirm: site.pagesProject });
  assert.ok(!manager.snapshot().update.steps.some((step) => step.id === 'domain'));
  assert.ok(!calls.includes('domain'));
});
