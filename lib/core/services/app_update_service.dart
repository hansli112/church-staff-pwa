import 'app_update_service_stub.dart'
    if (dart.library.js_interop) 'app_update_service_web.dart'
    as impl;

/// 「檢查更新」按下去之後發生了什麼。
enum AppUpdateResult {
  /// 找到新版，正在換 —— 換完頁面會自己重載，不必再提示什麼。
  updating,

  /// 已經是最新的。
  latest,

  /// 這個環境沒有 service worker（非 web，或瀏覽器不支援／被停用）。
  /// 按鈕不該出現在這種環境。
  unsupported,
}

/// 手動觸發「換到新版」。
///
/// 平常不需要它：`web/app_update.js` 會在載入與切回前景時自己檢查。這個入口是
/// 給「我看起來還是舊版」的情況 —— 使用者想自己按一下，而不是被叫去把 App 從
/// 多工列滑掉。
///
/// 真正的交接流程在 `web/app_update.js`（那裡有 SW 的 waiting／skipWaiting／
/// controllerchange 這些細節，也有測試）。這裡只是把它接到 UI 上。
class AppUpdateService {
  const AppUpdateService();

  /// 這個環境有沒有更新入口。沒有就不要顯示按鈕。
  bool get isSupported => impl.isUpdateCheckSupported();

  /// 去問伺服器有沒有新版；有就換過去（換完頁面會重載）。
  ///
  /// 網路不通時往上丟例外 —— 靜靜回一句「已是最新版本」是騙人的，而這個按鈕
  /// 存在的理由正是使用者已經不相信畫面上的版本了。
  Future<AppUpdateResult> checkForUpdate() async {
    switch (await impl.checkForUpdate()) {
      case 'updating':
        return AppUpdateResult.updating;
      case 'latest':
        return AppUpdateResult.latest;
      default:
        return AppUpdateResult.unsupported;
    }
  }
}
