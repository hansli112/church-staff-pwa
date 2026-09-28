import 'dart:convert';

import 'package:church_staff_pwa/core/services/release_check_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

ReleaseCheckService _service(http.Response Function() respond) =>
    ReleaseCheckService(client: MockClient((_) async => respond()));

void main() {
  group('isNewerRelease', () {
    test('逐段比數字，10 月比 9 月新', () {
      expect(isNewerRelease('2026.10.1', '2026.9.1'), isTrue);
      expect(isNewerRelease('2026.9.2', '2026.9.1'), isTrue);
      expect(isNewerRelease('2027.1.1', '2026.12.9'), isTrue);
    });

    test('一樣或比較舊都不算', () {
      expect(isNewerRelease('2026.9.1', '2026.9.1'), isFalse);
      expect(isNewerRelease('2026.9.1', '2026.10.1'), isFalse);
    });

    test('目前版本讀不到（舊版精靈、不是精靈裝的）不提醒', () {
      expect(isNewerRelease('2026.9.1', null), isFalse);
      expect(isNewerRelease('2026.9.1', 'installer-abc'), isFalse);
      expect(isNewerRelease('latest', '2026.9.1'), isFalse);
    });
  });

  group('fetchLatest', () {
    test('讀出版本、說明和教學連結', () async {
      final release = await _service(
        () => http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'version': '2026.10.1',
              'notes': ['可以上傳教會 Logo', 3],
              'guideUrl': 'https://example.org/update',
            }),
          ),
          200,
        ),
      ).fetchLatest();
      expect(release!.version, '2026.10.1');
      expect(release.notes, ['可以上傳教會 Logo']);
      expect(release.guideUrl, 'https://example.org/update');
    });

    test('不是 https 的連結不給點', () async {
      final release = await _service(
        () => http.Response(
          jsonEncode({
            'version': '2026.10.1',
            'guideUrl': 'javascript:alert(1)',
          }),
          200,
        ),
      ).fetchLatest();
      expect(release!.guideUrl, isNull);
    });

    test('讀不到或格式不對就安靜地回 null', () async {
      expect(
        await _service(() => http.Response('', 404)).fetchLatest(),
        isNull,
      );
      expect(
        await _service(() => http.Response('not json', 200)).fetchLatest(),
        isNull,
      );
      expect(
        await _service(
          () => http.Response(jsonEncode({'version': 'v2'}), 200),
        ).fetchLatest(),
        isNull,
      );
    });
  });
}
