import 'app_reload_service_stub.dart'
    if (dart.library.js_interop) 'app_reload_service_web.dart'
    as impl;

/// 聚會清單變了就整頁重新載入：分頁、各 provider 裡依聚會分組的快取都要
/// 重建，重新載入最單純也最不會漏。[reason] 相同時一個分頁只重載一次，
/// 萬一本機快取寫不進去（無痕模式），也不會一直重載。
Future<bool> reloadAppOnce(String reason) => impl.reloadAppOnce(reason);
