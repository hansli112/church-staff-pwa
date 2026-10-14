import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/backend.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/state/app_build.dart';

import '../support/harness.dart';
import '../support/seed.dart';

const _play12 = AppBuild(store: AppStore.googlePlay, version: '1.0.0', number: 12);
const _apple12 = AppBuild(store: AppStore.appStore, version: '1.0.0', number: 12);

void main() {
  testWidgets('我的 shows the version the phone is running', (tester) async {
    await pumpApp(tester, seededChurch(as: staffMei), overrides: [appBuildProvider.overrideWithValue(_play12)]);
    await tester.tap(find.text('我的').last);
    await settle(tester);
    await tester.scrollUntilVisible(find.text('目前版本'), 180, scrollable: find.byType(Scrollable).last);
    expect(find.text('1.0.0 (12)'), findsOneWidget);
  });

  testWidgets('older than the lowest build the backend allows: the app asks for the update, and the button opens the store', (
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
  });

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

  testWidgets('raised while the app is open: it asks then, and whatever was typed is still there after', (tester) async {
    final b = seededChurch(as: staffMei);
    await pumpApp(tester, b, overrides: [appBuildProvider.overrideWithValue(_play12)]);
    await tester.tap(find.text('我的').last);
    await settle(tester);
    await tester.tap(find.text(staffMei.name).first);
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

  testWidgets('the web app never asks: it updates itself', (tester) async {
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
