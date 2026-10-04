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
    await expectLater(b.church('grace').saveChurchLink(link), throwsA(anything));
  });
}
