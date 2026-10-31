import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/features/me/notifications_screen.dart';
import 'package:martha/features/rosters/roster_day_screen.dart';
import 'package:martha/state/push.dart';

import '../support/fake_push.dart';
import '../support/harness.dart';
import '../support/seed.dart';

/// 李美玉, in 恩典堂 and 希望堂, with two notifications from 恩典堂 and one
/// from 希望堂, none of them seen.
MemoryBackend _withNotifications() {
  final b = seededChurch(as: staffMei);
  b.addChurch('希望堂', id: 'hope');
  b.addMember('hope', staffMei);
  b.addNotification(
    'mei',
    NotificationItem(
      id: 'put-on',
      churchId: 'grace',
      kind: NotificationKind.rosterChange,
      title: '恩典堂',
      body: '你被排進 10/4 主日崇拜：司琴',
      link: '/rosters/sunday/2026-10-04',
      at: testNow.subtract(const Duration(hours: 3)),
    ),
  );
  b.addNotification(
    'mei',
    NotificationItem(
      id: 'week',
      churchId: 'grace',
      kind: NotificationKind.reminder,
      title: '平安 李美玉，這週的服事',
      body: '10/4（週日）主日崇拜 司琴、招待',
      link: '/home',
      at: testNow.subtract(const Duration(minutes: 30)),
    ),
  );
  b.addNotification(
    'mei',
    NotificationItem(
      id: 'hope',
      churchId: 'hope',
      kind: NotificationKind.reminder,
      title: '平安 李美玉，這週的服事',
      body: '10/3（週六）青年崇拜 司會',
      link: '/home',
      at: testNow.subtract(const Duration(hours: 1)),
    ),
  );
  return b;
}

Future<void> _openList(WidgetTester tester) async {
  await tester.tap(find.byTooltip('通知，有未讀的'));
  await settle(tester);
}

void main() {
  testWidgets('the bell has a dot while this church has unread ones; the app icon counts every church', (tester) async {
    final push = FakePush(state: PushPermission.granted);
    final b = _withNotifications();
    await pumpApp(tester, b, overrides: [pushServiceProvider.overrideWithValue(push)]);
    expect(find.byTooltip('通知，有未讀的'), findsOneWidget);
    expect(push.badge, 3);

    await _openList(tester);
    // Newest first; a push headed with the church's name says what happened.
    expect(findShown('平安 李美玉，這週的服事'), findsOneWidget);
    expect(findShown('10/4（週日）主日崇拜 司琴、招待\n30 分鐘前'), findsOneWidget);
    expect(findShown('你被排進 10/4 主日崇拜：司琴'), findsOneWidget);
    expect(findShown('3 小時前'), findsOneWidget);
    expect(
      tester.getTopLeft(findShown('平安 李美玉，這週的服事')).dy,
      lessThan(tester.getTopLeft(findShown('你被排進 10/4 主日崇拜：司琴')).dy),
    );
    expect(findShownContaining('青年崇拜'), findsNothing, reason: "希望堂's are in its own list");
    expect(
      find.byWidgetPredicate((w) => w is Semantics && w.properties.label == '未讀'),
      findsNWidgets(2),
      reason: 'unread when it opened',
    );

    // Opening it read them: here and on the app icon, where 希望堂's is left.
    expect(b.users['mei']!.notificationsSeen['grace'], testNow.subtract(const Duration(minutes: 30)));
    expect(push.badge, 1);
    await tester.tap(find.byType(BackButton));
    await settle(tester);
    expect(find.byTooltip('通知，有未讀的'), findsNothing);
    expect(find.byTooltip('通知'), findsOneWidget);
  });

  testWidgets('one opens what it is about; one about 首頁 goes back there', (tester) async {
    final b = _withNotifications();
    await pumpApp(
      tester,
      b,
      overrides: [pushServiceProvider.overrideWithValue(FakePush(state: PushPermission.granted))],
    );
    await _openList(tester);
    await tester.tap(findShown('你被排進 10/4 主日崇拜：司琴'));
    await settle(tester);
    expect(find.byType(RosterDayScreen), findsOneWidget);

    GoRouter.of(tester.element(find.byType(RosterDayScreen))).pop();
    await settle(tester);
    await tester.tap(findShown('平安 李美玉，這週的服事'));
    await settle(tester);
    expect(find.byTooltip('通知'), findsOneWidget, reason: '首頁, its bell');
  });

  testWidgets('a tapped push opens its page and counts as read, unless an older one is still unread', (tester) async {
    final push = FakePush(state: PushPermission.granted);
    final b = _withNotifications();
    await pumpApp(tester, b, overrides: [pushServiceProvider.overrideWithValue(push)]);
    // 你被排進, older, is unread: reading the reminder would read it too.
    push.taps.add('/c/grace?to=%2Fhome&notification=week');
    await settle(tester);
    expect(push.badge, 3);

    push.taps.add('/c/grace?to=%2Frosters%2Fsunday%2F2026-10-04&notification=put-on');
    await settle(tester);
    expect(find.byType(RosterDayScreen), findsOneWidget);
    expect(push.badge, 2);

    push.taps.add('/c/grace?to=%2Fhome&notification=week');
    await settle(tester);
    expect(find.byTooltip('通知'), findsOneWidget, reason: '首頁, no dot: none of 恩典堂 unread');
    expect(push.badge, 1, reason: "希望堂's is left");
  });

  testWidgets('a new one while the list is open is read too', (tester) async {
    final push = FakePush(state: PushPermission.granted);
    final b = _withNotifications();
    await pumpApp(tester, b, overrides: [pushServiceProvider.overrideWithValue(push)]);
    await _openList(tester);
    final now = testNow.add(const Duration(minutes: 1));
    b.addNotification(
      'mei',
      NotificationItem(
        id: 'left',
        churchId: 'grace',
        kind: NotificationKind.rosterChange,
        title: '恩典堂',
        body: '你被移出 10/11 主日崇拜：招待',
        link: '/rosters/sunday/2026-10-11',
        at: now,
      ),
    );
    await settle(tester);
    expect(findShown('你被移出 10/11 主日崇拜：招待'), findsOneWidget);
    expect(b.users['mei']!.notificationsSeen['grace'], now);
    expect(push.badge, 1);
  });

  testWidgets('none yet: it says so, with 開啟通知 until they are on, and the way to the settings', (tester) async {
    final b = seededChurch(as: staffMei);
    await pumpApp(tester, b, overrides: [pushServiceProvider.overrideWithValue(FakePush())]);
    await tester.tap(find.byTooltip('通知'));
    await settle(tester);
    expect(findShown('最近 30 天沒有通知'), findsOneWidget);
    expect(findShown('開啟通知'), findsWidgets);

    await tester.tap(find.byTooltip('通知設定'));
    await settle(tester);
    expect(find.byType(NotificationsScreen), findsOneWidget);
  });
}
