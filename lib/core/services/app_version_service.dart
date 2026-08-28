import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class AppVersionInfo {
  const AppVersionInfo({required this.generatedAt});

  final DateTime generatedAt;
}

class AppVersionService {
  const AppVersionService();

  /// 個人頁「更新於」要回答的是「我手上這個 App 是哪一版」，不是「伺服器現在
  /// 是哪一版」——後者對使用者沒有意義，而且會在「舊 bundle ＋ 新伺服器」時
  /// 顯示成已更新。
  ///
  /// 所以這裡刻意不加 `?t=` 也不送 `cache-control: no-cache`：`version.json`
  /// 跟著 bundle 一起進 service worker 那個以 build SHA 為名的快取
  /// （`web/cache_sw.js` 走 cache-first），拿到的就是正在跑的那一版。加了
  /// cache-bust 等於繞過快取去問伺服器，那行字就又變回伺服器的版本。
  Future<AppVersionInfo?> fetchVersionInfo() async {
    final candidates = [
      Uri.base.resolve('version.json'),
      Uri.base.resolve('/version.json'),
    ];

    for (final uri in candidates) {
      try {
        final response = await http.get(uri);
        if (response.statusCode != 200) {
          continue;
        }

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final generatedAtRaw = data['generated_at'];
        DateTime? generatedAt;
        if (generatedAtRaw is String && generatedAtRaw.isNotEmpty) {
          generatedAt = DateTime.tryParse(generatedAtRaw);
        }

        generatedAt ??= _parseLastModified(response);
        if (generatedAt == null) continue;

        return AppVersionInfo(generatedAt: generatedAt.toLocal());
      } catch (_) {
        continue;
      }
    }

    return null;
  }

  DateTime? _parseLastModified(http.Response response) {
    final value = response.headers['last-modified'];
    if (value == null || value.isEmpty) return null;
    try {
      return DateFormat(
        "EEE, dd MMM yyyy HH:mm:ss 'GMT'",
        'en_US',
      ).parseUtc(value);
    } catch (_) {
      return null;
    }
  }
}
