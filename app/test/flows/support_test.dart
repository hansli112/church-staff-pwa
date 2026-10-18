import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/app.dart';
import 'package:martha/core/design/components.dart';
import 'package:martha/data/backend.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/state/providers.dart';
import 'package:martha/state/support.dart';

import '../support/harness.dart';
import '../support/seed.dart';

class FakeStore implements SupportStore {
  FakeStore({this.now, this.items = _items, this.unreachable = false});

  static const _items = [
    SupportItem(id: 'tip_small', title: '請喝咖啡', price: 'NT\$90', subscription: false),
    SupportItem(id: 'supporter_monthly', title: '每月支持', price: 'NT\$60', subscription: true),
    SupportItem(id: 'supporter_monthly_plus', title: '每月支持', price: 'NT\$150', subscription: true),
  ];

  /// When a purchase is paid; the test's clock.
  final DateTime Function()? now;

  /// What the store sells; empty before any product is set up there.
  final List<SupportItem> items;

  /// The store can't be reached.
  final bool unreachable;
  final _results = StreamController<PurchaseResult>.broadcast(sync: true);
  final bought = <String>[];
  int refreshes = 0;

  /// The store reporting [plan] paid again, as a renewal does.
  void renew(DateTime at, {String plan = 'supporter_monthly'}) =>
      _results.add((productId: plan, outcome: PurchaseOutcome.thanks, paidAt: at));

  @override
  bool get available => true;

  @override
  Future<List<SupportItem>> products() async => unreachable ? throw StateError('offline') : items;

  @override
  Future<void> buy(SupportItem item) async {
    bought.add(item.id);
    _results.add((productId: item.id, outcome: PurchaseOutcome.thanks, paidAt: now?.call()));
  }

  @override
  Future<void> restore() async {}

  @override
  Future<void> refresh() async => refreshes++;

  @override
  Stream<PurchaseResult> get results => _results.stream;

  @override
  String get name => 'Google Play';

  @override
  Uri manageSubscription(String plan) => Uri.parse('https://play.google.com/store/account/subscriptions?sku=$plan');
}

class FakeIcons implements AppIconSwitcher {
  String? icon;

  @override
  Future<String?> current() async => icon;

  @override
  Future<void> set(String? name) async => icon = name;
}

/// Scrolls [finder] to the middle of the page, clear of the tab bar.
Future<void> showMiddle(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pump();
}

Future<void> pumpWithStore(
  WidgetTester tester,
  SupportStore store,
  AppIconSwitcher icons, {
  MemoryBackend? backend,
}) async {
  tester.view.physicalSize = const Size(393 * 3, 852 * 3);
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.localesTestValue = const [Locale('zh', 'TW')];
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...await testOverrides(backend ?? seededChurch(as: staffMei)),
        supportStoreProvider.overrideWithValue(store),
        appIconSwitcherProvider.overrideWithValue(icons),
      ],
      retry: (_, _) => null,
      child: const MarthaApp(),
    ),
  );
  await settle(tester);
}

