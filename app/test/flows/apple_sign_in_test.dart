import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/data/memory/memory_backend.dart';

import '../support/harness.dart';
import '../support/seed.dart';

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(findShown(text).last);
  await settle(tester);
}

Future<void> go(WidgetTester tester, String location) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
  await settle(tester);
}

void main() {
  testWidgets('without Apple set up for this build, sign-in has no Apple button', (tester) async {
    await pumpApp(tester, MemoryBackend(clock: testClock));
    expect(find.text('使用 Google 登入'), findsOneWidget);
    expect(find.text('透過 Apple 登入'), findsNothing);
  });

  group('the sign-in buttons', () {
    double top(WidgetTester tester, String label) => tester.getTopLeft(findShown(label).last).dy;

    testWidgets('on iPhone Apple comes first, elsewhere Google', (tester) async {
      final b = MemoryBackend(clock: testClock)..auth.offersApple = true;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await pumpApp(tester, b);
        expect(top(tester, '透過 Apple 登入'), lessThan(top(tester, '使用 Google 登入')));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
      await pumpApp(tester, MemoryBackend(clock: testClock)..auth.offersApple = true);
      expect(top(tester, '使用 Google 登入'), lessThan(top(tester, '透過 Apple 登入')));
    });

    testWidgets("are white with each one's own mark, Google's G in its colours", (tester) async {
      await pumpApp(tester, MemoryBackend(clock: testClock)..auth.offersApple = true);
      for (final label in ['使用 Google 登入', '透過 Apple 登入']) {
        final button = tester.widget<ButtonStyleButton>(
          find.ancestor(of: findShown(label).last, matching: find.bySubtype<ButtonStyleButton>()).first,
        );
        expect(button.style!.backgroundColor!.resolve({}), Colors.white, reason: label);
      }
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Image && w.image is AssetImage && (w.image as AssetImage).assetName == 'assets/icons/google_g.png',
        ),
        findsOneWidget,
      );
    });
  });

  testWidgets('Apple sign-in creates the account with the name Apple gives', (tester) async {
    final b = MemoryBackend(clock: testClock)
      ..auth.offersApple = true
      ..auth.appleAccount = 'x7f9d2@privaterelay.appleid.com'
      ..auth.appleName = '王小明';
    await pumpApp(tester, b);

    await tapText(tester, '透過 Apple 登入');
    expect(find.text('加入你的教會'), findsOneWidget);
    expect(find.text('驗證你的 email'), findsNothing, reason: 'Apple accounts count as verified');
    final user = b.users.values.single;
    expect(user.email, 'x7f9d2@privaterelay.appleid.com');
    expect(user.name, '王小明');
  });

  testWidgets('closing Apple’s sheet leaves sign-in as it was, with no error', (tester) async {
    final b = MemoryBackend(clock: testClock)
      ..auth.offersApple = true
      ..auth.appleAccount = null;
    await pumpApp(tester, b);
    await tapText(tester, '透過 Apple 登入');
    expect(find.text('透過 Apple 登入'), findsOneWidget);
    expect(b.auth.currentUser, isNull);
    expect(find.textContaining('請稍後再試'), findsNothing);
  });

  testWidgets('Apple with the email of a password account links once signed in the old way', (tester) async {
    final b = MemoryBackend(clock: testClock)..auth.offersApple = true;
    final uid = b.auth.signInAs('ming@example.com', name: '小明').uid;
    b.auth.setPassword('ming@example.com', 'secret123');
    await b.auth.signOut();
    b.auth.appleAccount = 'ming@example.com';
    await pumpApp(tester, b);

    await tapText(tester, '透過 Apple 登入');
    expect(findShownContaining('這個 email 已經有帳號'), findsOneWidget);
    expect(b.auth.currentUser, isNull);

    await tapText(tester, '用 email 登入');
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'ming@example.com');
    await tester.enterText(fields.at(1), 'secret123');
    await tapText(tester, '登入');
    expect(b.auth.currentUser!.uid, uid);

    await b.auth.signOut();
    await settle(tester);
    await tapText(tester, '透過 Apple 登入');
    expect(b.auth.currentUser!.uid, uid, reason: 'Apple now signs in to the same account');
  });

  group('deleting an account that signs in with Apple', () {
    testWidgets('revokes Sign in with Apple, then deletes', (tester) async {
      final b = seededChurch(as: staffHao);
      b.auth.appleIds[b.auth.currentUser!.email] = b.auth.currentUser!.email;
      b.auth.appleAccount = b.auth.currentUser!.email;
      await pumpApp(tester, b);
      await go(tester, '/account');
      await tester.tap(find.widgetWithText(TextButton, '刪除帳號'));
      await settle(tester);
      await tester.tap(find.text('刪除帳號').last);
      await settle(tester);
      expect(b.auth.appleRevoked, ['hao@example.com']);
      expect(b.members['grace']!.containsKey('hao'), isFalse);
    });

    testWidgets('closing Apple’s sheet deletes nothing', (tester) async {
      final b = seededChurch(as: staffHao);
      b.auth.appleIds[b.auth.currentUser!.email] = b.auth.currentUser!.email;
      b.auth.appleAccount = null;
      await pumpApp(tester, b);
      await go(tester, '/account');
      await tester.tap(find.widgetWithText(TextButton, '刪除帳號'));
      await settle(tester);
      await tester.tap(find.text('刪除帳號').last);
      await settle(tester);
      expect(b.auth.appleRevoked, isEmpty);
      expect(b.members['grace']!.containsKey('hao'), isTrue);
      expect(b.auth.currentUser, isNotNull);
    });
  });
}
