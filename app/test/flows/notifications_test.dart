import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/core/design/components.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/state/push.dart';

import '../support/fake_push.dart';
import '../support/harness.dart';
import '../support/seed.dart';

void main() {
  testWidgets('reminders come every Monday at 7 p.m. until another day or hour is picked', (tester) async {
    final b = seededChurch(as: staffMei);
    await pumpApp(tester, b);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me/notifications');
    await settle(tester);

    // The choice below says when; the switch does not say it again.
    expect(find.text('每週一，列出這週的服事'), findsNothing);
    await tester.tap(find.text('前一天'));
    await settle(tester);
    expect(b.members['grace']!['mei']!.reminderTiming, ReminderTiming.dayBefore);

    await tester.tap(find.text('兩個都要'));
    await settle(tester);
    expect(b.members['grace']!['mei']!.reminderTiming, ReminderTiming.both);

    expect(find.text('晚上 7 點'), findsOneWidget);
    await tester.tap(find.text('時間'));
    await settle(tester);
    for (final hour in ['早上 6 點', '中午 12 點', '下午 1 點', '晚上 10 點']) {
      expect(find.text(hour), findsOneWidget);
    }
    expect(find.text('早上 5 點'), findsNothing);
    expect(find.text('晚上 11 點'), findsNothing);
    await tester.tap(find.text('早上 8 點'));
    await settle(tester);
    expect(b.members['grace']!['mei']!.reminderHour, 8);
    expect(find.text('早上 8 點'), findsOneWidget, reason: 'the sheet closed, the row says it');
  });

  testWidgets('with reminders off, there is no time to pick', (tester) async {
    final b = seededChurch(as: staffMei);
    await pumpApp(tester, b);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me/notifications');
    await settle(tester);

    await tester.tap(find.text('服事提醒'));
    await settle(tester);
    expect(b.members['grace']!['mei']!.mutedNotifications, {NotificationKind.reminder});
    expect(find.text('前一天'), findsNothing);
    expect(find.text('時間'), findsNothing);
    expect(find.text('每週一，列出這週的服事'), findsOneWidget, reason: 'what turning it on would bring');
  });

  testWidgets("an admin's own notifications are under 管理員; nobody else has them", (tester) async {
    await pumpApp(tester, seededChurch());
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me/notifications');
    await settle(tester);
    expect(find.text('管理員'), findsOneWidget);
    for (final kind in ['同工加入', '同工退出', '申請加入']) {
      expect(find.text(kind), findsOneWidget);
    }
    expect(find.textContaining('只通知管理員'), findsNothing, reason: 'the heading says it');

    await pumpApp(tester, seededChurch(as: staffMei));
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me/notifications');
    await settle(tester);
    expect(find.text('管理員'), findsNothing);
    expect(find.text('同工加入'), findsNothing);
  });

  group('turned on the first time, while the phone asks', () {
    bool shownOn(WidgetTester tester, String title) => tester
        .widget<Switch>(find.descendant(of: find.widgetWithText(SwitchRow, title), matching: find.byType(Switch)))
        .value;

    Future<FakePush> open(WidgetTester tester, PushPermission answer, Completer<void> prompt) async {
      final push = FakePush(answer: answer, prompt: prompt);
      await pumpApp(tester, seededChurch(as: staffMei), overrides: [pushServiceProvider.overrideWithValue(push)]);
      GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me/notifications');
      await settle(tester);
      return push;
    }

    testWidgets('the switch shows on at once, asked once however often tapped', (tester) async {
      final prompt = Completer<void>();
      final push = await open(tester, PushPermission.granted, prompt);
      expect(shownOn(tester, '服事提醒'), isFalse);
      await tester.tap(find.text('服事提醒'));
      await settle(tester);
      expect(shownOn(tester, '服事提醒'), isTrue);
      await tester.tap(find.text('服事提醒'));
      await tester.tap(find.text('找人代／交換'));
      await settle(tester);
      expect(push.asked, 1);
      prompt.complete();
      await settle(tester);
      expect(shownOn(tester, '服事提醒'), isTrue);
      expect(shownOn(tester, '找人代／交換'), isFalse);
    });

    testWidgets('refused, it goes back off', (tester) async {
      final prompt = Completer<void>();
      await open(tester, PushPermission.denied, prompt);
      await tester.tap(find.text('服事提醒'));
      await settle(tester);
      expect(shownOn(tester, '服事提醒'), isTrue);
      prompt.complete();
      await settle(tester);
      expect(shownOn(tester, '服事提醒'), isFalse);
    });
  });
}
