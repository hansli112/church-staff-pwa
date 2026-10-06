import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/state/push.dart';

import '../support/harness.dart';
import '../support/seed.dart';

class FakePush implements PushService {
  FakePush({this.answer = PushPermission.notAsked});

  /// What the permission prompt comes back with.
  final PushPermission answer;
  final notices = StreamController<PushNotice>.broadcast();

  @override
  Future<PushPermission> permission() async => PushPermission.notAsked;

  @override
  Future<PushPermission> enable() async => answer;

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

  testWidgets('turning notifications on without allowing them says what to do', (tester) async {
    await pumpApp(tester, seededChurch(), overrides: [pushServiceProvider.overrideWithValue(FakePush())]);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me/notifications');
    await settle(tester);

    await tester.tap(find.text('開啟通知'));
    await settle(tester);
    expect(find.textContaining('請按「允許」'), findsOneWidget);
  });
}
