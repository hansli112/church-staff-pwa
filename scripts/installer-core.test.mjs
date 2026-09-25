import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, rm, symlink, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { createInstallationManager, createInstallationPlan, publicError, STEPS } from './installer/core.mjs';
import { createDemoProviders } from './install-core.mjs';
import { commandEnvironment, runCommand } from './installer/process.mjs';

const ACCOUNT = '0123456789abcdef0123456789abcdef';
const identity = { googleEmail: 'operator@example.invalid', accounts: [{ id: ACCOUNT, name: 'Test' }] };
const input = () => ({
  appName: '範例教會', shortName: '同工助手', timeZone: 'Asia/Taipei', region: 'asia-east1',
  services: [{ name: '主日崇拜', label: '主日', weekday: 7 }, { name: '週間聚會', label: '週間', weekday: 3 }],
  adminName: '測試管理員', adminEmail: 'admin@example.invalid', cloudflareAccountId: ACCOUNT,
});
const confirmation = (plan) => ({
  digest: plan.digest, confirmProject: plan.projectId, confirmAdmin: plan.admin.email,
  acknowledgeRegion: true, acknowledgeEmail: true,
});
async function fixture(t, options = {}) {
  const rootDir = await mkdtemp(path.join(os.tmpdir(), 'installer-core-'));
  t.after(() => rm(rootDir, { recursive: true, force: true }));
  const calls = [];
  const providers = createDemoProviders({ delayMs: 0, ...options });
  for (const key of ['google', 'cloudflare']) {
    const original = providers[key].execute;
    providers[key].execute = async (step, context) => { calls.push(step); return original(step, context); };
  }
  const build = providers.build;
  providers.build = async (context) => { calls.push('build'); return build(context); };
  const manager = createInstallationManager({ rootDir, ...providers, demo: true, sourceRevision: 'test-v1' });
  t.after(() => manager.dispose());
  await manager.connectGoogle();
  await manager.connectCloudflare();
  return { rootDir, manager, calls, providers };
}

test('plan is pure, stable, core-only and creates safe resource names', () => {
  const options = { runId: '12345678-1234-4123-8123-123456789abc', sourceRevision: 'v1' };
  const plan = createInstallationPlan(input(), identity, options);
  assert.deepEqual(plan, createInstallationPlan(input(), identity, options));
  assert.match(plan.projectId, /^[a-z][a-z0-9-]{4,28}[a-z0-9]$/);
  assert.equal(plan.pagesProject, plan.projectId);
  assert.equal(plan.churchConfig.services[0].id, 'service1');
  assert.deepEqual(Object.values(plan.churchConfig.features), [false, false, false, false]);
  assert.equal(plan.churchConfig.devotional.enabled, false);
  // Sign-in uses email; the profile username follows bootstrap-admin's default (the name).
  assert.equal(plan.admin.username, '測試管理員');
  assert.equal(plan.mode, 'cloud');
  assert.equal('activationEmailConfirmed' in plan, false);
});

for (const [label, change] of [
  ['ungranted account', { cloudflareAccountId: 'f'.repeat(32) }],
  ['arbitrary project', { projectId: 'existing-project' }],
  ['invalid region', { region: '../outside' }],
  ['invalid admin email', { adminEmail: 'not-email' }],
  ['empty services', { services: [] }],
  ['invalid weekday', { services: [{ label: 'Test', name: 'Test', weekday: 0 }] }],
  ['invalid timezone', { timeZone: 'Not/AZone' }],
]) {
  test(`plan rejects ${label}`, () => assert.throws(() => createInstallationPlan({ ...input(), ...change }, identity)));
}

test('plan creation requires authorized identity and makes no provider mutations', async (t) => {
  const { manager, calls, rootDir } = await fixture(t);
  const plan = await manager.plan(input());
  assert.deepEqual(calls, []);
  assert.equal(manager.snapshot().status, 'ready');
  const file = JSON.parse(await readFile(path.join(rootDir, '.local/install', plan.runId, 'state.json')));
  assert.equal(file.approved, false);
  assert.equal(file.plan.mode, 'demo');
  assert.equal((await manager.listRuns())[0].runId, plan.runId);
});

test('apply requires all explicit confirmations before any mutation', async (t) => {
  const { manager, calls } = await fixture(t);
  const plan = await manager.plan(input());
  for (const field of ['digest', 'confirmProject', 'confirmAdmin', 'acknowledgeRegion', 'acknowledgeEmail']) {
    const values = confirmation(plan);
    delete values[field];
    await assert.rejects(manager.apply(values), /核對/);
  }
  assert.deepEqual(calls, []);
});

