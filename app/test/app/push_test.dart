import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/state/push.dart';

import '../support/fake_push.dart';
import '../support/harness.dart';
import '../support/seed.dart';

void main() {
  testWidgets('a notification arriving with the app open shows, and opens its page', (tester) async {
    final push = FakePush();
    await pumpApp(tester, seededChurch(), overrides: [pushServiceProvider.overrideWithValue(push)]);

    push.notices.add(const PushNotice(title: '恩典堂', body: '你被排進 10/4 主日崇拜：司琴', link: '/rosters'));
    await settle(tester);
    expect(find.text('恩典堂：你被排進 10/4 主日崇拜：司琴'), findsOneWidget);

    await tester.tap(find.text('查看'));
    await settle(tester);
    final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
    expect(router.state.uri.path, '/rosters');
  });

  testWidgets('a notification linking outside the app shows without a way to open it', (tester) async {
    final push = FakePush();
    await pumpApp(tester, seededChurch(), overrides: [pushServiceProvider.overrideWithValue(push)]);

    push.notices.add(const PushNotice(title: '恩典堂', body: '有新消息', link: '//evil.example'));
    await settle(tester);
    expect(find.text('恩典堂：有新消息'), findsOneWidget);
    expect(find.text('查看'), findsNothing);
  });

  testWidgets('turning notifications on without allowing them says what to do', (tester) async {
    await pumpApp(tester, seededChurch(), overrides: [pushServiceProvider.overrideWithValue(FakePush())]);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me/notifications');
    await settle(tester);

    await tester.tap(find.text('服事提醒'));
    await settle(tester);
    expect(find.textContaining('請點「允許」'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isFalse);
  });

  testWidgets('allowed, but the device cannot get a token: says it will try again', (tester) async {
    final push = FakePush(answer: PushPermission.granted, registers: false);
    await pumpApp(tester, seededChurch(), overrides: [pushServiceProvider.overrideWithValue(push)]);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me/notifications');
    await settle(tester);

    await tester.tap(find.text('服事提醒'));
    await settle(tester);
    expect(find.textContaining('下次打開 App 會再試'), findsOneWidget);
  });

  testWidgets('allowed, but the device cannot get a token: the switch turned on stays on', (tester) async {
    final push = FakePush(answer: PushPermission.granted, registers: false);
    final b = seededChurch();
    final pastor = b.members['grace']!['pastor']!;
    b.members['grace']!['pastor'] = pastor.copyWith(mutedNotifications: {NotificationKind.reminder});
    await pumpApp(tester, b, overrides: [pushServiceProvider.overrideWithValue(push)]);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me/notifications');
    await settle(tester);

    await tester.tap(find.text('服事提醒'));
    await settle(tester);
    expect(b.members['grace']!['pastor']!.mutedNotifications, isEmpty);
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);
  });

  testWidgets('not yet allowed on the phone: the switches are off, and turning one on asks', (tester) async {
    final push = FakePush(answer: PushPermission.granted);
    final b = seededChurch();
    await pumpApp(tester, b, overrides: [pushServiceProvider.overrideWithValue(push)]);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me/notifications');
    await settle(tester);

    expect(find.text('開啟通知'), findsNothing, reason: 'the switches are the way in');
    for (final s in tester.widgetList<Switch>(find.byType(Switch))) {
      expect(s.value, isFalse, reason: 'nothing comes yet');
      expect(s.onChanged, isNotNull);
    }
    expect(find.text('前一天晚上'), findsNothing);

    await tester.tap(find.text('服事提醒'));
    await settle(tester);
    expect(push.asked, 1);
    for (final s in tester.widgetList<Switch>(find.byType(Switch))) {
      expect(s.value, isTrue);
    }
    expect(find.text('前一天晚上'), findsOneWidget);
  });

  testWidgets('not allowed when asked: the switch stays off', (tester) async {
    final push = FakePush(answer: PushPermission.denied);
    final b = seededChurch();
    await pumpApp(tester, b, overrides: [pushServiceProvider.overrideWithValue(push)]);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me/notifications');
    await settle(tester);

    await tester.tap(find.text('服事提醒'));
    await settle(tester);
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isFalse);
    expect(find.text('到設定開啟通知'), findsOneWidget);
  });
}
