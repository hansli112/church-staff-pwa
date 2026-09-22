import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'package:church_staff_pwa/core/types/service_type.dart';
import 'roster_photo.dart';

/// 使用者看得懂的失敗。訊息已經是中文（多半是 API 自己寫的），呼叫端直接顯示。
class RosterImportException implements Exception {
  final String message;
  const RosterImportException(this.message);

  @override
  String toString() => message;
}

typedef IdTokenProvider = Future<String?> Function();

/// 把服事表照片送去辨識，拿回可以貼進匯入框的 JSON。
///
/// 回傳的是**字串**而不是解析好的物件，而且刻意填回原本那個文字框：辨識完
/// 的結果要讓人看一眼再按匯入，而按下匯入之後走的還是
/// `parseRosterImportJson` —— 跟手動貼上完全同一條路。辨識只是省掉打字，
/// 不是另一條匯入流程。
class RosterImportService {
  /// 一張密密麻麻的服事表模型要跑一陣子。worker 那邊給上游 60 秒，這裡要留
  /// 得比它寬，否則使用者會先看到「逾時」，而那邊其實正要成功。
  static const Duration _timeout = Duration(seconds: 90);

  final http.Client _client;
  final IdTokenProvider _idToken;
  final Uri _endpoint;

  RosterImportService({
    http.Client? client,
    IdTokenProvider? idToken,
    Uri? endpoint,
  }) : _client = client ?? http.Client(),
       _idToken = idToken ?? _firebaseIdToken,
       _endpoint = endpoint ?? Uri.base.resolve('/api/roster/import-image');

  static Future<String?> _firebaseIdToken() =>
      FirebaseAuth.instance.currentUser?.getIdToken() ?? Future.value(null);

  /// 送出照片，回傳排版過的 JSON 字串。
  Future<String> convert({
    required ServiceType type,
    required List<RosterPhoto> photos,
  }) async {
    if (photos.isEmpty) {
      throw const RosterImportException('請先選一張服事表照片');
    }

    final token = await _idToken();
    if (token == null || token.isEmpty) {
      throw const RosterImportException('請先登入');
    }

    final request = http.Request('POST', _endpoint)
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['content-type'] = 'application/json; charset=utf-8'
      ..body = jsonEncode({
        'type': type.name,
        'images': [for (final photo in photos) photo.toJson()],
      });

    final http.Response response;
    try {
      final streamed = await _client.send(request).timeout(_timeout);
      response = await http.Response.fromStream(streamed).timeout(_timeout);
    } on TimeoutException {
      throw const RosterImportException('辨識逾時了。照片太大的話可以先縮小，或分成兩張再試');
    } catch (_) {
      throw const RosterImportException('連線失敗，請檢查網路後再試一次');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RosterImportException(_errorMessage(response));
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw const RosterImportException('辨識完成，但回應看不懂，請再試一次');
    }
    final entries = (decoded is Map<String, dynamic>)
        ? decoded['entries']
        : null;
    if (entries is! List) {
      throw const RosterImportException('辨識完成，但回應看不懂，請再試一次');
    }
    if (entries.isEmpty) {
      throw const RosterImportException('這張照片沒有讀出任何日期，請確認拍到整張表');
    }

    // 排版過再填回文字框。擠成一行的話，使用者想確認哪天排了誰得先自己讀
    // 一段 JSON —— 而「看一眼再匯入」正是保留這個文字框的理由。
    return '${const JsonEncoder.withIndent('  ').convert(entries)}\n';
  }

  /// 優先用 API 自己寫的訊息；沒有才退回依狀態碼猜。
  ///
  /// 沒有訊息通常代表回應不是這支函式產生的（Cloudflare 擋下、舊的 service
  /// worker 接走），那時狀態碼是唯一的線索。
  String _errorMessage(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        final message = decoded['error'];
        if (message is String && message.trim().isNotEmpty) {
          return message.trim();
        }
      }
    } catch (_) {
      // 落到下面依狀態碼給訊息。
    }
    return switch (response.statusCode) {
      401 => '請重新登入後再試一次',
      403 => '沒有編輯服事表的權限',
      413 => '照片太大了，請先縮小再試',
      429 => '辨識用量已達上限，請稍後再試',
      503 => '辨識服務忙碌中，請稍後再試一次',
      >= 500 => '伺服器忙碌中，請稍後再試',
      _ => '辨識失敗，請稍後再試',
    };
  }
}
