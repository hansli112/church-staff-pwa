import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/data/memory/demo_data.dart';
import 'package:martha/features/shell/shell.dart';

import '../support/harness.dart';

void main() {
  testWidgets('signed-in member sees the four tabs from the ARB file', (
    tester,
  ) async {
    await pumpApp(tester, demoBackend(clock: testClock));

    expect(find.text('首頁'), findsWidgets);
    expect(find.text('服事表'), findsOneWidget);
    expect(find.text('行事曆'), findsOneWidget);
    expect(find.text('設定'), findsOneWidget);

    await tester.tap(find.text('設定'));
    await settle(tester);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('a desktop-wide window keeps the app a readable width', (tester) async {
    await pumpApp(tester, demoBackend(clock: testClock));
    tester.view.physicalSize = const Size(1440 * 3, 900 * 3);
    await settle(tester);

    expect(tester.getSize(find.byType(NavigationBar)).width, 640);
    expect(tester.getCenter(find.byType(NavigationBar)).dx, 720, reason: 'centred');
  });
  testWidgets('the tabs fade in after loading, not slide in like an opened page', (tester) async {
    await pumpApp(tester, demoBackend(clock: testClock));
    final route = ModalRoute.of(tester.element(find.byType(AppShell)))!;
    expect(route.settings, isA<CustomTransitionPage<void>>());
    expect(
      (route.settings as CustomTransitionPage<void>).transitionsBuilder(
        tester.element(find.byType(AppShell)),
        const AlwaysStoppedAnimation(0.5),
        const AlwaysStoppedAnimation(0),
        const SizedBox(),
      ),
      isA<FadeTransition>(),
    );
  });
}
