'use strict';

// Custom cache-first service worker for church_staff_pwa.
//
// Why this exists: Flutter 3.27+ ships a `flutter_service_worker.js` that
// unregisters itself on activate (the auto-generated one is intentionally
// destructive — Flutter expects apps to bring their own SW). Without a
// caching SW, every reload re-downloads main.dart.js (~3MB) and
// canvaskit.wasm (~7MB).
//
// Strategy:
//   - cache-first for hashed/static assets (.js, .wasm, fonts, images)
//   - network-first for navigation entry files so updates land fast
//     (index.html, manifest.json, version.json, flutter_bootstrap.js)
//   - never intercept Firestore / Firebase / Google Calendar / FCM —
//     those must always be live
//
// Cache invalidation: bump CACHE_VERSION when shipping a release that needs
// to throw away the previous bundle. The activate handler will delete any
// cache whose key doesn't match the current version.

const CACHE_VERSION = 'v1';
const CACHE_NAME = `church-staff-pwa-${CACHE_VERSION}`;

// Same-origin paths that should be re-fetched from network when online so
// users see updates promptly. Cached copy is the offline fallback.
const NETWORK_FIRST_PATHS = new Set([
  '/',
  '/index.html',
  '/version.json',
  '/manifest.json',
  '/flutter_bootstrap.js',
  '/flutter.js',
  '/cache_sw.js',
  '/flutter_service_worker.js',
  '/firebase-messaging-sw.js',
]);

// Cross-origin hostnames whose responses must never be cached.
const NEVER_CACHE_HOSTNAME_SUFFIXES = [
  'firestore.googleapis.com',
  'firebaseinstallations.googleapis.com',
  'fcmregistrations.googleapis.com',
  'identitytoolkit.googleapis.com',
  'securetoken.googleapis.com',
  'fcm.googleapis.com',
  'googleapis.com', // Calendar API + general Firebase
  'firebaseio.com',
  'cloudfunctions.net',
  'gstatic.com', // Firebase JS SDK; let the browser's HTTP cache handle it
  'raw.githubusercontent.com', // daily verse JSON
];

self.addEventListener('install', () => {
  // Activate immediately on first install so the page is controlled on the
  // very next reload instead of the one after.
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(
      keys
        .filter((k) => k.startsWith('church-staff-pwa-') && k !== CACHE_NAME)
        .map((k) => caches.delete(k)),
    );
    await self.clients.claim();
  })());
});

self.addEventListener('message', (event) => {
  if (event.data && event.data.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);

  // Never intercept live API calls.
  if (NEVER_CACHE_HOSTNAME_SUFFIXES.some((h) => url.hostname.endsWith(h))) {
    return;
  }

  // Only handle same-origin assets here. Other cross-origin fetches go to
  // the network unmanaged.
  if (url.origin !== self.location.origin) return;

  if (NETWORK_FIRST_PATHS.has(url.pathname)) {
    event.respondWith(networkFirst(request));
  } else {
    event.respondWith(cacheFirst(request));
  }
});

async function networkFirst(request) {
  const cache = await caches.open(CACHE_NAME);
  try {
    const response = await fetch(request);
    if (response && response.ok) {
      // Clone before caching — Response bodies can only be consumed once.
      cache.put(request, response.clone()).catch(() => {});
    }
    return response;
  } catch (e) {
    const cached = await cache.match(request);
    if (cached) return cached;
    throw e;
  }
}

async function cacheFirst(request) {
  const cache = await caches.open(CACHE_NAME);
  const cached = await cache.match(request);
  if (cached) return cached;
  const response = await fetch(request);
  if (response && response.ok) {
    cache.put(request, response.clone()).catch(() => {});
  }
  return response;
}
