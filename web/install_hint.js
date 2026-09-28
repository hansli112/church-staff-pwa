'use strict';

// 讓同工把網站「加到主畫面」，以及把他們從 LINE 這類 App 內建瀏覽器帶出去。
//
// 為什麼在 Flutter 之前跑、而且是獨立檔案：
//
//   1. 台灣教會的網址多半貼在 LINE 群組。LINE、Facebook、Instagram 點開連結
//      用的是自己的 in-app browser：不能加到主畫面、關掉就登出、收不到推播。
//      同工不會知道差別，只會覺得「這個 App 很難用」。這件事要在 Flutter 那
//      幾 MB 載完之前就講，不然他們已經在裡面登入了。
//   2. `beforeinstallprompt` 只發一次，而且很早。等 Flutter 起來再掛監聽器
//      就錯過了，所以這裡先接住、存起來，給首頁那張「加到主畫面」卡片用。
//
// Flutter 那側讀的是 window.churchInstallHint（見
// lib/core/services/install_hint_service_web.dart）。

(function () {
  var ua = navigator.userAgent || '';

  function detectInAppBrowser() {
    if (/ Line\//i.test(ua)) return 'LINE';
    if (/FBAN|FBAV|FB_IAB|FBIOS/i.test(ua)) return 'Facebook';
    if (/Instagram/i.test(ua)) return 'Instagram';
    if (/MicroMessenger/i.test(ua)) return '微信';
    return null;
  }

  function detectPlatform() {
    if (/iPhone|iPad|iPod/i.test(ua)) return 'ios';
    // iPadOS 13+ 的 Safari 預設自稱 Macintosh；多點觸控才分得出來。
    if (/Macintosh/i.test(ua) && navigator.maxTouchPoints > 1) return 'ios';
    if (/Android/i.test(ua)) return 'android';
    return 'other';
  }

  // iPhone 上每個瀏覽器的分享鈕位置不同：Safari 在下方（或收在「⋯」裡），
  // Chrome 在網址列右邊。Android 一律照 Chrome 教。
  function detectBrowser() {
    if (/CriOS/i.test(ua)) return 'chrome';
    if (/FxiOS|EdgiOS|OPiOS/i.test(ua)) return 'other';
    if (/Safari/i.test(ua)) return 'safari';
    return 'other';
  }

  function isStandalone() {
    return (window.matchMedia && window.matchMedia('(display-mode: standalone)').matches) ||
      window.navigator.standalone === true;
  }

  var platform = detectPlatform();
  var browser = detectBrowser();
  var inAppBrowser = detectInAppBrowser();
  var deferredPrompt = null;

  window.addEventListener('beforeinstallprompt', function (event) {
    // 不讓 Chrome 自己跳迷你橫幅：時機由首頁卡片的「安裝」按鈕決定。
    event.preventDefault();
    deferredPrompt = event;
  });
  window.addEventListener('appinstalled', function () {
    deferredPrompt = null;
  });

  window.churchInstallHint = {
    platform: function () { return platform; },
    browser: function () { return browser; },
    isStandalone: isStandalone,
    canPrompt: function () { return deferredPrompt !== null; },
    /// 回傳 'accepted'、'dismissed' 或 'unavailable'。
    prompt: function () {
      var event = deferredPrompt;
      if (!event) return Promise.resolve('unavailable');
      deferredPrompt = null; // 一個事件只能 prompt() 一次。
      return event.prompt().then(function () { return event.userChoice; })
        .then(function (choice) { return choice && choice.outcome === 'accepted' ? 'accepted' : 'dismissed'; })
        .catch(function () { return 'unavailable'; });
    },
  };

  if (!inAppBrowser || isStandalone()) return;

  var url = new URL(window.location.href);

  // LINE 看到這個參數就會改用手機的預設瀏覽器開啟。分享出去的連結多半已經
  // 帶了；沒帶的話這裡補一次。參數已經在、卻還是在 LINE 裡，代表 LINE 沒有
  // 照做（舊版或設定關掉），就改成顯示說明，不再重導，免得無限循環。
  if (inAppBrowser === 'LINE' && url.searchParams.get('openExternalBrowser') !== '1') {
    url.searchParams.set('openExternalBrowser', '1');
    window.location.replace(url.href);
    return;
  }

  var DISMISS_KEY = 'church-in-app-browser-dismissed';
  try {
    if (sessionStorage.getItem(DISMISS_KEY) === '1') return;
  } catch (_) { /* 無痕模式讀不到就照常顯示。 */ }

  url.searchParams.delete('openExternalBrowser');
  var cleanUrl = url.href;
  var target = platform === 'ios' ? 'Safari' : 'Chrome';

  function show() {
    var style = document.createElement('style');
    style.textContent =
      '#in-app-browser{position:fixed;inset:0;z-index:10000;background:#fff;color:#1f2937;display:flex;align-items:center;justify-content:center;padding:24px;' +
      'font-family:"Noto Sans TC","PingFang TC","Microsoft JhengHei",sans-serif;line-height:1.7}' +
      '#in-app-browser .card{max-width:420px;width:100%}' +
      '#in-app-browser h1{font-size:22px;margin:0 0 12px}' +
      '#in-app-browser p{margin:0 0 12px;font-size:16px}' +
      '#in-app-browser ol{margin:0 0 16px;padding-left:22px;font-size:16px}' +
      '#in-app-browser button,#in-app-browser a.button{display:block;width:100%;box-sizing:border-box;margin:10px 0 0;padding:12px;border-radius:10px;font:inherit;font-size:16px;' +
      'text-align:center;text-decoration:none;border:1px solid #2563eb;background:#2563eb;color:#fff;cursor:pointer}' +
      '#in-app-browser .secondary{background:#fff;color:#2563eb}' +
      '#in-app-browser .quiet{border-color:transparent;background:transparent;color:#6b7280}' +
      '#in-app-browser code{word-break:break-all;background:#f3f4f6;padding:2px 6px;border-radius:6px;font-size:14px}';
    document.head.appendChild(style);

    var overlay = document.createElement('div');
    overlay.id = 'in-app-browser';
    overlay.setAttribute('role', 'dialog');
    overlay.setAttribute('aria-modal', 'true');
    overlay.innerHTML =
      '<div class="card">' +
      '<h1>請改用 ' + target + ' 開啟</h1>' +
      '<p>你現在是在 ' + inAppBrowser + ' 裡面開啟。在這裡沒辦法加到手機主畫面，關掉之後也常常要重新登入。</p>' +
      '<ol>' +
      (platform === 'ios'
        ? '<li>按右下角或右上角的「⋯」或分享圖示</li><li>選「在 Safari 中開啟」</li>'
        : '<li>按右上角的「⋮」</li><li>選「在瀏覽器中開啟」或「用 Chrome 開啟」</li>') +
      '</ol>' +
      '<p>找不到的話，複製下面的網址，貼到 ' + target + ' 的網址列：<br><code></code></p>' +
      (platform === 'android' ? '<a class="button" data-action="chrome">直接用 Chrome 開啟</a>' : '') +
      '<button type="button" class="secondary" data-action="copy">複製網址</button>' +
      '<button type="button" class="quiet" data-action="stay">先在這裡使用</button>' +
      '</div>';
    overlay.querySelector('code').textContent = cleanUrl;

    var chrome = overlay.querySelector('[data-action="chrome"]');
    if (chrome) {
      // Android 的 intent URL：大多數 App 內建瀏覽器會把它交給 Chrome。
      chrome.href = 'intent://' + cleanUrl.replace(/^https?:\/\//, '') +
        '#Intent;scheme=https;package=com.android.chrome;end';
    }
    overlay.querySelector('[data-action="copy"]').addEventListener('click', function (event) {
      var button = event.currentTarget;
      var done = function () { button.textContent = '已複製，請貼到 ' + target; };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(cleanUrl).then(done, function () { window.prompt('請複製這個網址', cleanUrl); });
      } else {
        window.prompt('請複製這個網址', cleanUrl);
      }
    });
    overlay.querySelector('[data-action="stay"]').addEventListener('click', function () {
      try { sessionStorage.setItem(DISMISS_KEY, '1'); } catch (_) { /* 只影響這次。 */ }
      overlay.remove();
    });
    document.body.appendChild(overlay);
  }

  if (document.body) show();
  else document.addEventListener('DOMContentLoaded', show);
})();
