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
  assert.deepEqual(update.steps.map((step) => step.status), UPDATE_STEPS.map(() => 'complete'));
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
