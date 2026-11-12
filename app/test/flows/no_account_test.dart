import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/models.dart';

import '../support/harness.dart';
import '../support/seed.dart';

Future<void> tapText(WidgetTester tester, String text) async {
  final target = find.text(text).last;
  await tester.ensureVisible(target);
  await tester.tap(target);
  await settle(tester);
}

Future<void> go(WidgetTester tester, String location) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
  await settle(tester);
}

// 黃鎮台 serves 招待 on Sundays and has no account: a 同工 all the same.
const huang = PendingMember(
  id: 'old-huang',
  name: '黃鎮台',
  zones: [
    Zone(serviceType: 'sunday', duties: ['招待']),
  ],
);

MemoryBackend church({Member as = pastor}) {
  final b = seededChurch(as: as);
  b.addPending('grace', huang);
  return b;
}

void main() {
  testWidgets('one without an account is picked like anyone, said to hear nothing', (tester) async {
    final b = church(as: editor);
    await pumpApp(tester, b);
    await go(tester, '/rosters/sunday/2026-10-11');
    await tapText(tester, '招待');
    expect(find.text('沒有帳號'), findsOneWidget, reason: 'under his name: tell him yourself');
    await tapText(tester, '黃鎮台');
    await tapText(tester, '完成');
    final duty = savedDay(b, 11).duties.firstWhere((d) => d.role == '招待');
    expect(duty.uids['黃鎮台'], 'old-huang', reason: 'his, for when he signs in');
  });

  testWidgets('an admin opens his page from 同工 and sets what he serves; he holds no 身分', (tester) async {
    final b = church();
    await pumpApp(tester, b);
    await go(tester, '/me/members');
    expect(find.textContaining('沒有帳號'), findsWidgets);
    expect(find.textContaining('還沒登入'), findsNothing);
    await tapText(tester, '黃鎮台');
    expect(find.text('新增身分'), findsNothing);
    expect(find.text('招待'), findsOneWidget);
    await tapText(tester, '服事項目');
    await tapText(tester, '司琴');
    expect(b.pendingMembers['grace']!['old-huang']!.zones.single.duties, ['招待', '司琴']);
  });

  testWidgets("he is one of the service's 同工, whose 負責人 sets what he serves", (tester) async {
    final b = church(as: editor);
    await pumpApp(tester, b);
    await go(tester, '/me/groups/service/sunday');
    await tester.scrollUntilVisible(find.text('4 人'), 200, scrollable: find.byType(Scrollable).last);
    await tapText(tester, '4 人');
    await tapText(tester, '黃鎮台');
    await tapText(tester, '服事項目');
    await tapText(tester, '司會');
    expect(b.pendingMembers['grace']!['old-huang']!.zones.single.duties, ['招待', '司會']);
  });

  testWidgets('加入同工 adds someone not in the church by name, and goes on to what they serve', (tester) async {
    final b = church(as: editor);
    await pumpApp(tester, b);
    await go(tester, '/me/groups/service/sunday');
    await tester.scrollUntilVisible(find.text('4 人'), 200, scrollable: find.byType(Scrollable).last);
    await tapText(tester, '4 人');
    await tapText(tester, '加入同工');
    await tester.enterText(find.byType(TextField).last, '黃鎮台');
    await settle(tester);
    expect(find.textContaining('新增「'), findsNothing, reason: 'a name someone here has');
    await tester.enterText(find.byType(TextField).last, '王小明');
    await settle(tester);
    await tapText(tester, '新增「王小明」');
    final added = b.pendingMembers['grace']!.values.singleWhere((p) => p.name == '王小明');
    expect(added.zones.single.serviceType, 'sunday');
    await tapText(tester, '服事項目');
    await tapText(tester, '招待');
    expect(b.pendingMembers['grace']![added.id]!.zones.single.duties, ['招待']);
  });

  testWidgets('a name typed in the picker is for this once, not a 同工', (tester) async {
    final b = church(as: editor);
    await pumpApp(tester, b);
    await go(tester, '/rosters/sunday/2026-10-11');
    await tapText(tester, '招待');
    await tapText(tester, '找其他人');
    await tester.enterText(find.byType(TextField).last, '張講員');
    await settle(tester);
    expect(find.text('只排這一次'), findsOneWidget);
  });
}
