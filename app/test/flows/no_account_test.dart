import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/data/backend.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/domain/staff_order.dart';

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
    expect(find.text('黃鎮台'), findsOneWidget);
    expect(find.text('沒有帳號'), findsNothing, reason: 'picked like anyone: it is no reason to pick him or not');
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

  testWidgets('a name typed in the picker is for this once', (tester) async {
    final b = church(as: editor);
    await pumpApp(tester, b);
    await go(tester, '/rosters/sunday/2026-10-11');
    await tapText(tester, '招待');
    await tester.enterText(find.byType(TextField).last, '張講員');
    await settle(tester);
    await tapText(tester, '臨時排「張講員」');
    await tapText(tester, '完成');
    expect(peopleOn(b, 11, '招待'), contains('張講員'));
    expect(b.pendingMembers['grace']?.values.where((p) => p.name == '張講員'), isEmpty);
  });

  testWidgets('or a 同工 without an account, arranged now and theirs when they join by that name', (tester) async {
    final b = church(as: editor);
    await pumpApp(tester, b);
    await go(tester, '/rosters/sunday/2026-10-11');
    await tapText(tester, '招待');
    await tester.enterText(find.byType(TextField).last, '王小明');
    await settle(tester);
    await tapText(tester, '新增同工「王小明」');
    await tapText(tester, '完成');
    final added = b.pendingMembers['grace']!.values.singleWhere((p) => p.name == '王小明');
    expect(added.zones.single.serviceType, 'sunday');
    expect(added.zones.single.duties, ['招待'], reason: 'listed first for it next time');
    final duty = savedDay(b, 11).duties.firstWhere((d) => d.role == '招待');
    expect(duty.people, contains('王小明'));
    expect(duty.uids['王小明'], added.id, reason: 'his, for when he joins');
  });

  testWidgets('on a duty of one, 新增同工 puts them there at once', (tester) async {
    final b = church(as: editor);
    await pumpApp(tester, b);
    await go(tester, '/rosters/sunday/2026-10-11');
    await tapText(tester, '司琴');
    await tester.enterText(find.byType(TextField).last, '王小明');
    await settle(tester);
    await tapText(tester, '新增同工「王小明」');
    final added = b.pendingMembers['grace']!.values.singleWhere((p) => p.name == '王小明');
    expect(savedDay(b, 11).duties.firstWhere((d) => d.role == '司琴').uids, {'王小明': added.id});
  });

  testWidgets('a 同工 being added: the duty spins and opens nothing till they are on it', (tester) async {
    final b = church(as: editor);
    await pumpApp(tester, b);
    await go(tester, '/rosters/sunday/2026-10-11');
    await tapText(tester, '司琴');
    await tester.enterText(find.byType(TextField).last, '王小明');
    await settle(tester);
    b.writeHeld = Completer<void>();
    await tapText(tester, '新增同工「王小明」');
    final row = find.ancestor(of: find.text('司琴'), matching: find.byType(InkWell)).first;
    expect(find.descendant(of: row, matching: find.byType(CircularProgressIndicator)), findsOneWidget);
    expect(tester.widget<InkWell>(row).onTap, isNull);
    b.writeHeld!.complete();
    b.writeHeld = null;
    await settle(tester);
    expect(find.descendant(of: row, matching: find.byType(CircularProgressIndicator)), findsNothing);
    expect(savedDay(b, 11).duties.firstWhere((d) => d.role == '司琴').people, ['王小明']);
  });

  testWidgets('a name someone here has is not offered as a new 同工', (tester) async {
    final b = church(as: editor);
    await pumpApp(tester, b);
    await go(tester, '/rosters/sunday/2026-10-11');
    await tapText(tester, '招待');
    await tester.enterText(find.byType(TextField).last, '黃鎮台');
    await settle(tester);
    expect(find.textContaining('新增同工'), findsNothing, reason: 'a name someone here has');
    expect(find.textContaining('臨時排「'), findsNothing);
  });

  testWidgets('an admin fixes his name, on the rosters too', (tester) async {
    final b = church();
    b.rosters['grace']![Roster.idFor('sunday', Day(2026, 10, 11))] = Roster(
      type: 'sunday',
      day: Day(2026, 10, 11),
      duties: const [
        Duty(role: '招待', people: ['李美玉', '黃鎮台'], uids: {'李美玉': 'mei', '黃鎮台': 'old-huang'}),
      ],
    );
    b.staffOrders['grace']!['sunday'] = StaffOrder({
      '招待': ['黃鎮台', '陳志豪'],
    });
    await pumpApp(tester, b);
    await go(tester, '/me/members/old-huang');
    await tapText(tester, '名字');
    await tester.enterText(find.byType(TextField).last, '李美玉');
    await settle(tester);
    expect(find.text('教會裡已經有人叫「李美玉」'), findsOneWidget, reason: 'as it is typed');
    await tapText(tester, '儲存');
    expect(b.pendingMembers['grace']!['old-huang']!.name, '黃鎮台');
    await tapText(tester, '取消');

    await tapText(tester, '名字');
    await tester.enterText(find.byType(TextField).last, '黃振台');
    b.renameHeld = Completer();
    await tapText(tester, '儲存');
    expect(find.text('黃振台'), findsWidgets, reason: 'shown at once, though the server has not answered');
    b.renameHeld!.complete();
    await settle(tester);
    expect(find.text('已改名'), findsOneWidget);
    expect(b.pendingMembers['grace']!['old-huang']!.name, '黃振台');
    final duty = savedDay(b, 11).duties.single;
    expect(duty.people, ['李美玉', '黃振台'], reason: 'where he was');
    expect(duty.uids, {'李美玉': 'mei', '黃振台': 'old-huang'});
    expect(b.staffOrders['grace']!['sunday']!.rankingOf('招待'), ['黃振台', '陳志豪'], reason: 'still first');
  });

  testWidgets('only admins rename them', (tester) async {
    final b = church(as: editor);
    await expectLater(b.church('grace').renamePending('old-huang', '黃振台'), throwsA(isA<Object>()));
    expect(b.pendingMembers['grace']!['old-huang']!.name, '黃鎮台');
  });

  testWidgets('刪除這筆資料 goes back at once, off 同工 while the backend deletes it', (tester) async {
    final b = church();
    await pumpApp(tester, b);
    await go(tester, '/me/members');
    await tapText(tester, '黃鎮台');
    b.writeHeld = Completer();
    await tapText(tester, '刪除這筆資料');
    await tapText(tester, '刪除');
    expect(find.text('刪除這筆資料'), findsNothing, reason: 'back at once');
    expect(find.text('黃鎮台'), findsNothing, reason: 'off the list, though the server has not answered');
    b.writeHeld!.complete();
    await settle(tester);
    expect(b.pendingMembers['grace'], isEmpty);
    expect(find.text('已刪除'), findsOneWidget);
  });
}
