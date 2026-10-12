import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/harness.dart';
import '../support/seed.dart';

// English runs longer than Chinese: every main page, as an admin who sees
// all of it, on a phone in English, must lay out without overflowing (a
// widget test fails on any overflow).
const _pages = [
  '/home',
  '/rosters',
  '/rosters/sunday/2026-10-04',
  '/calendar',
  '/me',
  '/me/profile',
  '/me/language',
  '/me/church',
  '/me/link',
  '/me/webhook',
  '/me/calendar',
  '/me/notifications',
  '/me/support',
  '/me/invites',
  '/me/members',
  '/me/members/mei',
  '/me/services',
  '/me/services/sunday',
  '/account',
];

void main() {
  for (final textScale in [1.0, 1.3]) {
    testWidgets('the main pages fit in English, text at $textScale×', (tester) async {
      await pumpApp(tester, seededChurch(), deviceLocales: const [Locale('en', 'US')], textScale: textScale);
      for (final page in _pages) {
        GoRouter.of(tester.element(find.byType(Scaffold).first)).go(page);
        await settle(tester);
        expect(tester.takeException(), isNull, reason: page);
        expect(find.text('服事表'), findsNothing, reason: page);
      }
    });
  }
}
