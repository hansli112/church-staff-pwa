/* App shell only. FCM owns its separate worker/scope and is never touched. */
'use strict';
const META = 'martha-app-meta-v1';
const STATE_URL = new URL('/__martha_app_cache/state-v1', self.location.origin).href;
const origin = self.location.origin;
const releases = new Map();
const publicIndexes = new Map();
const clientReleases = new Map();
const publicAsset = (url) => !url.search && !url.hash && (
  url.origin === 'https://www.gstatic.com' && /^\/firebasejs\/\d+\.\d+\.\d+\/firebase-(?:app|auth|firestore|firestore-pipelines|functions|storage|messaging|analytics|installations|app-check|performance|remote-config)\.js$/.test(url.pathname) ||
  url.origin === 'https://fonts.gstatic.com' && /^\/s\/(?:notosanstc|notosanssc|roboto)\/v\d+\/[A-Za-z0-9_.-]+\.woff2?$/.test(url.pathname));
const publicIndexUrl = (p) => absolute(`/__martha_app_cache/public/${p.project}/${p.id}`);
async function publicIndex(p) {
  const key = `${p.project}:${p.id}`;
  if (!publicIndexes.has(key)) publicIndexes.set(key, (async () => {
    const cache = await caches.open(cacheName(p));
    const response = await cache.match(publicIndexUrl(p));
    if (!response) return new Map();
    const index = await response.json();
    if (index.schema !== 1 || !Array.isArray(index.files)) fail('Invalid public asset cache');
    const files = new Map(index.files);
    for (const [url, hash] of files) if (!publicAsset(new URL(url)) || !/^[0-9a-f]{64}$/.test(hash.sha256) || !Number.isSafeInteger(hash.size)) fail('Invalid public asset cache');
    return files;
  })());
  return publicIndexes.get(key);
}
async function capturePublic(url, p, response) {
  if (!publicAsset(new URL(url))) fail('Not a public static dependency');
  const cache = await caches.open(cacheName(p));
  const index = await publicIndex(p);
  const expected = index.get(url);
  const cached = expected && await cache.match(url);
  if (cached) return checked(cached, expected);
  const downloaded = response || await fetch(url, { cache: 'force-cache', credentials: 'omit', mode: 'cors' });
  if (!downloaded.ok || downloaded.type === 'opaque') fail('Public dependency download failed');
  const bytes = await downloaded.clone().arrayBuffer();
  if (bytes.byteLength > 4 * 1024 * 1024 || index.size >= 112 || [...index.values()].reduce((sum, file) => sum + file.size, 0) + bytes.byteLength > 24 * 1024 * 1024) return downloaded;
  const entry = { sha256: await digest(bytes), size: bytes.byteLength };
  if (expected && expected.sha256 !== entry.sha256) fail('Pinned public dependency changed');
  await cache.put(url, downloaded.clone());
  index.set(url, entry);
  await cache.put(publicIndexUrl(p), new Response(JSON.stringify({ schema: 1, files: [...index] })));
  return downloaded;
}
let active;
// An update staged in the background, switched to when the app next opens.
let pending;
let loaded;
let operation = Promise.resolve();
const digest = async (bytes) => [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))].map((b) => b.toString(16).padStart(2, '0')).join('');
const cacheName = (p) => `martha-app-${p.project}-${p.id}`;
const absolute = (path) => new URL(path, origin).href;
const fail = (message) => { throw new Error(message); };

