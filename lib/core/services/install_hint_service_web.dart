import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'install_hint_service.dart';

/// `web/install_hint.js` 掛在 window 上的物件。那支腳本沒載到（例如被舊快取
/// 服務的舊 index.html）時是 undefined，這裡就當成不用提醒。
@JS('churchInstallHint')
external _InstallHintJs? get _hint;

extension type _InstallHintJs(JSObject _) implements JSObject {
  external JSString platform();
  external JSString? browser();
  external JSBoolean isStandalone();
  external JSBoolean canPrompt();
  external JSPromise<JSString> prompt();
}

InstallHint readInstallHint() {
  final hint = _hint;
  if (hint == null) {
    return const InstallHint(
      platform: InstallPlatform.other,
      isStandalone: false,
      canPrompt: false,
    );
  }
  return InstallHint(
    platform: switch (hint.platform().toDart) {
      'ios' => InstallPlatform.ios,
      'android' => InstallPlatform.android,
      _ => InstallPlatform.other,
    },
    // 舊版 install_hint.js 沒有 browser()；讀不到就照一般瀏覽器教。
    browser: switch (_browserOf(hint)) {
      'safari' => InstallBrowser.safari,
      'chrome' => InstallBrowser.chrome,
      _ => InstallBrowser.other,
    },
    isStandalone: hint.isStandalone().toDart,
    canPrompt: hint.canPrompt().toDart,
  );
}

Future<String> promptInstall() async {
  final hint = _hint;
  if (hint == null) return 'unavailable';
  return (await hint.prompt().toDart).toDart;
}

String? _browserOf(_InstallHintJs hint) {
  if (!hint.has('browser')) return null;
  return hint.browser()?.toDart;
}
