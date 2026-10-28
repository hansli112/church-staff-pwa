import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';

import '../support/harness.dart';
import '../support/seed.dart';

// 排好幾週 (#90). The tests start on Thursday 1 October 2026: 10/4 has
// everyone, 10/11 nobody on 司琴 yet.

Future<void> go(WidgetTester tester, String path) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(path);
  await settle(tester);
}

/// The cell of [role] on October [date].
Finder cell(String role, int date) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.label == '$role, 10月$date日 週日',
);

void main() {
  testWidgets('a cell picks its people at once; nobody is told until 通知同工, once', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    expect(find.text('2026年10月'), findsOneWidget);
    expect(find.text('2026年11月'), findsOneWidget);
    final notify = find.widgetWithText(TextButton, '通知同工');
    expect(tester.widget<TextButton>(notify).onPressed, isNull, reason: 'nothing to tell yet');

    await tester.tap(cell('司琴', 11));
    await settle(tester);
    await tester.tap(find.text('李美玉').last);
    await settle(tester);
    expect(peopleOn(b, 11, '司琴'), ['李美玉']);
    expect(b.planned['grace']!['sunday'], {'mei'});
    expect(find.descendant(of: cell('司琴', 11), matching: find.text('李美玉')), findsOneWidget);

    await tester.tap(notify);
    await settle(tester);
    expect(find.text('已通知 1 位同工'), findsOneWidget);
    expect(b.planned['grace'], isEmpty);
    expect(tester.widget<TextButton>(notify).onPressed, isNull);
  });

  testWidgets('a 事工’s 負責人 sees only the duties it leads', (tester) async {
    const worship = Ministry(id: 'worship', name: '敬拜團', duties: [MinistryDuty('sunday', '司琴')]);
    final b = seededChurch(
      extra: [
        staffMei.withIdentities(const [MinistryLead('worship')]),
      ],
      as: staffMei,
    );
    b.ministries['grace'] = const MinistrySettings(ministries: [worship], ids: ['worship']);
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    expect(cell('司琴', 11), findsOneWidget);
    expect(cell('司會', 11), findsNothing);
    expect(cell('招待', 11), findsNothing);
  });

  testWidgets('opens at the first month with a gap; the months before are a tap away', (tester) async {
    final b = seededChurch();
    for (final date in [11, 18, 25]) {
      b.rosters['grace']![Roster.idFor('sunday', Day(2026, 10, date))] = savedDay(
        b,
        4,
      ).copyWith(day: Day(2026, 10, date));
    }
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    expect(find.text('2026年10月'), findsNothing);
    expect(find.text('2026年11月'), findsOneWidget);
    await tester.tap(find.text('顯示前面的月份'));
    await settle(tester);
    expect(find.text('2026年10月'), findsOneWidget);
    expect(find.text('2027年1月'), findsOneWidget, reason: 'the months after stay');
  });

  testWidgets('the picker says how often someone serves that month, and what else that day', (tester) async {
    final b = seededChurch();
    b.rosters['grace']![Roster.idFor('youth', Day(2026, 10, 11))] = Roster(
      type: 'youth',
      day: Day(2026, 10, 11),
      duties: const [
        Duty(role: '司會', people: ['李美玉'], uids: {'李美玉': 'mei'}),
      ],
    );
    await pumpApp(tester, b);
    await go(tester, '/rosters/sunday/2026-10-11');
    await tester.tap(find.text('司琴'));
    await settle(tester);
    // 10/4 主日 and 10/11 青年; not the day being arranged.
    expect(find.text('這個月已排 2 次 · 同一天：青年崇拜 司會'), findsOneWidget);
  });
}
