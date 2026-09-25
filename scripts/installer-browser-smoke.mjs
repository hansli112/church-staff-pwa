#!/usr/bin/env node
// Offline browser smoke test of the installer wizard: demo providers only (no
// cloud requests), driven in a real headless Chrome over the DevTools protocol.
//
//   node scripts/installer-browser-smoke.mjs [--screenshots DIRECTORY]
//
// CHROME selects the browser binary (default: google-chrome). Not part of
// `node --test` because it needs a local Chrome.
import { spawn } from 'node:child_process';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { setTimeout as sleep } from 'node:timers/promises';
import { createInstallationManager } from './installer/core.mjs';
import { startInstallerServer } from './installer/server.mjs';
import { createDemoProviders } from './install-core.mjs';

const screenshotFlag = process.argv.indexOf('--screenshots');
const out = screenshotFlag > 0 ? path.resolve(process.argv[screenshotFlag + 1]) : null;
// Chrome's singleton socket path must stay short, so use the system temp root.
const temporaryRoot = os.platform() === 'win32' ? os.tmpdir() : '/tmp';

const stateRoot = await mkdtemp(path.join(temporaryRoot, 'smoke-state-'));
const manager = createInstallationManager({ rootDir: stateRoot, ...createDemoProviders({ failAt: 'rules', delayMs: 120 }), demo: true, sourceRevision: 'smoke' });
const server = await startInstallerServer({ manager, port: 0 });
const entry = createServer((_request, response) => {
  response.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
  response.end(`<a id="open" href="${server.url}">Open installer</a>`);
});
await new Promise((resolve, reject) => {
  entry.once('error', reject);
  entry.listen(0, 'localhost', resolve);
});
const profile = await mkdtemp(path.join(temporaryRoot, 'smoke-chrome-'));
const chrome = spawn(process.env.CHROME || 'google-chrome', ['--headless=new', '--disable-gpu', '--no-first-run', `--user-data-dir=${profile}`, '--remote-debugging-port=0', 'about:blank'], { stdio: ['ignore', 'ignore', 'pipe'] });
const wsUrl = await new Promise((resolve, reject) => {
  let buf = '';
  chrome.stderr.on('data', (c) => { buf += c; const m = buf.match(/DevTools listening on (ws:\S+)/); if (m) resolve(m[1]); });
  setTimeout(() => reject(new Error('chrome did not start: ' + buf.slice(0, 800))), 20000);
});
const port = new URL(wsUrl).port;
const target = (await (await fetch(`http://127.0.0.1:${port}/json/list`)).json()).find((t) => t.type === 'page');
const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((r) => ws.addEventListener('open', r, { once: true }));
let id = 0; const pending = new Map(); const consoleErrors = [];
const startupEvents = [];
ws.addEventListener('message', (e) => {
  const msg = JSON.parse(e.data);
  if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); }
  if (msg.method === 'Page.frameNavigated' && msg.params.frame.url.startsWith(server.localOrigin)) startupEvents.push('navigation');
  if (msg.method === 'Network.requestWillBeSent' && msg.params.request.url.startsWith(server.localOrigin)) {
    const url = new URL(msg.params.request.url);
    if (url.pathname.startsWith('/api/')) startupEvents.push(`${msg.params.request.method} ${url.pathname}`);
  }
  if (msg.method === 'Runtime.exceptionThrown') consoleErrors.push(msg.params.exceptionDetails.text);
  if (msg.method === 'Log.entryAdded' && msg.params.entry.level === 'error') consoleErrors.push(msg.params.entry.text);
});
const send = (method, params = {}) => new Promise((resolve) => { const n = ++id; pending.set(n, resolve); ws.send(JSON.stringify({ id: n, method, params })); });
const evaluate = async (expression) => {
  const r = await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true });
  if (r.result.exceptionDetails) throw new Error(r.result.exceptionDetails.exception?.description ?? r.result.exceptionDetails.text);
  return r.result.result.value;
};
const waitFor = async (expression, label, ms = 15000) => {
  const end = Date.now() + ms;
  while (Date.now() < end) { if (await evaluate(expression).catch(() => false)) return; await sleep(100); }
  throw new Error(`timeout: ${label}; status=${await evaluate("document.getElementById('status')?.textContent").catch(() => '?')}`);
};
const shot = async (name, width) => {
  await send('Emulation.setDeviceMetricsOverride', { width, height: 900, deviceScaleFactor: 1, mobile: width < 600 });
  await sleep(300);
  const overflow = await evaluate('document.documentElement.scrollWidth > window.innerWidth');
  const { result } = await send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: true });
  if (out) await writeFile(path.join(out, `${name}.png`), Buffer.from(result.data, 'base64'));
  return overflow;
};
const results = [];
const check = (label, ok) => { results.push(`${ok ? 'PASS' : 'FAIL'} ${label}`); if (!ok) process.exitCode = 1; };
try {
  await send('Runtime.enable'); await send('Log.enable'); await send('Page.enable'); await send('Network.enable');
  await send('Page.navigate', { url: `http://localhost:${entry.address().port}/` });
  await waitFor("!!document.getElementById('open')", 'cross-site entry page');
  await evaluate("document.getElementById('open').click()");
  await waitFor("document.getElementById('status').textContent.includes('先連接')", 'session established');
  const boot = startupEvents.slice(0, startupEvents.indexOf('GET /api/state') + 1);
  check('cross-site bootstrap navigates once before reading state', boot.join(',') === 'navigation,POST /api/session,navigation,GET /api/session,GET /api/state');
  check('private link opened and hash token removed from URL', !(await evaluate('location.hash')));
  check('demo banner visible', await evaluate("!document.getElementById('demo-banner').hidden"));
  check('plan disabled before accounts connected', await evaluate("document.getElementById('plan').disabled"));
  await evaluate("document.getElementById('connect-google').click()");
  await waitFor("document.getElementById('google-identity').textContent.includes('@')", 'google connected');
  await evaluate("document.getElementById('connect-cloudflare').click()");
  await waitFor("document.getElementById('cloudflare-account').value.length === 32", 'cloudflare account selected');
  await evaluate(`(() => { const f = document.getElementById('settings-form');
    f.appName.value = '範例教會同工助手'; f.shortName.value = '同工助手';
    f.adminName.value = '測試管理員'; f.adminEmail.value = 'admin@example.invalid';
    document.getElementById('add-service').click();
    const rows = document.querySelectorAll('.service-row');
    rows[1].querySelector('[data-field=label]').value = '青崇';
    rows[1].querySelector('[data-field=name]').value = '青年崇拜';
    rows[1].querySelector('[data-field=weekday]').value = '6'; })()`);
  check('desktop layout has no horizontal overflow', !(await shot('installer-desktop-form', 1280)));
  await evaluate("document.getElementById('plan').click()");
  await waitFor("!document.getElementById('confirmation').hidden", 'plan preview');
  const summary = await evaluate("document.getElementById('summary').textContent");
  check('summary shows project, region and admin', /church-/.test(summary) && summary.includes('asia-east1') && summary.includes('admin@example.invalid'));
  check('apply disabled until both confirmations ticked', await evaluate("document.getElementById('apply').disabled"));
  await evaluate("document.getElementById('confirm-region').click()");
  check('one confirmation is not enough', await evaluate("document.getElementById('apply').disabled"));
  await evaluate("document.getElementById('confirm-email').click()");
  check('apply enabled after both confirmations', !(await evaluate("document.getElementById('apply').disabled")));
  check('mobile layout has no horizontal overflow', !(await shot('installer-mobile-confirm', 390)));
  await send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 900, deviceScaleFactor: 1, mobile: false });
  // Double click must not start two runs.
  await evaluate("document.getElementById('apply').click(); document.getElementById('apply').click()");
  await waitFor("[...document.querySelectorAll('#steps li')].some((li) => li.dataset.state === 'failed')", 'demo interruption at rules');
  check('interruption shown as error with resume button', (await evaluate("document.getElementById('error-message').textContent")).includes('示範中斷') && (await evaluate("document.getElementById('apply').textContent")).includes('接續'));
  // Demo steps finish too fast for polling to catch, so render a running build directly.
  await send('Emulation.setDeviceMetricsOverride', { width: 390, height: 900, deviceScaleFactor: 1, mobile: true });
  const running = await evaluate(`(() => {
    clearInterval(timer);
    render({ ...current, busy: true, steps: current.steps.map((s) => ({ ...s, status: s.id === 'build' ? 'running' : s.status })) });
    const text = document.querySelector('#steps li[data-state=running] .step-state').textContent;
    const result = { text, status: document.getElementById('status').textContent, overflow: document.documentElement.scrollWidth > innerWidth };
    timer = setInterval(refresh, 1500);
    return result;
  })()`);
  check('running step shows elapsed time and expected duration without overflow', /秒/.test(running.text) && running.text.includes('十幾分鐘') && running.status.includes('已經過') && !running.overflow);
  const pendingLabel = await evaluate(`(() => {
    clearInterval(timer);
    render({ ...current, status: 'paused', busy: false, error: { code: 'GOOGLE_OPERATION_PENDING', message: 'Google 仍在建立資源' },
      steps: current.steps.map((step) => ({ ...step, status: step.id === 'firebase' ? 'waiting' : step.status })) });
    const result = [document.querySelector('#steps li[data-state=waiting] .step-state').textContent,
      document.getElementById('apply').textContent];
    timer = setInterval(refresh, 1500);
    return result;
  })()`);
  check('pending Firebase operation says wait then resume', pendingLabel.every((label) => label.includes('稍後接續')));
  await send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 900, deviceScaleFactor: 1, mobile: false });
  const runId = await evaluate("document.getElementById('run-id').textContent");
  // Reload keeps the HttpOnly session and restores progress from the server.
  await send('Page.reload');
  await waitFor("document.getElementById('run-id').textContent.length > 0", 'progress restored after reload');
  check('reload restores the same run from server state', (await evaluate("document.getElementById('run-id').textContent")) === runId);
  await send('Page.navigate', { url: `http://localhost:${entry.address().port}/` });
  await waitFor("!!document.getElementById('open')", 'return to cross-site entry');
  await evaluate("document.getElementById('open').click()");
  await waitFor("document.getElementById('run-id').textContent.length > 0", 'consumed link resumes with existing cookie');
  check('opening a consumed link resumes only an existing session',
    (await evaluate("document.getElementById('run-id').textContent")) === runId &&
    await evaluate("document.getElementById('fatal').hidden && !location.hash"));
  const reuse = await evaluate(`fetch('/api/session', { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Installer-Request': '1' }, body: JSON.stringify({ token: ${JSON.stringify(new URL(server.url).hash.slice(1))} }) }).then((r) => r.status)`);
  check('consumed one-time link cannot create another session', reuse === 401);
  await evaluate("document.getElementById('confirm-region').click(); document.getElementById('confirm-email').click(); document.getElementById('apply').click()");
  await waitFor("!document.getElementById('complete').hidden", 'resume via UI completes', 20000);
  check('completion card links to website', (await evaluate("document.getElementById('website').href")).endsWith('.pages.dev/'));
  await shot('installer-complete', 1280);
  check('resume completes the same run without a new project', manager.snapshot().status === 'complete' && manager.snapshot().plan.runId === runId);
  check('completed state exposes verified website', manager.snapshot().website === `https://${manager.snapshot().plan.pagesProject}.pages.dev/`);
  await send('Network.clearBrowserCookies');
  const beforeMissingCookie = startupEvents.filter((event) => event === 'navigation').length;
  await send('Page.reload');
  await waitFor("!document.getElementById('fatal').hidden", 'missing cookie guidance');
  await sleep(400);
  const noCookie = {
    message: await evaluate("document.getElementById('fatal').textContent"),
    navigations: startupEvents.filter((event) => event === 'navigation').length - beforeMissingCookie,
  };
  check('missing cookie shows guidance without a navigation loop', noCookie.message.includes('Cookie') && noCookie.navigations === 1);
  if (!noCookie.message.includes('Cookie') || noCookie.navigations !== 1) results.push(`  missing-cookie diagnostic: ${JSON.stringify(noCookie)}`);
  await send('Page.navigate', { url: `http://localhost:${entry.address().port}/` });
  await waitFor("!!document.getElementById('open')", 'return to entry without a cookie');
  await evaluate("document.getElementById('open').click()");
  await waitFor("!document.getElementById('fatal').hidden", 'used token without a cookie');
  check('used private link cannot recreate a session after cookies are cleared',
    (await evaluate("document.getElementById('fatal').textContent")).includes('開啟連結已失效'));
  // Every browser error comes from an intentional 401 in the security tests.
  const unexpected = consoleErrors.filter((error) => !error.includes('status of 401'));
  check('no unexpected browser console errors', unexpected.length === 0 && consoleErrors.length >= 3);
  if (unexpected.length) results.push(...unexpected.map((error) => `  console: ${error}`));
} catch (error) {
  results.push(`FAIL ${error.message}`); process.exitCode = 1;
} finally {
  console.log(results.join('\n'));
  ws.close();
  const exited = chrome.exitCode === null ? new Promise((resolve) => chrome.once('exit', resolve)) : null;
  chrome.kill('SIGKILL');
  await exited; // Chrome keeps writing its profile until it exits.
  await server.close();
  await new Promise((resolve) => entry.close(resolve));
  await rm(profile, { recursive: true, force: true }); await rm(stateRoot, { recursive: true, force: true });
}
