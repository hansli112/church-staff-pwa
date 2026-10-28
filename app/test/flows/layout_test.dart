import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/core/languages.dart';
import 'package:martha/domain/models.dart';

import '../support/harness.dart';
import '../support/seed.dart';

// Other languages run longer than Chinese: every main page, as an admin who sees all of it, on a phone in each
// language, must lay out without overflowing (a widget test fails on any
// overflow).
const _pages = [
  '/home',
  '/home/notifications',
  '/turn-on-notifications',
  '/rosters',
  '/rosters/sunday/2026-10-04',
  '/calendar',
  '/me',
  '/me/profile',
  '/me/profile/name',
  '/me/about',
  '/me/language',
  '/me/church',
  '/me/timezone',
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
  '/me/groups',
  '/me/groups/service/sunday',
  '/me/groups/ministry/worship',
  '/account',
];

void main() {
  for (final language in AppLanguage.values) {
    for (final textScale in [1.0, 1.3]) {
      testWidgets('the main pages fit in ${language.label}, text at $textScale×', (tester) async {
        final b = seededChurch()
          ..ministries['grace'] = const MinistrySettings(
            ministries: [
              Ministry(id: 'worship', name: '敬拜團', duties: [MinistryDuty('sunday', '司琴')]),
            ],
            ids: ['worship'],
          );
        await pumpApp(tester, b, deviceLocales: [language.locale], textScale: textScale);
        for (final page in _pages) {
          GoRouter.of(tester.element(find.byType(Scaffold).first)).go(page);
          await settle(tester);
          expect(tester.takeException(), isNull, reason: page);
          if (language != AppLanguage.zhHant) expect(find.text('服事表'), findsNothing, reason: page);
        }
      });
    }
  }
}
