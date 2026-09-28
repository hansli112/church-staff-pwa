import 'package:web/web.dart' as web;

const _key = 'church-app-reloaded-for';

Future<bool> reloadAppOnce(String reason) async {
  try {
    if (web.window.sessionStorage.getItem(_key) == reason) return false;
    web.window.sessionStorage.setItem(_key, reason);
  } catch (_) {
    // 無痕模式讀不到 sessionStorage：寧可不重載，下次開 App 就是新清單。
    return false;
  }
  web.window.location.reload();
  return true;
}
