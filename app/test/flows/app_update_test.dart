import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/state/app_update.dart';

import '../state/app_update_test.dart' show Updates;
import '../support/harness.dart';
import '../support/seed.dart';

void main() {
  testWidgets('running release stays readable without overflow at enlarged text size', (tester) async {
    final updates = Updates()..runningVersion = '0123456789abcdefabcd';
    await pumpApp(
      tester,
      seededChurch(),
      textScale: 2,
      overrides: [appUpdateGatewayProvider.overrideWithValue(updates)],
    );
    await tester.tap(find.text('我的').last);
    await settle(tester);
    await tester.scrollUntilVisible(find.text('目前版本'), 180, scrollable: find.byType(Scrollable).last);
    expect(find.text('0123456789abcdefabcd'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('我的 shows the running release and update checks do not refresh the page', (tester) async {
    final updates = Updates();
    await pumpApp(tester, seededChurch(), overrides: [appUpdateGatewayProvider.overrideWithValue(updates)]);
    await tester.tap(find.text('我的').last);
    await settle(tester);
    expect(find.text('running-release'), findsOneWidget);
    await tester.tap(find.text('檢查更新'));
    await settle(tester);
    expect(find.text('running-release'), findsOneWidget);
    expect(find.text('更新並重新開啟'), findsOneWidget);
    expect(updates.reloads, 0);
  });
}
