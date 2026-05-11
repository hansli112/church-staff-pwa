import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:church_staff_pwa/core/utils/error_messages.dart';

void main() {
  group('mapErrorToUserMessage', () {
    // ── FirebaseAuthException ──────────────────────────────────────────────

    test('user-not-found → 帳號或密碼錯誤', () {
      // ignore: invalid_use_of_protected_member
      final e = FirebaseAuthException(code: 'user-not-found');
      expect(mapErrorToUserMessage(e), '帳號或密碼錯誤');
    });

    test('wrong-password → 帳號或密碼錯誤', () {
      // ignore: invalid_use_of_protected_member
      final e = FirebaseAuthException(code: 'wrong-password');
      expect(mapErrorToUserMessage(e), '帳號或密碼錯誤');
    });

    test('invalid-credential → 帳號或密碼錯誤', () {
      // ignore: invalid_use_of_protected_member
      final e = FirebaseAuthException(code: 'invalid-credential');
      expect(mapErrorToUserMessage(e), '帳號或密碼錯誤');
    });

    test('user-disabled → 帳號已被停用', () {
      // ignore: invalid_use_of_protected_member
      final e = FirebaseAuthException(code: 'user-disabled');
      expect(mapErrorToUserMessage(e), '帳號已被停用，請聯絡管理員');
    });

    test('email-already-in-use → 此電子郵件已被註冊', () {
      // ignore: invalid_use_of_protected_member
      final e = FirebaseAuthException(code: 'email-already-in-use');
      expect(mapErrorToUserMessage(e), '此電子郵件已被註冊');
    });

    test('weak-password → 密碼強度不足', () {
      // ignore: invalid_use_of_protected_member
      final e = FirebaseAuthException(code: 'weak-password');
      expect(mapErrorToUserMessage(e), '密碼強度不足，至少 6 個字元');
    });

    test('invalid-email → 電子郵件格式錯誤', () {
      // ignore: invalid_use_of_protected_member
      final e = FirebaseAuthException(code: 'invalid-email');
      expect(mapErrorToUserMessage(e), '電子郵件格式錯誤');
    });

    test('network-request-failed → 網路連線失敗', () {
      // ignore: invalid_use_of_protected_member
      final e = FirebaseAuthException(code: 'network-request-failed');
      expect(mapErrorToUserMessage(e), '網路連線失敗，請檢查網路');
    });

    test('too-many-requests → 登入嘗試次數過多', () {
      // ignore: invalid_use_of_protected_member
      final e = FirebaseAuthException(code: 'too-many-requests');
      expect(mapErrorToUserMessage(e), '登入嘗試次數過多，請稍後再試');
    });

    test('FirebaseAuthException 未知 code → fallback 登入失敗', () {
      // ignore: invalid_use_of_protected_member
      final e = FirebaseAuthException(code: 'some-unknown-auth-error');
      expect(mapErrorToUserMessage(e), '登入失敗，請稍後再試');
    });

    // ── FirebaseException（Firestore / Storage 等）─────────────────────────

    test('permission-denied → 沒有權限', () {
      final e = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
      expect(mapErrorToUserMessage(e), '沒有權限執行此操作，請聯絡管理員');
    });

    test('unavailable → 網路不穩', () {
      final e = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
      );
      expect(mapErrorToUserMessage(e), '網路不穩，請稍後再試');
    });

    test('deadline-exceeded → 網路不穩', () {
      final e = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'deadline-exceeded',
      );
      expect(mapErrorToUserMessage(e), '網路不穩，請稍後再試');
    });

    test('not-found → 資料不存在', () {
      final e = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'not-found',
      );
      expect(mapErrorToUserMessage(e), '資料不存在');
    });

    test('already-exists → 資料已存在', () {
      final e = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'already-exists',
      );
      expect(mapErrorToUserMessage(e), '資料已存在');
    });

    test('failed-precondition → 操作條件不符', () {
      final e = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'failed-precondition',
      );
      expect(mapErrorToUserMessage(e), '操作條件不符，請重新整理頁面');
    });

    test('FirebaseException 未知 code → 資料處理失敗 fallback', () {
      final e = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'some-unknown-code',
      );
      expect(mapErrorToUserMessage(e), '資料處理失敗，請稍後再試');
    });

    // ── TimeoutException ───────────────────────────────────────────────────

    test('TimeoutException → 操作逾時', () {
      final e = TimeoutException('timeout');
      expect(mapErrorToUserMessage(e), '操作逾時，請稍後再試');
    });

    test('TimeoutException（duration 為 null）→ 操作逾時', () {
      final e = TimeoutException(null);
      expect(mapErrorToUserMessage(e), '操作逾時，請稍後再試');
    });

    // ── null 與其他 Exception ──────────────────────────────────────────────

    test('null 輸入 → 操作失敗 fallback', () {
      expect(mapErrorToUserMessage(null), '操作失敗，請稍後再試');
    });

    test('一般 Exception → 操作失敗 fallback', () {
      expect(mapErrorToUserMessage(Exception('some error')), '操作失敗，請稍後再試');
    });

    test('字串型例外（非 Exception 物件）→ 操作失敗 fallback', () {
      expect(mapErrorToUserMessage('random error string'), '操作失敗，請稍後再試');
    });

    test('StateError → 操作失敗 fallback', () {
      expect(mapErrorToUserMessage(StateError('bad state')), '操作失敗，請稍後再試');
    });
  });
}
