import 'install_hint_service_stub.dart'
    if (dart.library.js_interop) 'install_hint_service_web.dart'
    as impl;

/// 這支手機要怎麼把網站加到主畫面。
enum InstallPlatform { ios, android, other }

/// 首頁「加到手機主畫面」卡片需要知道的事，讀自 `web/install_hint.js`。
class InstallHint {
  const InstallHint({
    required this.platform,
    required this.isStandalone,
    required this.canPrompt,
  });

  final InstallPlatform platform;

  /// 已經是從主畫面開的（不是在瀏覽器分頁裡）。
  final bool isStandalone;

  /// Android Chrome 給了 beforeinstallprompt，可以直接跳出安裝視窗。
  final bool canPrompt;

  /// 手機、還在瀏覽器裡開：值得提醒一下。桌機不提醒，那裡沒有主畫面。
  bool get shouldSuggest => platform != InstallPlatform.other && !isStandalone;
}

class InstallHintService {
  const InstallHintService();

  InstallHint read() => impl.readInstallHint();

  /// 跳出 Chrome 的安裝視窗。回傳 true 代表使用者按了安裝。
  Future<bool> prompt() async => await impl.promptInstall() == 'accepted';
}
