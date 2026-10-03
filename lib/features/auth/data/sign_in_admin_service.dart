import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../domain/sign_in_account_exception.dart';

typedef IdTokenProvider = Future<String?> Function();

/// Creates and removes staff sign-ins through the site's own /api/accounts.
///
/// The browser SDK can create a sign-in but cannot remove anyone else's, so
/// deleting a staff member used to leave their sign-in behind and the email
/// could not be added again. The Pages Function holds a service account that
/// can do both (see worker/account_admin.js).
///
/// Sites set up before that, deployed without the key, or served without
/// Pages Functions at all answer "unavailable": [create] returns null,
/// [delete] does nothing, and the caller does what it did before.
class SignInAdminService {
  static const Duration _timeout = Duration(seconds: 20);

  final http.Client _client;
  final IdTokenProvider _idToken;
  final Uri _endpoint;

  SignInAdminService({
    http.Client? client,
    IdTokenProvider? idToken,
    Uri? endpoint,
  }) : _client = client ?? http.Client(),
       _idToken = idToken ?? _firebaseIdToken,
       _endpoint = endpoint ?? Uri.base.resolve('/api/accounts');

  static Future<String?> _firebaseIdToken() =>
      FirebaseAuth.instance.currentUser?.getIdToken() ?? Future.value(null);

  /// The uid of the new sign-in, or null when this site cannot do it here.
  ///
  /// If [email] already has a sign-in no staff member uses, the server takes
  /// it over with [password] rather than refusing.
  Future<String?> create({
    required String email,
    required String password,
    required String name,
  }) async {
    final response = await _send(
      'POST',
      _endpoint,
      body: {'email': email, 'password': password, 'name': name},
    );
    if (response == null) return null;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final uid = decoded is Map<String, dynamic> ? decoded['uid'] : null;
      if (uid is String && uid.isNotEmpty) return uid;
    } catch (_) {
      // A host without Pages Functions can answer a POST with the app's page.
    }
    if (response.statusCode == 201) {
      throw const SignInAccountException('已送出，但回應看不懂，請重新整理確認帳號是否已建立');
    }
    return null;
  }

  /// Removes the sign-in for [uid] (one that is already gone counts). Does
  /// nothing on a site that cannot remove sign-ins.
  Future<void> delete(String uid) async {
    final uri = _endpoint.replace(
      pathSegments: [..._endpoint.pathSegments, uid],
    );
    await _send('DELETE', uri);
  }

  /// The response, or null when the site has no account management.
  Future<http.Response?> _send(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
  }) async {
    final token = await _idToken();
    if (token == null || token.isEmpty) {
      throw const SignInAccountException('請重新登入後再試一次');
    }
    final request = http.Request(method, uri)
      ..headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['content-type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      final streamed = await _client.send(request).timeout(_timeout);
      response = await http.Response.fromStream(streamed).timeout(_timeout);
    } on TimeoutException {
      throw const SignInAccountException('操作逾時，請稍後再試');
    } catch (_) {
      throw const SignInAccountException('連線失敗，請檢查網路後再試一次');
    }

    // 501: the function exists but the site has no key. 404/405: no function.
    if (const {404, 405, 501}.contains(response.statusCode)) return null;
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }
    throw SignInAccountException(_errorMessage(response));
  }

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
      // Fall through to the status-based message.
    }
    return switch (response.statusCode) {
      401 => '請重新登入後再試一次',
      403 => '只有管理員可以新增或刪除同工帳號',
      >= 500 => '伺服器忙碌中，請稍後再試',
      _ => '操作失敗，請稍後再試',
    };
  }
}
