import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/core/design/components.dart';
import 'package:martha/core/languages.dart';
import 'package:martha/data/backend.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/models.dart';

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

  Future<void> openGrace(WidgetTester tester, MemoryBackend b) async {
    b.auth.operators.add('pastor');
    await pumpApp(tester, b);
    await go(tester, '/admin');
    await tester.tap(find.text('恩典堂'));
    await settle(tester);
  }

  /// The row of [name]: its button says what a tap on it does.
  Finder button(String name, String label) =>
      find.descendant(of: find.widgetWithText(ListRow, name), matching: find.widgetWithText(TextButton, label));

  testWidgets('設為管理員 shows at once and goes through in the background; 復原 takes it back', (tester) async {
    final b = seededChurch();
    await openGrace(tester, b);
    expect(button('李美玉', '設為管理員'), findsOneWidget);

    final held = b.adminChangeHeld = Completer();
    await tester.tap(button('李美玉', '設為管理員'));
    await tester.pump();
    expect(button('李美玉', '取消管理員'), findsOneWidget, reason: 'shown before the backend answers');
    expect(find.text('已把「李美玉」設為管理員'), findsOneWidget);
    expect(b.memberOf('grace', 'mei')!.isAdmin, isFalse);
    held.complete();
    b.adminChangeHeld = null;
    await settle(tester);
    expect(b.memberOf('grace', 'mei')!.isAdmin, isTrue);
    expect(button('李美玉', '取消管理員'), findsOneWidget);

    await tester.tap(find.text('復原'));
    await settle(tester);
    expect(b.memberOf('grace', 'mei')!.isAdmin, isFalse);
    expect(button('李美玉', '設為管理員'), findsOneWidget);
  });

  testWidgets('取消管理員 takes an admin off; the only admin has no such button', (tester) async {
    final b = seededChurch();
    await openGrace(tester, b);
    expect(button('王牧師', '取消管理員'), findsNothing, reason: 'a church keeps one admin');

    await tester.tap(button('李美玉', '設為管理員'));
    await settle(tester);
    await tester.tap(button('王牧師', '取消管理員'));
    await settle(tester);
    expect(b.memberOf('grace', 'pastor')!.isAdmin, isFalse);
    expect(find.text('已取消「王牧師」的管理員'), findsOneWidget);
    expect(button('李美玉', '取消管理員'), findsNothing);
  });

  testWidgets('復原 of 取消管理員, even before it is through, gives back a whole church\'s 牧者', (tester) async {
    final b = seededChurch(
      extra: const [
        Member(uid: 'lin', name: '林牧師', role: Role.admin, identities: [PastorIdentity(null)]),
      ],
    );
    await openGrace(tester, b);

    final held = b.adminChangeHeld = Completer();
    await tester.tap(button('林牧師', '取消管理員'));
    await settle(tester);
    await tester.tap(find.text('復原'));
    await settle(tester);
    expect(button('林牧師', '取消管理員'), findsOneWidget);
    held.complete();
    b.adminChangeHeld = null;
    await settle(tester);
    expect(b.memberOf('grace', 'lin')!.identities, [const PastorIdentity(null)]);
  });

  testWidgets('a change the backend refuses goes back, saying why', (tester) async {
    final b = seededChurch();
    await openGrace(tester, b);
    b.setOnline(false);
    await tester.tap(button('李美玉', '設為管理員'));
    await settle(tester);
    expect(b.memberOf('grace', 'mei')!.isAdmin, isFalse);
    expect(button('李美玉', '設為管理員'), findsOneWidget);
    expect(find.text('離線中，連線後才能儲存'), findsOneWidget);
  });

  testWidgets('deleted churches stay out of the list, and a search still finds them', (tester) async {
    final b = seededChurch();
    b.auth.operators.add('pastor');
    b.addChurch('舊教會', status: ChurchStatus.deleted);
    await pumpApp(tester, b);
    await go(tester, '/admin');
    expect(find.text('恩典堂'), findsOneWidget);
    expect(find.text('舊教會'), findsNothing);

    await tester.enterText(find.byType(TextField), '舊');
    await settle(tester);
    expect(find.text('舊教會'), findsOneWidget);
  });
}
