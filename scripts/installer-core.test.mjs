import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, rm, symlink, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { coreChurchConfig, createInstallationManager, createInstallationPlan, publicError, regionForTimeZone, REGIONS, STEPS } from './installer/core.mjs';
import { createDemoProviders } from './install-core.mjs';
import { setUpAccountAdmin } from './installer/core.mjs';
import { commandEnvironment, runCommand } from './installer/process.mjs';
import { git } from './test-git.mjs';

const ACCOUNT = '0123456789abcdef0123456789abcdef';
const identity = { googleEmail: 'operator@example.invalid', accounts: [{ id: ACCOUNT, name: 'Test' }] };
const input = () => ({
  appName: '範例教會', shortName: '同工助手', timeZone: 'Asia/Taipei', region: 'asia-east1',
  siteName: 'example-staff',
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
  // The account step asks Cloudflare first, then Google (setUpAccountAdmin).
  const keyState = providers.cloudflare.accountAdminKeyState;
  providers.cloudflare.accountAdminKeyState = async (context, options) => { calls.push('account-admin'); return keyState(context, options); };
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
  // The church names the site; the Google project stays derived from the run.
  assert.equal(plan.pagesProject, 'example-staff');
  assert.equal(createInstallationPlan({ ...input(), siteName: ' Example-Staff ' }, identity, options).pagesProject, 'example-staff');
  assert.equal(plan.churchConfig.services[0].id, 'service1');
  assert.deepEqual(Object.values(plan.churchConfig.features), [false, false, false, false]);
  assert.equal(plan.churchConfig.devotional.enabled, false);
  // Sign-in uses email; the profile username follows bootstrap-admin's default (the name).
  assert.equal(plan.admin.username, '測試管理員');
  assert.equal(plan.mode, 'cloud');
  assert.equal('activationEmailConfirmed' in plan, false);
});

// The app only knows exact IANA spellings; Intl takes any case. A site whose
// config says europe/amsterdam would never get past its loading screen.
test('plan stores the time zone in the spelling Intl resolves to', () => {
  for (const [typed, stored] of [
    ['europe/amsterdam', 'Europe/Amsterdam'],
    ['ASIA/TAIPEI', 'Asia/Taipei'],
    ['us/pacific', 'America/Los_Angeles'],
    ['utc', 'UTC'],
    ['Europe/Amsterdam', 'Europe/Amsterdam'],
  ]) {
    assert.equal(createInstallationPlan({ ...input(), timeZone: typed }, identity).churchConfig.timeZone, stored);
  }
});

// Churches do not pick a data center unless they open the advanced option.
test('without a chosen region the plan uses the one nearest the time zone', () => {
  for (const [timeZone, region] of [
    ['Asia/Taipei', 'asia-east1'], ['America/Los_Angeles', 'us-central1'], ['us/pacific', 'us-central1'],
    ['Europe/Amsterdam', 'europe-west1'], ['Asia/Kuala_Lumpur', 'asia-southeast1'],
  ]) {
    for (const automatic of [undefined, '']) {
      const plan = createInstallationPlan({ ...input(), timeZone, region: automatic }, identity);
      assert.equal(plan.region, region, `${timeZone} ${JSON.stringify(automatic)}`);
    }
  }
  const plan = createInstallationPlan({ ...input(), timeZone: 'America/Los_Angeles', region: 'us-east1' }, identity);
  assert.equal(plan.region, 'us-east1');
});

test('every time zone maps to a region the wizard offers', async () => {
  const offered = new Set(REGIONS.map(([id]) => id));
  const zones = (await readFile(new URL('../test/support/installer_time_zones.txt', import.meta.url), 'utf8'))
    .split('\n').filter((line) => line && !line.startsWith('#'));
  for (const zone of zones) assert.ok(offered.has(regionForTimeZone(zone)), zone);
  for (const [zone, region] of [
    ['Asia/Hong_Kong', 'asia-east2'], ['Asia/Tokyo', 'asia-northeast1'], ['Asia/Seoul', 'asia-northeast1'],
    ['Asia/Singapore', 'asia-southeast1'], ['Australia/Sydney', 'australia-southeast1'], ['Pacific/Auckland', 'australia-southeast1'],
    ['America/New_York', 'us-east1'], ['America/Toronto', 'us-east1'], ['America/Chicago', 'us-central1'],
    ['America/Vancouver', 'us-central1'], ['Europe/London', 'europe-west1'],
    ['Asia/Jayapura', 'asia-southeast1'], ['Pacific/Guam', 'asia-northeast1'], ['Atlantic/Bermuda', 'us-east1'],
    ['Atlantic/Azores', 'europe-west1'], ['Arctic/Longyearbyen', 'europe-west1'],
    // No continent: the nearest by UTC offset.
    ['UTC', 'europe-west1'], ['Etc/GMT+8', 'us-central1'], ['Etc/GMT+5', 'us-east1'], ['Etc/GMT-8', 'asia-east1'],
    ['Antarctica/McMurdo', 'australia-southeast1'],
  ]) assert.equal(regionForTimeZone(zone), region, zone);
});