function pointer(p, expected) {
  if (!p || p.schema !== 1 || !/^[a-z][a-z0-9-]{0,62}$/.test(p.project) || !/^[0-9a-f]{20}$/.test(p.id) ||
      p.metadata !== `/releases/${p.id}/release.json` || p.manifest !== `/releases/${p.id}/release-manifest.json` ||
      !/^[0-9a-f]{64}$/.test(p.manifestSha256)) fail('Invalid release pointer');
  if (expected && (p.project !== expected.project || p.id !== expected.id)) fail('Release scope changed');
  return p;
}
function manifest(m, p) {
  const prefix = `/releases/${p.id}/`;
  if (!m || m.schema !== 1 || m.project !== p.project || m.id !== p.id ||
      !/^[0-9a-f]{64}$/.test(m.identity) || !m.identity.startsWith(p.id) ||
      m.shell !== `${prefix}app.html` || m.bootstrap !== `${prefix}flutter_bootstrap.js` || !Array.isArray(m.files)) fail('Invalid release manifest');
  const paths = new Set();
  for (const file of m.files) {
    if (!file || typeof file.url !== 'string' || !/^[0-9a-f]{64}$/.test(file.sha256) ||
        !Number.isSafeInteger(file.size) || file.size < 0 || typeof file.optional !== 'boolean' || paths.has(file.url)) fail('Invalid release file');
    const url = new URL(file.url, origin);
    const allowed = /^\/main\.dart(?:\.js_\d+\.part)?\.[0-9a-f]{10}\.js$/.test(file.url) || /^\/main\.dart\.[0-9a-f]{10}\.(?:wasm|mjs)$/.test(file.url) ||
      /^\/asset-bundles\/[0-9a-f]{10}\/assets\/(?:[A-Za-z0-9_.-]+\/)*[A-Za-z0-9_.-]+$/.test(file.url) ||
      (file.url.startsWith(prefix) && /^[A-Za-z0-9_.\/-]+$/.test(file.url.slice(prefix.length)));
    if (url.origin !== origin || url.pathname !== file.url || url.search || url.hash || file.url.includes('/../') || !allowed ||
        file.url.endsWith('/martha_app_sw.js') || file.url.includes('firebase-messaging')) fail('Invalid release file scope');
    paths.add(file.url);
  }
  // The JS main is the one entry every browser can run. Since wasm builds it
  // is cached like the engine, as the page uses it, so it may be optional.
  if (![m.shell, m.bootstrap].every((path) => m.files.some((f) => f.url === path && !f.optional)) ||
      !m.files.some((f) => /^\/main\.dart\.[0-9a-f]{10}\.js$/.test(f.url) && (!f.optional || f.engine))) fail('Incomplete critical release');
  return m;
}
async function checked(response, expected) {
  if (!response?.ok || response.type === 'opaque') fail('Release download failed');
  const bytes = await response.clone().arrayBuffer();
  if (await digest(bytes) !== expected.sha256 || (expected.size != null && bytes.byteLength !== expected.size)) fail('Release hash mismatch');
  return response;
}
async function loadState() {
  if (loaded) return loaded;
  loaded = (async () => {
    const meta = await caches.open(META);
    const saved = await meta.match(STATE_URL);
    if (!saved) return;
    const state = await saved.json();
    if (state.schema !== 1 || !Array.isArray(state.releases)) fail('Invalid cached release state');
    for (const raw of state.releases) {
      const p = pointer(raw);
      const cache = await caches.open(cacheName(p));
      const response = await cache.match(absolute(p.manifest));
      if (!response) continue;
      const verified = await checked(response, { sha256: p.manifestSha256 });
      releases.set(`${p.project}:${p.id}`, { pointer: p, manifest: manifest(await verified.json(), p) });
    }
    if (state.active && releases.has(`${state.active.project}:${state.active.id}`)) active = state.active;
    if (state.pending && releases.has(`${state.pending.project}:${state.pending.id}`)) pending = state.pending;
  })();
  return loaded;
}
async function saveState() {
  const meta = await caches.open(META);
  await meta.put(STATE_URL, new Response(JSON.stringify({ schema: 1, active, pending, releases: [...releases.values()].map((r) => r.pointer) }), { headers: { 'Content-Type': 'application/json' } }));
}
const stagedUrl = (p) => absolute(`/__martha_app_cache/staged/${p.project}/${p.id}`);
const mainKind = (url) => /^\/main\.dart\.[0-9a-f]{10}\.(js|wasm|mjs)$/.exec(url)?.[1];
/**
 * The engine files of [m] this browser will run: those like the ones it ran
 * of [from] (the same canvaskit files, main entries of the same kinds). All of
 * them when that says nothing, or when [m] is the first to have a wasm build.
 * Never the debug symbols: an update fetched every engine, 46 MB, before.
 */
async function enginesFor(m, from) {
  const all = m.files.filter((f) => f.engine && !f.url.endsWith('.symbols'));
  if (!from) return all;
  const cache = await caches.open(cacheName(from.pointer));
  const kits = new Set();
  const kinds = new Set();
  for (const f of from.manifest.files) {
    if (!f.engine || !await cache.match(absolute(f.url))) continue;
    const kit = /^\/releases\/[0-9a-f]{20}\/(canvaskit\/.+)$/.exec(f.url)?.[1];
    if (kit) kits.add(kit);
    if (mainKind(f.url)) kinds.add(mainKind(f.url));
  }
  const picked = all.filter((f) => kits.has(f.url.slice(`/releases/${m.id}/`.length)) || kinds.has(mainKind(f.url)));
  const firstWasm = !from.manifest.files.some((f) => mainKind(f.url) === 'wasm') && all.some((f) => mainKind(f.url) === 'wasm');
  return picked.some((f) => mainKind(f.url)) && !firstWasm ? picked : all;
}
/**
 * Downloads and verifies a release. To boot it: its required files and the
 * engine files the page [used]. To update to it ([from] is the release being
 * replaced): everything but the engine files this browser will not run, and
 * the list of what was staged, which apply checks.
 */
