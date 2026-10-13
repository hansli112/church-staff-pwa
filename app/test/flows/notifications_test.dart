import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/domain/models.dart';

import '../support/harness.dart';
import '../support/seed.dart';

void main() {
  testWidgets('reminders come every Monday evening until another time is picked', (tester) async {
    final b = seededChurch(as: staffMei);
    await pumpApp(tester, b);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me/notifications');
    await settle(tester);

    // The choice below says when; the switch does not say it again.
    expect(find.text('每週一晚上，列出這週的服事'), findsNothing);
    await tester.tap(find.text('前一天晚上'));
    await settle(tester);
    expect(b.members['grace']!['mei']!.reminderTiming, ReminderTiming.dayBefore);

    await tester.tap(find.text('兩個都要'));
    await settle(tester);
    expect(b.members['grace']!['mei']!.reminderTiming, ReminderTiming.both);
  });

  testWidgets('with reminders off, there is no time to pick', (tester) async {
    final b = seededChurch(as: staffMei);
    await pumpApp(tester, b);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me/notifications');
    await settle(tester);

    await tester.tap(find.text('服事提醒'));
    await settle(tester);
    expect(b.members['grace']!['mei']!.mutedNotifications, {NotificationKind.reminder});
    expect(find.text('前一天晚上'), findsNothing);
    expect(find.text('每週一晚上，列出這週的服事'), findsOneWidget, reason: 'what turning it on would bring');
  });
}
