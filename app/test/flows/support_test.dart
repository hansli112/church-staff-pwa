import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/app.dart';
import 'package:martha/data/backend.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/state/support.dart';

import '../support/harness.dart';
import '../support/seed.dart';

class FakeStore implements SupportStore {
  final _results = StreamController<({String productId, PurchaseOutcome outcome})>.broadcast(sync: true);
  final bought = <String>[];

  @override
  bool get available => true;

  @override
  Future<List<SupportItem>> products() async => const [
    SupportItem(id: 'tip_small', title: '請喝咖啡', price: 'NT\$90', subscription: false),
    SupportItem(id: 'supporter_monthly', title: '每月支持', price: 'NT\$60', subscription: true),
  ];

  @override
  Future<void> buy(SupportItem item) async {
    bought.add(item.id);
    _results.add((productId: item.id, outcome: PurchaseOutcome.thanks));
  }

  @override
  Future<void> restore() async {}

  @override
  Stream<({String productId, PurchaseOutcome outcome})> get results => _results.stream;
}

class FakeIcons implements AppIconSwitcher {
  String? icon;

  @override
  Future<String?> current() async => icon;

  @override
  Future<void> set(String? name) async => icon = name;
}

Future<void> pumpWithStore(
  WidgetTester tester,
  SupportStore store,
  AppIconSwitcher icons, {
  MemoryBackend? backend,
}) async {
  tester.view.physicalSize = const Size(393 * 3, 852 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
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
  testWidgets('without a store (the web) there is no support entry', (tester) async {
    await pumpApp(tester, seededChurch(as: staffMei));
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

    await tester.tap(find.text('紫'));
    await settle(tester);
    expect(icons.icon, isNull, reason: 'icons are for subscribers');

    await tester.tap(find.text('請喝咖啡'));
    await settle(tester);
    expect(find.text('謝謝你的支持'), findsOneWidget);

    await tester.tap(find.text('每月支持').last);
    await settle(tester);
    await tester.tap(find.text('紫'));
    await settle(tester);
    expect(icons.icon, 'Purple');
    expect(store.bought, ['tip_small', 'supporter_monthly']);
    expect(find.text('支持者'), findsOneWidget);
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

    testWidgets('no costs set yet: nothing to show', (tester) async {
      await open(tester, null);
      expect(find.text('這個月的雲端費用'), findsNothing);
      await open(tester, const Funding(month: '2026-10', target: 0, received: 50, carried: 0, monthsLeft: 0));
      expect(find.text('這個月的雲端費用'), findsNothing);
    });
  });
}
