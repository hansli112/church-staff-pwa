import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/core/languages.dart';
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

  testWidgets('a cost\'s name in the other languages is saved; one left empty is not', (tester) async {
    final b = seededChurch();
    b.auth.operators.add('pastor');
    b.fundingCosts = const [_cloud];
    await pumpApp(tester, b);
    await go(tester, '/admin/funding');

    await tester.tap(find.text('雲端'));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('costName-en')), ' Cloud hosting ');
    await tester.enterText(find.byKey(const Key('costName-ja')), 'クラウド');
    await tester.tap(find.text('儲存').last);
    await settle(tester);
    expect(b.fundingCosts.single.names, {AppLanguage.en: 'Cloud hosting', AppLanguage.ja: 'クラウド'});

    await tester.tap(find.text('雲端'));
    await settle(tester);
    expect(find.text('Cloud hosting'), findsOneWidget, reason: 'opened again, it shows what was saved');
    await tester.enterText(find.byKey(const Key('costName-ja')), '');
    await tester.tap(find.text('儲存').last);
    await settle(tester);
    expect(b.fundingCosts.single.names, {AppLanguage.en: 'Cloud hosting'});
  });

  testWidgets('the back office warms up its stats and costs as it opens', (tester) async {
    final b = seededChurch();
    b.auth.operators.add('pastor');
    await pumpApp(tester, b);
    await go(tester, '/admin');
    expect(b.warmedUp, contains(WarmUp.backOffice));
  });
  testWidgets('saved, but not read back: the costs say so and wait for a retry before another change', (tester) async {
    final b = seededChurch();
    b.auth.operators.add('pastor');
    b.fundingCosts = const [_cloud];
    await pumpApp(tester, b);
    await go(tester, '/admin/funding');

    await tester.tap(find.text('雲端'));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('costAmount')), '400');
    final held = b.backOfficeReadsHeld = Completer();
    await tester.tap(find.text('儲存').last);
    await settle(tester);
    held.completeError(const CloudException(CloudErrorCode.unavailable));
    b.backOfficeReadsHeld = null;
    await settle(tester);
    expect(b.fundingCosts.single.amount, 400);
    expect(find.textContaining('顯示上次的資料'), findsOneWidget);
    await tester.tap(find.text('雲端'));
    await settle(tester);
    expect(find.text('費用項目'), findsNothing, reason: 'a change from an out-of-date list would undo the save');

    await tester.tap(find.text('重試'));
    await settle(tester);
    expect(find.textContaining('顯示上次的資料'), findsNothing);
    await tester.tap(find.text('雲端'));
    await settle(tester);
    expect(find.text('費用項目'), findsOneWidget);
  });
}
