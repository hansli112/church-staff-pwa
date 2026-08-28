import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import {
  BUILD_CACHE,
  FONT_CACHE,
  ORIGIN,
  VENDOR_CACHE,
  loadServiceWorker,
} from './helpers.js';

describe('版本資訊 version.json', () => {
  // This is the whole reason this test directory exists. `version.json` has
  // been network-first twice (once by construction, once when the custom SW
  // was written), and both times it silently broke the same thing: 個人頁的
  // 「更新於」顯示伺服器最新的部署時間，而不是這台裝置正在跑的版本。 A device
  // still serving an old main.dart.js from an old cache showed the newest
  // deploy's timestamp and looked up to date — which is exactly the case the
  // line exists to reveal. Someone reported a bug that was already fixed,
  // and the screenshot "proving" they were on the new build proved nothing.
  test('從綁 build 的快取讀，也就是「正在跑的那一版」', async () => {
    const sw = loadServiceWorker();
    sw.seed(BUILD_CACHE, `${ORIGIN}/version.json`);

    assert.equal(await sw.request(`${ORIGIN}/version.json`), `cache:${BUILD_CACHE}`);
  });

  test('快取沒有時才去網路，並且存起來', async () => {
    const sw = loadServiceWorker();

    assert.equal(await sw.request(`${ORIGIN}/version.json`), 'network');
    assert.deepEqual(sw.cachedUrls(BUILD_CACHE), [`${ORIGIN}/version.json`]);
  });
});

describe('進入點走 network-first', () => {
  // These are the files that must be able to point at a newer build; caching
  // them first would pin the app to whatever it loaded on day one.
  for (const path of [
    '/',
    '/index.html',
    '/app_update.js',
    '/manifest.json',
    '/flutter_bootstrap.js',
    '/flutter.js',
  ]) {
    test(`${path} 有網路時一律拿網路那份`, async () => {
      const sw = loadServiceWorker();
      sw.seed(BUILD_CACHE, `${ORIGIN}${path}`);

      assert.equal(await sw.request(`${ORIGIN}${path}`), 'network');
    });
  }

  test('離線時退回快取', async () => {
    const sw = loadServiceWorker();
    sw.seed(BUILD_CACHE, `${ORIGIN}/index.html`);
    sw.setFetch(async () => {
      throw new Error('offline');
    });

    assert.equal(await sw.request(`${ORIGIN}/index.html`), `cache:${BUILD_CACHE}`);
  });

  test('離線又沒有快取就照實拋錯', async () => {
    const sw = loadServiceWorker();
    sw.setFetch(async () => {
      throw new Error('offline');
    });

    await assert.rejects(() => sw.request(`${ORIGIN}/index.html`), /offline/);
  });
});

describe('靜態資產走 cache-first', () => {
  test('App bundle 放在綁 build SHA 的快取', async () => {
    const sw = loadServiceWorker();
    sw.seed(BUILD_CACHE, `${ORIGIN}/main.dart.js`);

    assert.equal(await sw.request(`${ORIGIN}/main.dart.js`), `cache:${BUILD_CACHE}`);
  });

  test('CanvasKit 放在綁 Flutter 版本的 vendor 快取，才能跨 deploy 存活', async () => {
    const sw = loadServiceWorker();
    sw.seed(VENDOR_CACHE, `${ORIGIN}/canvaskit/canvaskit.wasm`);

    assert.equal(
      await sw.request(`${ORIGIN}/canvaskit/canvaskit.wasm`),
      `cache:${VENDOR_CACHE}`,
    );
  });

  test('字型與圖示不算 vendor：tree-shake 過的 MaterialIcons 必須跟著 build 換', async () => {
    // 這個子集是 build 產物（只含這一版用到的字符），放進 vendor 快取的話，
    // 新版第一次用到的圖示會永遠是空白方框。
    const sw = loadServiceWorker();

    assert.equal(await sw.request(`${ORIGIN}/assets/fonts/MaterialIcons-Regular.otf`), 'network');
    assert.deepEqual(sw.cachedUrls(VENDOR_CACHE), []);
    assert.deepEqual(sw.cachedUrls(BUILD_CACHE), [
      `${ORIGIN}/assets/fonts/MaterialIcons-Regular.otf`,
    ]);
  });
});

