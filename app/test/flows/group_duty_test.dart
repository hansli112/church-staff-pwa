import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/core/design/components.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../support/harness.dart';
import '../support/seed.dart';

// 服事交給小組: a duty on a day given to a 小組. 喜樂小組 has 李美玉 and
// 陳志豪; 恩典小組 nobody. The tests start on Thursday 1 October 2026.

const joy = SmallGroupDetails(id: 'joy', name: '喜樂小組', service: 'sunday');
const grace = SmallGroupDetails(id: 'grace-g', name: '恩典小組', service: 'sunday');

MemoryBackend church({Member as = pastor, bool given = false}) {
  final b = seededChurch(as: as);
  b.smallGroups['grace'] = {joy.id: joy, grace.id: grace};
  final members = b.members['grace']!;
  for (final uid in ['mei', 'hao']) {
    members[uid] = members[uid]!.copyWith(smallGroups: {'joy'});
  }
  if (given) {
    b.rosters['grace']![Roster.idFor('sunday', Day(2026, 10, 18))] = Roster(
      type: 'sunday',
      day: Day(2026, 10, 18),
      duties: const [
        Duty(role: '司會', people: ['林同工'], uids: {'林同工': 'editor'}),
        Duty(role: '招待', people: ['喜樂小組'], groups: {'喜樂小組': 'joy'}),
      ],
    );
  }
  b.notify();
  return b;
}

Future<void> go(WidgetTester tester, String path) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(path);
  await settle(tester);
}

Duty dutyOn(MemoryBackend b, int day, String role) => savedDay(b, day).duties.firstWhere((d) => d.role == role);

void main() {
  testWidgets('the picker lists the 小組 last, with how many are in each; picking one gives it the duty', (
    tester,
  ) async {
    final b = church();
    await pumpApp(tester, b);
    await go(tester, '/rosters/sunday/2026-10-11');
    await tester.tap(find.text('招待').last);
    await settle(tester);
    expect(find.text('搜尋同工或小組'), findsOneWidget);
    expect(find.text('小組'), findsOneWidget);
    expect(find.text('2 位同工'), findsOneWidget);
    expect(find.text('0 位同工'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('喜樂小組'), 100, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('喜樂小組'));
    await settle(tester);
    await tester.tap(find.text('完成'));
    await settle(tester);
    final usher = dutyOn(b, 11, '招待');
    expect(usher.people, containsAll(['李美玉', '喜樂小組']));
    expect(usher.groups, {'喜樂小組': 'joy'});
    expect(usher.uids, {'李美玉': 'mei'});

    // The day shows its name, the 小組's icon after it.
    final icon = find.byIcon(Symbols.groups_rounded);
    expect(icon, findsOneWidget);
    final name = find.textContaining('喜樂小組', findRichText: true).first;
    expect(tester.getCenter(icon).dx, greaterThan(tester.getTopLeft(name).dx));
  });

  testWidgets('searching finds a 小組 by name, and typing its name offers no name to type in', (tester) async {
    final b = church();
    await pumpApp(tester, b);
    await go(tester, '/rosters/sunday/2026-10-11');
    await tester.tap(find.text('招待').last);
    await settle(tester);
    await tester.enterText(find.byType(TextField), '喜樂');
    await settle(tester);
    expect(find.text('喜樂小組'), findsOneWidget);
    expect(find.text('恩典小組'), findsNothing);
    await tester.enterText(find.byType(TextField), '喜樂小組');
    await settle(tester);
    expect(find.textContaining('只排這一次'), findsNothing);
  });

  testWidgets('a 小組 on the day is ticked under 小組, not among the names typed in', (tester) async {
    final b = church(given: true);
    await pumpApp(tester, b);
    await go(tester, '/rosters/sunday/2026-10-18');
    await tester.tap(find.text('招待').last);
    await settle(tester);
    expect(find.text('臨時排過的人'), findsNothing);
    await tester.scrollUntilVisible(find.text('喜樂小組'), 100, scrollable: find.byType(Scrollable).last);
    final row = find.widgetWithText(ListRow, '喜樂小組');
    expect(find.descendant(of: row, matching: find.byIcon(Symbols.check_circle_rounded)), findsOneWidget);
  });

  testWidgets('one of the 小組 sees the duty as theirs: under 你的服事 with the 小組, no 我不行; and on 首頁', (
    tester,
  ) async {
    final b = church(as: staffHao, given: true);
    await pumpApp(tester, b);
    // 首頁: 10/4, his by name, and 10/18, his 小組's.
    expect(find.widgetWithText(ListRow, '主日崇拜'), findsNWidgets(2));
    await go(tester, '/rosters/sunday/2026-10-18');
    expect(find.text('你的服事'), findsOneWidget);
    final row = find.widgetWithText(ListRow, '招待');
    expect(find.descendant(of: row, matching: find.text('喜樂小組')), findsOneWidget);
    expect(find.text('我不行'), findsNothing);
  });

  testWidgets('安排服事: the cell says the 小組', (tester) async {
    final b = church(given: true);
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    expect(find.bySemanticsLabel(RegExp('^招待, .*10月18日')), findsOneWidget);
    expect(find.text('喜樂小組'), findsOneWidget);
  });

  testWidgets('a 小組 renamed: the days it is given a duty say its new name', (tester) async {
    final b = church(given: true);
    await pumpApp(tester, b);
    await b.church('grace').saveSmallGroup(joy.copyWith(name: '喜樂團契'), before: joy);
    expect(dutyOn(b, 18, '招待').people, ['喜樂團契']);
    expect(dutyOn(b, 18, '招待').groups, {'喜樂團契': 'joy'});
  });
}
