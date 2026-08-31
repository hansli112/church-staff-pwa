import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import { fakeRegistration, fakeWorker, loadAppUpdate } from './helpers.js';

/// vm 裡建立的物件跟這裡不同 realm，deepEqual 會因為 prototype 不同而失敗，
/// 所以只比訊息型別。
const types = (worker) => worker.posted.map((message) => message.type);

describe('換到新版的交接', () => {
  // 這是「重整了還是舊版」的成因。新的 SW 在上一次造訪就裝好、停在 waiting，
  // 這一次載入時 update() 抓到的檔案跟它一模一樣，updatefound 不會再觸發 ——
  // 舊的流程只在那個事件裡送 SKIP_WAITING，於是沒有人送，舊 SW 繼續服務舊
  // bundle，重整幾次都一樣。
  test('上一次留下來停在 waiting 的 worker，這次載入就叫它讓位', async () => {
    const waiting = fakeWorker('installed');
    const sw = loadAppUpdate({ registration: fakeRegistration({ waiting }) });

    await sw.load();

    assert.deepEqual(types(waiting), ['SKIP_WAITING']);
  });

  test('worker 在監聽器掛上之前就 installed 也抓得到', async () => {
    // statechange 已經發生過就不會再來一次，只靠監聽器會漏掉。
    const installing = fakeWorker('installed');
    const sw = loadAppUpdate({ registration: fakeRegistration({ installing }) });

    await sw.load();

    assert.deepEqual(types(installing), ['SKIP_WAITING']);
  });

  test('之後才裝好的 worker，statechange 時讓位', async () => {
    const registration = fakeRegistration();
    const sw = loadAppUpdate({ registration });
    await sw.load();

    const worker = fakeWorker('installing');
    registration.fireUpdateFound(worker);
    assert.deepEqual(types(worker), [], '還在裝就先不要動');

    worker.advanceTo('installed');
    assert.deepEqual(types(worker), ['SKIP_WAITING']);
  });

  test('第一次安裝不介入：沒有東西要接手', async () => {
    const installing = fakeWorker('installed');
    const sw = loadAppUpdate({
      hasController: false,
      registration: fakeRegistration({ installing }),
    });

    await sw.load();

    assert.deepEqual(types(installing), []);
  });

  test('接手完成（controllerchange）才 reload，而且只 reload 一次', async () => {
    const sw = loadAppUpdate();
    await sw.load();

    await sw.controllerChange();
    await sw.controllerChange();

    assert.equal(sw.reloads.length, 1);
  });

  test('第一次安裝的 controllerchange 不 reload', async () => {
    // 那會讓第一次造訪的人看到「載入中」兩次。
    const sw = loadAppUpdate({ hasController: false });
    await sw.load();

    await sw.controllerChange();

    assert.equal(sw.reloads.length, 0);
  });
});

describe('切回前景時檢查', () => {
  // 裝成 App 的 PWA 從多工列切回來不算 navigation，瀏覽器不會自己檢查有沒有
  // 新版 —— 可以好幾天都停在舊版。
  test('切回前景會檢查一次', async () => {
    const registration = fakeRegistration();
    const sw = loadAppUpdate({ registration });
    await sw.load();
    const before = registration.updateCalls;

    await sw.visibilityChange('visible');

    assert.equal(registration.updateCalls, before + 1);
  });

  test('切到背景不檢查', async () => {
    const registration = fakeRegistration();
    const sw = loadAppUpdate({ registration });
    await sw.load();
    const before = registration.updateCalls;

    await sw.visibilityChange('hidden');

    assert.equal(registration.updateCalls, before);
  });

  test('已經有 waiting 就直接讓位，不必再問伺服器', async () => {
    const waiting = fakeWorker('installed');
    const registration = fakeRegistration();
    const sw = loadAppUpdate({ registration });
    await sw.load();
    registration.waiting = waiting;
    const before = registration.updateCalls;

    await sw.visibilityChange('visible');

    assert.deepEqual(types(waiting), ['SKIP_WAITING']);
    assert.equal(registration.updateCalls, before);
  });

  test('離線時的背景檢查不會炸掉頁面', async () => {
    const registration = fakeRegistration();
    registration.onUpdate = () => {
      throw new Error('offline');
    };
    const sw = loadAppUpdate({ registration });
    await sw.load();

    await sw.visibilityChange('visible');

    assert.equal(registration.updateCalls, 1);
  });
});