async function prepare(raw, { used = [], from, stage = false } = {}) {
  await loadState();
  const p = pointer(raw);
  const response = await checked(await fetch(absolute(p.manifest), { cache: 'no-store', credentials: 'omit' }), { sha256: p.manifestSha256 });
  const m = manifest(await response.clone().json(), p);
  const cache = await caches.open(cacheName(p));
  const usedPaths = new Set(used.filter((url) => typeof url === 'string').map((url) => new URL(url, origin)).filter((url) => url.origin === origin).map((url) => url.pathname));
  const engines = stage ? new Set((await enginesFor(m, from)).map((f) => f.url)) : usedPaths;
  const staged = [];
  for (const file of m.files) {
    if (file.optional && (file.engine ? !engines.has(file.url) : !stage)) continue;
    staged.push(file.url);
    const cached = await cache.match(absolute(file.url));
    if (cached) { await checked(cached, file); continue; }
    const asset = await checked(await fetch(absolute(file.url), { cache: 'no-store', credentials: 'omit' }), file);
    await cache.put(absolute(file.url), asset);
  }
  await cache.put(absolute(p.manifest), response);
  if (stage) await cache.put(stagedUrl(p), new Response(JSON.stringify(staged)));
  releases.set(`${p.project}:${p.id}`, { pointer: p, manifest: m });
  await saveState();
  return p;
}
async function apply(p) {
  await loadState();
  const release = releases.get(`${p.project}:${p.id}`);
  if (!release || release.pointer.manifestSha256 !== p.manifestSha256) fail('Release was not verified');
  const cache = await caches.open(cacheName(p));
  const staged = await cache.match(stagedUrl(p));
  if (!staged) fail('Release is incomplete');
  // Quota eviction or a partial stage cannot switch the active offline shell.
  const urls = new Set(await staged.json());
  for (const file of release.manifest.files) if (urls.has(file.url)) await checked(await cache.match(absolute(file.url)), file);
  active = p;
  if (pending?.project === p.project && pending.id === p.id) pending = undefined;
  await saveState();
}
const latest = async () => pointer(await (await fetch(absolute('/release.json'), { cache: 'no-store', credentials: 'omit' })).json());
/** Stages [p] over the active release, for the next time the app opens. */
async function stage(p) {
  await prepare(p, { stage: true, from: active && releases.get(`${active.project}:${active.id}`) });
  if (!active || active.project !== p.project || active.id !== p.id) pending = p;
  await saveState();
}
/** Looks for a newer release and stages it; quietly, offline or not. */
async function update() {
  await loadState();
  if (!active) return;
  const p = await latest();
  if (p.project !== active.project || p.id === active.id || p.id === pending?.id) return;
  await stage(p);
}
const queue = (work) => {
  const task = operation.then(work);
  operation = task.catch(() => {});
  return task;
};

