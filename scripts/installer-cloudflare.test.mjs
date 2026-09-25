import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readdir, rm, stat, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { CLOUDFLARE_SCOPES, createCloudflareInstaller, parseDevicePrompt } from './installer/cloudflare.mjs';
import { privateEnvironment, runIsolatedCommand } from './installer/process.mjs';

const ACCOUNT = 'a'.repeat(32);
const PLAN = { runId: 'run-example-1234', projectId: 'new-church-example', pagesProject: 'new-church-example', cloudflareAccountId: ACCOUNT };
const prompt = 'To authorize Wrangler, please visit:\n\n https://dash.cloudflare.com/oauth2/device\n\nand enter the code:\n\n ABCD-EFGH\n';
const identity = { loggedIn: true, authType: 'OAuth Token', email: 'operator@example.test', accounts: [{ id: ACCOUNT, name: 'New church' }], tokenPermissions: CLOUDFLARE_SCOPES };
const response = (result, status = 200) => ({ ok: status >= 200 && status < 300, status, json: async () => ({ success: status === 200, result }) });
const project = (subdomain = `${PLAN.pagesProject}.pages.dev`) => ({ id: 'pages-id-1', name: PLAN.pagesProject, subdomain, production_branch: 'main', source: null, deployment_configs: { production: { env_vars: { FIREBASE_PROJECT_ID: { type: 'plain_text', value: PLAN.projectId }, INSTALLER_RUN_ID: { type: 'plain_text', value: PLAN.runId } } } } });
const intent = () => ({ runId: PLAN.runId, accountId: ACCOUNT, name: PLAN.pagesProject });
async function fixture(t, { command, fetchImpl, ...options } = {}) {
  const sessionDir = await mkdtemp(path.join(os.tmpdir(), 'installer-cloudflare-test-'));
  t.after(() => rm(sessionDir, { recursive: true, force: true }));
  const calls = [];
  const installer = createCloudflareInstaller({
    sessionDir, environment: { PATH: '/safe/bin', HOME: '/real-home', CLOUDFLARE_API_TOKEN: 'real-token', CF_API_KEY: 'real-key', WRANGLER_AUTH_URL: 'https://wrong.example', NODE_OPTIONS: '--require=/bad.js', HTTPS_PROXY: 'https://wrong.example' },
    command: async (exe, args, opts) => {
      calls.push({ exe, args, opts });
      if (command) return command(exe, args, opts);
      if (args[0] === '--version') return { exitCode: 0, stdout: '4.138.0\n' };
      if (args[0] === 'login') { opts.onStdout?.(prompt); return { exitCode: 0, stdout: 'secret-token-in-cli-diagnostic' }; }
      if (args[0] === 'whoami') return { exitCode: 0, stdout: JSON.stringify(identity) };
      if (args[0] === 'auth') return { exitCode: 0, stdout: JSON.stringify({ type: 'oauth', token: 'mock-oauth-token' }) };
      return { exitCode: 0, stdout: 'raw-logs-never-public' };
    },
    fetchImpl: fetchImpl || (() => { throw new Error('Unexpected network operation'); }), ...options,
  });
  t.after(() => installer.dispose());
  const checkpoint = { resources: {}, intents: {} };
  const saves = [];
  const context = { plan: PLAN, checkpoint, runDir: sessionDir, transient: {}, emit: () => {}, save: async (patch) => {
    saves.push(structuredClone(patch));
    Object.assign(checkpoint.resources, patch.resources);
    Object.assign(checkpoint.intents, patch.intents);
  } };
  return { installer, calls, sessionDir, context, saves };
}

