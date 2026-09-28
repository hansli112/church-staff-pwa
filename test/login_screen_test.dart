import 'package:church_staff_pwa/features/auth/presentation/providers/session_provider.dart';
import 'package:church_staff_pwa/features/auth/presentation/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/church_test_config.dart';
import 'support/signed_in_auth_repository.dart';

Future<SignedInAuthRepository> _pumpLogin(WidgetTester tester) async {
  final repo = SignedInAuthRepository(null);
  final session = SessionProvider(repo);
  addTearDown(session.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<SessionProvider>.value(
      value: session,
      child: const MaterialApp(home: LoginScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  setUp(setTestChurchConfig);

  testWidgets('忘記密碼帶入登入欄的 Email，寄出後只說「如果有帳號」', (tester) async {
    final repo = await _pumpLogin(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      ' staff@example.org ',
    );
    await tester.tap(find.text('忘記密碼？'));
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    final field = find.descendant(
      of: dialog,
      matching: find.byType(TextFormField),
    );
    expect(
      tester.widget<TextFormField>(field).controller!.text,
      'staff@example.org',
    );

    await tester.tap(find.text('寄出'));
    await tester.pumpAndSettle();

    expect(repo.resetEmails, ['staff@example.org']);
    expect(find.text('請到信箱收信'), findsOneWidget);
    expect(find.textContaining('如果 staff@example.org 有帳號'), findsOneWidget);

    await tester.tap(find.text('好'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('忘記密碼沒填 Email 不寄信', (tester) async {
    final repo = await _pumpLogin(tester);
    await tester.tap(find.text('忘記密碼？'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('寄出'));
    await tester.pumpAndSettle();

    expect(repo.resetEmails, isEmpty);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('請輸入 Email'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('寄信失敗時訊息留在對話框，不當成登入錯誤', (tester) async {
    final repo = await _pumpLogin(tester);
    repo.resetException = Exception('boom');
    await tester.tap(find.text('忘記密碼？'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextFormField),
      ),
      'staff@example.org',
    );
    await tester.tap(find.text('寄出'));
    await tester.pumpAndSettle();

    expect(find.text('無法寄出重設信，請稍後再試'), findsOneWidget);
    expect(find.text('請到信箱收信'), findsNothing);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('無法寄出重設信，請稍後再試'), findsNothing);
  });
}
