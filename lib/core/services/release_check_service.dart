import 'dart:convert';

import 'package:http/http.dart' as http;

/// 安裝精靈裝的網站不會跟著 GitHub 自動更新，要教會自己用精靈更新。這裡讀
/// 上游 repo 的 release.json，讓管理員知道有新版本、以及更新了什麼。
///
/// 只有維護者改了 release.json 的版本號才算新版本 —— 只改文件或小修正的
/// commit 不會去吵教會。
const upstreamReleaseUrl =
    'https://raw.githubusercontent.com/hansli112/church-staff-pwa/main/release.json';

class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.notes,
    required this.guideUrl,
  });

  final String version;
  final List<String> notes;
  final String? guideUrl;
}

class ReleaseCheckService {
  const ReleaseCheckService({this.url = upstreamReleaseUrl, this.client});

  final String url;

  /// 測試注入；正式環境用 http 套件預設的 client。
  final http.Client? client;

  /// 讀不到（離線、GitHub 掛了、格式不對）就回 null：這是提醒，不是功能，
  /// 失敗不該打擾管理員。
  Future<ReleaseInfo?> fetchLatest() async {
    try {
      final uri = Uri.parse(url);
      final response = await (client?.get(uri) ?? http.get(uri)).timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode != 200) return null;
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map<String, dynamic>) return null;
      final version = data['version'];
      if (version is! String || _parse(version) == null) return null;
      final notes = data['notes'];
      final guideUrl = data['guideUrl'];
      return ReleaseInfo(
        version: version,
        notes: notes is List ? notes.whereType<String>().toList() : const [],
        guideUrl: guideUrl is String && guideUrl.startsWith('https://')
            ? guideUrl
            : null,
      );
    } catch (_) {
      return null;
    }
  }
}

/// [latest] 比 [current] 新嗎？版本號是「年.月.序號」，逐段比數字 ——
/// 字串比較會把 2026.10.1 排在 2026.9.1 前面。[current] 讀不到時不算有新版：
/// 那是舊版精靈裝的，或根本不是精靈裝的網站。
bool isNewerRelease(String latest, String? current) {
  final a = _parse(latest);
  final b = current == null ? null : _parse(current);
  if (a == null || b == null) return false;
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}

List<int>? _parse(String version) {
  final match = RegExp(r'^(\d{4})\.(\d{1,2})\.(\d{1,3})$').firstMatch(version);
  if (match == null) return null;
  return [for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)];
}