test('official device flow uses minimal scopes and never forwards raw output or inherited credentials', async (t) => {
  const { installer, calls, sessionDir } = await fixture(t);
  const events = [];
  assert.deepEqual(await installer.startLogin({ emit: (event) => events.push(event) }), { loggedIn: true, email: identity.email, accounts: identity.accounts });
  assert.equal(events.length, 1);
  assert.equal(events[0].userCode, 'ABCD-EFGH');
  assert.equal(events[0].verificationUrl, 'https://dash.cloudflare.com/oauth2/device');
  assert.ok(!JSON.stringify(events).includes('secret-token'));
  assert.deepEqual(calls[1].args, ['login', '--device', '--browser=false', '--scopes', ...CLOUDFLARE_SCOPES]);
  assert.equal(calls[1].opts.timeoutMs, 310_000);
  for (const { opts } of calls) {
    assert.ok(opts.env.HOME.startsWith(sessionDir + path.sep));
    assert.equal((await stat(opts.env.HOME)).mode & 0o777, 0o700);
    for (const name of ['CLOUDFLARE_API_TOKEN', 'CF_API_KEY', 'WRANGLER_AUTH_URL', 'NODE_OPTIONS', 'HTTPS_PROXY']) assert.equal(opts.env[name], undefined);
    assert.equal(opts.env.CLOUDFLARE_AUTH_USE_KEYRING, 'false');
  }
  const cliHome = calls[0].opts.env.HOME;
  await writeFile(path.join(cliHome, 'fake-token'), 'fake-refresh-token');
  await installer.dispose();
  await assert.rejects(stat(cliHome), { code: 'ENOENT' });
});

test('device prompt accepts only official bare verification URI and a bounded user code', () => {
  for (const address of ['https://evil.example/oauth2/device', 'https://dash.cloudflare.com.evil.example/oauth2/device', 'https://user@dash.cloudflare.com/oauth2/device', 'https://dash.cloudflare.com/oauth2/device?token=secret', 'https://dash.cloudflare.com/oauth2/device#secret', 'https://dash.cloudflare.com/settings/api-tokens']) assert.equal(parseDevicePrompt(prompt.replace('https://dash.cloudflare.com/oauth2/device', address)), null);
  assert.equal(parseDevicePrompt('oauth_token=secret\nhttps://dash.cloudflare.com/oauth2/device'), null);
});

test('denied or timed-out authorization is sanitized and cleans partial credentials', async (t) => {
  for (const failure of ['denied', 'timeout']) {
    const { installer, sessionDir } = await fixture(t, { command: async (_exe, args, opts) => {
      if (args[0] === '--version') return { exitCode: 0, stdout: '4.138.0' };
      await writeFile(path.join(opts.env.HOME, 'partial-token'), 'secret');
      opts.onStdout(prompt);
      if (failure === 'timeout') throw new Error('timeout secret-access-token');
      return { exitCode: 1, stdout: 'denied secret-access-token', stderr: 'secret-refresh-token' };
    } });
    await assert.rejects(installer.startLogin(), (error) => !error.message.includes('secret') && /授權/.test(error.message));
    assert.deepEqual(await readdir(sessionDir), []);
  }
});

test('cancel is observed without falling back to API tokens or browser callbacks', async (t) => {
  const controller = new AbortController(); controller.abort();
  const { installer } = await fixture(t, { command: async () => { throw new Error('cancel'); } });
  await assert.rejects(installer.startLogin({ signal: controller.signal }), /已取消/);
});

test('Pages existing outside this run is rejected before any mutation', async (t) => {
  const methods = [];
  const { installer, context } = await fixture(t, { fetchImpl: async (_url, options) => { methods.push(options.method); return response(project()); } });
  await assert.rejects(installer.execute('pages-project', context), /不會接管/);
  assert.deepEqual(methods, ['GET']);
});

test('Pages create records intent before POST and includes production binding atomically', async (t) => {
  let created = false;
  let savedIntent;
  let post;
  const { installer, context, saves } = await fixture(t, { fetchImpl: async (url, options) => {
    assert.equal(options.redirect, 'error');
    assert.equal(options.headers.Authorization, 'Bearer mock-oauth-token');
    if (url.includes('/deployments?')) return response([]);
    if (options.method === 'POST') {
      assert.deepEqual(savedIntent(), intent());
      post = JSON.parse(options.body); created = true; return response(project());
    }
    return created ? response(project()) : response(null, 404);
  } });
  savedIntent = () => context.checkpoint.intents.pagesProject;
  await installer.execute('pages-project', context);
  assert.equal(post.production_branch, 'main');
  assert.equal(post.deployment_configs.production.env_vars.FIREBASE_PROJECT_ID.value, PLAN.projectId);
  assert.equal(saves[0].intents.pagesProject.runId, PLAN.runId);
  assert.equal(context.checkpoint.resources.pagesProjectId, 'pages-id-1');
  assert.ok(!JSON.stringify(saves).includes('mock-oauth-token'));
});

