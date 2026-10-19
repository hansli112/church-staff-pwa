import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/data/backend.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/state/app_build.dart';

import '../support/harness.dart';
import '../support/seed.dart';

const _play12 = AppBuild(store: AppStore.googlePlay, version: '1.0.0', number: 12);
const _apple12 = AppBuild(store: AppStore.appStore, version: '1.0.0', number: 12);

Future<void> go(WidgetTester tester, String location) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
  await settle(tester);
}

void main() {
  testWidgets('關於 shows the version the phone is running', (tester) async {
    await pumpApp(tester, seededChurch(as: staffMei), overrides: [appBuildProvider.overrideWithValue(_play12)]);
    await go(tester, '/me/about');
    expect(find.text('1.0.0 (12)'), findsOneWidget);
  });

  testWidgets(
    '關於 has no row for updates: the store updates the app itself',
    (tester) async {
      await pumpApp(tester, seededChurch(as: staffMei), overrides: [appBuildProvider.overrideWithValue(_play12)]);
      await go(tester, '/me/about');
      expect(find.text('App 更新'), findsNothing);
      expect(find.textContaining('檢查更新'), findsNothing);
    },
    variant: const TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS}),
  );

  testWidgets('with a hot fix applied, 關於 says which, so a report tells which code was running', (tester) async {
    const patched = AppBuild(store: AppStore.googlePlay, version: '1.0.0', number: 12, patch: 2);
    await pumpApp(tester, seededChurch(as: staffMei), overrides: [appBuildProvider.overrideWithValue(patched)]);
    await go(tester, '/me/about');
    expect(find.text('1.0.0 (12) · 修正 2'), findsOneWidget);
  });

  testWidgets(
    'older than the lowest build the backend allows: the app asks for the update, and the button opens the store',
    (
      tester,
    ) async {
      final launches = captureLaunches();
      final b = seededChurch(as: staffMei)..minimumBuilds = const MinimumBuilds(android: 13);
      await pumpApp(tester, b, overrides: [appBuildProvider.overrideWithValue(_play12)]);
      expect(find.text('請更新馬大別忙'), findsOneWidget);
      expect(find.text('首頁'), findsNothing);
      await tester.tap(find.text('到 Google Play 更新'));
      await settle(tester);
      expect(launches.opened, ['https://play.google.com/store/apps/details?id=app.marthasit']);
    },
  );

  testWidgets('new enough, or nothing set: the app is as always', (tester) async {
    final b = seededChurch(as: staffMei)..minimumBuilds = const MinimumBuilds(android: 12, ios: 99);
    await pumpApp(tester, b, overrides: [appBuildProvider.overrideWithValue(_play12)]);
    expect(find.text('請更新馬大別忙'), findsNothing);
    expect(find.text('首頁'), findsWidgets);
  });

  testWidgets('each store has its own lowest build', (tester) async {
    final b = seededChurch(as: staffMei)..minimumBuilds = const MinimumBuilds(android: 99, ios: 13);
    await pumpApp(tester, b, overrides: [appBuildProvider.overrideWithValue(_apple12)]);
    expect(find.text('請更新馬大別忙'), findsOneWidget);
    expect(find.text('到 App Store 更新'), findsOneWidget);
  });

  testWidgets('the App Store button opens the app\'s page there', (tester) async {
    final launches = captureLaunches();
    final b = seededChurch(as: staffMei)..minimumBuilds = const MinimumBuilds(ios: 13);
    await pumpApp(tester, b, overrides: [appBuildProvider.overrideWithValue(_apple12)]);
    await tester.tap(find.text('到 App Store 更新'));
    await settle(tester);
    expect(launches.opened, ['https://apps.apple.com/app/id6823826952']);
  });

  testWidgets('raised while the app is open: it asks then, and whatever was typed is still there after', (
    tester,
  ) async {
    final b = seededChurch(as: staffMei);
    await pumpApp(tester, b, overrides: [appBuildProvider.overrideWithValue(_play12)]);
    await tester.tap(find.text('設定').last);
    await settle(tester);
    await tester.tap(find.text(staffMei.name).first);
    await settle(tester);
    await tester.tap(find.text('名字'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, '美美');
    b
      ..minimumBuilds = const MinimumBuilds(android: 13)
      ..notify();
    await settle(tester);
    expect(find.text('請更新馬大別忙'), findsOneWidget);
    b
      ..minimumBuilds = const MinimumBuilds()
      ..notify();
    await settle(tester);
    expect(find.text('請更新馬大別忙'), findsNothing);
    expect(find.text('美美'), findsOneWidget);
  });

  testWidgets('while it asks, nothing reaches the app underneath: not the keyboard, back, or a toast', (tester) async {
    final b = seededChurch(as: staffMei);
    await pumpApp(tester, b, overrides: [appBuildProvider.overrideWithValue(_play12)]);
    await tester.tap(find.text('設定').last);
    await settle(tester);
    await tester.tap(find.text(staffMei.name).first);
    await settle(tester);
    await tester.tap(find.text('名字'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, '美美');
    expect(tester.testTextInput.isVisible, isTrue);
    b
      ..minimumBuilds = const MinimumBuilds(android: 13)
      ..notify();
    await settle(tester);
    expect(tester.testTextInput.isVisible, isFalse, reason: 'the keyboard closes');
    expect(await tester.binding.handlePopRoute(), isTrue);
    await settle(tester);
    final messenger = tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first);
    messenger.showSnackBar(const SnackBar(content: Text('有人排了你')));
    await settle(tester);
    expect(find.text('有人排了你'), findsNothing);
    b
      ..minimumBuilds = const MinimumBuilds()
      ..notify();
    await settle(tester);
    expect(find.text('美美'), findsOneWidget, reason: 'back did not leave the page being edited');
  });

  testWidgets('without a store build (the web, the demo) it never asks', (tester) async {
    final b = seededChurch(as: staffMei)..minimumBuilds = const MinimumBuilds(android: 99, ios: 99);
    await pumpApp(tester, b, overrides: [appBuildProvider.overrideWithValue(null)]);
    expect(find.text('請更新馬大別忙'), findsNothing);
  });

  testWidgets('signed out, an old app asks too', (tester) async {
    final b = MemoryBackend(clock: testClock)..minimumBuilds = const MinimumBuilds(android: 13);
    await pumpApp(tester, b, overrides: [appBuildProvider.overrideWithValue(_play12)]);
    expect(find.text('請更新馬大別忙'), findsOneWidget);
  });
}
