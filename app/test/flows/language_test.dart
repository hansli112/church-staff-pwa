import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:martha/app.dart' show shownLanguagePref;
import 'package:martha/core/languages.dart';
import 'package:martha/data/memory/memory_backend.dart';

import '../support/harness.dart';
import '../support/seed.dart';

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await settle(tester);
}

void main() {
  testWidgets('a phone in English gets the app in English, dates too, and the account says so', (tester) async {
    final b = seededChurch(as: staffMei);
    await pumpApp(tester, b, deviceLocales: const [Locale('en', 'US')]);

    expect(find.text('Schedule'), findsWidgets);
    expect(find.textContaining('Oct'), findsWidgets);
    expect(find.text('服事表'), findsNothing);
    expect(b.users['mei']!.appLocale, 'en');
  });

  testWidgets('a phone in Chinese in Malaysia gets Simplified Chinese, dates too', (tester) async {
    final b = seededChurch(as: staffMei);
    await pumpApp(tester, b, deviceLocales: const [Locale('zh', 'MY')]);

    expect(find.text('事奉表'), findsWidgets);
    expect(find.textContaining('周'), findsWidgets);
    expect(find.text('服事表'), findsNothing);
    expect(b.users['mei']!.appLocale, 'zh-Hans');
  });

  testWidgets('the language shown is kept on the device, for the next start’s fonts', (tester) async {
    final b = seededChurch(as: staffMei);
    await pumpApp(tester, b, deviceLocales: const [Locale('zh', 'TW')]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(shownLanguagePref), 'zh-Hant');

    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me/language');
    await settle(tester);
    await tester.tap(find.text('简体中文'));
    await settle(tester);
    expect(b.users['mei']!.locale, 'zh-Hans');
    expect(find.text('跟随系统'), findsOneWidget);
    expect(prefs.getString(shownLanguagePref), 'zh-Hans');
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

  testWidgets("Firebase's emails, and a new church's services, are in the app's language", (tester) async {
    final b = MemoryBackend(clock: testClock);
    await pumpApp(tester, b, deviceLocales: const [Locale('en', 'US')]);
    await tapText(tester, 'Sign in with email');
    await tapText(tester, 'Create account');
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Amy');
    await tester.enterText(fields.at(1), 'amy@example.com');
    await tester.enterText(fields.at(2), 'secret123');
    await tapText(tester, 'Sign up');
    expect(b.auth.emailLanguages, [AppLanguage.en], reason: 'the verification email sent on sign-up');
    await tapText(tester, 'Resend email');
    expect(b.auth.emailLanguages, [AppLanguage.en, AppLanguage.en]);

    await tapText(tester, 'Create a church');
    b.auth.verify('amy@example.com');
    await tapText(tester, 'I’ve verified');
    await tester.enterText(find.byType(TextField), 'Grace Church');
    await tester.pump();
    await tapText(tester, 'Create');
    final services = b.services[b.churches.values.single.id]!.services;
    expect(services.single.name, 'Sunday Service');
    expect(services.single.duties, contains('Piano'));
  });

  testWidgets('the password reset email is in the language shown', (tester) async {
    final b = MemoryBackend(clock: testClock);
    await pumpApp(tester, b, deviceLocales: const [Locale('en', 'US')]);
    await tapText(tester, 'Sign in with email');
    await tester.enterText(find.byType(TextFormField).first, 'amy@example.com');
    await tapText(tester, 'Forgot password');
    expect(b.auth.resetEmails, ['amy@example.com']);
    expect(b.auth.emailLanguages, [AppLanguage.en]);
  });
}