void main() {
  testWidgets('without a store (the web), while the website takes no payments, no support entry', (tester) async {
    await pumpApp(tester, seededChurch(as: staffMei));
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me');
    await settle(tester);
    expect(find.text('支持馬大別忙'), findsNothing);
  });

  testWidgets("on the web, once the website takes payments, the website's support page in my language", (
    tester,
  ) async {
    final launcher = captureLaunches();
    await pumpApp(
      tester,
      seededChurch(as: staffMei),
      overrides: [isWebProvider.overrideWithValue(true), sitePaymentsProvider.overrideWithValue(true)],
      deviceLocales: const [Locale('en', 'US')],
    );
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me');
    await settle(tester);
    await tester.tap(find.text('Support Martha, sit'));
    await settle(tester);
    expect(launcher.opened.single, endsWith('/en/support?lang=en'));
  });

  testWidgets(
    "the apps open the privacy policy and the terms as the app's, which hide the ways to the website's payments",
    (
      tester,
    ) async {
      final launcher = captureLaunches();
      await pumpApp(tester, seededChurch(as: staffMei));
      GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me');
      await settle(tester);
      await tester.tap(find.text('隱私權政策'));
      await tester.tap(find.text('服務條款'));
      await settle(tester);
      expect(launcher.opened, [endsWith('/privacy?lang=zh-Hant&from=app'), endsWith('/terms?lang=zh-Hant&from=app')]);
    },
  );

  testWidgets('the web app opens them as the website', (tester) async {
    final launcher = captureLaunches();
    await pumpApp(tester, seededChurch(as: staffMei), overrides: [isWebProvider.overrideWithValue(true)]);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me');
    await settle(tester);
    await tester.tap(find.text('隱私權政策'));
    await settle(tester);
    expect(launcher.opened.single, endsWith('/privacy?lang=zh-Hant'));
  });

  testWidgets('the apps never send people to pay on the website, whatever the build says', (tester) async {
    await pumpApp(tester, seededChurch(as: staffMei), overrides: [sitePaymentsProvider.overrideWithValue(true)]);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me');
    await settle(tester);
    expect(find.text('支持馬大別忙'), findsNothing);
  });

  testWidgets('a tip thanks; the subscription unlocks icons and a badge only I see', (tester) async {
    final store = FakeStore();
    final icons = FakeIcons();
    await pumpWithStore(tester, store, icons);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me');
    await settle(tester);
    expect(find.text('支持者'), findsNothing);
    await tester.tap(find.text('支持馬大別忙'));
    await settle(tester);

    await showMiddle(tester, find.text('紫'));
    await tester.tap(find.text('紫'));
    await settle(tester);
    expect(icons.icon, isNull, reason: 'icons are for subscribers');

    await showMiddle(tester, find.text('請喝咖啡'));
    await tester.tap(find.text('請喝咖啡'));
    await settle(tester);
    expect(find.text('謝謝你的支持'), findsOneWidget);

    await tester.tap(find.text('NT\$60'));
    await settle(tester);
    await showMiddle(tester, find.text('紫'));
    await tester.tap(find.text('紫'));
    await settle(tester);
    expect(icons.icon, 'Purple');
    expect(store.bought, ['tip_small', 'supporter_monthly']);
    expect(find.text('支持者'), findsOneWidget);
  });

  testWidgets('the subscription says it renews and where to cancel, beside the terms and privacy policy', (
    tester,
  ) async {
    final launcher = captureLaunches();
    await pumpWithStore(tester, FakeStore(), FakeIcons());
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me/support');
    await settle(tester);
    expect(findShown('每月自動續訂，可以隨時到 Google Play 的訂閱設定取消'), findsOneWidget);
    expect(findShown('管理訂閱'), findsNothing, reason: 'nothing to manage before subscribing');
    await tester.tap(findShown('服務條款'));
    await tester.tap(findShown('隱私權政策'));
    await settle(tester);
    expect(launcher.opened, [endsWith('/terms?lang=zh-Hant&from=app'), endsWith('/privacy?lang=zh-Hant&from=app')]);

    await tester.tap(find.text('NT\$60'));
    await settle(tester);
    await tester.tap(find.text('管理訂閱'));
    await settle(tester);
    expect(launcher.opened.last, 'https://play.google.com/store/account/subscriptions?sku=supporter_monthly');
  });

  testWidgets('two monthly plans; the badge is on the one I pay for, and the other switches to it', (tester) async {
    final launches = captureLaunches();
    final store = FakeStore();
    await pumpWithStore(tester, store, FakeIcons());
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me/support');
    await settle(tester);
    expect(find.text('每月支持'), findsNWidgets(3), reason: 'the section and both plans: one name, two amounts');
    Finder badgeOn(String price) =>
        find.descendant(of: find.widgetWithText(ListRow, price), matching: find.text('支持者'));

    await tester.tap(find.text('NT\$60'));
    await settle(tester);
    expect(badgeOn('NT\$60'), findsOneWidget);
    expect(badgeOn('NT\$150'), findsNothing);
    await tester.tap(find.text('NT\$60'));
    await settle(tester);
    expect(store.bought, ['supporter_monthly'], reason: 'the plan already paid for is not bought again');

    await tester.tap(find.text('NT\$150'));
    await settle(tester);
    expect(store.bought, ['supporter_monthly', 'supporter_monthly_plus']);
    expect(badgeOn('NT\$150'), findsOneWidget);
    expect(badgeOn('NT\$60'), findsNothing);
    await tester.tap(find.text('管理訂閱'));
    await settle(tester);
    expect(launches.opened.last, endsWith('sku=supporter_monthly_plus'));
  });

  testWidgets('before the store sells anything, it says so instead of an error', (tester) async {
    await pumpWithStore(tester, FakeStore(items: const []), FakeIcons());
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me/support');
    await settle(tester);
    expect(find.text('App 內支持即將開放'), findsOneWidget);
    expect(find.text('現在無法連上商店，請稍後再試'), findsNothing);
  });

  testWidgets("when the store can't be reached, try again later", (tester) async {
    await pumpWithStore(tester, FakeStore(unreachable: true), FakeIcons());
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me/support');
    await settle(tester);
    expect(find.text('現在無法連上商店，請稍後再試'), findsOneWidget);
  });

  group('the subscription', () {
    late DateTime now;
    late FakeStore store;
    late FakeIcons icons;

    /// Subscribes on [now] and picks the purple icon.
    Future<void> subscribe(WidgetTester tester) async {
      now = testNow;
      store = FakeStore(now: () => now);
      icons = FakeIcons();
      await pumpWithStore(
        tester,
        store,
        icons,
        backend: seededChurch(as: staffMei, clock: () => now),
      );
      GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me/support');
      await settle(tester);
      await tester.tap(find.text('NT\$60'));
      await settle(tester);
      await showMiddle(tester, find.text('紫'));
      await tester.tap(find.text('紫'));
      await settle(tester);
      expect(icons.icon, 'Purple');
    }

    /// The app opened again on [now].
    Future<void> reopen(WidgetTester tester) async {
      ProviderScope.containerOf(tester.element(find.byType(Scaffold).first)).invalidate(supporterPlanProvider);
      GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me');
      await settle(tester);
    }

    testWidgets('lapsed, the badge goes and the icon is the default again', (tester) async {
      await subscribe(tester);
      now = testNow.add(const Duration(days: 34));
      await reopen(tester);
      expect(find.text('支持者'), findsOneWidget, reason: 'a month and a few days to renew');

      now = testNow.add(const Duration(days: 36));
      await reopen(tester);
      expect(find.text('支持者'), findsNothing);
      expect(icons.icon, isNull);
    });

    testWidgets('each renewal the store reports keeps it another month', (tester) async {
      await subscribe(tester);
      store.renew(testNow.add(const Duration(days: 30)));
      now = testNow.add(const Duration(days: 60));
      await reopen(tester);
      expect(find.text('支持者'), findsOneWidget);
      expect(icons.icon, 'Purple');
    });

    testWidgets('the larger plan keeps it too, and the app remembers which plan', (tester) async {
      await subscribe(tester);
      store.renew(testNow.add(const Duration(days: 10)), plan: 'supporter_monthly_plus');
      now = testNow.add(const Duration(days: 40));
      await reopen(tester);
      expect(find.text('支持者'), findsOneWidget);
      expect(icons.icon, 'Purple');
      GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me/support');
      await settle(tester);
      expect(
        find.descendant(of: find.widgetWithText(ListRow, 'NT\$150'), matching: find.text('支持者')),
        findsOneWidget,
      );
    });

    testWidgets('opening the app asks the store again once I have subscribed, never before', (tester) async {
      await subscribe(tester);
      final before = store.refreshes;
      await reopen(tester);
      expect(store.refreshes, before + 1);

      final other = FakeStore();
      await pumpWithStore(tester, other, FakeIcons());
      expect(other.refreshes, 0);
    });
  });

  group('this month\'s cloud costs', () {
    Future<MemoryBackend> open(WidgetTester tester, Funding? funding) async {
      final b = seededChurch(as: staffMei)..funding = funding;
      await pumpWithStore(tester, FakeStore(), FakeIcons(), backend: b);
      GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me/support');
      await settle(tester);
      return b;
    }

    testWidgets('what has come in against the target; a shortfall is not spelled out', (tester) async {
      await open(tester, const Funding(month: '2026-10', target: 500, received: 220, carried: 80, monthsLeft: 0));
      expect(find.text('這個月的雲端費用'), findsOneWidget);
      expect(find.text('NT\$300 / NT\$500'), findsOneWidget);
      expect(find.textContaining('還差'), findsNothing, reason: 'the platform operator covers a shortfall');
      expect(find.text('這個月已經足夠'), findsNothing);
      expect(find.text('含前幾個月留下的 NT\$80'), findsOneWidget);
    });

    testWidgets('a payment shows up while the page is open', (tester) async {
      final b = await open(
        tester,
        const Funding(month: '2026-10', target: 500, received: 220, carried: 0, monthsLeft: 0),
      );
      b.funding = const Funding(month: '2026-10', target: 500, received: 1400, carried: 0, monthsLeft: 1);
      b.notify();
      await settle(tester);
      expect(find.text('NT\$1,400 / NT\$500'), findsOneWidget);
      expect(find.text('這個月已經足夠，多的還能再維持 1 個月'), findsOneWidget);
    });

    testWidgets('where the money goes: each cost a month', (tester) async {
      await open(
        tester,
        const Funding(
          month: '2026-10',
          target: 564,
          received: 0,
          carried: 0,
          monthsLeft: 0,
          costs: [
            FundingCost(name: '雲端', perMonth: 300),
            FundingCost(name: 'Apple 開發者', perMonth: 264, yearly: true),
          ],
        ),
      );
      expect(find.text('每個月用在哪裡'), findsOneWidget);
      expect(find.text('雲端'), findsOneWidget);
      expect(find.text('NT\$300'), findsOneWidget);
      expect(find.text('NT\$264'), findsOneWidget);
      expect(find.text('每年付一次的費用平均分到每個月'), findsOneWidget);
    });

    testWidgets('only monthly costs: no word about yearly ones', (tester) async {
      await open(
        tester,
        const Funding(
          month: '2026-10',
          target: 300,
          received: 0,
          carried: 0,
          monthsLeft: 0,
          costs: [FundingCost(name: '雲端', perMonth: 300)],
        ),
      );
      expect(find.text('每個月用在哪裡'), findsOneWidget);
      expect(find.text('每年付一次的費用平均分到每個月'), findsNothing);
    });

    testWidgets('no costs set yet: nothing to show', (tester) async {
      await open(tester, null);
      expect(find.text('這個月的雲端費用'), findsNothing);
      await open(tester, const Funding(month: '2026-10', target: 0, received: 50, carried: 0, monthsLeft: 0));
      expect(find.text('這個月的雲端費用'), findsNothing);
    });
  });
}