test('resume queries real state, accepts its own empty project, rejects foreign deployments', async (t) => {
  let deployed = [];
  const { installer, context } = await fixture(t, { fetchImpl: async (url) => response(url.includes('/deployments?') ? deployed : project()) });
  context.checkpoint.intents.pagesProject = intent();
  await installer.execute('pages-project', context);
  deployed = [{ id: 'foreign-deploy', environment: 'production', deployment_trigger: { metadata: { branch: 'main', commit_message: 'someone else' } } }];
  await assert.rejects(installer.execute('pages-project', context), /非本次安裝/);
});

test('publish always specifies production and resumes a confirmed matching deployment without uploading again', async (t) => {
  let deployed = [];
  const { installer, calls, context } = await fixture(t, { fetchImpl: async (url) => response(url.includes('/deployments?') ? deployed : project()), wait: async () => {
    deployed = [{ id: 'deployment-1', environment: 'production', deployment_trigger: { metadata: { branch: 'main', commit_message: 'installer:run-example-1234:installer-abcd' } }, latest_stage: { name: 'deploy', status: 'success' } }];
  } });
  context.checkpoint.intents.pagesProject = intent();
  const buildDir = path.join(context.runDir, 'web-build');
  for (const name of ['index.html', 'main.dart.js', 'flutter_bootstrap.js', 'cache_sw.js', 'firebase-messaging-sw.js', 'version.json', 'canvaskit/canvaskit.wasm', '_worker.js/index.js']) {
    await mkdir(path.dirname(path.join(buildDir, name)), { recursive: true });
    await writeFile(path.join(buildDir, name), 'mock-public-build');
  }
  context.transient = { buildDir, buildVersion: 'installer-abcd' };
  await installer.execute('publish', context);
  const upload = calls.find(({ args }) => args[0] === 'pages');
  assert.deepEqual(upload.args, ['pages', 'deploy', buildDir, '--project-name', PLAN.pagesProject, '--branch', 'main', '--commit-message', 'installer:run-example-1234:installer-abcd', '--commit-dirty=true']);
  assert.equal(upload.opts.env.CLOUDFLARE_ACCOUNT_ID, ACCOUNT);
  assert.equal(context.transient.website, 'https://new-church-example.pages.dev');
  const count = calls.filter(({ args }) => args[0] === 'pages').length;
  await installer.execute('publish', context);
  assert.equal(calls.filter(({ args }) => args[0] === 'pages').length, count);
});

test('changed production binding or non-selected account stops all writes', async (t) => {
  const modified = project(); modified.deployment_configs.production.env_vars.FIREBASE_PROJECT_ID.value = 'other-project';
  const { installer, context } = await fixture(t, { fetchImpl: async () => response(modified) });
  context.checkpoint.intents.pagesProject = intent();
  await assert.rejects(installer.execute('pages-project', context), /不會接管/);
  context.plan = { ...PLAN, cloudflareAccountId: 'b'.repeat(32) };
  await assert.rejects(installer.execute('pages-project', context), /明確選擇/);
});

test('shutdown waits for the CLI to stop before removing its credential directory', async (t) => {
  let started;
  const ready = new Promise((resolve) => { started = resolve; });
  let cliHome;
  const { installer } = await fixture(t, { command: async (_exe, args, opts) => {
    if (args[0] === '--version') return { exitCode: 0, stdout: '4.138.0' };
    cliHome = opts.env.HOME;
    return new Promise((resolve) => {
      opts.signal.addEventListener('abort', async () => {
        await writeFile(path.join(cliHome, 'last-token-write'), 'fake-secret');
        resolve({ exitCode: 1, stdout: '' });
      }, { once: true });
      started();
    });
  } });
  const rejected = assert.rejects(installer.startLogin(), /取消/);
  await ready;
  await installer.dispose();
  await rejected;
  await assert.rejects(stat(cliHome), { code: 'ENOENT' });
});