// Updating a site installed before that fixes its config on the way.
test('an installed config is respelled the same way', () => {
  const config = coreChurchConfig({ appName: 'x', shortName: 'x', timeZone: 'europe/oslo', services: [{ id: 'service1', label: '主日', name: '主日崇拜', weekday: 7, enabled: true }] });
  assert.equal(config.timeZone, 'Europe/Oslo');
});

for (const [label, change] of [
  ['ungranted account', { cloudflareAccountId: 'f'.repeat(32) }],
  ['arbitrary project', { projectId: 'existing-project' }],
  ['invalid region', { region: '../outside' }],
  ['invalid admin email', { adminEmail: 'not-email' }],
  ['empty services', { services: [] }],
  ['invalid weekday', { services: [{ label: 'Test', name: 'Test', weekday: 0 }] }],
  ['invalid timezone', { timeZone: 'Not/AZone' }],
  ['missing site name', { siteName: undefined }],
  ['site name starting with a digit', { siteName: '1church' }],
  ['site name with a dot', { siteName: 'church.staff' }],
  ['site name with a double dash', { siteName: 'church--staff' }],
  ['site name ending with a dash', { siteName: 'church-' }],
  ['site name too long', { siteName: 'a'.repeat(41) }],
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
  // Every step but the account one, which keeps nothing (its key is never saved).
  assert.equal(Object.keys(file.intents).length, STEPS.length - 1);
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

test('an unfinished install planned by an earlier compatible version resumes on the new one', async (t) => {
  const { manager, rootDir } = await fixture(t);
  const plan = await manager.plan(input());
  const newer = createInstallationManager({ rootDir, ...createDemoProviders({ delayMs: 0 }), sourceRevision: 'test-v2', resumableRevisions: ['test-v1'], demo: true });
  t.after(() => newer.dispose());
  assert.deepEqual((await newer.listRuns()).map((run) => run.runId), [plan.runId]);
  await newer.load(plan.runId);
  await newer.connectGoogle();
  await newer.connectCloudflare();
  await newer.apply(confirmation(plan));
  assert.equal(newer.snapshot().status, 'complete');
  // The record keeps the version that planned it; new plans take the new one.
  assert.equal(JSON.parse(await readFile(path.join(rootDir, '.local/install', plan.runId, 'state.json'))).plan.sourceRevision, 'test-v1');
  const unrelated = createInstallationManager({ rootDir, ...createDemoProviders(), sourceRevision: 'test-v3', resumableRevisions: ['test-v2'], demo: true });
  t.after(() => unrelated.dispose());
  assert.deepEqual(await unrelated.listRuns(), []);
  await assert.rejects(unrelated.load(plan.runId), /程式版本/);
});

test('resumable versions run from RESUMES_FROM to the checkout, and none without that history', async (t) => {
  const { readResumableRevisions } = await import('./install-core.mjs');
  const dir = await mkdtemp(path.join(os.tmpdir(), 'installer-resumes-'));
  t.after(() => rm(dir, { recursive: true, force: true }));
  await git(dir, 'init', '-q', '-b', 'main');
  const ids = [];
  for (const name of ['before', 'floor', 'after', 'head']) {
    await git(dir, 'commit', '-q', '--allow-empty', '-m', name);
    ids.push(await git(dir, 'rev-parse', 'HEAD'));
  }
  assert.deepEqual(await readResumableRevisions(dir), []);
  await mkdir(path.join(dir, 'scripts/installer'), { recursive: true });
  await writeFile(path.join(dir, 'scripts/installer/RESUMES_FROM'), `${ids[1]}\n# note\n`);
  assert.deepEqual(new Set(await readResumableRevisions(dir)), new Set(ids.slice(1)));
  await writeFile(path.join(dir, 'scripts/installer/RESUMES_FROM'), `${'0'.repeat(40)}\n`);
  assert.deepEqual(await readResumableRevisions(dir), []);
  // CI checks out one commit, so only the shipped file's shape is checked here.
  assert.match(await readFile(new URL('./installer/RESUMES_FROM', import.meta.url), 'utf8'), /^[0-9a-f]{40}\n/);
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

test('Cloudflare device code expiry is exposed as time left, never an absolute clock', async (t) => {
  const rootDir = await mkdtemp(path.join(os.tmpdir(), 'installer-core-'));
  t.after(() => rm(rootDir, { recursive: true, force: true }));
  const providers = createDemoProviders({ delayMs: 0 });
  let release;
  providers.cloudflare.startLogin = ({ emit }) => {
    emit({ verificationUrl: 'https://dash.cloudflare.com/oauth2/device/verify', userCode: 'aB3dE7f8', expiresInMs: 300_000 });
    return new Promise((resolve) => { release = resolve; });
  };
  const manager = createInstallationManager({ rootDir, ...providers, demo: true, sourceRevision: 'test-v1' });
  t.after(() => manager.dispose());
  const connecting = manager.connectCloudflare();
  const { device } = manager.snapshot();
  assert.equal(device.code, 'aB3dE7f8');
  assert.ok(device.expiresInMs > 295_000 && device.expiresInMs <= 300_000);
  assert.equal(device.expiresAt, undefined);
  release();
  await connecting;
  assert.equal(manager.snapshot().device, undefined);
});

test('connecting Google uses the provider authorization flow when it has one', async (t) => {
  const rootDir = await mkdtemp(path.join(os.tmpdir(), 'installer-core-'));
  t.after(() => rm(rootDir, { recursive: true, force: true }));
  const providers = createDemoProviders({ delayMs: 0 });
  let authorized = 0;
  providers.google.authorize = async () => { authorized++; return { email: 'person@example.invalid' }; };
  const manager = createInstallationManager({ rootDir, ...providers, demo: true, sourceRevision: 'test-v1' });
  t.after(() => manager.dispose());
  await manager.connectGoogle();
  assert.equal(authorized, 1);
  assert.equal(manager.snapshot().identity.googleEmail, 'person@example.invalid');
});

// A valid PNG header of the given size: enough for the size check, not an image.
function png(size, fill = 0) {
  const bytes = Buffer.alloc(64, fill);
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).copy(bytes);
  bytes.writeUInt32BE(13, 8);
  bytes.write('IHDR', 12, 'latin1');
  bytes.writeUInt32BE(size, 16);
  bytes.writeUInt32BE(size, 20);
  return bytes;
}
const SIZES = { 'favicon.png': 32, 'icons/Icon-192.png': 192, 'icons/Icon-512.png': 512, 'icons/Icon-maskable-192.png': 192, 'icons/Icon-maskable-512.png': 512 };
const encodedIcons = (sizes = SIZES) => Object.fromEntries(Object.entries(sizes).map(([name, size]) => [name, png(size).toString('base64')]));
function recordBuildIcons(providers) {
  const received = [];
  const build = providers.build;
  providers.build = async (context) => { received.push(context.icons); return build(context); };
  return received;
}
// A connected demo manager whose build records the icons it is given; pass
// rootDir to open a second manager on the same records, as after a restart.
async function iconFixture(t, rootDir) {
  if (!rootDir) {
    rootDir = await mkdtemp(path.join(os.tmpdir(), 'installer-core-icons-'));
    t.after(() => rm(rootDir, { recursive: true, force: true }));
  }
  const providers = createDemoProviders({ delayMs: 0 });
  const received = recordBuildIcons(providers);
  const manager = createInstallationManager({ rootDir, ...providers, demo: true, sourceRevision: 'test-v1' });
  t.after(() => manager.dispose());
  await manager.connectGoogle();
  await manager.connectCloudflare();
  return { rootDir, manager, received };
}

test('a first install can bring its logo: stored beside the record, covered by the plan, handed to the build', async (t) => {
  const { manager, rootDir, received } = await iconFixture(t);
  const plan = await manager.plan({ ...input(), icons: encodedIcons() });
  assert.deepEqual(Object.keys(plan.icons).sort(), Object.keys(SIZES).sort());
  assert.ok(Object.values(plan.icons).every((hash) => /^[0-9a-f]{64}$/.test(hash)));
  const stored = await readFile(path.join(rootDir, '.local/install', plan.runId, 'logo', 'icons_Icon-512.png'));
  assert.ok(stored.equals(png(512)));
  const state = JSON.parse(await readFile(path.join(rootDir, '.local/install', plan.runId, 'state.json')));
  assert.equal(JSON.stringify(state).includes(png(512).toString('base64')), false);
  await manager.apply(confirmation(plan));
  assert.equal(received.length, 1);
  assert.ok(received[0]['icons/Icon-512.png'].equals(png(512)));
  assert.equal(manager.snapshot().status, 'complete');
});

test('without a logo the plan and the build stay on the neutral icons', async (t) => {
  const { manager, received } = await iconFixture(t);
  const plan = await manager.plan(input());
  assert.equal(plan.icons, undefined);
  await manager.apply(confirmation(plan));
  assert.deepEqual(received, [undefined]);
});

test('a broken logo is refused before any record is written', async (t) => {
  const { manager } = await fixture(t);
  await assert.rejects(manager.plan({ ...input(), icons: encodedIcons({ ...SIZES, 'icons/Icon-512.png': 256 }) }), /Logo 圖片轉換失敗/);
  await assert.rejects(manager.plan({ ...input(), icons: 'not icons' }), /Logo 圖片轉換失敗/);
  assert.deepEqual(await manager.listRuns(), []);
});

test('a resumed install builds the same logo, and a changed logo file stops it before it starts', async (t) => {
  const { manager, rootDir } = await fixture(t, { failAt: 'rules' });
  const plan = await manager.plan({ ...input(), icons: encodedIcons() });
  await assert.rejects(manager.apply(confirmation(plan)), /示範中斷/);
  const { manager: next, received } = await iconFixture(t, rootDir);
  await next.load(plan.runId);
  const logo = path.join(rootDir, '.local/install', plan.runId, 'logo', 'favicon.png');
  const original = await readFile(logo);
  await writeFile(logo, png(32, 1));
  await assert.rejects(next.apply(confirmation(plan)), /Logo 檔案遺失或被更改/);
  assert.notEqual(next.snapshot().status, 'running');
  await writeFile(logo, original);
  await next.apply(confirmation(plan));
  assert.ok(received.at(-1)['favicon.png'].equals(png(32)));
  assert.equal(next.snapshot().status, 'complete');
});

test('a logo file swapped for a link is refused, not followed', async (t) => {
  const { manager, rootDir } = await iconFixture(t);
  const plan = await manager.plan({ ...input(), icons: encodedIcons() });
  const logo = path.join(rootDir, '.local/install', plan.runId, 'logo', 'favicon.png');
  const elsewhere = path.join(rootDir, 'favicon-copy.png');
  await writeFile(elsewhere, await readFile(logo), { mode: 0o600 });
  await rm(logo);
  await symlink(elsewhere, logo);
  await assert.rejects(manager.apply(confirmation(plan)), /Logo 檔案遺失或被更改/);
  assert.equal(manager.snapshot().status, 'ready');
});

// The key passes from Google to Cloudflare in memory. A first install has not
// published, so old keys go at once; an update keeps them until it has.
function accountProviders(calls, { stored = true, live = true, key = { id: 'new0123456789abcd', json: '{"k":1}' } } = {}) {
  return {
    google: {
      newAccountAdminKey: async (_context, options) => { calls.push(['key', options]); return key; },
      retireOtherAccountAdminKeys: async (_context, options) => { calls.push(['retire', options]); },
    },
    cloudflare: {
      accountAdminKeyState: async (_context, options) => { calls.push(['state', options]); return { stored, live }; },
      storeAccountAdminKey: async (_context, json, options) => { calls.push(['store', json, options]); },
    },
  };
}

test('a first install stores the new key, then retires the others at once', async () => {
  const calls = [];
  const context = { transient: {} };
  await setUpAccountAdmin({ ...accountProviders(calls, { stored: false }), context });
  assert.deepEqual(calls, [
    ['state', { update: false }], ['key', { update: false, configured: false }],
    ['store', '{"k":1}', { update: false }], ['retire', { keep: 'new0123456789abcd' }],
  ]);
  assert.equal(context.transient.accountAdminRedeploy, 'key-new012345678');
});

test('an update stores the new key and leaves retiring the old ones until it has published', async () => {
  const calls = [];
  const context = { transient: {} };
  await setUpAccountAdmin({ ...accountProviders(calls), context, update: true });
  assert.ok(!calls.some(([name]) => name === 'retire'));
  assert.equal(context.transient.retireAccountAdminKeys, 'new0123456789abcd');
  assert.equal(context.transient.accountAdminRedeploy, 'key-new012345678');
});

test('a failed store never retires anything', async () => {
  const calls = [];
  const providers = accountProviders(calls, { stored: false });
  providers.cloudflare.storeAccountAdminKey = async () => { throw new Error('Cloudflare down'); };
  await assert.rejects(setUpAccountAdmin({ ...providers, context: { transient: {} } }), /Cloudflare down/);
  assert.ok(!calls.some(([name]) => name === 'retire'));
});

test('a key stored by an update that never deployed gets deployed now', async () => {
  for (const [live, expected] of [[false, 'key'], [true, undefined], [undefined, undefined]]) {
    const context = { transient: {} };
    await setUpAccountAdmin({ ...accountProviders([], { live, key: null }), context, update: true });
    assert.equal(context.transient.accountAdminRedeploy, expected);
  }
});
