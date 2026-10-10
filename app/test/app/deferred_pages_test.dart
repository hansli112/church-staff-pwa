import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/deferred_pages.dart';
import 'package:martha/state/fonts.dart';
import 'package:martha/state/web_page.dart';

import '../support/harness.dart';
import '../support/seed.dart';

Future<void> go(WidgetTester tester, String location) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
  await settle(tester);
}

void main() {
  testWidgets('church info appears after its screen code arrives, without holding up home', (tester) async {
    final download = Completer<void>();
    addTearDown(() {
      if (!download.isCompleted) download.complete();
    });
    await pumpApp(
      tester,
      seededChurch(),
      overrides: [
        loadPageLibraryProvider.overrideWithValue((library) async {
          await download.future;
          await library.load();
        }),
      ],
    );
    expect(find.text('我接下來的服事'), findsOneWidget);

    await go(tester, '/me/church');
    expect(find.text('匯出資料'), findsNothing, reason: 'the page code is still downloading');

    download.complete();
    await settle(tester);
    expect(find.text('匯出資料'), findsOneWidget);
  });

  testWidgets('a cold church-info link keeps the splash until its destination is drawn', (tester) async {
    final download = Completer<void>();
    addTearDown(() {
      if (!download.isCompleted) download.complete();
    });
    var hidden = 0;
    tester.platformDispatcher.defaultRouteNameTestValue = '/me/church';
    await pumpApp(
      tester,
      seededChurch(),
      overrides: [
        hideSplashProvider.overrideWithValue(() => hidden++),
        loadPageLibraryProvider.overrideWithValue((library) async {
          await download.future;
          await library.load();
        }),
      ],
    );
    expect(hidden, 0, reason: 'the first destination is still downloading');

    download.complete();
    await settle(tester);
    expect(find.text('匯出資料'), findsOneWidget);
    expect(hidden, 1, reason: 'after its first usable frame, only once');
  });

  testWidgets('a stalled first code download exposes a recoverable error instead of an endless splash', (tester) async {
    final download = Completer<void>();
    addTearDown(() {
      if (!download.isCompleted) download.complete();
    });
    var hidden = 0;
    tester.platformDispatcher.defaultRouteNameTestValue = '/me/church';
    await pumpApp(
      tester,
      seededChurch(),
      overrides: [
        hideSplashProvider.overrideWithValue(() => hidden++),
        loadPageLibraryProvider.overrideWithValue((library) async {
          await download.future;
          await library.load();
        }),
      ],
    );
    await tester.pump(const Duration(seconds: 16));
    await settle(tester);
    expect(find.text('載入失敗，請檢查網路後再試一次'), findsOneWidget);
    expect(find.text('重試'), findsOneWidget);
    expect(hidden, 1, reason: 'the error is usable, not hidden underneath the splash');
  });

  testWidgets('a failed first download can be retried without reloading or dismissing the splash twice', (
    tester,
  ) async {
    final retryDownload = Completer<void>();
    addTearDown(() {
      if (!retryDownload.isCompleted) retryDownload.complete();
    });
    var first = true;
    var hidden = 0;
    tester.platformDispatcher.defaultRouteNameTestValue = '/me/church';
    await pumpApp(
      tester,
      seededChurch(),
      overrides: [
        hideSplashProvider.overrideWithValue(() => hidden++),
        loadPageLibraryProvider.overrideWithValue((library) async {
          if (first) {
            first = false;
            throw StateError('code download failed');
          }
          await retryDownload.future;
          await library.load();
        }),
      ],
    );
    expect(find.text('載入失敗，請檢查網路後再試一次'), findsOneWidget);
    expect(hidden, 1);

    await tester.tap(find.text('重試'));
    await settle(tester);
    expect(find.text('載入失敗，請檢查網路後再試一次'), findsNothing);
    expect(find.text('匯出資料'), findsNothing);
    retryDownload.complete();
    await settle(tester);
    expect(find.text('匯出資料'), findsOneWidget);
    expect(hidden, 1);
  });

  testWidgets('photo import downloads on opening, without changing its service route', (tester) async {
    final download = Completer<void>();
    addTearDown(() {
      if (!download.isCompleted) download.complete();
    });
    await pumpApp(
      tester,
      seededChurch(),
      overrides: [
        loadPageLibraryProvider.overrideWithValue((library) async {
          await download.future;
          await library.load();
        }),
      ],
    );
    await go(tester, '/rosters/import/sunday');
    expect(find.text('拍照'), findsNothing, reason: 'not built before the code is ready');
    download.complete();
    await settle(tester);
    expect(find.text('拍照'), findsOneWidget);
    expect(find.text('這個月還可以辨識 30 張'), findsOneWidget);
    expect(
      GoRouter.of(tester.element(find.byType(Scaffold).first)).routerDelegate.currentConfiguration.uri.path,
      '/rosters/import/sunday',
    );
  });

  testWidgets('a cold platform-console link loads only its code and keeps its destination', (tester) async {
    final download = Completer<void>();
    addTearDown(() {
      if (!download.isCompleted) download.complete();
    });
    final backend = seededChurch()..auth.operators.add('pastor');
    tester.platformDispatcher.defaultRouteNameTestValue = '/admin';
    await pumpApp(
      tester,
      backend,
      overrides: [
        loadPageLibraryProvider.overrideWithValue((library) async {
          await download.future;
          await library.load();
        }),
      ],
    );
    expect(find.text('恩典堂'), findsNothing, reason: 'the console body has not downloaded');
    download.complete();
    await settle(tester);
    expect(find.text('恩典堂'), findsOneWidget);
    expect(
      GoRouter.of(tester.element(find.byType(Scaffold).first)).routerDelegate.currentConfiguration.uri.path,
      '/admin',
    );
  });

  testWidgets('calendar connection keeps its OAuth result through the code download', (tester) async {
    final download = Completer<void>();
    addTearDown(() {
      if (!download.isCompleted) download.complete();
    });
    tester.platformDispatcher.defaultRouteNameTestValue = '/me/calendar?result=denied';
    await pumpApp(
      tester,
      seededChurch(),
      overrides: [
        loadPageLibraryProvider.overrideWithValue((library) async {
          await download.future;
          await library.load();
        }),
      ],
    );
    expect(find.text('沒有連接成功，請再試一次'), findsNothing, reason: 'the screen is still downloading');
    download.complete();
    await settle(tester);
    expect(find.text('沒有連接成功，請再試一次'), findsOneWidget);
    expect(
      GoRouter.of(
        tester.element(find.byType(Scaffold).first),
      ).routerDelegate.currentConfiguration.uri.queryParameters['result'],
      'denied',
    );
  });

  testWidgets('the old-version move screen loads only when opened and still returns normally', (tester) async {
    final download = Completer<void>();
    addTearDown(() {
      if (!download.isCompleted) download.complete();
    });
    await pumpApp(
      tester,
      seededChurch(),
      overrides: [
        loadPageLibraryProvider.overrideWithValue((library) async {
          await download.future;
          await library.load();
        }),
      ],
    );
    await go(tester, '/welcome/move');
    expect(find.text('選擇搬家檔'), findsNothing, reason: 'not downloaded yet');
    download.complete();
    await settle(tester);
    expect(find.text('選擇搬家檔'), findsOneWidget);
    await tester.tap(find.byType(BackButton).last);
    await settle(tester);
    // Welcome's existing back behavior sends church members to 我的.
    expect(
      GoRouter.of(tester.element(find.byType(Scaffold).first)).routerDelegate.currentConfiguration.uri.path,
      '/me',
    );
    expect(find.text('選擇搬家檔'), findsNothing);
  });

  testWidgets('a previous destination finishing cannot expose a still-downloading first page', (tester) async {
    final churchInfo = Completer<void>();
    final calendar = Completer<void>();
    addTearDown(() {
      if (!churchInfo.isCompleted) churchInfo.complete();
      if (!calendar.isCompleted) calendar.complete();
    });
    var hidden = 0;
    var drawn = 0;
    tester.platformDispatcher.defaultRouteNameTestValue = '/me/church';
    await pumpApp(
      tester,
      seededChurch(),
      overrides: [
        hideSplashProvider.overrideWithValue(() => hidden++),
        onFirstPageDrawnProvider.overrideWithValue(() => drawn++),
        loadPageLibraryProvider.overrideWithValue((library) async {
          if (library == PageLibrary.churchInfo) await churchInfo.future;
          if (library == PageLibrary.calendarSettings) await calendar.future;
          await library.load();
        }),
      ],
    );
    await go(tester, '/me/calendar?result=denied');
    churchInfo.complete();
    await settle(tester);
    expect(hidden, 0);
    expect(drawn, 0);
    expect(find.text('匯出資料'), findsNothing);

    calendar.complete();
    await settle(tester);
    expect(find.text('沒有連接成功，請再試一次'), findsOneWidget);
    expect(hidden, 1);
    expect(drawn, 1);
  });

  testWidgets('returning before a download finishes does not reopen that page', (tester) async {
    final download = Completer<void>();
    addTearDown(() {
      if (!download.isCompleted) download.complete();
    });
    await pumpApp(
      tester,
      seededChurch(),
      overrides: [
        loadPageLibraryProvider.overrideWithValue((library) async {
          await download.future;
          await library.load();
        }),
      ],
    );
    await tester.tap(find.text('我的'));
    await settle(tester);
    await tester.tap(find.text('教會資訊'));
    await settle(tester);
    await tester.tap(find.byType(BackButton).last);
    await settle(tester);
    download.complete();
    await settle(tester);
    expect(find.text('匯出資料'), findsNothing);
    expect(
      GoRouter.of(tester.element(find.byType(Scaffold).first)).routerDelegate.currentConfiguration.uri.path,
      '/me',
    );
    await tester.tap(find.text('教會資訊'));
    await settle(tester);
    expect(find.text('匯出資料'), findsOneWidget, reason: 'the successful download is reusable');
  });

  testWidgets('changing the first route does not restart the three-second font deadline', (tester) async {
    var hidden = 0;
    await pumpApp(
      tester,
      seededChurch(),
      overrides: [
        fontsReadyProvider.overrideWithValue(Completer<void>().future),
        hideSplashProvider.overrideWithValue(() => hidden++),
      ],
    );
    expect(hidden, 0);
    await go(tester, '/me/church');
    expect(hidden, 0);
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.text('匯出資料'), findsOneWidget);
    expect(hidden, 1, reason: 'the original deadline has elapsed, not three seconds from the new route');
  });

  testWidgets('a direct console download identifies its page and offers a way home on failure', (tester) async {
    final download = Completer<void>();
    addTearDown(() {
      if (!download.isCompleted) download.complete();
    });
    tester.platformDispatcher.defaultRouteNameTestValue = '/admin';
    await pumpApp(
      tester,
      seededChurch()..auth.operators.add('pastor'),
      overrides: [
        loadPageLibraryProvider.overrideWithValue((library) async {
          await download.future;
          await library.load();
        }),
      ],
    );
    expect(find.text('平台後台'), findsOneWidget, reason: 'wayfinding before the module arrives');
    download.completeError(StateError('download failed'));
    await settle(tester);
    expect(find.text('重試'), findsOneWidget);
    await tester.tap(find.byTooltip('回首頁'));
    await settle(tester);
    expect(find.text('我接下來的服事'), findsOneWidget);
  });
}