test('Pages settings fingerprint detects unexpected changes even when ownership labels remain', async (t) => {
  const state = project();
  const { installer, context } = await fixture(t, { fetchImpl: async (url) => response(url.includes('/deployments?') ? [] : state) });
  context.checkpoint.intents.pagesProject = intent();
  await installer.execute('pages-project', context);
  state.deployment_configs.production.compatibility_flags = ['unexpected_flag'];
  await assert.rejects(installer.execute('pages-project', context), /設定已變更/);
});

test('publish refuses an incomplete build before invoking the upload CLI', async (t) => {
  const { installer, calls, context } = await fixture(t, { fetchImpl: async (url) => response(url.includes('/deployments?') ? [] : project()) });
  context.checkpoint.intents.pagesProject = intent();
  context.transient = { buildDir: path.join(context.runDir, 'incomplete'), buildVersion: 'installer-test' };
  await mkdir(context.transient.buildDir);
  await writeFile(path.join(context.transient.buildDir, 'index.html'), 'incomplete');
  await assert.rejects(installer.execute('publish', context), /產物不完整/);
  assert.equal(calls.filter(({ args }) => args[0] === 'pages').length, 0);
});

test('real runner enforces exact environment and bounded timeout without cloud commands', async () => {
  const result = await runIsolatedCommand(process.execPath, ['-e', 'process.stdout.write(JSON.stringify({home:process.env.HOME, secret:process.env.TEST_SECRET}))'], { env: privateEnvironment('/isolated', { PATH: '/usr/bin', TEST_SECRET: 'do-not-inherit' }) });
  assert.deepEqual(JSON.parse(result.stdout), { home: '/isolated' });
  await assert.rejects(runIsolatedCommand(process.execPath, ['-e', 'setInterval(()=>{},1000)'], { env: {}, timeoutMs: 20 }), /逾時/);
});

test('website comes from the Cloudflare subdomain, not a guess from the project name', async (t) => {
  const suffixed = `${PLAN.pagesProject}-7xq.pages.dev`;
  const { installer, context } = await fixture(t, { fetchImpl: async (url) => response(url.includes('/deployments?') ? [] : project(suffixed)) });
  context.checkpoint.intents.pagesProject = intent();
  await installer.execute('pages-project', context);
  assert.equal(context.checkpoint.resources.pagesSubdomain, suffixed);
  for (const bad of ['evil.invalid', 'other-site.pages.dev', null]) {
    const next = await fixture(t, { fetchImpl: async (url) => response(url.includes('/deployments?') ? [] : project(bad)) });
    next.context.checkpoint.intents.pagesProject = intent();
    await assert.rejects(next.installer.execute('pages-project', next.context), /網站網址|不會接管/);
  }
});

test('private environment keeps Wrangler normal output visible', async () => {
  // Wrangler levels: none < error < warn < info < log < debug; below 'log' hides stdout results.
  assert.equal(privateEnvironment('/private/home', { PATH: '/bin' }).WRANGLER_LOG, 'log');
});

test('preflight is read-only: rejects a taken Pages name and never creates anything', async (t) => {
  const methods = [];
  const taken = await fixture(t, { fetchImpl: async (url, options) => { methods.push(options?.method ?? 'GET'); return response(project()); } });
  await assert.rejects(taken.installer.preflight(PLAN), /已被使用/);
  const free = await fixture(t, { fetchImpl: async (url, options) => { methods.push(options?.method ?? 'GET'); return new Response('{}', { status: 404 }); } });
  await free.installer.preflight(PLAN);
  assert.deepEqual([...new Set(methods)], ['GET']);
});
