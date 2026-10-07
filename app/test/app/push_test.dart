import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/state/push.dart';

import '../support/harness.dart';
import '../support/seed.dart';

class FakePush implements PushService {
  FakePush({this.answer = PushPermission.notAsked, this.registers = true});

  /// What the permission prompt comes back with.
  final PushPermission answer;

  /// False: allowed, but the device gets no token.
  final bool registers;
  final notices = StreamController<PushNotice>.broadcast();

  @override
  Future<PushPermission> permission() async => PushPermission.notAsked;

  @override
  Future<PushPermission> enable() async {
    if (!registers) throw Exception('apns-token-not-set');
    return answer;
  }

  @override
  Future<void> refresh(String uid) async {}

  @override
  Future<void> unregister(String uid) async {}

  @override
  Stream<String> get openedLinks => const Stream.empty();

  @override
  Stream<PushNotice> get foreground => notices.stream;
}

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

    await tester.tap(find.text('開啟通知'));
    await settle(tester);
    expect(find.textContaining('請按「允許」'), findsOneWidget);
  });

  testWidgets('allowed, but the device cannot get a token: says it will try again', (tester) async {
    final push = FakePush(answer: PushPermission.granted, registers: false);
    await pumpApp(tester, seededChurch(), overrides: [pushServiceProvider.overrideWithValue(push)]);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me/notifications');
    await settle(tester);

    await tester.tap(find.text('開啟通知'));
    await settle(tester);
    expect(find.textContaining('下次打開 App 會再試'), findsOneWidget);
  });
}