test('full installation uses the same interface and saves each completed step', async (t) => {
  const { manager, calls, rootDir } = await fixture(t);
  const plan = await manager.plan(input());
  await manager.apply(confirmation(plan));
  assert.deepEqual(calls, STEPS.map((step) => step.id));
  assert.equal(manager.snapshot().status, 'complete');
  assert(manager.snapshot().steps.every((step) => step.status === 'complete'));
  const file = JSON.parse(await readFile(path.join(rootDir, '.local/install', plan.runId, 'state.json')));
  assert.equal(file.approved, true);
  assert.equal(file.status, 'complete');
  assert.equal(Object.keys(file.intents).length, STEPS.length);
  assert.equal(JSON.stringify(file).includes('access_token'), false);
  await assert.rejects(manager.plan(input()), /不能更改/);
});

test('same-run retry re-inspects earlier steps without creating another plan', async (t) => {
  const { manager, calls } = await fixture(t, { failAt: 'rules' });
  const plan = await manager.plan(input());
  await assert.rejects(manager.apply(confirmation(plan)), /示範中斷/);
  assert.equal(manager.snapshot().status, 'paused');
  assert.equal(manager.snapshot().steps.find((step) => step.id === 'rules').status, 'failed');
  const firstLength = calls.length;
  await manager.apply(confirmation(plan));
  assert.deepEqual(calls.slice(firstLength), STEPS.map((step) => step.id));
  assert.equal(manager.snapshot().plan.runId, plan.runId);
  assert.equal(manager.snapshot().status, 'complete');
});

test('restart loads private checkpoint but requires reconnecting the same identities', async (t) => {
  const { manager, rootDir } = await fixture(t, { failAt: 'rules' });
  const plan = await manager.plan(input());
  await assert.rejects(manager.apply(confirmation(plan)));
  const providers = createDemoProviders({ delayMs: 0 });
  providers.google.inspectIdentity = async () => ({ email: 'different@example.invalid' });
  const next = createInstallationManager({ rootDir, ...providers, demo: true, sourceRevision: 'test-v1' });
  t.after(() => next.dispose());
  await next.load(plan.runId);
  await assert.rejects(next.apply(confirmation(plan)), /帳號與安裝紀錄不符/);
  providers.google.inspectIdentity = async () => ({ email: identity.googleEmail });
  await next.apply(confirmation(plan));
  assert.equal(next.snapshot().status, 'complete');
});

test('demo state cannot be resumed by a live manager', async (t) => {
  const { manager, rootDir } = await fixture(t);
  const plan = await manager.plan(input());
  const live = createInstallationManager({ rootDir, ...createDemoProviders(), sourceRevision: 'test-v1', demo: false });
  await assert.rejects(live.load(plan.runId), /示範安裝與真實安裝/);
  assert.deepEqual(await live.listRuns(), []);
});

test('changed plan, different source and path traversal fail closed', async (t) => {
  const { manager, rootDir } = await fixture(t);
  const plan = await manager.plan(input());
  await assert.rejects(manager.load('../outside'), /識別碼/);
  const otherVersion = createInstallationManager({ rootDir, ...createDemoProviders(), sourceRevision: 'other-version', demo: true });
  await assert.rejects(otherVersion.load(plan.runId), /程式版本/);
  const file = path.join(rootDir, '.local/install', plan.runId, 'state.json');
  const record = JSON.parse(await readFile(file));
  record.plan.projectId = 'unrelated-existing';
  await writeFile(file, JSON.stringify(record));
  await assert.rejects(manager.load(plan.runId), /設定已被更改/);
});

test('private state never follows a .local symlink', async (t) => {
  const { manager, rootDir } = await fixture(t);
  const other = await mkdtemp(path.join(os.tmpdir(), 'installer-outside-'));
  t.after(() => rm(other, { recursive: true, force: true }));
  await symlink(other, path.join(rootDir, '.local'));
  await assert.rejects(manager.plan(input()), /real directory/);
});

test('world-readable run storage is rejected rather than permissions silently changed', async (t) => {
  const { manager, rootDir } = await fixture(t);
  await mkdir(path.join(rootDir, '.local/install'), { recursive: true, mode: 0o755 });
  await assert.rejects(manager.plan(input()), /權限過寬/);
});

