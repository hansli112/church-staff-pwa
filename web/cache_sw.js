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
// Cache invalidation: CI replaces __BUILD_VERSION__ with the deploy SHA so
// each release produces a unique cache name. The activate handler then
// deletes any cache whose key doesn't match the current version.
//
// Two caches, on purpose:
//   - app cache    keyed by build SHA. main.dart.js and friends change on
//                  every deploy, so they must be re-fetched every deploy.
//   - vendor cache keyed by the Flutter SDK version. canvaskit.wasm alone is
//                  ~7 MB (2.8 MB gzipped) and does NOT change when app code
//                  changes — only when the pinned Flutter version does.
//                  Sharing one build-keyed cache meant every deploy threw it
//                  away and the next visit re-downloaded the whole engine.
//                  CI injects the Flutter version pinned in
//                  .github/workflows/deploy-flutter-pwa.yml, so bumping
//                  Flutter is what invalidates the engine — nothing else.
//
// Local builds keep the literal '__BUILD_VERSION__'. That's intentionally
// fine: `flutter run -d chrome` bypasses SWs, and for hand-served
// `flutter build web` you'd clear DevTools storage between iterations
// anyway. The only place per-deploy invalidation actually matters is
// production, and the deploy workflow is fail-fast if the placeholder
// isn't substituted.

const CACHE_VERSION = '__BUILD_VERSION__';
const CACHE_NAME = `church-staff-pwa-${CACHE_VERSION}`;

const VENDOR_VERSION = '__VENDOR_VERSION__';
const VENDOR_CACHE_NAME = `church-staff-pwa-vendor-${VENDOR_VERSION}`;

// CanvasKit 內建字型不含中文字。遇到 bundle 裡沒有的字，engine 會在
// runtime 去 fonts.gstatic.com 抓 Noto Sans TC/SC 的 subset —— 也就是說
// 捲動到還沒載過的姓名時，會臨時發網路請求、解字型、重排版，直接表現成
// 一格一格的卡頓。iOS 加到桌面的 PWA 又特別容易把 HTTP cache 清掉，
// 所以每次冷啟動都可能重來一次。
//
// 這個 cache 不綁任何版本：字型 URL 本身就是內容定址（改版會換 URL），
// 而且跟 App 或 Flutter 版本都無關，沒有理由跟著失效。
const FONT_CACHE_NAME = 'church-staff-pwa-fonts-v1';
const FONT_HOSTNAMES = ['fonts.gstatic.com', 'fonts.googleapis.com'];

// 字型 subset 是「每遇到一個新的 Unicode 範圍就多一個 URL」，沒有上限的話
// 這個 cache 會一直長大。iOS 的每來源儲存配額很小，一旦超過，Safari 會把
// 整個來源的 Cache Storage 清掉 —— 連 App 本體與引擎的快取一起賠進去。
// 超過上限就從最舊的開始刪（Cache.keys() 依插入順序回傳）。
const FONT_CACHE_MAX_ENTRIES = 64;

// Same-origin path prefixes whose bytes are tied to the Flutter SDK version
// rather than to our app code, so they can outlive an app deploy.
//
// ONLY /canvaskit/ qualifies. Do NOT add /assets/fonts/ or the bundled icon
// fonts here: `uses-material-design: true` makes Flutter tree-shake
// MaterialIcons down to the glyphs this build actually references (12 KB, not
// the SDK's 1.6 MB) and ships it at an unhashed URL. Caching that across
// deploys means the first release that uses a new icon renders it as a tofu
// box forever, because the vendor cache still holds the older subset.
//
// This requires `flutter build web --no-web-resources-cdn`: with the default
// CDN mode the engine loads CanvasKit from www.gstatic.com and this prefix
// never matches anything.
const VENDOR_PATH_PREFIXES = ['/canvaskit/'];

// Same-origin paths that should be re-fetched from network when online so
// users see updates promptly. Cached copy is the offline fallback.
//
// `/version.json` deliberately does NOT belong here — it falls through to
// cacheFirst below. 個人頁的「更新於」讀的就是這份檔案，而那行字要回答的是
// 「我手上這個 App 是哪一版」，不是「伺服器現在部署到哪一版」。CACHE_NAME 綁
// build SHA，所以 cache-first 拿到的必定是「正在跑的那一版」隨 bundle 一起進
// 快取的那份 —— 這正是 477ad89 的意圖（它把 version.json 的產生移到
// `flutter build` 之前，就是為了讓它進得了這個快取）。
//
// 放進 network-first 會靜默撤銷那個修正：舊的 SW 還在服務舊的 main.dart.js，
// version.json 卻是網路上最新的，畫面顯示「已更新」但跑的其實是舊 bundle ——
// 一個裝置到底更新了沒有，就再也看不出來。實際踩過一次：一位使用者截圖顯示
// 「更新於 10:51」，那正是伺服器部署完成的時間，跟他手機上跑的版本無關。
//
// 更新偵測不靠這個檔案，靠的是 SW 自己的 updatefound / SKIP_WAITING
// （見 web/app_update.js），所以 cache-first 不會讓任何人卡在舊版。
// `/app_update.js` 同理但反過來：它是「換到新版」那段交接程式碼，被自己的舊
// 快取服務的話，卡住的裝置就再也救不回來（修好的交接流程永遠載不進去）。
const NETWORK_FIRST_PATHS = new Set([
  '/',
  '/index.html',
  '/app_update.js',
  '/manifest.json',
  '/flutter_bootstrap.js',
  '/flutter.js',
]);

