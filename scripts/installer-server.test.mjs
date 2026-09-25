import assert from 'node:assert/strict';
import { request as httpRequest } from 'node:http';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { createInstallationManager } from './installer/core.mjs';
import { startInstallerServer } from './installer/server.mjs';
import { createDemoProviders } from './install-core.mjs';

async function fixture(t, options = {}) {
  const rootDir = await mkdtemp(path.join(os.tmpdir(), 'installer-server-'));
  const manager = createInstallationManager({ rootDir, ...createDemoProviders({ delayMs: 0 }), demo: true });
  const server = await startInstallerServer({ manager, port: 0, ...options });
  t.after(async () => { await server.close(); await rm(rootDir, { recursive: true, force: true }); });
  const baseHeaders = { Origin: server.origin, 'X-Installer-Request': '1', 'Content-Type': 'application/json' };
  const call = (route, body, headers = {}) => fetch(`${server.localOrigin}${route}`, {
    method: body === undefined ? 'GET' : 'POST', headers: { ...baseHeaders, ...headers },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  async function login() {
    const response = await call('/api/session', { token: new URL(server.url).hash.slice(1) });
    const cookie = response.headers.get('set-cookie')?.split(';')[0];
    const { csrf } = await response.json();
    assert.equal(response.status, 200);
    return { Cookie: cookie, 'X-Installer-CSRF': csrf };
  }
  return { manager, server, call, login };
}

test('static UI uses restrictive headers and never includes the private bootstrap token', async (t) => {
  const { server } = await fixture(t);
  const response = await fetch(server.localOrigin);
  const body = await response.text();
  assert.equal(response.status, 200);
  assert.match(response.headers.get('content-security-policy'), /frame-ancestors 'none'/);
  assert.equal(response.headers.get('cache-control'), 'no-store');
  assert.equal(response.headers.get('referrer-policy'), 'no-referrer');
  assert.equal(body.includes(new URL(server.url).hash.slice(1)), false);
  assert.match(body, /教會安裝精靈/);
});

// The Cloud Shell terminal link opens the wizard as a cross-site navigation.
// fetch() rewrites Sec-Fetch-Mode, so these use http.request.
function rawGet(origin, route, headers) {
  return new Promise((resolve, reject) => {
    const request = httpRequest(`${origin}${route}`, { headers }, (response) => {
      let body = '';
      response.setEncoding('utf8').on('data', (chunk) => { body += chunk; }).on('end', () => resolve({ status: response.statusCode, body }));
    });
    request.on('error', reject).end();
  });
}

test('only the top-level page load may arrive cross-site', async (t) => {
  const { server, call } = await fixture(t);
  const navigation = { 'Sec-Fetch-Site': 'cross-site', 'Sec-Fetch-Mode': 'navigate', 'Sec-Fetch-Dest': 'document' };
  const page = await rawGet(server.localOrigin, '/', navigation);
  assert.equal(page.status, 200);
  assert.match(page.body, /教會安裝精靈/);
  assert.equal((await rawGet(server.localOrigin, '/', { ...navigation, 'Sec-Fetch-Dest': 'iframe' })).status, 403);
  assert.equal((await rawGet(server.localOrigin, '/app.js', { ...navigation, 'Sec-Fetch-Dest': 'script', 'Sec-Fetch-Mode': 'no-cors' })).status, 403);
  assert.equal((await rawGet(server.localOrigin, '/api/state', { ...navigation, 'X-Installer-Request': '1' })).status, 403);
  assert.equal((await call('/api/session', { token: new URL(server.url).hash.slice(1) }, { 'Sec-Fetch-Site': 'cross-site' })).status, 403);
});

test('API requires one-time bootstrap, HttpOnly cookie and anti-CSRF token', async (t) => {
  const { call, login } = await fixture(t);
  assert.equal((await call('/api/state')).status, 401);
  assert.equal((await call('/api/session', { token: 'wrong' })).status, 401);
  const auth = await login();
  assert.equal((await call('/api/state', undefined, auth)).status, 200);
  assert.equal((await call('/api/session', { token: 'already-used' })).status, 401);
  assert.equal((await call('/api/connect/google', {}, { Cookie: auth.Cookie })).status, 403);
  const state = await call('/api/session', undefined, auth);
  assert.equal((await state.json()).csrf, auth['X-Installer-CSRF']);
});

test('session cookie is HttpOnly and SameSite Strict', async (t) => {
  const { call, server } = await fixture(t);
  const response = await call('/api/session', { token: new URL(server.url).hash.slice(1) });
  assert.match(response.headers.get('set-cookie'), /HttpOnly; SameSite=Strict/);
});

for (const [label, headers] of [
  ['foreign origin', { Origin: 'https://evil.invalid' }],
  ['spoofed proxy host', { 'X-Forwarded-Host': 'evil.invalid' }],
  ['cross-site fetch', { 'Sec-Fetch-Site': 'cross-site' }],
  ['missing request marker', { 'X-Installer-Request': '' }],
  ['missing mutation origin', { Origin: '' }],
]) {
  test(`rejects ${label} before creating a session`, async (t) => {
    const { call, server } = await fixture(t);
    assert.equal((await call('/api/session', { token: new URL(server.url).hash.slice(1) }, headers)).status, 403);
  });
}

// fetch() silently replaces a custom Host header, so send it with http.request.
test('rejects DNS rebinding host before creating a session', async (t) => {
  const { server } = await fixture(t);
  const { port } = new URL(server.localOrigin);
  const status = await new Promise((resolve, reject) => {
    const body = JSON.stringify({ token: new URL(server.url).hash.slice(1) });
    const request = httpRequest({ host: '127.0.0.1', port, path: '/api/session', method: 'POST', headers: {
      Host: 'evil.invalid', Origin: server.origin, 'X-Installer-Request': '1', 'Content-Type': 'application/json',
    } }, (response) => { response.resume(); resolve(response.statusCode); });
    request.on('error', reject);
    request.end(body);
  });
  assert.equal(status, 403);
});

test('static serving cannot expose private files, arbitrary paths or a public initialization API', async (t) => {
  const { call, server } = await fixture(t);
  for (const file of ['/.local/church.json', '/scripts/installer/google.mjs', '/%2e%2e/package.json', '/api/admin']) {
    const response = await call(file);
    assert([401, 404].includes(response.status), `${file}: ${response.status}`);
  }
  assert.equal((await fetch(`${server.localOrigin}/app.js`)).status, 200);
  assert.equal((await fetch(`${server.localOrigin}/style.css`)).status, 200);
});

test('body content type and malformed JSON are rejected', async (t) => {
  const { call, server } = await fixture(t);
  assert.equal((await call('/api/session', {}, { 'Content-Type': 'text/plain' })).status, 415);
  const response = await fetch(`${server.localOrigin}/api/session`, {
    method: 'POST', headers: { Origin: server.origin, 'X-Installer-Request': '1', 'Content-Type': 'application/json' }, body: '{broken',
  });
  assert.equal(response.status, 400);
});

test('expired bootstrap cannot establish a session', async (t) => {
  let clock = 100;
  const { call, server } = await fixture(t, { now: () => clock, bootstrapTimeoutMs: 10 });
  clock = 120;
  assert.equal((await call('/api/session', { token: new URL(server.url).hash.slice(1) })).status, 401);
});

test('idle expiry clears provider identity and requires a fresh session', async (t) => {
  let clock = 100;
  const { call, login, manager } = await fixture(t, { now: () => clock, idleTimeoutMs: 20 });
  const auth = await login();
  await manager.connectGoogle();
  assert(manager.snapshot().identity.googleEmail);
  clock += 25;
  assert.equal((await call('/api/state', undefined, auth)).status, 401);
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(manager.snapshot().identity.googleEmail, undefined);
});

test('public origin is restricted to private Cloud Shell preview domains', async () => {
  await assert.rejects(startInstallerServer({ manager: { dispose() {} }, port: 0, publicOrigin: 'https://installer.evil.invalid' }), /Cloud Shell/);
});

test('authenticated HTTP flow connects, plans, confirms, completes and lists resumable state', async (t) => {
  const { call, login, manager } = await fixture(t);
  const auth = await login();
  assert.equal((await call('/api/connect/google', {}, auth)).status, 202);
  while (manager.snapshot().busy) await new Promise((resolve) => setImmediate(resolve));
  assert.equal((await call('/api/connect/cloudflare', {}, auth)).status, 202);
  while (manager.snapshot().busy) await new Promise((resolve) => setImmediate(resolve));
  const response = await call('/api/plan', {
    appName: '範例教會', shortName: '同工助手', timeZone: 'Asia/Taipei', region: 'asia-east1',
    services: [{ name: '主日崇拜', label: '主日', weekday: 7 }],
    adminName: '測試管理員', adminEmail: 'admin@example.invalid', cloudflareAccountId: '0123456789abcdef0123456789abcdef',
  }, auth);
  assert.equal(response.status, 200);
  const plan = await response.json();
  assert.equal((await call('/api/runs', undefined, auth)).status, 200);
  assert.equal((await call('/api/apply', {
    digest: plan.digest, confirmProject: plan.projectId, confirmAdmin: plan.admin.email,
    acknowledgeRegion: true, acknowledgeEmail: true,
  }, auth)).status, 202);
  while (manager.snapshot().busy) await new Promise((resolve) => setImmediate(resolve));
  const state = await (await call('/api/state', undefined, auth)).json();
  assert.equal(state.status, 'complete');
  assert.equal(state.demo, true);
  assert.equal(state.plan.runId, plan.runId);
  assert.equal(state.website, `https://${plan.pagesProject}.pages.dev/`);
  assert.equal('resources' in state, false);
  assert.equal('backups' in state, false);
});

test('a running step keeps the session alive; expiry waits for a grace period after it stops', async (t) => {
  let clock = 1_000;
  let busy = false;
  let disposed = 0;
  const manager = { snapshot: () => ({ busy }), dispose: async () => { disposed += 1; }, cancel() {} };
  const server = await startInstallerServer({ manager, port: 0, now: () => clock, idleTimeoutMs: 100, absoluteTimeoutMs: 1_000 });
  t.after(() => server.close());
  const headers = { Origin: server.origin, 'X-Installer-Request': '1', 'Content-Type': 'application/json' };
  const response = await fetch(`${server.localOrigin}/api/session`, { method: 'POST', headers, body: JSON.stringify({ token: new URL(server.url).hash.slice(1) }) });
  const auth = { ...headers, Cookie: response.headers.get('set-cookie').split(';')[0] };
  const state = () => fetch(`${server.localOrigin}/api/state`, { headers: auth }).then((r) => r.status);
  busy = true;
  clock += 5_000; // Past both the idle and absolute limits while a step runs (tab closed).
  assert.equal(await state(), 200);
  busy = false;
  clock += 50; // Within the grace period after the step stopped.
  assert.equal(await state(), 200);
  clock += 200;
  assert.equal(await state(), 401);
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(disposed, 1);
});
