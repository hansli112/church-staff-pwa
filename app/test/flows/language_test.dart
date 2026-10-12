import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/harness.dart';
import '../support/seed.dart';

void main() {
  testWidgets('a phone in English gets the app in English, dates too, and the account says so', (tester) async {
    final b = seededChurch(as: staffMei);
    await pumpApp(tester, b, deviceLocales: const [Locale('en', 'US')]);

    expect(find.text('Schedule'), findsWidgets);
    expect(find.textContaining('Oct'), findsWidgets);
    expect(find.text('服事表'), findsNothing);
    expect(b.users['mei']!.appLocale, 'en');
  });

  testWidgets('a phone in a language the app lacks gets the next one on its list it has', (tester) async {
    final b = seededChurch(as: staffMei);
    await pumpApp(tester, b, deviceLocales: const [Locale('de', 'DE'), Locale('zh', 'TW')]);
    expect(find.text('服事表'), findsWidgets);
    expect(b.users['mei']!.appLocale, 'zh-Hant');
  });

  testWidgets('picking a language changes the app at once, over the phone’s', (tester) async {
    final b = seededChurch(as: staffMei);
    await pumpApp(tester, b, deviceLocales: const [Locale('zh', 'TW')]);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me/language');
    await settle(tester);

    await tester.tap(find.text('English'));
    await settle(tester);
    expect(b.users['mei']!.locale, 'en');
    expect(b.users['mei']!.appLocale, 'en');
    expect(find.text('Use system language'), findsOneWidget);

    await tester.tap(find.text('Use system language'));
    await settle(tester);
    expect(b.users['mei']!.locale, isNull);
    expect(b.users['mei']!.appLocale, 'zh-Hant');
    expect(find.text('跟隨系統'), findsOneWidget);
  });
}
