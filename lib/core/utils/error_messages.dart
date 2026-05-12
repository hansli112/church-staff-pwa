import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

/// 將任意例外轉換為對非技術使用者友善的繁中訊息。
///
/// 呼叫端應另外以 [dart:developer] 的 [log] 記錄原始 error 與 stackTrace，
/// 保留完整資訊供未來串接 Sentry 使用。
String mapErrorToUserMessage(Object? error) {
  // 1. FirebaseAuthException（登入/Auth 相關）
  if (error is FirebaseAuthException) {
    return switch (error.code) {
      'user-not-found' || 'invalid-credential' || 'wrong-password' =>
        '帳號或密碼錯誤',
      'user-disabled' => '帳號已被停用，請聯絡管理員',
      'email-already-in-use' => '此電子郵件已被註冊',
      'weak-password' => '密碼強度不足，至少 6 個字元',
      'invalid-email' => '電子郵件格式錯誤',
      'network-request-failed' => '網路連線失敗，請檢查網路',
      'too-many-requests' => '登入嘗試次數過多，請稍後再試',
      _ => '登入失敗，請稍後再試',
    };
  }

  // 2. FirebaseException（Firestore、Storage 等）
  if (error is FirebaseException) {
    return switch (error.code) {
      'permission-denied' => '沒有權限執行此操作，請聯絡管理員',
      'unavailable' || 'deadline-exceeded' => '網路不穩，請稍後再試',
      'not-found' => '資料不存在',
      'already-exists' => '資料已存在',
      'failed-precondition' => '操作條件不符，請重新整理頁面',
      _ => '資料處理失敗，請稍後再試',
    };
  }

  // 3. TimeoutException
  if (error is TimeoutException) {
    return '操作逾時，請稍後再試';
  }

  // 4. 其他所有例外
  return '操作失敗，請稍後再試';
}
