import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../support/harness.dart';
import '../support/seed.dart';

Future<void> go(WidgetTester tester, String location) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
  await settle(tester);
}

String path(WidgetTester tester) => GoRouter.of(tester.element(find.byType(Scaffold).last)).state.uri.path;

void main() {
  testWidgets('an admin manages the church from the top of 我的: members, invites, services settings, one tap each', (
    tester,
  ) async {
    await pumpApp(tester, seededChurch());
    await go(tester, '/me');
    expect(find.text('管理教會').hitTestable(), findsOneWidget);
    for (final (row, to) in [('同工', '/me/members'), ('邀請', '/me/invites'), ('服事設定', '/me/services')]) {
      expect(find.text(row).hitTestable(), findsOneWidget, reason: '$row without scrolling');
      await tester.tap(find.text(row));
      await settle(tester);
      expect(path(tester), to);
      await go(tester, '/me');
    }
  });

  testWidgets('教會資訊 keeps the rest, without the three already in 我的', (tester) async {
    await pumpApp(tester, seededChurch());
    await go(tester, '/me/church');
    expect(find.text('邀請'), findsNothing);
    expect(find.text('服事設定'), findsNothing);
    expect(find.text('外部通知'), findsOneWidget);
  });

  testWidgets('staff have no 管理教會', (tester) async {
    await pumpApp(tester, seededChurch(as: staffMei));
    await go(tester, '/me');
    expect(find.text('管理教會'), findsNothing);
    expect(find.text('邀請'), findsNothing);
  });

  testWidgets('everyone finds the LINE community, which opens in LINE', (tester) async {
    final launches = captureLaunches();
    await pumpApp(tester, seededChurch(as: staffMei));
    await go(tester, '/me');
    await tester.scrollUntilVisible(find.text('LINE 社群'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('問問題、回報問題、和其他教會交流'), findsOneWidget);
    await tester.tap(find.text('LINE 社群'));
    await settle(tester);
    expect(launches.opened.single, startsWith('https://line.me/ti/g2/'));
    expect(launches.modes.single, PreferredLaunchMode.externalApplication);
  });
}
