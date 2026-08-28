'use strict';

// Service worker 註冊與「換到新版」的交接流程。
//
// 為什麼不寫在 index.html 裡（原本是）：這段程式碼決定「這台裝置能不能換到新
// 版」，一旦自己被舊快取服務，卡住的裝置就再也救不回來。獨立成檔之後可以列進
// cache_sw.js 的 NETWORK_FIRST_PATHS，永遠拿得到最新的一份；順便也才測得到
// （web-tests/app_update.test.js）。
//
// 交接流程本身：新的 SW 裝好之後會停在 waiting，要有人送 SKIP_WAITING 才會
// activate；activate 會觸發 controllerchange，那時整頁 reload 一次，使用者就
// 換到新的 bundle 了。
//
// 踩過的坑，每一條都對應底下一段程式碼：
//
//   1. 只在 updatefound 裡送 SKIP_WAITING 是不夠的。新的 SW 若在「上一次造訪」
//      就已經裝好、停在 waiting（頁面在交接完成前被關掉），這一次載入時
//      update() 抓到的檔案跟等待中那顆一模一樣，updatefound 不會再觸發 ——
//      沒有人送 SKIP_WAITING，舊 SW 就永遠繼續服務舊 bundle，重整幾次都一樣。
//      所以註冊後要先看 registration.waiting。
//
//   2. statechange 可能已經錯過。監聽器是在 updatefound 之後才掛上去的，worker
//      若在那之前就到達 installed，那個事件就再也不會來。掛的同時也要檢查一次
//      當下的 state。
//
//   3. PWA 從背景切回來不算一次 navigation，瀏覽器不會自己去檢查 SW 有沒有更
//      新。裝在桌面的 App 可以好幾天不重新載入 —— visibilitychange 時補一次
//      update()。

(function () {
  if (!('serviceWorker' in navigator)) {
    // 個人頁的「檢查更新」按鈕靠這個函式存在與否決定顯不顯示。
    return;
  }

  // 第一次裝 SW 時 controller 會從 null 變成新 SW，那也會觸發 controllerchange。
  // 無條件 reload 的話，使用者第一次造訪會看到「載入中」兩次。只有已經有
  // controller 的「升級」情境才 reload。
  var hadInitialController = !!navigator.serviceWorker.controller;
  var reloading = false;

  navigator.serviceWorker.addEventListener('controllerchange', function () {
    if (!hadInitialController) {
      hadInitialController = true;
      return;
    }
    // controllerchange 在某些瀏覽器上會連續來兩次，reload 兩次會讓畫面閃兩下。
    if (reloading) return;
    reloading = true;
    window.location.reload();
  });

  /// 有 worker 停在 waiting 就叫它讓位。回傳有沒有真的送出訊息。
  function activateWaiting(registration) {
    if (!registration || !registration.waiting) return false;
    // 首次安裝不必介入（會自然 activate），這裡一定是升級：有 waiting 就代表
    // 已經有另一個 SW 在控制頁面。
    registration.waiting.postMessage({ type: 'SKIP_WAITING' });
    return true;
  }

  /// 盯著正在安裝的 worker，裝好就叫它讓位。
  function activateWhenInstalled(worker) {
    if (!worker) return;

    function maybeSkip() {
      if (worker.state === 'installed' && navigator.serviceWorker.controller) {
        worker.postMessage({ type: 'SKIP_WAITING' });
      }
    }

    worker.addEventListener('statechange', maybeSkip);
    // 掛上監聽器之前就可能已經 installed 了 —— 那個 statechange 不會再來。
    maybeSkip();
  }

  function watch(registration) {
    activateWaiting(registration);
    activateWhenInstalled(registration.installing);
    registration.addEventListener('updatefound', function () {
      activateWhenInstalled(registration.installing);
    });
  }

  // 註冊只做一次，之後所有人（visibilitychange、檢查更新按鈕）共用同一個
  // registration。
  var registrationPromise = null;

  function ensureRegistration() {
    if (!registrationPromise) {
      registrationPromise = navigator.serviceWorker
        .register('cache_sw.js')
        .then(function (registration) {
          watch(registration);
          return registration;
        })
        .catch(function (error) {
          console.error('Cache SW registration failed:', error);
          // 失敗不要記下來，下次（例如按了檢查更新）可以重試。
          registrationPromise = null;
          throw error;
        });
    }
    return registrationPromise;
  }

  /// 檢查有沒有新版，有就換過去（換完會 reload）。
  ///
  /// 回傳 'updating'（找到新版，正在換）或 'latest'（已經是最新）。網路不通時
  /// reject，呼叫端要把錯誤說出來 —— 靜靜地回「已是最新」是騙人的。
  ///
  /// 個人頁的「檢查更新」按鈕呼叫這個（見 AppUpdateService）。
  window.churchAppCheckForUpdate = function () {
    return ensureRegistration()
      .then(function (registration) {
        // 上一次留下來的 waiting，按鈕按下去就該把它換上。
        if (activateWaiting(registration)) return 'updating';
        return registration.update().then(function () {
          if (activateWaiting(registration)) return 'updating';
          if (registration.installing) {
            activateWhenInstalled(registration.installing);
            return 'updating';
          }
          return 'latest';
        });
      });
  };

  window.addEventListener('load', function () {
    ensureRegistration().catch(function () {
      // ensureRegistration 已經印過了。
    });

    // Firebase Cloud Messaging 推播 SW 走自己的 scope，跟更新流程無關。
    navigator.serviceWorker
      .register('firebase-messaging-sw.js', {
        scope: 'firebase-cloud-messaging-push-scope',
      })
      .catch(function (error) {
        console.error('Firebase messaging SW registration failed:', error);
      });
  });

  // 切回前景時檢查一次。裝成 App 的 PWA 從多工列切回來不算 navigation，
  // 瀏覽器不會自己檢查，可以好幾天都停在舊版。
  document.addEventListener('visibilitychange', function () {
    if (document.visibilityState !== 'visible') return;
    ensureRegistration()
      .then(function (registration) {
        if (activateWaiting(registration)) return;
        return registration.update();
      })
      .catch(function () {
        // 離線時 update() 會失敗，這是背景檢查，不吵使用者。
      });
  });
})();
