import 'package:church_staff_pwa/features/auth/domain/sign_in_account_exception.dart';
import 'package:church_staff_pwa/features/auth/presentation/providers/user_admin_provider.dart';
import 'package:church_staff_pwa/features/auth/presentation/widgets/account_error_snack_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _text(SnackBar bar) => (bar.content as Text).data!;

void main() {
  test('給管理員看的訊息原樣顯示', () {
    expect(
      _text(
        accountErrorSnackBar(
          const AccountSafetyException('不能刪除自己的帳號。'),
          prefix: '刪除失敗：',
        ),
      ),
      '不能刪除自己的帳號。',
    );
    final bar = accountErrorSnackBar(
      const SignInAccountException('這個 Email 已經是「王管理」的帳號'),
      prefix: '錯誤：',
    );
    expect(_text(bar), '這個 Email 已經是「王管理」的帳號');
    expect(bar.action, isNull);
  });

  // 要到 Firebase 主控台處理的，附上連結，也留久一點讓人讀完。
  test('有說明頁時附上「開啟 Firebase」並停留 20 秒', () {
    final bar = accountErrorSnackBar(
      const SignInAccountException(
        '這個 Email 之前建立過登入帳號',
        helpUrl:
            'https://console.firebase.google.com/project/x/authentication/users',
      ),
      prefix: '錯誤：',
    );
    expect(bar.action?.label, '開啟 Firebase');
    expect(bar.duration, const Duration(seconds: 20));
  });

  test('其他錯誤加上前綴並翻成白話', () {
    expect(
      _text(accountErrorSnackBar(Exception('boom'), prefix: '刪除失敗：')),
      '刪除失敗：操作失敗，請稍後再試',
    );
  });
}
