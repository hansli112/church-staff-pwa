import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/data/backend.dart';

import '../support/harness.dart';
import '../support/seed.dart';

const _cloud = CostItem(name: '雲端', amount: 300, currency: Currency.twd, per: CostPeriod.month);
const _domain = CostItem(name: '網域', amount: 600, currency: Currency.twd, per: CostPeriod.year);

void main() {
  Future<void> go(WidgetTester tester, String path) async {
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(path);
    await settle(tester);
  }

  testWidgets('opened again, costs show at once as last read, and change once read anew', (tester) async {
    final b = seededChurch();
    b.auth.operators.add('pastor');
    b.fundingCosts = const [_cloud];
    await pumpApp(tester, b);
    await go(tester, '/admin/funding');
    expect(find.text('雲端'), findsOneWidget);
    await go(tester, '/me');

    b.fundingCosts = const [_cloud, _domain];
    final held = b.backOfficeReadsHeld = Completer();
    await go(tester, '/admin/funding');
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('雲端'), findsOneWidget);
    expect(find.text('網域'), findsNothing);
    // A cost changes from the server's list only.
    await tester.tap(find.text('雲端'));
    await settle(tester);
    expect(find.text('費用項目'), findsNothing);

    held.complete();
    await settle(tester);
    expect(find.text('網域'), findsOneWidget);
    await tester.tap(find.text('雲端'));
    await settle(tester);
    expect(find.text('費用項目'), findsOneWidget);
  });

  testWidgets('stats that cannot be read again stay, saying when they were read', (tester) async {
    final b = seededChurch();
    b.auth.operators.add('pastor');
    b.cloud.stats.add(DailyStats(day: testToday, values: const {'users': 40}));
    await pumpApp(tester, b);
    await go(tester, '/admin/stats');
    expect(find.text('40'), findsOneWidget);
    await go(tester, '/me');

    b.setOnline(false);
    await go(tester, '/admin/stats');
    expect(find.text('40'), findsOneWidget);
    expect(find.textContaining('顯示上次的資料'), findsOneWidget);
  });

  testWidgets('the back office warms up its stats and costs as it opens', (tester) async {
    final b = seededChurch();
    b.auth.operators.add('pastor');
    await pumpApp(tester, b);
    await go(tester, '/admin');
    expect(b.warmedUp, contains(WarmUp.backOffice));
  });
}