test('provider credentials cannot be persisted through the checkpoint interface', async (t) => {
  const { manager, providers, rootDir } = await fixture(t);
  providers.google.execute = async (_, context) => context.save({ resources: { auth: { access_token: 'never-persist-this' } } });
  const plan = await manager.plan(input());
  await assert.rejects(manager.apply(confirmation(plan)), /Credentials/);
  const content = await readFile(path.join(rootDir, '.local/install', plan.runId, 'state.json'), 'utf8');
  assert.equal(content.includes('never-persist-this'), false);
  assert.equal(manager.snapshot().error.message.includes('never-persist-this'), false);
});

test('double-click cannot start a second concurrent operation; cancellation preserves the plan', async (t) => {
  const { manager, providers } = await fixture(t);
  let entered;
  const ready = new Promise((resolve) => { entered = resolve; });
  providers.google.execute = async (_, { signal }) => {
    entered();
    await new Promise((_, reject) => signal.addEventListener('abort', () => reject(new Error('cancelled')), { once: true }));
  };
  const plan = await manager.plan(input());
  const running = manager.apply(confirmation(plan));
  await ready;
  await assert.rejects(manager.apply(confirmation(plan)), /另一個步驟/);
  manager.cancel();
  await assert.rejects(running, /cancelled/);
  assert.equal(manager.snapshot().status, 'paused');
  assert.equal(manager.snapshot().plan.runId, plan.runId);
});

test('ActionRequired displays a waiting step and allowlisted official action', async (t) => {
  const { manager, providers } = await fixture(t);
  providers.google.execute = async () => {
    throw Object.assign(new Error('請在官方頁面完成確認'), {
      code: 'AUTH_SETUP_REQUIRED', safeToDisplay: true, actionRequired: true,
      helpUrl: 'https://console.firebase.google.com/project/example/authentication',
    });
  };
  const plan = await manager.plan(input());
  await assert.rejects(manager.apply(confirmation(plan)));
  assert.equal(manager.snapshot().steps[0].status, 'waiting');
  assert.match(manager.snapshot().error.action.url, /^https:\/\/console.firebase.google.com\//);
});

test('raw error output and malicious help links never reach the browser', () => {
  const unsafe = Object.assign(new Error('Authorization: Bearer private'), { stdout: 'private-key', helpUrl: 'https://evil.invalid/' });
  assert.equal(JSON.stringify(publicError(unsafe)).includes('private'), false);
  assert.equal(publicError(unsafe).action, undefined);
  assert.equal(publicError({ safeToDisplay: true, message: 'safe', action: { url: 'https://user:password@console.firebase.google.com/' } }).action, undefined);
});

test('process runner passes literal arguments without a shell and supports exact environments', async () => {
  const result = await runCommand(process.execPath, ['-e', 'console.log(JSON.stringify({arg:process.argv[1],keys:Object.keys(process.env)}))', '$(touch /should-not-run)'], { env: { ONLY_TEST: '1' }, replaceEnv: true });
  const output = JSON.parse(result.stdout);
  assert.equal(output.arg, '$(touch /should-not-run)');
  assert.deepEqual(output.keys, ['ONLY_TEST']);
  assert.equal(result.exitCode, 0);
});

test('process runner bounds failure output and timeout without exposing it in the message', async () => {
  await assert.rejects(runCommand(process.execPath, ['-e', 'console.error("private-token");process.exit(2)']), (error) => {
    assert.equal(error.message.includes('private-token'), false);
    assert.equal(error.exitCode, 2);
    return true;
  });
  await assert.rejects(runCommand(process.execPath, ['-e', 'setInterval(()=>{},1000)'], { timeoutMs: 20 }), /逾時/);
  const environment = commandEnvironment({ CLOUDFLARE_API_TOKEN: undefined });
  assert.equal(environment.CLOUDFLARE_API_TOKEN, undefined);
});

test('failed read-only preflight records nothing and blocks confirmation', async (t) => {
  const { manager, providers, rootDir, calls } = await fixture(t);
  providers.cloudflare.preflight = async () => { throw Object.assign(new Error('此網站名稱已被使用'), { safeToDisplay: true, code: 'CLOUDFLARE_INSTALL_FAILED' }); };
  await assert.rejects(manager.plan(input()), /已被使用/);
  assert.equal(manager.snapshot().plan, undefined);
  assert.deepEqual(await manager.listRuns(), []);
  assert.deepEqual(calls, []);
  await assert.rejects(readFile(path.join(rootDir, '.local/install')), /ENOENT|EISDIR/);
});

test('preflight re-checks that the connected Google account is still the planned one', async (t) => {
  const { manager, providers } = await fixture(t);
  providers.google.inspectIdentity = async () => ({ email: 'someone-else@example.invalid' });
  await assert.rejects(manager.plan(input()), /帳號與安裝紀錄不符/);
});
