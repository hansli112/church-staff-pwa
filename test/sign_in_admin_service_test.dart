import 'dart:convert';

import 'package:church_staff_pwa/features/auth/data/sign_in_admin_service.dart';
import 'package:church_staff_pwa/features/auth/domain/sign_in_account_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _endpoint = Uri.parse('https://staff.example.org/api/accounts');

SignInAdminService _service(
  MockClientHandler handler, {
  Future<String?> Function()? idToken,
}) => SignInAdminService(
  client: MockClient(handler),
  idToken: idToken ?? () async => 'token',
  endpoint: _endpoint,
);

http.Response _json(Object body, int status) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Future<String?> _create(SignInAdminService service) =>
    service.create(email: 'new@example.org', password: 'secret1', name: '新同工');

void main() {
  group('create', () {
    test('送出 Email、密碼、名字與登入 token，回傳 uid', () async {
      late http.Request sent;
      final uid = await _create(
        _service((request) async {
          sent = request;
          return _json({'uid': 'new-uid', 'reused': false}, 201);
        }),
      );
      expect(uid, 'new-uid');
      expect(sent.method, 'POST');
      expect(sent.url, _endpoint);
      expect(sent.headers['Authorization'], 'Bearer token');
      expect(jsonDecode(sent.body), {
        'email': 'new@example.org',
        'password': 'secret1',
        'name': '新同工',
      });
    });

    // 舊網站（沒金鑰）回 501；沒有 Pages Functions 的主機回 404/405，
    // 或把 POST 當成一般網頁回 index.html。這些都改用瀏覽器建立。
    test('網站沒有帳號管理時回傳 null', () async {
      for (final response in [
        _json({'error': '這個網站還沒有設定帳號管理'}, 501),
        http.Response('', 404),
        http.Response('', 405),
        http.Response('<!doctype html><html></html>', 200),
      ]) {
        expect(await _create(_service((_) async => response)), isNull);
      }
    });

    test('伺服器的錯誤訊息原樣給管理員看', () async {
      final service = _service(
        (_) async => _json({'error': '這個 Email 已經是「王管理」的帳號'}, 409),
      );
      await expectLater(
        _create(service),
        throwsA(
          isA<SignInAccountException>().having(
            (e) => e.message,
            'message',
            '這個 Email 已經是「王管理」的帳號',
          ),
        ),
      );
    });

    test('沒有錯誤訊息時依狀態碼說明', () async {
      final service = _service((_) async => http.Response('', 502));
      await expectLater(
        _create(service),
        throwsA(
          isA<SignInAccountException>().having(
            (e) => e.message,
            'message',
            '伺服器忙碌中，請稍後再試',
          ),
        ),
      );
    });

    // 連不上不是「網站沒有帳號管理」：改用瀏覽器建立會讓同一個 Email 卡住。
    test('連線失敗是錯誤，不會改用舊做法', () async {
      final service = _service(
        (_) async => throw http.ClientException('offline'),
      );
      await expectLater(
        _create(service),
        throwsA(isA<SignInAccountException>()),
      );
    });

    test('沒登入時不送出', () async {
      var called = false;
      final service = _service((_) async {
        called = true;
        return _json({'uid': 'x'}, 201);
      }, idToken: () async => null);
      await expectLater(
        _create(service),
        throwsA(isA<SignInAccountException>()),
      );
      expect(called, isFalse);
    });
  });

  group('delete', () {
    test('uid 當成路徑的一段送出', () async {
      late http.Request sent;
      await _service((request) async {
        sent = request;
        return http.Response('', 204);
      }).delete('abc/def');
      expect(sent.method, 'DELETE');
      expect(sent.url.pathSegments, ['api', 'accounts', 'abc/def']);
    });

    test('網站沒有帳號管理時不算失敗', () async {
      for (final status in [404, 405, 501]) {
        await _service((_) async => http.Response('', status)).delete('uid');
      }
    });

    test('其他失敗丟出例外，不會只刪資料', () async {
      final service = _service(
        (_) async => _json({'error': '不能刪除自己的帳號。'}, 403),
      );
      await expectLater(
        service.delete('uid'),
        throwsA(isA<SignInAccountException>()),
      );
    });
  });
}
