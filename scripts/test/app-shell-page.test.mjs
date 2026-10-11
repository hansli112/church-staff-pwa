import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import { runInNewContext } from 'node:vm';

const root = join(dirname(fileURLToPath(import.meta.url)), '../..');
test('page reports frozen boot version and never reloads for visibility or update checks', async () => {
  const listeners = {};
  const boot = Object.freeze({ schema: 1, id: 'a'.repeat(20), project: 'demo-martha', metadata: `/releases/${'a'.repeat(20)}/release.json` });
  let splash = {};
  let observer;
  let idle;
  let registrations = 0;
  let reloads = 0;
  const messages = [];
  const worker = { postMessage(data, ports) { messages.push(data); ports[0].postMessage(data.type === 'CHECK' ? { ok: true, available: true, release: { id: 'b'.repeat(20) } } : { ok: true }); } };
  const location = { pathname: '/me', reload() { reloads++; } };
  const window = { marthaBootRelease: boot, location, addEventListener(name, fn) { listeners[name] = fn; }, dispatchEvent() {}, requestIdleCallback(fn) { idle = fn; } };
  const document = { body: {}, activeElement: null, getElementById() { return splash; }, addEventListener(name, fn) { listeners[name] = fn; } };
  const navigator = { serviceWorker: { async register() { registrations++; return { active: worker }; }, async getRegistration() { return { active: worker }; } } };
  runInNewContext(readFileSync(join(root, 'app/web/martha_app.js'), 'utf8'), { window, document, navigator, location, MessageChannel, MutationObserver: class { constructor(fn) { observer = fn; } observe() {} disconnect() {} }, performance: { getEntriesByType() { return []; } }, URL, Event, setTimeout, clearTimeout, console });
  assert.equal(window.marthaUpdate.runningVersion, boot.id);
  assert.equal(registrations, 0);
  splash = null; observer();
  assert.equal(registrations, 0);
  idle();
  await new Promise((resolve) => setTimeout(resolve, 10));
  assert.equal(registrations, 1);
  assert.ok(messages.some((m) => m.type === 'INIT'));
  const checked = await window.marthaUpdate.check();
  assert.equal(checked.available, true);
  assert.equal(window.marthaUpdate.runningVersion, boot.id);
  assert.equal(reloads, 0);
  assert.equal(listeners.visibilitychange, undefined);
  window.marthaUpdate.setEditing(true);
  await assert.rejects(window.marthaUpdate.apply(), /editing/);
  window.marthaUpdate.setEditing(false);
  await window.marthaUpdate.apply();
  assert.equal(reloads, 1);
});

test('page tells the worker which main entries and engine it ran, and nothing else of its own', async () => {
  const id = 'a'.repeat(20);
  const boot = Object.freeze({ schema: 1, id, project: 'demo-martha', metadata: `/releases/${id}/release.json` });
  const messages = [];
  let idle;
  const worker = { postMessage(data, ports) { messages.push(data); ports[0].postMessage({ ok: true }); } };
  const origin = 'https://demo-martha.invalid';
  const loaded = [
    `${origin}/main.dart.ad50759298.wasm`, `${origin}/main.dart.b108204f3a.mjs`, `${origin}/releases/${id}/canvaskit/skwasm.wasm`,
    `${origin}/main.dart.js_1.part.5567a01230.js`, `${origin}/asset-bundles/0123456789/assets/FontManifest.json`, `${origin}/api/calendar`,
  ];
  const window = { marthaBootRelease: boot, location: { pathname: '/home' }, addEventListener() {}, requestIdleCallback(fn) { idle = fn; } };
  const document = { body: {}, activeElement: null, getElementById() { return null; } };
  const navigator = { serviceWorker: { async register() { return { active: worker }; } } };
  runInNewContext(readFileSync(join(root, 'app/web/martha_app.js'), 'utf8'), { window, document, navigator, MessageChannel, MutationObserver: class {}, performance: { getEntriesByType() { return loaded.map((name) => ({ name })); } }, URL, setTimeout, clearTimeout, console });
  idle();
  await new Promise((resolve) => setTimeout(resolve, 10));
  assert.deepEqual(messages.find((m) => m.type === 'INIT').used, loaded.slice(0, 3));
});
