import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/state/app_update.dart';

import '../state/app_update_test.dart' show Updates;
import '../support/harness.dart';
import '../support/seed.dart';

/// 設定, then 關於馬大別忙 near its foot.
Future<void> openAbout(WidgetTester tester) async {
  await tester.tap(find.text('設定').last);
  await settle(tester);
  await tester.scrollUntilVisible(find.text('關於馬大別忙'), 180, scrollable: find.byType(Scrollable).last);
  await tester.ensureVisible(find.text('關於馬大別忙'));
  await settle(tester);
  await tester.tap(find.text('關於馬大別忙'));
  await settle(tester);
}

void main() {
  testWidgets('running release stays readable without overflow at enlarged text size', (tester) async {
    final updates = Updates()..runningVersion = '0123456789abcdefabcd';
    await pumpApp(
      tester,
      seededChurch(),
      textScale: 2,
      overrides: [appUpdateGatewayProvider.overrideWithValue(updates)],
    );
    await openAbout(tester);
    expect(find.text('0123456789abcdefabcd'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('關於 shows the running release and update checks do not refresh the page', (tester) async {
    final updates = Updates();
    await pumpApp(tester, seededChurch(), overrides: [appUpdateGatewayProvider.overrideWithValue(updates)]);
    await openAbout(tester);
    expect(find.text('running-release'), findsOneWidget);
    await tester.tap(find.text('檢查更新'));
    await settle(tester);
    expect(find.text('running-release'), findsOneWidget);
    expect(find.text('更新並重新開啟'), findsOneWidget);
    expect(updates.reloads, 0);
  });
}
