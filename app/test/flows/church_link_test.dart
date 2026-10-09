import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/domain/models.dart';

import '../support/harness.dart';
import '../support/seed.dart';

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await settle(tester);
}

Future<void> go(WidgetTester tester, String location) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
  await settle(tester);
}

Finder field(String label) => find.widgetWithText(TextField, label);

void main() {
  const link = ChurchLink(title: '主日奉獻', body: '線上奉獻與收據', url: 'https://grace.example/give');

  testWidgets('the church link sits above my services and opens in the browser', (tester) async {
    final b = seededChurch(as: staffMei)..churchLinks['grace'] = link;
    await pumpApp(tester, b);
    expect(find.text('主日奉獻'), findsOneWidget);
    expect(find.text('線上奉獻與收據'), findsOneWidget);
    final linkTop = tester.getTopLeft(find.text('主日奉獻')).dy;
    final servicesTop = tester.getTopLeft(find.text('我接下來的服事')).dy;
    expect(linkTop, lessThan(servicesTop));

    final launcher = captureLaunches();
    await tapText(tester, '主日奉獻');
    expect(launcher.opened, ['https://grace.example/give']);
  });

  testWidgets('without a church link the home page has no extra space', (tester) async {
    await pumpApp(tester, seededChurch(as: staffMei));
    expect(find.byIcon(Icons.open_in_new), findsNothing);
    final firstSection = tester.getTopLeft(find.text('我接下來的服事')).dy;
    await pumpApp(tester, seededChurch(as: staffMei)..churchLinks['grace'] = link);
    expect(tester.getTopLeft(find.text('我接下來的服事')).dy, greaterThan(firstSection));
  });

  testWidgets('a church link shows even with no upcoming services', (tester) async {
    await pumpApp(tester, seededChurch(as: john)..churchLinks['grace'] = link);
    expect(find.text('主日奉獻'), findsOneWidget);
    expect(find.text('看服事表'), findsOneWidget);
  });

  testWidgets('an admin sets, edits and removes the church link', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/me/church');
    expect(find.text('未設定'), findsOneWidget);
    await tapText(tester, '教會連結');

    await tester.enterText(field('連結'), 'http://grace.example');
    await tapText(tester, '儲存');
    expect(find.text('請輸入標題'), findsOneWidget);
    expect(find.text('請輸入 https:// 開頭的連結'), findsOneWidget);
    expect(b.churchLinks['grace'], isNull);

    await tester.enterText(field('標題'), '主日奉獻');
    await tester.enterText(field('敘述（選填）'), '線上奉獻與收據');
    await tester.enterText(field('連結'), 'https://grace.example/give');
    await tapText(tester, '儲存');
    expect(b.churchLinks['grace'], link);

    await tapText(tester, '教會連結');
    expect(tester.widget<TextField>(field('標題')).controller!.text, '主日奉獻', reason: 'filled from the saved link');
    await tester.enterText(field('標題'), '奉獻');
    await tapText(tester, '儲存');
    expect(b.churchLinks['grace']!.title, '奉獻');

    await tapText(tester, '教會連結');
    await tapText(tester, '移除教會連結');
    expect(b.churchLinks['grace'], isNull);
    expect(find.text('已移除教會連結'), findsOneWidget);
    await tapText(tester, '復原');
    expect(b.churchLinks['grace']!.title, '奉獻');
  });

  testWidgets('only admins can change the church link', (tester) async {
    final b = seededChurch(as: editor);
    await pumpApp(tester, b);
    await go(tester, '/me/church');
    expect(find.text('教會連結'), findsNothing);
    await expectLater(b.church('grace').setChurchLink(link), throwsA(anything));
  });

  group('daily content source', () {
    const src = 'https://feed.example/today.json';
    const sourced = ChurchLink(title: '教會官網', url: 'https://grace.example', source: src);

    testWidgets('the home page shows fresh fetched content, else the fixed link', (tester) async {
      final b = seededChurch(as: staffMei)
        ..churchLinks['grace'] = sourced
        ..linkContents['grace'] = LinkContent(
          source: src,
          title: '今日經文',
          body: '耶和華是我的牧者',
          fetchedAt: testNow.subtract(const Duration(hours: 3)),
        );
      await pumpApp(tester, b);
      expect(find.text('今日經文'), findsOneWidget);
      expect(find.text('教會官網'), findsNothing);

      b.linkContents['grace'] = LinkContent(
        source: src,
        title: '今日經文',
        fetchedAt: testNow.subtract(const Duration(hours: 49)),
      );
      b.notify();
      await settle(tester);
      expect(find.text('教會官網'), findsOneWidget, reason: 'over 48 hours old');
    });

    testWidgets('until the content comes, neither it nor the fixed link shows', (tester) async {
      final held = Completer<void>();
      final b = seededChurch(as: staffMei)
        ..churchLinks['grace'] = sourced
        ..linkContents['grace'] = LinkContent(
          source: src,
          title: '今日經文',
          fetchedAt: testNow.subtract(const Duration(hours: 3)),
        )
        ..linkContentHeld = held;
      await pumpApp(tester, b);
      expect(find.text('我接下來的服事'), findsOneWidget, reason: 'the rest of the page is up');
      expect(find.text('教會官網'), findsNothing, reason: 'not the fixed link it is about to replace');
      expect(find.text('今日經文'), findsNothing);

      held.complete();
      await settle(tester);
      expect(find.text('今日經文'), findsOneWidget);
      expect(find.text('教會官網'), findsNothing);
    });

    testWidgets('if the content cannot be read, the fixed link shows', (tester) async {
      final held = Completer<void>();
      final b = seededChurch(as: staffMei)
        ..churchLinks['grace'] = sourced
        ..linkContentHeld = held;
      await pumpApp(tester, b);
      held.completeError(StateError('offline'));
      await settle(tester);
      expect(find.text('教會官網'), findsOneWidget);
    });

    testWidgets('fetched content gives way to the fixed link once 48 hours pass', (tester) async {
      var now = testNow;
      final b = seededChurch(as: staffMei, clock: () => now)
        ..churchLinks['grace'] = sourced
        ..linkContents['grace'] = LinkContent(
          source: src,
          title: '今日經文',
          fetchedAt: testNow.subtract(const Duration(hours: 47)),
        );
      await pumpApp(tester, b);
      expect(find.text('今日經文'), findsOneWidget);

      // No new content arrives; only time passes.
      now = testNow.add(const Duration(hours: 1));
      await tester.pump(const Duration(hours: 1));
      await settle(tester);
      expect(find.text('今日經文'), findsNothing);
      expect(find.text('教會官網'), findsOneWidget);
    });

    testWidgets('an admin adds a source and a time; it is fetched at once', (tester) async {
      final b = seededChurch()
        ..churchLinks['grace'] = const ChurchLink(title: '教會官網', url: 'https://grace.example')
        ..linkSourceAnswers[src] = const LinkContent(source: src, title: '今日經文', body: '詩篇 23');
      await pumpApp(tester, b);
      await go(tester, '/me/link');
      expect(find.text('每天更新時間'), findsNothing, reason: 'only with a source');
      await tester.enterText(field('JSON 網址'), src);
      await tester.pump();
      expect(find.text('04:30'), findsOneWidget, reason: 'the default');
      await tapText(tester, '每天更新時間');
      await tapText(tester, '05:00');
      expect(find.text('05:00'), findsOneWidget);
      await tester.ensureVisible(find.text('儲存').last);
      await tapText(tester, '儲存');
      expect(find.text('已儲存，抓到「今日經文」'), findsOneWidget);
      expect(b.churchLinks['grace']!.source, src);
      expect(b.churchLinks['grace']!.fetchMinute, 300);
      expect(b.linkSourceFetches, [src]);
      expect(find.text('JSON 網址'), findsNothing, reason: 'the page closed');

      await go(tester, '/me/link');
      expect(find.textContaining('上次更新：'), findsOneWidget);
      expect(find.textContaining('10/1 09:00'), findsOneWidget);
    });

    testWidgets('undoing a removal brings the source back with the link', (tester) async {
      final b = seededChurch()
        ..churchLinks['grace'] = const ChurchLink(
          title: '教會官網',
          url: 'https://grace.example',
          source: src,
          fetchMinute: 300,
        )
        ..linkSourceAnswers[src] = const LinkContent(source: src, title: '今日經文');
      await pumpApp(tester, b);
      await go(tester, '/me/link');
      await tapText(tester, '移除教會連結');
      expect(b.churchLinks['grace'], isNull);
      await tapText(tester, '復原');
      final back = b.churchLinks['grace']!;
      expect((back.title, back.source, back.fetchMinute), ('教會官網', src, 300));
    });

    testWidgets('a source that fails says why and stays on the page', (tester) async {
      final b = seededChurch()
        ..churchLinks['grace'] = const ChurchLink(title: '教會官網', url: 'https://grace.example')
        ..linkSourceAnswers[src] = LinkFetchError.timeout;
      await pumpApp(tester, b);
      await go(tester, '/me/link');
      await tester.enterText(field('JSON 網址'), src);
      await tapText(tester, '儲存');
      expect(find.text('上次沒有抓到：對方網站 5 秒內沒有回應'), findsOneWidget);
      expect(find.text('JSON 網址'), findsOneWidget);
      expect(b.churchLinks['grace']!.source, src, reason: 'saved anyway; it runs again tomorrow');
    });

    testWidgets('a source must be https', (tester) async {
      final b = seededChurch()..churchLinks['grace'] = const ChurchLink(title: '教會官網', url: 'https://grace.example');
      await pumpApp(tester, b);
      await go(tester, '/me/link');
      await tester.enterText(field('JSON 網址'), 'http://feed.example');
      await tapText(tester, '儲存');
      expect(find.text('請輸入 https:// 開頭的連結'), findsOneWidget);
      expect(b.linkSourceFetches, isEmpty);
    });
  });
}
