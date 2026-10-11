import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/data/backend.dart';

import '../support/harness.dart';
import '../support/seed.dart';

void main() {
  testWidgets('a cost deletion whose undo fails says so, not 已復原', (tester) async {
    const cloud = CostItem(name: '雲端', amount: 300, currency: Currency.twd, per: CostPeriod.month);
    const domain = CostItem(name: '網域', amount: 600, currency: Currency.twd, per: CostPeriod.year);
    final b = seededChurch();
    b.auth.operators.add('pastor');
    b.fundingCosts = const [cloud, domain];
    await pumpApp(tester, b);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/admin/funding');
    await settle(tester);

    await tester.tap(find.text('網域'));
    await settle(tester);
    await tester.tap(find.text('刪除').last);
    await settle(tester);
    expect(b.fundingCosts, const [cloud]);

    b.setOnline(false);
    await tester.tap(find.text('復原'));
    await settle(tester);
    expect(find.text('復原失敗，請再試一次'), findsOneWidget);
    expect(find.text('已復原'), findsNothing);
    expect(b.fundingCosts, const [cloud]);
  });
}
