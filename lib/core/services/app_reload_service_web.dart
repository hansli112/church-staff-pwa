import 'package:web/web.dart' as web;

const _key = 'church-app-reloaded-for';

/// 同一份清單在這個分頁最多重載兩次：一次是正常的換版，第二次留給「第一次
/// 重載後讀到的還是舊資料」這種情況。再多就是出錯了，寧可不重載。
const _maxReloadsPerReason = 2;

Future<bool> reloadAppOnce(String reason) async {
  try {
    final previous = web.window.sessionStorage.getItem(_key) ?? '';
    final separator = previous.indexOf('\n');
    final count = separator > 0 && previous.substring(separator + 1) == reason
        ? int.tryParse(previous.substring(0, separator)) ?? 0
        : 0;
    if (count >= _maxReloadsPerReason) return false;
    web.window.sessionStorage.setItem(_key, '${count + 1}\n$reason');
  } catch (_) {
    // 無痕模式讀不到 sessionStorage：寧可不重載，下次開 App 就是新清單。
    return false;
  }
  web.window.location.reload();
  return true;
}
