import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/harness.dart';
import '../support/seed.dart';

// An admin renames the church from 教會資訊, as 同工 rename one another:
// the name, a pencil beside it, opens 改名.

Future<void> go(WidgetTester tester, String location) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
  await settle(tester);
}

void main() {
  testWidgets('an admin taps the name, renames it, and everyone sees the new one', (tester) async {
    final b = seededChurch();
    final was = b.churches['grace']!.name;
    await pumpApp(tester, b);
    await go(tester, '/me/church');
    await tester.tap(find.text(was));
    await settle(tester);
    expect(find.text('改名'), findsOneWidget);
    await tester.enterText(find.byType(TextField), ' 恩典之家 ');
    await tester.pump();
    await tester.tap(find.text('儲存'));
    await settle(tester);
    expect(b.churches['grace']!.name, '恩典之家');
    expect(find.text('恩典之家'), findsOneWidget);
  });

  testWidgets('to anyone else it is only a name', (tester) async {
    final b = seededChurch(as: staffMei);
    final was = b.churches['grace']!.name;
    await pumpApp(tester, b);
    await go(tester, '/me/church');
    await tester.tap(find.text(was));
    await settle(tester);
    expect(find.text('改名'), findsNothing);
  });
}
