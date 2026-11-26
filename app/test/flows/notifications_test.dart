import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:martha/core/design/components.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/state/push.dart';

import '../support/fake_push.dart';
import '../support/harness.dart';
import '../support/seed.dart';

/// Whether the choice row with [title] has its check mark.
bool checked(WidgetTester tester, String title) => find
    .descendant(
      of: find.ancestor(of: find.text(title), matching: find.byType(InkWell)).first,
      matching: find.byIcon(Symbols.check_rounded),
    )
    .evaluate()
    .isNotEmpty;

void main() {
  testWidgets('reminders come every Monday at 7 p.m. until another day or hour is picked', (tester) async {
    final b = seededChurch(as: staffMei);
    await pumpApp(tester, b);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me/notifications');
    await settle(tester);
    ReminderTiming timing() => b.members['grace']!['mei']!.reminderTiming;

    // The choice below says when; the switch does not say it again.
    expect(find.text('每週一，列出這週的服事'), findsNothing);
    expect(find.text('兩個都要'), findsNothing);
    expect(find.text('可以兩個都選。天數 1 到 14'), findsOneWidget);
    expect(checked(tester, '每週一'), isTrue);
    expect(checked(tester, '服事前'), isFalse);

    // The last one on stays on: the switch above turns reminders off.
    await tester.tap(find.text('每週一'));
    await settle(tester);
    expect(timing(), ReminderTiming.weekly);
    expect(checked(tester, '每週一'), isTrue);

    await tester.tap(find.text('服事前'));
    await settle(tester);
    expect(timing(), ReminderTiming.both);
    await tester.tap(find.text('每週一'));
    await settle(tester);
    expect(timing(), ReminderTiming.dayBefore);
    expect(checked(tester, '每週一'), isFalse);
    await tester.tap(find.text('服事前'));
    await settle(tester);
    expect(timing(), ReminderTiming.dayBefore);

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

  testWidgets('how many days before: typed in the row, saved when done, kept as it was when not 1 to 14', (
    tester,
  ) async {
    final b = seededChurch(as: staffMei);
    await pumpApp(tester, b);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me/notifications');
    await settle(tester);
    int days() => b.members['grace']!['mei']!.reminderDays;
    final field = find.byType(TextField);
    String shown() => tester.widget<TextField>(field).controller!.text;
    expect(shown(), '1');

    // Typing a number is choosing it: the row turns on.
    await tester.enterText(field, '3');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(days(), 3);
    expect(b.members['grace']!['mei']!.reminderTiming, ReminderTiming.both);
    expect(checked(tester, '服事前'), isTrue);

    for (final wrong in ['', '0', '15']) {
      await tester.enterText(field, wrong);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      expect(days(), 3, reason: '"$wrong"');
      expect(shown(), '3', reason: '"$wrong" goes back to the last');
    }

    await tester.enterText(field, '14');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(days(), 14);
  });

  testWidgets('with reminders off, there is no time to pick', (tester) async {
    final b = seededChurch(as: staffMei);
    await pumpApp(tester, b);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me/notifications');
    await settle(tester);

    await tester.tap(find.text('服事提醒'));
    await settle(tester);
    expect(b.members['grace']!['mei']!.mutedNotifications, {NotificationKind.reminder});
    expect(find.text('服事前'), findsNothing);
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
