import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/data/backend.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/family.dart';
import 'package:martha/domain/models.dart';

import '../support/harness.dart';
import '../support/seed.dart';

// 家人: 李美玉 (mei) adds her son 李小恩, one of the 同工 without an account,
// and asks her husband 陳志豪 (hao). The tests start on Thursday 1 October
// 2026; 李小恩 ushers on 10/11.

Future<void> go(WidgetTester tester, String path) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(path);
  await settle(tester);
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await settle(tester);
}

const kid = PendingMember(id: 'kid', name: '李小恩');

MemoryBackend church({Member as = staffMei}) {
  final b = seededChurch(as: as);
  b.addPending('grace', kid);
  final id = Roster.idFor('sunday', Day(2026, 10, 11));
  final day = b.rosters['grace']![id]!;
  b.rosters['grace']![id] = day.copyWith(
    duties: [
      for (final d in day.duties)
        d.role == '招待' ? d.copyWith(people: [...d.people, '李小恩'], uids: {...d.uids, '李小恩': 'kid'}) : d,
    ],
  );
  b.notify();
  return b;
}

/// 加入家人, picking [name].
Future<void> add(WidgetTester tester, String name) async {
  await tapText(tester, '加入家人');
  await tapText(tester, name);
}

void main() {
  testWidgets('one without an account is family at once, and their days are on 首頁 with their name', (tester) async {
    final b = church();
    await pumpApp(tester, b);
    await go(tester, '/me');
    await tapText(tester, '家人');
    b.familyHeld = Completer();
    await add(tester, '李小恩');
    expect(find.text('李小恩'), findsOneWidget, reason: 'in at once, though the server has not answered');
    b.familyHeld!.complete();
    b.familyHeld = null;
    await settle(tester);
    expect(find.text('李美玉（你）'), findsOneWidget);
    expect(find.text('李小恩'), findsOneWidget);
    expect(find.text('沒有帳號'), findsOneWidget);
    expect(findShown('家人的服事會列在你的首頁。沒有帳號的家人被排到服事時，也通知你。'), findsOneWidget);

    await go(tester, '/home');
    expect(find.text('我和家人接下來的服事'), findsOneWidget);
    // 10/11: mine, then his; one each.
    expect(find.text('李小恩'), findsOneWidget);
    expect(find.textContaining('招待'), findsNWidgets(3), reason: '10/4 and 10/11 mine, 10/11 his');

    await go(tester, '/me/family');
    b.familyHeld = Completer();
    await tapText(tester, '移出');
    expect(find.text('李小恩'), findsNothing, reason: 'out at once, though the server has not answered');
    expect(find.text('儲存中…'), findsOneWidget);
    b.familyHeld!.completeError(const CloudException(CloudErrorCode.unavailable));
    await settle(tester);
    expect(find.text('李小恩'), findsOneWidget, reason: 'back, as the server has it');
    b.familyHeld = null;
    await tapText(tester, '移出');
    expect(findShown('已把李小恩移出家人'), findsOneWidget);
    expect(b.households['grace'], isEmpty);
    await tapText(tester, '復原');
    expect(b.households['grace']!.values.single.people, ['mei', 'kid']);
  });

  testWidgets('one with an account is asked, says yes on 首頁, and sees the family\'s days', (tester) async {
    final b = church();
    await pumpApp(tester, b);
    await go(tester, '/me/family');
    await add(tester, '陳志豪');
    expect(find.text('等對方接受'), findsOneWidget);
    expect(find.text('收回'), findsOneWidget);

    b.auth.signInAs('hao@example.com', uid: 'hao', name: staffHao.name);
    await pumpApp(tester, b);
    await go(tester, '/home');
    expect(findShown('李美玉想加你為家人'), findsOneWidget);
    await tapText(tester, '接受');
    expect(findShown('李美玉想加你為家人'), findsNothing);
    expect(find.text('我和家人接下來的服事'), findsOneWidget);
    expect(find.text('李美玉'), findsWidgets, reason: 'her days, by her name');
    expect(b.households['grace']!.values.single.people, ['mei', 'hao']);
  });

  testWidgets('saying no leaves no family', (tester) async {
    final b = church();
    await pumpApp(tester, b);
    await go(tester, '/me/family');
    await add(tester, '陳志豪');
    b.auth.signInAs('hao@example.com', uid: 'hao', name: staffHao.name);
    await pumpApp(tester, b);
    await go(tester, '/home');
    await tapText(tester, '不要');
    expect(findShown('李美玉想加你為家人'), findsNothing);
    expect(b.households['grace'], isEmpty);
  });

  testWidgets('an admin sees whose family one is on their page, and takes them out', (tester) async {
    final b = church(as: pastor);
    b.households['grace'] = {
      'h1': const Household(
        id: 'h1',
        people: ['mei', 'hao', 'kid'],
        noAccount: ['kid'],
        names: {'mei': '李美玉', 'hao': '陳志豪', 'kid': '李小恩'},
      ),
      'h2': const Household(
        id: 'h2',
        people: ['john', 'kid'],
        noAccount: ['kid'],
        names: {'john': 'John Chen', 'kid': '李小恩'},
      ),
      // 林同工 asked 王牧師 only: no family yet.
      'h3': const Household(
        id: 'h3',
        people: ['editor'],
        invited: ['pastor'],
        invitedBy: {'pastor': 'editor'},
        names: {'editor': '林同工', 'pastor': '王牧師'},
      ),
    };
    b.notify();
    await pumpApp(tester, b);
    await go(tester, '/me/members/mei');
    await tester.scrollUntilVisible(find.text('陳志豪、李小恩'), 200);
    expect(find.text('陳志豪、李小恩'), findsOneWidget);

    await go(tester, '/me/members/editor');
    expect(find.text('家人'), findsNothing, reason: 'only asked');

    await go(tester, '/me/members/kid');
    await tester.scrollUntilVisible(find.text('John Chen'), 200);
    expect(find.text('李美玉、陳志豪'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('把李小恩移出John Chen的家'));
    await settle(tester);
    expect(findShown('把李小恩移出John Chen的家？'), findsOneWidget);
    b.familyHeld = Completer();
    await tapText(tester, '移出');
    expect(find.text('John Chen'), findsNothing, reason: 'out at once, though the server has not answered');
    b.familyHeld!.complete();
    await settle(tester);
    expect(b.households['grace']!.keys, ['h1', 'h3'], reason: 'a family of one is none');
    expect(find.text('John Chen'), findsNothing);
  });
}
