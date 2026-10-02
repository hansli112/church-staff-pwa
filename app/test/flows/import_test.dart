import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/harness.dart';
import '../support/seed.dart';

Future<void> go(WidgetTester tester, String location) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
  await settle(tester);
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await settle(tester);
}

void main() {
  testWidgets('pasted JSON previews with a report, then applies', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/rosters');
    await tester.tap(find.byTooltip('照片匯入'));
    await settle(tester);
    expect(find.text('這個月還可以辨識 30 張'), findsOneWidget);

    await tapText(tester, '貼上 JSON');
    await tester.enterText(
      find.byType(TextField),
      jsonEncode([
        {
          'date': '2026-10-18',
          'duties': [
            {
              'role': '司琴',
              'people': ['美玉'],
            },
            {
              'role': '招待',
              'people': ['陳志明'],
            },
          ],
        },
      ]),
    );
    await tapText(tester, '預覽');
    expect(find.text('名單裡沒有這些人（照原文寫入，沒有連到帳號）'), findsOneWidget);
    expect(find.text('名單裡有很像的：陳志豪'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('套用到服事表'), 300);
    await tapText(tester, '套用到服事表');
    expect(peopleOn(b, 18, '司琴'), ['李美玉']);
    expect(peopleOn(b, 18, '招待'), ['陳志明']);
    expect(savedDay(b, 18).duties[1].uids, {'李美玉': 'mei'});
  });

  testWidgets('used-up photos say when they come back', (tester) async {
    final b = seededChurch();
    b.cloud.photosUsed['grace'] = 30;
    await pumpApp(tester, b);
    await go(tester, '/rosters/import/sunday');
    expect(find.textContaining('這個月的 30 張用完了'), findsOneWidget);
    final take = tester.widget<FilledButton>(find.byType(FilledButton).first);
    expect(take.onPressed, isNull);
  });

  testWidgets('staff do not see photo import', (tester) async {
    await pumpApp(tester, seededChurch(as: staffMei));
    await go(tester, '/rosters');
    expect(find.byTooltip('照片匯入'), findsNothing);
  });
}