describe('不能攔截的請求', () => {
  test('service worker 本身：攔了就毀掉瀏覽器的更新偵測', async () => {
    const sw = loadServiceWorker();
    for (const path of ['/cache_sw.js', '/flutter_service_worker.js', '/firebase-messaging-sw.js']) {
      sw.seed(BUILD_CACHE, `${ORIGIN}${path}`);
      assert.equal(await sw.request(`${ORIGIN}${path}`), 'passthrough', path);
    }
  });

  test('後端 API 一律直通，不進任何快取', async () => {
    const sw = loadServiceWorker();
    const live = [
      'https://firestore.googleapis.com/v1/projects/church-staff-pwa/databases/(default)/documents/rosters',
      'https://identitytoolkit.googleapis.com/v1/accounts:lookup',
      'https://securetoken.googleapis.com/v1/token',
      'https://fcm.googleapis.com/fcm/send',
      'https://raw.githubusercontent.com/x/y/daily-verse.json',
    ];
    for (const url of live) {
      assert.equal(await sw.request(url), 'passthrough', url);
    }
    assert.deepEqual(sw.cacheNames(), []);
  });

  test('非 GET 不處理', async () => {
    const sw = loadServiceWorker();
    sw.seed(BUILD_CACHE, `${ORIGIN}/main.dart.js`);

    assert.equal(await sw.request(`${ORIGIN}/main.dart.js`, { method: 'POST' }), 'passthrough');
  });
});

describe('中文字型快取', () => {
  test('fonts.gstatic.com 進自己的快取，不跟著 deploy 失效', async () => {
    const sw = loadServiceWorker();

    assert.equal(await sw.request('https://fonts.gstatic.com/s/notosanstc/subset-1.woff2'), 'network');
    assert.deepEqual(sw.cachedUrls(FONT_CACHE), [
      'https://fonts.gstatic.com/s/notosanstc/subset-1.woff2',
    ]);
    assert.deepEqual(sw.cachedUrls(BUILD_CACHE), []);
  });

  test('字型主機排在 never-cache 的 gstatic.com 之前', async () => {
    // fonts.gstatic.com 也以 gstatic.com 結尾；順序寫反的話字型就完全不會被快取。
    const sw = loadServiceWorker();
    sw.seed(FONT_CACHE, 'https://fonts.gstatic.com/s/notosanstc/subset-1.woff2');

    assert.equal(
      await sw.request('https://fonts.gstatic.com/s/notosanstc/subset-1.woff2'),
      `cache:${FONT_CACHE}`,
    );
  });

  test('超過上限就從最舊的開始刪，避免 iOS 把整個來源的快取清掉', async () => {
    const sw = loadServiceWorker();
    for (let i = 0; i < 70; i += 1) {
      await sw.request(`https://fonts.gstatic.com/s/notosanstc/subset-${i}.woff2`);
    }

    const cached = sw.cachedUrls(FONT_CACHE);
    assert.equal(cached.length, 64);
    assert.equal(cached.at(0), 'https://fonts.gstatic.com/s/notosanstc/subset-6.woff2');
    assert.equal(cached.at(-1), 'https://fonts.gstatic.com/s/notosanstc/subset-69.woff2');
  });
});

describe('安裝與升級', () => {
  test('第一次安裝直接 skipWaiting', async () => {
    const sw = loadServiceWorker({ hasActiveWorker: false });
    await sw.install();

    assert.equal(sw.skipWaitingCalls.length, 1);
  });

  test('升級時等頁面說了才 skipWaiting，不把 bundle 從使用者腳下抽走', async () => {
    const sw = loadServiceWorker({ hasActiveWorker: true });
    await sw.install();
    assert.equal(sw.skipWaitingCalls.length, 0);

    sw.message({ type: 'SKIP_WAITING' });
    assert.equal(sw.skipWaitingCalls.length, 1);
  });

  test('不認得的訊息不會觸發 skipWaiting', async () => {
    const sw = loadServiceWorker();
    sw.message({ type: 'SOMETHING_ELSE' });
    sw.message(undefined);

    assert.equal(sw.skipWaitingCalls.length, 0);
  });

  test('activate 砍掉舊 build 的快取，留下現用的三個', async () => {
    const sw = loadServiceWorker();
    sw.seed(BUILD_CACHE, `${ORIGIN}/main.dart.js`);
    sw.seed(VENDOR_CACHE, `${ORIGIN}/canvaskit/canvaskit.wasm`);
    sw.seed(FONT_CACHE, 'https://fonts.gstatic.com/s/notosanstc/subset-1.woff2');
    sw.seed('church-staff-pwa-deadbeef-1', `${ORIGIN}/main.dart.js`);
    sw.seed('church-staff-pwa-vendor-flutter-3.35.0', `${ORIGIN}/canvaskit/canvaskit.wasm`);
    sw.seed('some-other-app-cache', `${ORIGIN}/whatever`);

    await sw.activate();

    assert.deepEqual(sw.cacheNames().sort(), [
      BUILD_CACHE,
      FONT_CACHE,
      VENDOR_CACHE,
      'some-other-app-cache', // 不是我們的前綴，不碰
    ].sort());
    assert.equal(sw.claimCalls.length, 1);
  });
});
