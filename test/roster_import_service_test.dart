import 'support/church_test_config.dart';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:church_staff_pwa/core/types/service_type.dart';
import 'package:church_staff_pwa/features/roster/data/roster_import_service.dart';
import 'package:church_staff_pwa/features/roster/data/roster_photo.dart';

const _photo = RosterPhoto(mimeType: 'image/jpeg', data: 'AAAA');

RosterImportService _service(MockClientHandler handler) => RosterImportService(
  client: MockClient(handler),
  idToken: () async => 'token',
  endpoint: Uri.parse('https://app.example/api/roster/import-image'),
);

Future<String> _errorFor(http.Response response) async {
  try {
    await _service(
      (_) async => response,
    ).convert(type: ServiceType.youth, photos: const [_photo]);
  } on RosterImportException catch (e) {
    return e.message;
  }
  fail('應該要丟 RosterImportException');
}

void main() {
  setUp(() => setTestChurchConfig(photoImport: true));
  group('RosterImportService 的錯誤訊息', () {
    test('API 自己寫的訊息原樣顯示，不加狀態碼', () async {
      final message = await _errorFor(
        http.Response(
          jsonEncode({'error': 'Gemini 免費版現在太多人用，過幾分鐘再試一次'}),
          503,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      expect(message, 'Gemini 免費版現在太多人用，過幾分鐘再試一次');
    });

    test('不是 API 產生的回應會帶上狀態碼，跟上面那句分得出來', () async {
      // Cloudflare 因為 CPU 超時砍掉 worker 時回的就是這種：503、HTML。
      final message = await _errorFor(
        http.Response('<html>Worker exceeded resource limits</html>', 503),
      );
      expect(message, contains('（503）'));
      expect(message, isNot('Gemini 免費版現在太多人用，過幾分鐘再試一次'));
    });
  });

  test('成功時回排版過的 JSON，填得回匯入框', () async {
    final service = _service((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['type'], 'youth');
      expect(body['images'], hasLength(1));
      return http.Response(
        jsonEncode({
          'entries': [
            {'date': '2026-10-04'},
          ],
        }),
        200,
      );
    });
    final json = await service.convert(
      type: ServiceType.youth,
      photos: const [_photo],
    );
    expect(json, contains('\n  {'));
    expect(jsonDecode(json), [
      {'date': '2026-10-04'},
    ]);
  });
}
