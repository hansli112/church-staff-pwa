import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
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

  testWidgets('支持紀錄 lists each payment by month: how much, which kind, which store, when, refunds counting nothing', (
    tester,
  ) async {
    final b = seededChurch();
    b.auth.operators.add('pastor');
    b.fundingPayments = [
      SupportPayment(
        store: PaymentStore.apple,
        productId: 'tip_small',
        amount: 7.79,
        currency: 'MYR',
        amountTwd: 62,
        month: '2026-10',
        at: DateTime(2026, 10, 1, 9, 15),
      ),
      SupportPayment(
        store: PaymentStore.google,
        productId: 'supporter_monthly',
        amount: 81,
        currency: 'TWD',
        amountTwd: 81,
        month: '2026-10',
        at: DateTime(2026, 10, 1, 8, 30),
      ),
      SupportPayment(
        store: PaymentStore.ecpay,
        productId: 'web_once',
        amount: 24,
        currency: 'TWD',
        amountTwd: 24,
        refundedTwd: 24,
        month: '2026-09',
        at: DateTime(2026, 9, 16, 17, 18),
      ),
      SupportPayment(
        store: PaymentStore.apple,
        productId: 'tip_large',
        amount: 40.8,
        currency: 'HKD',
        amountTwd: 172,
        month: '2026-08',
        at: DateTime(2026, 8, 24, 20, 37),
      ),
    ];
    await pumpApp(tester, b);
    await go(tester, '/admin/funding');
    expect(find.text('10月 2 筆'), findsOneWidget, reason: 'this month, on 雲端費用');
    await tester.tap(find.text('支持紀錄'));
    await settle(tester);

    expect(findShown('2026年10月 · NT\$143'), findsOneWidget);
    // What was paid, by its currency's code: HK\$ would show as \$ alone.
    expect(findShown('NT\$62  MYR 7.79'), findsOneWidget);
    expect(findShown('NT\$172  HKD 40.80'), findsOneWidget);
    expect(findShown('一次性 · App Store'), findsNWidgets(2));
    expect(findShown('每月 · Google Play'), findsOneWidget);
    expect(findShown('10/1 09:15'), findsOneWidget);
    expect(findShown('一次性 NT\$62 · 每月 NT\$81'), findsOneWidget);
    expect(findShown('2026年9月 · NT\$0'), findsOneWidget, reason: 'a refund counts nothing');
    expect(findShown('一次性 · 網站 · 9/16 17:18'), findsOneWidget);
    expect(findShown('已退款'), findsOneWidget);

    await tester.tap(find.text('每月'));
    await settle(tester);
    expect(findShown('2026年10月 · NT\$81'), findsOneWidget);
    expect(findShown('2026年9月 · NT\$0'), findsNothing, reason: 'no 每月 that month');
    expect(findShownContaining('App Store'), findsNothing);
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

  testWidgets('stats show the latest day in K, and a day touched on every card', (tester) async {
    final b = seededChurch();
    b.auth.operators.add('pastor');
    final yesterday = testToday.addDays(-1);
    b.cloud.stats
      ..add(DailyStats(day: testToday, values: const {'users': 729, 'users_active_7d': 32486}))
      ..add(DailyStats(day: yesterday, values: const {'users': 129, 'users_active_7d': 16727}));
    await pumpApp(tester, b);
    await go(tester, '/admin/stats');
    expect(find.text(DateFormat.MMMEd().format(testToday.midnight)), findsOneWidget);
    expect(find.text('729'), findsOneWidget);
    expect(find.text('+600'), findsOneWidget, reason: 'a total says how much it grew');
    expect(find.text('32.5K'), findsOneWidget);

    final chart = find.byKey(const Key('statsChart-users'));
    await tester.tapAt(tester.getTopLeft(chart) + const Offset(4, 36));
    await settle(tester);
    expect(find.text(DateFormat.MMMEd().format(yesterday.midnight)), findsOneWidget);
    expect(find.text('129'), findsOneWidget);
    expect(find.text('16.7K'), findsOneWidget, reason: 'every card shows the day touched');
    expect(find.text('+600'), findsNothing);
  });

  testWidgets('stats show who opened the app and the churches editing in 7 days, not 成員 and 服事表', (tester) async {
    final b = seededChurch();
    b.auth.operators.add('pastor');
    final values = {'users': 729, 'members': 670, 'rosters': 752, 'users_active_7d': 412, 'churches_editing_7d': 96};
    b.cloud.stats
      ..add(DailyStats(day: testToday, values: values))
      ..add(DailyStats(day: testToday.addDays(-1), values: {...values, 'users_active_7d': 400}));
    await pumpApp(tester, b);
    await go(tester, '/admin/stats');
    expect(find.text('7 天內打開過的人'), findsOneWidget);
    expect(find.text('412'), findsOneWidget);
    expect(find.text('+12'), findsNothing, reason: 'a week\'s count, not a total that grows');
    expect(find.text('7 天內改過服事表的教會'), findsOneWidget);
    expect(find.text('成員'), findsNothing);
    expect(find.text('服事表'), findsNothing);
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

  testWidgets('the list is newest first, 50 at a time, with how many there are; 顯示更多 shows the next', (tester) async {
    final b = seededChurch();
    b.auth.operators.add('pastor');
    for (var i = 1; i <= 54; i++) {
      b.addChurch('教會$i', id: 'c$i');
    }
    b.addChurch('舊教會', status: ChurchStatus.deleted);
    await pumpApp(tester, b);
    await go(tester, '/admin');
    expect(find.text('共 55 間'), findsOneWidget);
    expect(find.text('教會54'), findsOneWidget);

    final list = find.byType(Scrollable).last;
    await tester.scrollUntilVisible(find.text('顯示更多'), 500, scrollable: list);
    expect(find.text('教會5'), findsOneWidget);
    expect(find.text('教會4'), findsNothing);
    await tester.tap(find.text('顯示更多'));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('恩典堂'), 500, scrollable: list);
    expect(find.text('教會4'), findsOneWidget);
    expect(find.text('顯示更多'), findsNothing);
    expect(find.text('舊教會'), findsNothing);
  });

  testWidgets('a search waits for typing to pause, as each one reads every church', (tester) async {
    final b = seededChurch();
    b.auth.operators.add('pastor');
    b.addChurch('舊教會', status: ChurchStatus.deleted);
    await pumpApp(tester, b);
    await go(tester, '/admin');
    b.adminSearches.clear();

    for (final typed in ['舊', '舊教']) {
      await tester.enterText(find.byType(TextField), typed);
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(b.adminSearches, isEmpty);
    await settle(tester);
    expect(b.adminSearches, ['舊教']);
    expect(find.text('舊教會'), findsOneWidget);
  });

  testWidgets('a new search shows a spinner, not the last one\'s churches; one that fails says so, with 重試', (
    tester,
  ) async {
    final b = seededChurch();
    b.auth.operators.add('pastor');
    b.addChurch('舊教會', status: ChurchStatus.deleted);
    await pumpApp(tester, b);
    await go(tester, '/admin');

    await tester.enterText(find.byType(TextField), '舊');
    await settle(tester);
    expect(find.text('舊教會'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '恩');
    await tester.pump();
    expect(find.text('舊教會'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await settle(tester);
    expect(find.text('恩典堂'), findsOneWidget);

    b.auth.operators.remove('pastor');
    await tester.enterText(find.byType(TextField), '恩典');
    await settle(tester);
    expect(find.text('恩典堂'), findsNothing);
    expect(find.widgetWithText(ErrorRetry, '重試'), findsOneWidget);
    b.auth.operators.add('pastor');
    await tester.tap(find.text('重試'));
    await settle(tester);
    expect(find.text('恩典堂'), findsOneWidget);
  });

  testWidgets('a church\'s members that cannot be read say so, with 重試', (tester) async {
    final b = seededChurch();
    b.auth.operators.add('pastor');
    await pumpApp(tester, b);
    await go(tester, '/admin');
    b.auth.operators.remove('pastor');
    await tester.tap(find.text('恩典堂'));
    await settle(tester);
    expect(find.widgetWithText(ErrorRetry, '重試'), findsOneWidget);

    b.auth.operators.add('pastor');
    await tester.tap(find.text('重試'));
    await settle(tester);
    expect(button('李美玉', '設為管理員'), findsOneWidget);
  });
}
