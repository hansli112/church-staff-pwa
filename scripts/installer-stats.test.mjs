import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { createInstallationManager } from './installer/core.mjs';
import { createStatsReporter, STATS_URL } from './installer/stats.mjs';
import { createDemoProviders } from './install-core.mjs';
import { parseEvent } from '../stats-worker/index.js';

const RUN_ID = '12345678-1234-4123-8123-123456789abc';
const REVISION = 'a'.repeat(40);

test('a reported event carries only the event, ids, step, code and version', async () => {
  const sent = [];
  const report = createStatsReporter({ revision: REVISION, session: RUN_ID, fetchImpl: async (url, init) => sent.push({ url, init }) });
  report('stopped', { runId: RUN_ID, step: 'firebase', code: 'GOOGLE_TERMS_REQUIRED', email: 'admin@example.invalid' });
  report('stopped', { runId: RUN_ID, step: 'build', code: 'flutter exited: /home/someone' });
  assert.equal(sent[0].url, STATS_URL);
  assert.deepEqual(JSON.parse(sent[0].init.body), { event: 'stopped', session: RUN_ID, runId: RUN_ID, step: 'firebase', code: 'GOOGLE_TERMS_REQUIRED', revision: REVISION });
  assert.equal(JSON.parse(sent[1].init.body).code, 'OTHER');
  // The worker accepts exactly what the installer sends.
  for (const { init } of sent) assert.ok(parseEvent(JSON.parse(init.body)));
});

test('counting never waits on, or fails with, the endpoint', async () => {
  const hang = createStatsReporter({ fetchImpl: () => new Promise(() => {}) });
  const reject = createStatsReporter({ fetchImpl: async () => { throw new Error('offline'); } });
  const explode = createStatsReporter({ fetchImpl: () => { throw new Error('no fetch'); } });
  for (const report of [hang, reject, explode]) assert.equal(report('opened'), undefined);
  await new Promise((resolve) => setImmediate(resolve));
});

test('the worker refuses anything but the fixed event shape', () => {
  const base = { event: 'started', session: RUN_ID, runId: RUN_ID, revision: REVISION };
  assert.deepEqual(parseEvent(base), { event: 'started', session: RUN_ID, runId: RUN_ID, step: null, code: null, revision: REVISION });
  for (const bad of [null, [], { ...base, event: 'deleted' }, { ...base, session: 'x' }, { ...base, runId: 'church-name' },
    { ...base, step: 'Firebase' }, { ...base, code: 'admin@example.invalid' }, { ...base, revision: 'main' }]) {
    assert.equal(parseEvent(bad), null);
  }
});

async function counted(t, options, report) {
  const rootDir = await mkdtemp(path.join(os.tmpdir(), 'installer-stats-'));
  t.after(() => rm(rootDir, { recursive: true, force: true }));
  const events = [];
  const manager = createInstallationManager({ rootDir, ...createDemoProviders({ delayMs: 0, ...options }), demo: true, sourceRevision: 'test-v1',
    report: report ?? ((event, fields) => events.push({ event, ...fields })) });
  t.after(() => manager.dispose());
  await manager.connectGoogle();
  await manager.connectCloudflare();
  const plan = await manager.plan({
    appName: '範例教會', shortName: '同工助手', timeZone: 'Asia/Taipei', region: 'asia-east1', siteName: 'example-staff',
    services: [{ name: '主日崇拜', label: '主日', weekday: 7 }], adminName: '管理員', adminEmail: 'admin@example.invalid',
    cloudflareAccountId: '0123456789abcdef0123456789abcdef',
  });
  const confirm = { digest: plan.digest, confirmProject: plan.projectId, confirmAdmin: plan.admin.email, acknowledgeRegion: true, acknowledgeEmail: true };
  return { manager, events, plan, confirm };
}

test('an install counts its start, where it stopped, and its finish', async (t) => {
  const { manager, events, plan, confirm } = await counted(t, { failAt: 'database' });
  assert.deepEqual(events, []);
  await assert.rejects(manager.apply(confirm));
  await manager.apply(confirm);
  assert.deepEqual(events.map(({ event, step }) => [event, step]), [['started', undefined], ['stopped', 'database'], ['started', undefined], ['completed', undefined]]);
  assert.ok(events.every((event) => event.runId === plan.runId));
  assert.match(events[1].code, /^[A-Z_]+$/);
});

test('a reporter that throws never breaks the install', async (t) => {
  const { manager, confirm } = await counted(t, {}, () => { throw new Error('boom'); });
  await manager.apply(confirm);
  assert.equal(manager.snapshot().status, 'complete');
});
