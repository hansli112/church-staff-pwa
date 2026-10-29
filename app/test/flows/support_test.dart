import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:martha/app.dart';
import 'package:martha/core/design/components.dart';
import 'package:martha/core/languages.dart';
import 'package:martha/data/backend.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/state/app_build.dart';
import 'package:martha/state/providers.dart';
import 'package:martha/state/support.dart';

import '../support/harness.dart';
import '../support/seed.dart';

class FakeStore implements SupportStore {
  FakeStore({this.now, this.items = _items, this.unreachable = false});

  static const _items = [
    SupportItem(id: 'tip_small', price: 'NT\$90', subscription: false),
    SupportItem(id: 'supporter_monthly', price: 'NT\$60', subscription: true),
    SupportItem(id: 'supporter_monthly_plus', price: 'NT\$150', subscription: true),
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

  /// How many changes still fail, as the phone may refuse one.
  int failures = 0;

  /// Puts up the system's own note on the change, as iOS does: the app is
  /// covered (inactive) until it is closed.
  bool notes = false;

  @override
  Future<String?> current() async => icon;

  @override
  Future<void> set(String? name) async {
    if (failures > 0) {
      failures--;
      throw StateError('refused');
    }
    icon = name;
    if (notes) WidgetsBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
}

/// The monthly plan buttons, by price.
const plan60 = 'NT\$60／月';
const plan150 = 'NT\$150／月';

/// The mark on the plan I pay for.
Finder paidMark(String plan) =>
    find.descendant(of: find.widgetWithText(FilledButton, plan), matching: find.byIcon(Symbols.check_rounded));

/// Picks app icon [name] on its page, behind 支持馬大別忙.
Future<void> pickIcon(WidgetTester tester, String name) async {
  await tester.scrollUntilVisible(find.text('App 圖示'), 200, scrollable: find.byType(Scrollable).last);
  await showMiddle(tester, find.text('App 圖示'));
  await tester.tap(find.text('App 圖示'));
  await settle(tester);
  await tester.tap(find.text(name));
  await settle(tester);
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
  bool storePagesPublic = true,
  Map<String, Object> savedPrefs = const {},
  List<Locale> deviceLocales = const [Locale('zh', 'TW')],
}) async {
  tester.view.physicalSize = const Size(393 * 3, 852 * 3);
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.localesTestValue = deviceLocales;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...await testOverrides(backend ?? seededChurch(as: staffMei), savedPrefs: savedPrefs),
        supportStoreProvider.overrideWithValue(store),
        appIconSwitcherProvider.overrideWithValue(icons),
        storePagesPublicProvider.overrideWithValue(storePagesPublic),
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
      GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me/about');
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
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me/about');
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

  testWidgets("支持 sits with the rest of 馬大別忙's own, last, with 關於 at the very bottom", (tester) async {
    await pumpWithStore(tester, FakeStore(), FakeIcons());
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me');
    await settle(tester);

    Widget section(String row) => tester.widget(find.ancestor(of: find.text(row), matching: find.byType(ListSection)));
    double top(String row) => tester.getTopLeft(find.text(row)).dy;
    expect(section('LINE 社群'), same(section('支持馬大別忙')));
    expect(section('關於馬大別忙'), same(section('支持馬大別忙')));
    expect(section('語言'), isNot(same(section('支持馬大別忙'))), reason: 'a setting of mine, not the app');
    expect(top('支持馬大別忙'), lessThan(top('LINE 社群')));
    expect(top('LINE 社群'), lessThan(top('關於馬大別忙')));
    expect(top('語言'), lessThan(top('支持馬大別忙')));
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

    expect(find.text('App 圖示'), findsNothing, reason: 'icons are for subscribers');
    expect(findShownContaining('每月支持者可以換 App 圖示'), findsOneWidget);

    await showMiddle(tester, find.text('NT\$90'));
    await tester.tap(find.text('NT\$90'));
    await settle(tester);
    expect(find.text('謝謝你的支持'), findsOneWidget);

    await tester.tap(find.text(plan60));
    await settle(tester);
    expect(findShownContaining('每月支持者可以換 App 圖示'), findsNothing);
    await tester.scrollUntilVisible(find.text('App 圖示'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('預設'), findsOneWidget, reason: 'the icon in use');
    await pickIcon(tester, '紫');
    expect(icons.icon, 'Purple');
    expect(store.bought, ['tip_small', 'supporter_monthly']);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me/support');
    await settle(tester);
    await tester.scrollUntilVisible(find.text('App 圖示'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('紫'), findsOneWidget, reason: 'the icon in use');
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me');
    await settle(tester);
    expect(find.text('支持者'), findsOneWidget);
  });

  testWidgets('the subscription says it renews and where to cancel, beside the terms and privacy policy', (
    tester,
  ) async {
    final launcher = captureLaunches();
    await pumpWithStore(tester, FakeStore(), FakeIcons());
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me/support');
    await settle(tester);
    expect(findShownContaining('每月自動續訂，可以隨時到 Google Play 的訂閱設定取消'), findsOneWidget);
    expect(findShown('管理訂閱'), findsNothing, reason: 'nothing to manage before subscribing');
    await tester.tap(findShown('服務條款'));
    await tester.tap(findShown('隱私權政策'));
    await settle(tester);
    expect(launcher.opened, [endsWith('/terms?lang=zh-Hant&from=app'), endsWith('/privacy?lang=zh-Hant&from=app')]);

    await tester.tap(find.text(plan60));
    await settle(tester);
    await tester.tap(find.text('管理訂閱'));
    await settle(tester);
    expect(launcher.opened.last, 'https://play.google.com/store/account/subscriptions?sku=supporter_monthly');
  });

  testWidgets('two monthly plans; the one I pay for is marked, and the other switches to it', (tester) async {
    final launches = captureLaunches();
    final store = FakeStore();
    await pumpWithStore(tester, store, FakeIcons());
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me/support');
    await settle(tester);
    expect(find.text('每月支持'), findsOneWidget, reason: 'one name, two amounts: only the amounts show');

    await tester.tap(find.text(plan60));
    await settle(tester);
    expect(paidMark(plan60), findsOneWidget);
    expect(paidMark(plan150), findsNothing);
    await tester.tap(find.text(plan60));
    await settle(tester);
    expect(store.bought, ['supporter_monthly'], reason: 'the plan already paid for is not bought again');

    await tester.tap(find.text(plan150));
    await settle(tester);
    expect(store.bought, ['supporter_monthly', 'supporter_monthly_plus']);
    expect(paidMark(plan150), findsOneWidget);
    expect(paidMark(plan60), findsNothing);
    await tester.tap(find.text('管理訂閱'));
    await settle(tester);
    expect(launches.opened.last, endsWith('sku=supporter_monthly_plus'));
  });

  for (final (scale, sideBySide) in [(1.0, true), (2.0, false)]) {
    testWidgets('the amounts side by side, stacked when text at $scale× leaves no room', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      await pumpWithStore(tester, FakeStore(), FakeIcons());
      GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me/support');
      await settle(tester);
      final a = tester.getRect(find.widgetWithText(FilledButton, plan60));
      final b = tester.getRect(find.widgetWithText(FilledButton, plan150));
      expect(a.top == b.top, sideBySide);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('rating the app in its store is a way to support too', (tester) async {
    final launcher = captureLaunches();
    await pumpWithStore(tester, FakeStore(), FakeIcons());
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me/support');
    await settle(tester);
    await tester.scrollUntilVisible(find.text('評分支持我們'), 200);
    await tester.tap(find.text('評分支持我們'));
    await settle(tester);
    expect(launcher.opened, ['https://play.google.com/store/apps/details?id=app.marthasit']);
    expect(AppStore.appStore.review.toString(), 'https://apps.apple.com/app/id6823826952?action=write-review');
  });

  testWidgets('no rating row while the store pages are not public yet', (tester) async {
    await pumpWithStore(tester, FakeStore(), FakeIcons(), storePagesPublic: false);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me/support');
    await settle(tester);
    await tester.scrollUntilVisible(find.text('恢復購買'), 200);
    expect(find.text('評分支持我們'), findsNothing);
  });

  testWidgets('without a plan, the icon page is not there to see: back on 支持', (tester) async {
    await pumpWithStore(tester, FakeStore(), FakeIcons());
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me/support/icon');
    await settle(tester);
    expect(find.text('紫'), findsNothing);
    expect(find.text('一次性支持'), findsOneWidget);
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
      await tester.tap(find.text(plan60));
      await settle(tester);
      await pickIcon(tester, '紫');
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
      expect(paidMark(plan150), findsOneWidget);
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

  group("a church's own icon", () {
    final zhuwei = churchIcons.keys.single;
    const changed = '主畫面的圖示換成〈竹圍靈糧福音中心〉了';

    /// The app closed and opened again on this phone, a member of 竹圍.
    Future<void> reopen(WidgetTester tester, FakeIcons icons) async {
      final saved = await phonePrefs();
      await tester.pumpWidget(const SizedBox());
      await pumpWithStore(
        tester,
        FakeStore(),
        icons,
        backend: seededChurch(as: staffMei, id: zhuwei),
        savedPrefs: saved,
      );
    }

    testWidgets('its members get it on the home screen once, told so, with a way back', (tester) async {
      final icons = FakeIcons();
      await pumpWithStore(
        tester,
        FakeStore(),
        icons,
        backend: seededChurch(as: staffMei, id: zhuwei),
      );
      expect(icons.icon, 'Zhuwei');
      expect(findShownContaining(changed), findsOneWidget);

      await tester.tap(find.text('復原'));
      await settle(tester);
      expect(icons.icon, isNull);

      await reopen(tester, icons);
      expect(icons.icon, isNull, reason: 'once: put back, it stays back');
      expect(findShownContaining(changed), findsNothing);
    });

    testWidgets("on iOS the note waits for the system's own to be closed, not to fade under it", (tester) async {
      final icons = FakeIcons()..notes = true;
      await pumpWithStore(
        tester,
        FakeStore(),
        icons,
        backend: seededChurch(as: staffMei, id: zhuwei),
      );
      await tester.pump(const Duration(seconds: 10));
      expect(icons.icon, 'Zhuwei');
      expect(findShownContaining(changed), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(findShownContaining(changed), findsOneWidget);
      await settle(tester);
    });

    testWidgets('教會資訊 › App 圖示 puts it back or away, no subscription needed', (tester) async {
      final icons = FakeIcons();
      await pumpWithStore(
        tester,
        FakeStore(),
        icons,
        backend: seededChurch(as: staffMei, id: zhuwei),
      );
      GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me/church');
      await settle(tester);
      await tester.tap(find.text('App 圖示'));
      await settle(tester);
      expect(find.text('紫'), findsNothing, reason: "a supporter's");
      Finder checked(String name) => find.descendant(
        of: find.ancestor(of: findShown(name), matching: find.byType(InkWell)),
        matching: find.byIcon(Symbols.check_rounded),
      );
      await tester.tap(find.text('預設'));
      await settle(tester);
      expect(icons.icon, isNull);
      expect(checked('預設'), findsOneWidget, reason: 'a check, which a border on a blue icon is not');
      expect(checked('竹圍靈糧福音中心'), findsNothing);
      await tester.tap(findShown('竹圍靈糧福音中心'));
      await settle(tester);
      expect(icons.icon, 'Zhuwei');
      expect(checked('竹圍靈糧福音中心'), findsOneWidget);
      expect(checked('預設'), findsNothing);
    });

    testWidgets("kept, it stays: only a lapsed subscription's icon goes back", (tester) async {
      final icons = FakeIcons();
      await pumpWithStore(
        tester,
        FakeStore(),
        icons,
        backend: seededChurch(as: staffMei, id: zhuwei),
      );
      await reopen(tester, icons);
      expect(icons.icon, 'Zhuwei');
    });

    testWidgets("a supporter's icon, once the subscription lapses, gives way to it", (tester) async {
      final icons = FakeIcons()..icon = 'Purple';
      await pumpWithStore(
        tester,
        FakeStore(),
        icons,
        backend: seededChurch(as: staffMei, id: zhuwei),
        savedPrefs: {
          'supporter_until': testNow.add(const Duration(days: 1)).toIso8601String(),
          'supporter_plan': 'supporter_monthly',
        },
      );
      expect(icons.icon, 'Purple');

      final saved = await phonePrefs();
      await tester.pumpWidget(const SizedBox());
      await pumpWithStore(
        tester,
        FakeStore(),
        icons,
        backend: seededChurch(as: staffMei, id: zhuwei),
        savedPrefs: {...saved, 'supporter_until': testNow.subtract(const Duration(days: 1)).toIso8601String()},
      );
      expect(icons.icon, 'Zhuwei');
      expect(findShownContaining(changed), findsOneWidget);
    });

    testWidgets('refused by the phone, it is tried again next time', (tester) async {
      final icons = FakeIcons()..failures = 1;
      await pumpWithStore(
        tester,
        FakeStore(),
        icons,
        backend: seededChurch(as: staffMei, id: zhuwei),
      );
      expect(icons.icon, isNull);
      expect(findShownContaining(changed), findsNothing);
      await reopen(tester, icons);
      expect(icons.icon, 'Zhuwei');
    });

    testWidgets('joining the church with the app open puts it there', (tester) async {
      final icons = FakeIcons();
      final b = seededChurch(as: staffMei);
      await pumpWithStore(tester, FakeStore(), icons, backend: b);
      b
        ..addChurch('竹圍靈糧福音中心', id: zhuwei)
        ..addMember(zhuwei, staffMei);
      await settle(tester);
      expect(icons.icon, 'Zhuwei');
    });

    testWidgets('leaving the church takes it back', (tester) async {
      final icons = FakeIcons();
      final b = seededChurch(as: staffMei, id: zhuwei);
      await pumpWithStore(tester, FakeStore(), icons, backend: b);
      expect(icons.icon, 'Zhuwei');
      b.members[zhuwei]!.remove(staffMei.uid);
      b.notify();
      await settle(tester);
      expect(icons.icon, isNull);
    });

    testWidgets("a supporter's picked icon is not replaced", (tester) async {
      final icons = FakeIcons()..icon = 'Purple';
      await pumpWithStore(
        tester,
        FakeStore(),
        icons,
        backend: seededChurch(as: staffMei, id: zhuwei),
        savedPrefs: {
          'supporter_until': testNow.add(const Duration(days: 20)).toIso8601String(),
          'supporter_plan': 'supporter_monthly',
        },
      );
      expect(icons.icon, 'Purple');
      expect(findShownContaining(changed), findsNothing);
    });

    testWidgets("another church's members never get it, nor does the web app", (tester) async {
      final icons = FakeIcons();
      await pumpWithStore(tester, FakeStore(), icons);
      expect(icons.icon, isNull);
      expect(findShownContaining(changed), findsNothing);
      GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me/church');
      await settle(tester);
      expect(find.text('App 圖示'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await pumpApp(
        tester,
        seededChurch(as: staffMei, id: zhuwei),
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      expect(findShownContaining(changed), findsNothing);
    });
  });

  group('this month\'s support', () {
    Future<MemoryBackend> open(
      WidgetTester tester,
      Funding? funding, {
      List<Locale> deviceLocales = const [Locale('zh', 'TW')],
    }) async {
      final b = seededChurch(as: staffMei)..funding = funding;
      await pumpWithStore(tester, FakeStore(), FakeIcons(), backend: b, deviceLocales: deviceLocales);
      GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me/support');
      await settle(tester);
      return b;
    }

    testWidgets('what has come in against the target; a shortfall is not spelled out', (tester) async {
      await open(tester, const Funding(month: '2026-10', target: 500, received: 220, carried: 80, monthsLeft: 0));
      expect(find.text('這個月的支持'), findsOneWidget);
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

    testWidgets('each cost in the app\'s language: English when it has none, Chinese for Simplified', (tester) async {
      const funding = Funding(
        month: '2026-10',
        target: 350,
        received: 0,
        carried: 0,
        monthsLeft: 0,
        costs: [
          FundingCost(name: '雲端', names: {AppLanguage.en: 'Cloud hosting', AppLanguage.ja: 'クラウド'}, perMonth: 300),
          FundingCost(name: '網域', perMonth: 50),
        ],
      );
      for (final (locale, shown) in [
        (const Locale('en'), ['Cloud hosting', '網域']),
        (const Locale('ja'), ['クラウド', '網域']),
        (const Locale('ko'), ['Cloud hosting', '網域']),
        (const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'), ['雲端', '網域']),
      ]) {
        await open(tester, funding, deviceLocales: [locale]);
        await tester.scrollUntilVisible(find.text(shown.last), 200, scrollable: find.byType(Scrollable).first);
        for (final name in shown) {
          expect(find.text(name), findsOneWidget, reason: '$locale');
        }
      }
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
      expect(find.text('這個月的支持'), findsNothing);
      await open(tester, const Funding(month: '2026-10', target: 0, received: 50, carried: 0, monthsLeft: 0));
      expect(find.text('這個月的支持'), findsNothing);
    });
  });
}
