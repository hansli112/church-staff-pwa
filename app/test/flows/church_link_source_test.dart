import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/domain/models.dart';

import '../support/harness.dart';
import '../support/seed.dart';

void main() {
  const source = 'https://feed.example/today.json';
  const link = ChurchLink(title: '固定標題', url: 'https://grace.example', source: source);
  const failed = LinkContent(source: source, error: LinkFetchError.notToday);

  testWidgets('來源沒有今天的內容時首頁說明原因，管理員重試後顯示新內容', (tester) async {
    final b = seededChurch()
      ..churchLinks['grace'] = link
      ..linkContents['grace'] = failed;
    await pumpApp(tester, b);
    expect(find.text('固定標題'), findsNothing, reason: 'the fixed link must not stand in for the source');
    expect(findShownContaining('來源還沒有今天的內容'), findsOneWidget);

    b.linkSourceAnswers[source] = const LinkContent(
      source: source,
      title: '今日經文',
      body: '詩篇 23',
      link: 'https://feed.example/1001',
    );
    await tester.tap(find.widgetWithText(TextButton, '重試'));
    await settle(tester);
    expect(find.text('今日經文'), findsOneWidget);
    expect(find.textContaining('來源還沒有今天的內容'), findsNothing);
  });

  testWidgets('管理員在設定頁重新抓取已儲存的來源，不覆寫尚未儲存的欄位', (tester) async {
    final b = seededChurch()
      ..churchLinks['grace'] = link
      ..linkContents['grace'] = failed;
    await pumpApp(tester, b);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me/link');
    await settle(tester);
    expect(find.textContaining('來源還沒有今天的內容'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '標題'), '還沒儲存的標題');
    b.linkSourceAnswers[source] = const LinkContent(
      source: source,
      title: '今日經文',
      body: '',
      link: 'https://feed.example/1001',
    );
    await tester.tap(find.text('重新抓取'));
    await settle(tester);
    expect(find.textContaining('上次更新'), findsOneWidget);
    expect(b.churchLinks['grace'], link, reason: 'retry fetches; it saves nothing typed here');
    expect(find.widgetWithText(TextField, '還沒儲存的標題'), findsOneWidget);
  });

  testWidgets('一般同工看到來源狀態但不能重抓來源', (tester) async {
    final b = seededChurch(as: staffMei)
      ..churchLinks['grace'] = link
      ..linkContents['grace'] = failed;
    await pumpApp(tester, b);
    expect(findShownContaining('來源還沒有今天的內容'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '重試'), findsNothing);
  });
}