self.addEventListener('install', (event) => event.waitUntil(self.skipWaiting()));
self.addEventListener('activate', (event) => event.waitUntil(loadState().then(() => self.clients.claim())));
self.addEventListener('message', (event) => {
  if (!event.ports?.[0] || !event.source?.id) return;
  const port = event.ports[0];
  const task = queue(async () => {
    const source = await self.clients.get(event.source.id);
    if (!source || new URL(source.url).origin !== origin) fail('Invalid app client');
    const data = event.data;
    if (data?.type === 'INIT') {
      const boot = data.boot;
      if (!boot || !/^[0-9a-f]{20}$/.test(boot.id) || boot.metadata !== `/releases/${boot.id}/release.json`) fail('Invalid boot release');
      const p = pointer(await (await fetch(absolute(boot.metadata), { cache: 'no-store', credentials: 'omit' })).json(), boot);
      const used = Array.isArray(data.used) ? data.used : [];
      await prepare(p, { used });
      for (const url of used) {
        if (typeof url === 'string' && publicAsset(new URL(url, origin))) await capturePublic(url, p);
      }
      clientReleases.set(event.source.id, p);
      if (!active || active.project !== p.project) { active = p; await saveState(); }
      return { ok: true, id: p.id };
    }
    if (data?.type === 'CHECK') {
      await loadState();
      const p = await latest();
      if (p.project !== data.project) fail('Release project changed');
      if (p.id === data.runningId) return { ok: true, available: false, id: p.id };
      await stage(p);
      return { ok: true, available: true, release: p };
    }
    if (data?.type === 'APPLY') {
      // A window client's url is where the tab opened (the app starts at
      // /home), not where the app has navigated since, so the page says
      // where it is.
      if (data.safe !== true || typeof data.path !== 'string' || !/^\/(?:c\/[^/]+\/)?me\/?$/.test(data.path)) fail('Finish editing before updating');
      const p = pointer(data.release);
      await apply(p);
      return { ok: true, id: p.id };
    }
    fail('Unknown app-shell operation');
  });
  event.waitUntil(task.then((result) => port.postMessage(result), (error) => port.postMessage({ ok: false, error: error.message })));
});

const appRoute = (path) => /^\/(?:home|rosters|calendar|me|login|welcome|join|create|account|admin)(?:\/|$)/.test(path) || /^\/c\/[^/]+(?:\/(?:home|rosters|calendar|me|join)(?:\/|$)|\/?$)/.test(path);
self.addEventListener('fetch', (event) => {
  const request = event.request;
  const url = new URL(request.url);
  if (request.method !== 'GET' || request.headers?.has?.('authorization')) return;
  if (publicAsset(url)) {
    if (request.credentials === 'include') return;
    event.respondWith((async () => {
      await loadState();
      const p = clientReleases.get(event.clientId) || active;
      if (!p) return fetch(request);
      for (const release of releases.values()) {
        if (release.pointer.project !== p.project) continue;
        const index = await publicIndex(release.pointer);
        const expected = index.get(url.href);
        if (!expected) continue;
        const cache = await caches.open(cacheName(release.pointer));
        const cached = await cache.match(url.href);
        if (cached) return checked(cached, expected);
      }
      return capturePublic(url.href, p, await fetch(request));
    })());
    return;
  }
  if (url.origin !== origin) return;
  const navigation = request.mode === 'navigate' && appRoute(url.pathname);
  const staticAsset = !url.search && !url.hash && [...releases.values()].some((release) => release.manifest.files.some((file) => file.url === url.pathname));
  if (!navigation && !staticAsset) return;
  // What the app opens next is the release staged by then: a page never
  // changes under someone, and nobody has to go to 關於 to get a new version.
  if (navigation) event.waitUntil(queue(update).catch(() => {}));
  event.respondWith((async () => {
    await loadState();
    if (navigation && pending) {
      try { await apply(pending); } catch { pending = undefined; await saveState(); }
    }
    if (navigation && active) {
      const release = releases.get(`${active.project}:${active.id}`);
      const cache = await caches.open(cacheName(active));
      const file = release.manifest.files.find((f) => f.url === release.manifest.shell);
      const shell = await checked(await cache.match(absolute(release.manifest.shell)), file);
      const church = /^\/c\/([A-Za-z0-9_-]+)(?:\/|$)/.exec(url.pathname)?.[1];
      // A fresh Response keeps the requested navigation URL, rather than
      // propagating the immutable snapshot URL into the browser's base URL.
      const headers = new Headers(shell.headers);
      headers.delete('content-length'); headers.delete('content-encoding');
      if (!church) return new Response(await shell.arrayBuffer(), { headers });
      // Public installation identity only; never persist churchPage's HTML,
      // metadata, APIs or any account/church data in the app-shell cache.
      const html = (await shell.text()).replace(/<link rel="manifest" href="[^"]*">/, `<link rel="manifest" href="/c/${church}/manifest.json">`);
      return new Response(html, { headers });
    }
    if (navigation) return fetch(request);
    const release = [...releases.values()].find((r) => r.manifest.files.some((f) => f.url === url.pathname));
    if (!release) return fetch(request);
    const file = release.manifest.files.find((f) => f.url === url.pathname);
    const cache = await caches.open(cacheName(release.pointer));
    const cached = await cache.match(url.href);
    if (cached) return checked(cached, file);
    const response = await checked(await fetch(request), file);
    await cache.put(url.href, response.clone());
    return response;
  })());
});