// Service-worker scripts must always go directly to the network so the
// browser's update flow sees a fresh script and can install a new SW
// version. Caching SW bytes is dangerous because stale cached SW could
// break future updates.
const NEVER_INTERCEPT_PATHS = new Set([
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
  // Only auto-skipWaiting on first install (no previously active SW). On
  // upgrades we wait until the page explicitly posts SKIP_WAITING — that
  // lets index.html show "downloading update" UI and reload at a moment
  // the user is ready, instead of yanking the bundle out from under them.
  if (!self.registration.active) {
    self.skipWaiting();
  }
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    const keep = new Set([CACHE_NAME, VENDOR_CACHE_NAME, FONT_CACHE_NAME]);
    await Promise.all(
      keys
        .filter((k) => k.startsWith('church-staff-pwa-') && !keep.has(k))
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

  // 字型要擺在 never-cache 檢查之前：fonts.gstatic.com 也是 gstatic.com，
  // 會被下面那條規則掃到。
  if (FONT_HOSTNAMES.includes(url.hostname)) {
    event.respondWith(cacheFirst(event, FONT_CACHE_NAME, trimFontCache));
    return;
  }

  // Never intercept live API calls.
  if (NEVER_CACHE_HOSTNAME_SUFFIXES.some((h) => url.hostname.endsWith(h))) {
    return;
  }

  // Only handle same-origin assets here. Other cross-origin fetches go to
  // the network unmanaged.
  if (url.origin !== self.location.origin) return;

  // Service-worker scripts go to the network unmanaged so browser update
  // detection works correctly.
  if (NEVER_INTERCEPT_PATHS.has(url.pathname)) return;

  if (NETWORK_FIRST_PATHS.has(url.pathname)) {
    event.respondWith(networkFirst(event));
  } else if (VENDOR_PATH_PREFIXES.some((p) => url.pathname.startsWith(p))) {
    // Engine bytes survive app deploys — see the VENDOR_CACHE_NAME note above.
    event.respondWith(cacheFirst(event, VENDOR_CACHE_NAME));
  } else {
    event.respondWith(cacheFirst(event));
  }
});

async function networkFirst(event) {
  const request = event.request;
  const cache = await caches.open(CACHE_NAME);
  try {
    const response = await fetch(request);
    if (response && response.ok) {
      // Clone before caching — Response bodies can only be consumed once.
      event.waitUntil(persist(cache, request, response.clone()));
    }
    return response;
  } catch (e) {
    const cached = await cache.match(request);
    if (cached) return cached;
    throw e;
  }
}

async function cacheFirst(event, cacheName = CACHE_NAME, afterPut) {
  const request = event.request;
  const cache = await caches.open(cacheName);
  const cached = await cache.match(request);
  if (cached) return cached;
  const response = await fetch(request);
  if (response && response.ok) {
    // 只回應、不 await 寫入，讓使用者不必等 cache.put 才拿到 bytes。
    event.waitUntil(persist(cache, request, response.clone(), afterPut));
  }
  return response;
}

// 寫入一定要包在 event.waitUntil 裡。respondWith 的 promise 一 resolve，
// 這個 fetch event 就算處理完了，瀏覽器隨時可以把 service worker 收掉 ——
// 沒被 waitUntil 追蹤的 cache.put 會跟著 SW 一起被砍，表現成「快取時有時無」，
// 冷啟動一次抓進去好幾十個資產時特別容易中。
//
// put 失敗（iOS 上最常見的是配額爆掉）之後仍然要跑 afterPut：字型 cache 正是
// 靠 trim 縮回上限內的，把 trim 綁在成功路徑上等於「一超過配額就再也修不回來」，
// 剛好在最需要它的時候失效。
async function persist(cache, request, response, afterPut) {
  try {
    await cache.put(request, response);
  } catch (_) {
    // 寫不進去就算了，下次請求會重新抓。
  }
  if (!afterPut) return;
  try {
    await afterPut(cache);
  } catch (_) {
    // trim 失敗不影響已經回給頁面的回應。
  }
}

// 保留最新的 FONT_CACHE_MAX_ENTRIES 筆，其餘從最舊的開始刪。
async function trimFontCache(cache) {
  const keys = await cache.keys();
  const excess = keys.length - FONT_CACHE_MAX_ENTRIES;
  if (excess <= 0) return;
  await Promise.all(keys.slice(0, excess).map((key) => cache.delete(key)));
}
