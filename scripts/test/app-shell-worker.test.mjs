import assert from 'node:assert/strict';
import { createHash, webcrypto } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import { runInNewContext } from 'node:vm';

const root = join(dirname(fileURLToPath(import.meta.url)), '../..');
const origin = 'https://demo-martha.invalid';
const sha = (body) => createHash('sha256').update(body).digest('hex');
function release(letter, { wasm = false } = {}) {
  const id = letter.repeat(20);
  const entry = (ext) => [`/main.dart.${sha(`${ext} ${id}`).slice(0, 10)}.${ext}`, `${ext} ${id}`, true, true];
  const source = [
    [`/releases/${id}/app.html`, `<html>${id}</html>`, false],
    [`/releases/${id}/flutter_bootstrap.js`, `boot ${id}`, false],
    // Before wasm, the JS main was the one required entry; with wasm, each
    // browser's own entries are cached as it uses them, like the engine.
    ...(wasm ? [entry('js'), entry('wasm'), entry('mjs')] : [[`/main.dart.${sha(`entry ${id}`).slice(0, 10)}.js`, `entry ${id}`, false]]),
    [`/main.dart.js_1.part.${sha(`optional ${id}`).slice(0, 10)}.js`, `optional ${id}`, true],
  ];
  const manifest = { schema: 1, project: 'demo-martha', id, identity: id + '0'.repeat(44), shell: source[0][0], bootstrap: source[1][0], files: source.map(([url, body, optional, engine]) => ({ url, sha256: sha(body), size: Buffer.byteLength(body), optional, ...(engine ? { engine: true } : {}) })) };
  const manifestBytes = JSON.stringify(manifest);
  const pointer = { schema: 1, project: 'demo-martha', id, metadata: `/releases/${id}/release.json`, manifest: `/releases/${id}/release-manifest.json`, manifestSha256: sha(manifestBytes) };
  return { id, pointer, manifest, responses: new Map([...source.map(([url, body]) => [origin + url, body]), [origin + pointer.metadata, JSON.stringify(pointer)], [origin + pointer.manifest, manifestBytes]]) };
}
function worker(a, { clientUrl = origin + '/me' } = {}) {
  const listeners = {};
  const requests = [];
  const responses = new Map(a.responses);
  responses.set(origin + '/release.json', JSON.stringify(a.pointer));
  const stores = new Map();
  const key = (request) => new URL(typeof request === 'string' ? request : request.url, origin).href;
  const caches = { async open(name) {
    if (!stores.has(name)) stores.set(name, new Map());
    const store = stores.get(name);
    return { async match(request) { return store.get(key(request))?.clone(); }, async put(request, response) { store.set(key(request), response.clone()); }, async keys() { return [...store.keys()].map((url) => new Request(url)); } };
  }, async keys() { return [...stores.keys()]; } };
  let offline = false;
  const self = { location: new URL(origin + '/martha_app_sw.js'), clients: { async claim() {}, async get(id) { return { id, url: clientUrl }; } }, async skipWaiting() {}, addEventListener(name, fn) { listeners[name] = fn; } };
  runInNewContext(readFileSync(join(root, 'app/web/martha_app_sw.js'), 'utf8'), { self, caches, crypto: webcrypto, URL, Response, Request, Headers, TextEncoder, console, fetch: async (request) => {
    const url = key(request); requests.push(url);
    if (offline) throw new TypeError('offline');
    const body = responses.get(url); return new Response(body ?? 'not found', { status: body == null ? 404 : 200 });
  } });
  return { requests, responses, stores, setOffline() { offline = true; }, async message(type, data = {}) {
    return new Promise((resolve, reject) => {
      let task;
      listeners.message({ data: { type, ...data }, source: { id: 'tab', url: origin + '/me' }, ports: [{ postMessage: resolve }], waitUntil(value) { task = value; Promise.resolve(task).catch(reject); } });
    });
  }, async request(url, navigate = false) {
    let response;
    listeners.fetch({ request: { method: 'GET', url: /^https?:/.test(url) ? url : origin + url, credentials: navigate ? 'include' : 'same-origin', mode: navigate ? 'navigate' : 'cors' }, respondWith(value) { response = value; }, waitUntil() {} });
    return response ? await response : null;
  } };
}

test('previously used pinned Firebase SDK and Noto fonts reopen offline without caching live Google APIs', async () => {
  const a = release('a');
  const w = worker(a);
  const sdk = 'https://www.gstatic.com/firebasejs/12.19.0/firebase-app.js';
  const font = 'https://fonts.gstatic.com/s/notosanstc/v35/used.woff2';
  w.responses.set(sdk, 'public SDK');
  w.responses.set(font, 'used font');
  await w.message('INIT', { boot: a.pointer, used: [sdk, font] });
  assert.ok(w.requests.includes(sdk));
  assert.ok(w.requests.includes(font));
  assert.ok(!w.requests.some((url) => url.includes('unused.woff2')));
  w.setOffline();
  assert.equal(await (await w.request(sdk)).text(), 'public SDK');
  assert.equal(await (await w.request(font)).text(), 'used font');
  assert.equal(await w.request('https://identitytoolkit.googleapis.com/v1/accounts:lookup'), null);
  assert.equal(await w.request('https://firestore.googleapis.com/v1/projects/demo-martha'), null);
});

