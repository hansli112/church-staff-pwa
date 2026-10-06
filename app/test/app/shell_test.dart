import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/memory/demo_data.dart';

import '../support/harness.dart';

void main() {
  testWidgets('signed-in member sees the four tabs from the ARB file', (
    tester,
  ) async {
    await pumpApp(tester, demoBackend(today: testToday));

    expect(find.text('首頁'), findsWidgets);
    expect(find.text('服事表'), findsOneWidget);
    expect(find.text('行事曆'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);

    await tester.tap(find.text('我的'));
    await settle(tester);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('a desktop-wide window keeps the app a readable width', (tester) async {
    await pumpApp(tester, demoBackend(today: testToday));
    tester.view.physicalSize = const Size(1440 * 3, 900 * 3);
    await settle(tester);

    expect(tester.getSize(find.byType(NavigationBar)).width, 640);
    expect(tester.getCenter(find.byType(NavigationBar)).dx, 720, reason: 'centred');
  });
}
