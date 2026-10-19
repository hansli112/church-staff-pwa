import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/core/telemetry.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/state/push.dart';
import 'package:martha/state/session.dart';

import '../support/fake_push.dart';
import '../support/harness.dart';
import '../support/seed.dart';

class _Errors extends NoTelemetry {
  final errors = <Object>[];

  @override
  void recordError(Object error, StackTrace stack, {bool fatal = false}) => errors.add(error);
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await settle(tester);
}

/// Someone signed in and in no church yet, with an invite to 恩典堂 and
/// one to 希望堂.
MemoryBackend invited() {
  final b = MemoryBackend(clock: testClock);
  for (final (id, name, code) in [('grace', '恩典堂', 'GRACE2026'), ('hope', '希望堂', 'HOPE2026')]) {
    b.addChurch(name, id: id);
    b.addMember(id, const Member(uid: 'admin', name: '牧師', role: Role.admin));
    b.invites[code] = Invite(
      code: code,
      churchId: id,
      churchName: name,
      expiresAt: testNow.add(const Duration(days: 7)),
    );
  }
  b.auth.signInAs('new@gmail.com');
  return b;
}

Future<void> join(WidgetTester tester, String church, String code) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/c/$church/join/$code');
  await settle(tester);
  await tapText(tester, '加入');
}

Future<void> resume(WidgetTester tester) async {
  // Off to the phone's settings and back, one state at a time.
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await settle(tester);
}

void main() {
  testWidgets('joining asks for notifications, and the phone asks only once 開啟通知 is tapped', (tester) async {
    final push = FakePush(answer: PushPermission.granted);
    await pumpApp(tester, invited(), overrides: [pushServiceProvider.overrideWithValue(push)]);
    await join(tester, 'grace', 'GRACE2026');

    expect(find.text('被排到服事時通知你'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(push.asked, 0, reason: 'no system prompt before the person asks');

    await tapText(tester, '開啟通知');
    expect(push.asked, 1);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('開啟通知'), findsNothing, reason: 'on, so the home page does not offer it');
  });

  testWidgets('starting a church asks too', (tester) async {
    final b = MemoryBackend(clock: testClock)..auth.signInAs('new@gmail.com');
    await pumpApp(tester, b, overrides: [pushServiceProvider.overrideWithValue(FakePush())]);
    await tapText(tester, '建立新教會');
    await tester.enterText(find.byType(TextField), '恩典堂');
    await tester.pump();
    await tapText(tester, '建立');

    expect(find.text('被排到服事時通知你'), findsOneWidget);
  });

  testWidgets('not now: the home page offers it until hidden, and joining again does not ask', (tester) async {
    final push = FakePush();
    await pumpApp(tester, invited(), overrides: [pushServiceProvider.overrideWithValue(push)]);
    await join(tester, 'grace', 'GRACE2026');
    await tapText(tester, '稍後再說');

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(push.asked, 0);
    await tapText(tester, '開啟通知');
    expect(push.asked, 1);
    expect(find.textContaining('請點「允許」'), findsOneWidget, reason: 'the prompt was dismissed');

    await tester.tap(find.byTooltip('不再顯示'));
    await settle(tester);
    expect(find.text('開啟通知'), findsNothing);

    await join(tester, 'hope', 'HOPE2026');
    expect(find.text('被排到服事時通知你'), findsNothing, reason: 'asked once on this phone');
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets(
    'allowed from the home page: the app comes back before the prompt answers, and registering still finishes',
    (
      tester,
    ) async {
      final prompt = Completer<void>();
      final push = FakePush(answer: PushPermission.granted, prompt: prompt);
      await pumpApp(tester, seededChurch(as: staffMei), overrides: [pushServiceProvider.overrideWithValue(push)]);

      await tapText(tester, '開啟通知');
      // Android's prompt pauses the app; back, it sees notifications on and
      // the card goes, while registering is still under way.
      await resume(tester);
      expect(find.text('開啟通知'), findsNothing);

      prompt.complete();
      await settle(tester);
      expect(push.asked, 1);
      expect(find.text('開啟通知'), findsNothing);
    },
  );

  testWidgets('allowed from the home page, the card gone, then no token: recorded, and nothing breaks', (tester) async {
    final prompt = Completer<void>();
    final push = FakePush(answer: PushPermission.granted, registers: false, prompt: prompt);
    final telemetry = _Errors();
    await pumpApp(
      tester,
      seededChurch(as: staffMei),
      overrides: [pushServiceProvider.overrideWithValue(push), telemetryProvider.overrideWithValue(telemetry)],
    );

    await tapText(tester, '開啟通知');
    await resume(tester);
    prompt.complete();
    await settle(tester);
    expect(telemetry.errors, hasLength(1));
  });

  testWidgets('a phone that already allows them is not asked', (tester) async {
    final push = FakePush(state: PushPermission.granted);
    await pumpApp(tester, invited(), overrides: [pushServiceProvider.overrideWithValue(push)]);
    await join(tester, 'grace', 'GRACE2026');

    expect(find.text('被排到服事時通知你'), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('開啟通知'), findsNothing);
  });

  testWidgets('turned off on the phone: home and 通知 open its settings, and coming back sees them on', (
    tester,
  ) async {
    final push = FakePush(state: PushPermission.denied);
    await pumpApp(tester, seededChurch(as: staffMei), overrides: [pushServiceProvider.overrideWithValue(push)]);

    await tapText(tester, '到系統設定開啟通知');
    expect(push.settingsOpened, 1);
    expect(push.asked, 0, reason: 'the phone would not ask again');

    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me/notifications');
    await settle(tester);
    await tapText(tester, '到系統設定開啟通知');
    expect(push.settingsOpened, 2);

    push.state = PushPermission.granted;
    await resume(tester);
    expect(find.text('到系統設定開啟通知'), findsNothing);
    final reminders = tester.widget<Switch>(
      find.descendant(
        of: find.ancestor(of: find.text('服事提醒'), matching: find.byType(InkWell)),
        matching: find.byType(Switch),
      ),
    );
    expect(reminders.value, isTrue, reason: 'the switches work again');

    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/home');
    await settle(tester);
    expect(find.text('到系統設定開啟通知'), findsNothing);
  });

  testWidgets('a phone with no settings page to open says where to look', (tester) async {
    final push = FakePush(state: PushPermission.denied, hasSettings: false);
    await pumpApp(tester, seededChurch(as: staffMei), overrides: [pushServiceProvider.overrideWithValue(push)]);

    await tapText(tester, '到系統設定開啟通知');
    expect(find.text('通知被關掉了，請到系統設定打開'), findsOneWidget);
  });
}
