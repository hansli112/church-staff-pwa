import 'dart:js_interop';

/// `web/app_update.js` 掛在 window 上的入口。回傳 'updating' 或 'latest'，
/// 網路不通時 reject。
///
/// 瀏覽器沒有 service worker 時那支腳本會提早結束、不掛這個函式，所以這裡是
/// nullable —— 讀到 undefined 就是 null。
@JS('churchAppCheckForUpdate')
external JSFunction? get _checkForUpdate;

bool isUpdateCheckSupported() => _checkForUpdate != null;

Future<String> checkForUpdate() async {
  final entryPoint = _checkForUpdate;
  if (entryPoint == null) return 'unsupported';

  final promise = entryPoint.callAsFunction() as JSPromise<JSString>;
  return (await promise.toDart).toDart;
}