describe('個人頁的「檢查更新」', () => {
  test('沒有新版就回 latest', async () => {
    const registration = fakeRegistration();
    const sw = loadAppUpdate({ registration });
    await sw.load();

    assert.equal(await sw.checkForUpdate(), 'latest');
    assert.ok(registration.updateCalls >= 1, '要真的去問過伺服器');
  });

  test('問到新版就換過去', async () => {
    const registration = fakeRegistration();
    const waiting = fakeWorker('installed');
    registration.onUpdate = (reg) => {
      reg.waiting = waiting;
    };
    const sw = loadAppUpdate({ registration });
    await sw.load();

    assert.equal(await sw.checkForUpdate(), 'updating');
    assert.deepEqual(types(waiting), ['SKIP_WAITING']);
  });

  test('還在裝的時候按下去，也算正在更新', async () => {
    const registration = fakeRegistration();
    const installing = fakeWorker('installing');
    registration.onUpdate = (reg) => {
      reg.installing = installing;
    };
    const sw = loadAppUpdate({ registration });
    await sw.load();

    assert.equal(await sw.checkForUpdate(), 'updating');
    installing.advanceTo('installed');
    assert.deepEqual(types(installing), ['SKIP_WAITING'], '裝好之後接著讓位');
  });

  test('已經有 waiting 時直接換，不必等伺服器回答', async () => {
    const waiting = fakeWorker('installed');
    const registration = fakeRegistration();
    const sw = loadAppUpdate({ registration });
    await sw.load();
    registration.waiting = waiting;
    const before = registration.updateCalls;

    assert.equal(await sw.checkForUpdate(), 'updating');
    assert.equal(registration.updateCalls, before);
  });

  test('離線時往上丟，不能靜靜回「已是最新」', async () => {
    const registration = fakeRegistration();
    registration.onUpdate = () => {
      throw new Error('offline');
    };
    const sw = loadAppUpdate({ registration });
    await sw.load();

    await assert.rejects(() => sw.checkForUpdate(), /offline/);
  });

  test('註冊失敗會往上丟', async () => {
    const sw = loadAppUpdate({ registerError: new Error('SW blocked') });
    await sw.load();

    await assert.rejects(() => sw.checkForUpdate(), /SW blocked/);
  });
});

describe('註冊', () => {
  test('load 時註冊快取 SW 與推播 SW', async () => {
    const sw = loadAppUpdate();

    await sw.load();

    assert.deepEqual(
      sw.registerCalls.map((call) => call.url),
      ['cache_sw.js', 'firebase-messaging-sw.js'],
    );
    assert.equal(
      sw.registerCalls[1].options.scope,
      'firebase-cloud-messaging-push-scope',
    );
  });

  test('只註冊一次，按幾次檢查更新都共用同一個 registration', async () => {
    const sw = loadAppUpdate();
    await sw.load();

    await sw.checkForUpdate();
    await sw.checkForUpdate();

    const cacheSwRegistrations = sw.registerCalls.filter(
      (call) => call.url === 'cache_sw.js',
    );
    assert.equal(cacheSwRegistrations.length, 1);
  });

  test('沒有 serviceWorker 的瀏覽器不會掛上檢查更新的入口', async () => {
    // 個人頁靠這個函式在不在決定要不要顯示按鈕。
    const sw = loadAppUpdate({ noServiceWorker: true });

    assert.equal(sw.hasCheckForUpdate(), false);
  });
});
