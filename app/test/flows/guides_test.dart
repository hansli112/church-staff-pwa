import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/models.dart';

import '../support/harness.dart';
import '../support/seed.dart';

// 使用教學: the website's guides, for whoever has forgotten how something
// works, from 我的 and from the pages that need one most.

Future<void> go(WidgetTester tester, String location) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
  await settle(tester);
}

MemoryBackend withJoy(MemoryBackend b) {
  b.smallGroups['grace'] = {'joy': const SmallGroupDetails(id: 'joy', name: '喜樂小組', service: 'sunday')};
  return b;
}

void main() {
  testWidgets('我的 has 使用教學, the guides in the language shown', (tester) async {
    final launches = captureLaunches();
    await pumpApp(tester, seededChurch(as: staffMei));
    await go(tester, '/me');
    await tester.scrollUntilVisible(find.text('使用教學'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('使用教學'));
    await settle(tester);
    expect(launches.opened.single, endsWith('/blog/?lang=zh-Hant&from=app'));
  });

  testWidgets('安排服事 has no 使用說明: nothing on it needs one', (tester) async {
    await pumpApp(tester, seededChurch());
    await go(tester, '/rosters/plan/sunday');
    await tester.tap(find.byIcon(Symbols.more_horiz_rounded));
    await settle(tester);
    expect(find.text('使用說明'), findsNothing);
  });

  testWidgets("a 小組's page has 使用說明, a service's not", (tester) async {
    final launches = captureLaunches();
    await pumpApp(tester, withJoy(seededChurch()));
    await go(tester, '/me/groups/service/sunday');
    expect(find.byTooltip('使用說明'), findsNothing);
    await go(tester, '/me/groups/small/joy');
    await tester.tap(find.byTooltip('使用說明'));
    await settle(tester);
    expect(launches.opened.single, contains('/blog/small-groups/?'));
  });

  testWidgets('通知 has 使用說明, for when they do not come', (tester) async {
    final launches = captureLaunches();
    await pumpApp(tester, seededChurch(as: staffMei));
    await go(tester, '/me/notifications');
    await tester.tap(find.byTooltip('使用說明'));
    await settle(tester);
    expect(launches.opened.single, contains('/blog/notifications/?'));
  });

  testWidgets("首頁連結's 格式說明 opens the guide with the JSON a daily source returns", (tester) async {
    final launches = captureLaunches();
    await pumpApp(tester, seededChurch());
    await go(tester, '/me/link');
    await tester.scrollUntilVisible(find.text('格式說明'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('格式說明'));
    await settle(tester);
    expect(launches.opened.single, contains('/blog/home-link/?'));
  });
}