test('a corrupt new deferred asset cannot switch the verified offline release', async () => {
  const a = release('a');
  const b = release('b');
  const w = worker(a);
  await w.message('INIT', { boot: a.pointer, used: [] });
  for (const [url, response] of b.responses) w.responses.set(url, response);
  w.responses.set(origin + '/release.json', JSON.stringify(b.pointer));
  w.responses.set(origin + b.manifest.files.find((f) => f.optional).url, 'corrupt');
  const checked = await w.message('CHECK', { project: 'demo-martha', runningId: a.id });
  assert.equal(checked.ok, false);
  assert.match(checked.error, /hash mismatch/);
  assert.equal((await w.message('APPLY', { release: b.pointer, safe: true, path: '/me' })).ok, false);
  w.setOffline();
  assert.equal(await (await w.request('/home', true)).text(), `<html>${a.id}</html>`);
});

test('same-build checks keep optional modules lazy and updates require deliberate safe apply', async () => {
  const a = release('a');
  const b = release('b');
  const w = worker(a);
  await w.message('INIT', { boot: a.pointer, used: [] });
  assert.equal((await w.message('CHECK', { project: 'demo-martha', runningId: a.id })).available, false);
  assert.ok(!w.requests.some((url) => url.includes('.part.')));
  for (const [url, response] of b.responses) w.responses.set(url, response);
  w.responses.set(origin + '/release.json', JSON.stringify(b.pointer));
  assert.equal((await w.message('CHECK', { project: 'demo-martha', runningId: a.id })).available, true);
  assert.ok(w.requests.includes(origin + b.manifest.files.find((f) => f.optional).url));
  assert.equal((await w.message('APPLY', { release: b.pointer, safe: false, path: '/me' })).ok, false);
  assert.equal((await w.message('APPLY', { release: b.pointer, safe: true, path: '/me' })).ok, true);
  w.setOffline();
  assert.equal(await (await w.request('/home', true)).text(), `<html>${b.id}</html>`);
});

test('initial shell install leaves deferred code lazy and never intercepts API/user data', async () => {
  const a = release('a');
  const w = worker(a);
  assert.equal((await w.message('INIT', { boot: a.pointer, used: [] })).ok, true);
  assert.ok(w.requests.includes(origin + a.manifest.shell));
  assert.ok(!w.requests.some((url) => url.includes('.part.')));
  assert.equal(await w.request('/api/calendar'), null);
  assert.equal(await w.request('/c/grace/manifest.json'), null);
  assert.equal(await w.request('/firebase-messaging-sw.js'), null);
  w.setOffline();
  assert.equal(await (await w.request('/home', true)).text(), `<html>${a.id}</html>`);
});

test('a wasm release caches the entries this browser ran and reopens offline from them', async () => {
  const a = release('a', { wasm: true });
  const w = worker(a);
  const [js, wasm, module] = ['js', 'wasm', 'mjs'].map((ext) => a.manifest.files.find((f) => new RegExp(`^/main\\.dart\\.[0-9a-f]{10}\\.${ext}$`).test(f.url)).url);
  assert.equal((await w.message('INIT', { boot: a.pointer, used: [origin + wasm, origin + module] })).ok, true);
  assert.ok(w.requests.includes(origin + wasm));
  assert.ok(w.requests.includes(origin + module));
  assert.ok(!w.requests.includes(origin + js), 'Chrome never downloads the JS main it does not run');
  w.setOffline();
  assert.equal(await (await w.request('/home', true)).text(), `<html>${a.id}</html>`);
  assert.equal(await (await w.request(wasm)).text(), `wasm ${a.id}`);
  assert.equal(await (await w.request(module)).text(), `mjs ${a.id}`);
});

test('an update to a wasm release stages every entry before it can apply', async () => {
  const a = release('a');
  const b = release('b', { wasm: true });
  const w = worker(a);
  await w.message('INIT', { boot: a.pointer, used: [] });
  for (const [url, response] of b.responses) w.responses.set(url, response);
  w.responses.set(origin + '/release.json', JSON.stringify(b.pointer));
  assert.equal((await w.message('CHECK', { project: 'demo-martha', runningId: a.id })).available, true);
  for (const file of b.manifest.files) assert.ok(w.requests.includes(origin + file.url), file.url);
  assert.equal((await w.message('APPLY', { release: b.pointer, safe: true, path: '/me' })).ok, true);
  w.setOffline();
  assert.equal(await (await w.request('/home', true)).text(), `<html>${b.id}</html>`);
});

test('an update applies from 我的 even when the tab first opened elsewhere', async () => {
  // A window client's url is where the tab was created, not where the app
  // has navigated since: the app starts at /home.
  const a = release('a');
  const b = release('b');
  const w = worker(a, { clientUrl: origin + '/home' });
  await w.message('INIT', { boot: a.pointer, used: [] });
  for (const [url, response] of b.responses) w.responses.set(url, response);
  w.responses.set(origin + '/release.json', JSON.stringify(b.pointer));
  assert.equal((await w.message('CHECK', { project: 'demo-martha', runningId: a.id })).available, true);
  assert.equal((await w.message('APPLY', { release: b.pointer, safe: true, path: '/rosters' })).ok, false);
  assert.equal((await w.message('APPLY', { release: b.pointer, safe: true })).ok, false, 'a page must say where it is');
  assert.equal((await w.message('APPLY', { release: b.pointer, safe: true, path: '/me' })).ok, true);
  w.setOffline();
  assert.equal(await (await w.request('/home', true)).text(), `<html>${b.id}</html>`);
});

