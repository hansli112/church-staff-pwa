import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/event_roster.dart';
import 'package:martha/domain/models.dart';

import '../support/harness.dart';
import '../support/seed.dart';

// #84: 敬拜團's events are 敬拜團's; 陳志豪 leads it.
const worship = Ministry(id: 'worship', name: '敬拜團');

MemoryBackend church({Member as = staffHao}) {
  final b = seededChurch(
    as: as,
    extra: [
      staffHao.withIdentities(const [MinistryLead('worship')]),
    ],
  );
  b.ministries['grace'] = const MinistrySettings(ministries: [worship], ids: ['worship']);
  b.connectCalendar('grace', calendarName: '教會行事曆');
  b.calendarEvents['grace'] = [
    CalendarEvent(id: 'meeting', title: '同工會', start: DateTime(2026, 10, 10, 19), end: DateTime(2026, 10, 10, 21)),
    CalendarEvent(
      id: 'practice',
      title: '敬拜團練習',
      start: DateTime(2026, 10, 17, 19),
      end: DateTime(2026, 10, 17, 21),
      group: 'ministry:worship',
    ),
    CalendarEvent(
      id: 'youth',
      title: '青年團契',
      start: DateTime(2026, 10, 24, 19),
      end: DateTime(2026, 10, 24, 21),
      group: 'service:youth',
    ),
  ];
  return b;
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await settle(tester);
}

Future<void> go(WidgetTester tester, String path) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(path);
  await settle(tester);
}

void main() {
  testWidgets("跟我有關的 at first: the church's events and my groups'; 全部 shows the rest", (tester) async {
    await pumpApp(tester, church());
    await go(tester, '/calendar');
    expect(find.text('跟我有關的'), findsOneWidget);
    expect(find.text('同工會'), findsWidgets);
    expect(find.text('敬拜團練習'), findsWidgets);
    expect(find.text('青年團契'), findsNothing, reason: "青年崇拜's, and he is not in it");

    await tapText(tester, '跟我有關的');
    await tapText(tester, '全部');
    expect(find.text('青年團契'), findsWidgets);
    await tapText(tester, '全部');
    await tapText(tester, '全教會');
    expect(find.text('敬拜團練習'), findsNothing);
    expect(find.text('同工會'), findsWidgets);
  });

  testWidgets('an admin sees everything at first', (tester) async {
    await pumpApp(tester, church(as: pastor));
    await go(tester, '/calendar');
    expect(find.text('全部'), findsOneWidget);
    expect(find.text('青年團契'), findsWidgets);
  });

  testWidgets("a 負責人 makes and edits its group's events, and only reads the church's", (tester) async {
    final b = church();
    await pumpApp(tester, b);
    await go(tester, '/calendar');
    await tapText(tester, '同工會');
    expect(find.text('編輯活動'), findsNothing, reason: "the church's: read only");
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);

    await tester.tap(find.byTooltip('新增活動'));
    await settle(tester);
    expect(find.text('屬於'), findsNothing, reason: 'only 敬拜團 to give it to');
    await tester.enterText(find.widgetWithText(TextField, '活動名稱'), '敬拜團禱告會');
    await tester.pump();
    await tapText(tester, '儲存');
    final made = b.calendarEvents['grace']!.firstWhere((e) => e.title == '敬拜團禱告會');
    expect(made.group, 'ministry:worship');

    await tapText(tester, '敬拜團練習');
    expect(find.text('編輯活動'), findsOneWidget);
  });

  testWidgets('picking 屬於 puts the keyboard away, and it stays away', (tester) async {
    await pumpApp(tester, church(as: pastor));
    await go(tester, '/calendar');
    await tester.tap(find.byTooltip('新增活動'));
    await settle(tester);
    expect(tester.testTextInput.isVisible, isTrue, reason: 'the name is typed first');
    await tapText(tester, '屬於');
    expect(tester.testTextInput.isVisible, isFalse, reason: 'not over the list');
    await tapText(tester, '敬拜團');
    expect(tester.testTextInput.isVisible, isFalse, reason: 'not back over the sheet');
  });

  testWidgets("its 負責人 arranges all of the group's event roster", (tester) async {
    final b = church();
    await pumpApp(tester, b);
    await go(tester, '/calendar');
    await tapText(tester, '敬拜團練習');
    await tester.ensureVisible(find.text('安排服事').last);
    await tester.pump();
    await tapText(tester, '安排服事');
    await tester.tap(find.byTooltip('編輯'));
    await settle(tester);
    await tapText(tester, '新增服事項目');
    expect(find.byType(TextField), findsOneWidget, reason: 'any duty, typed in too');
  });

  testWidgets('跟我有關的 has the events I served at, a month gone by too', (tester) async {
    final b = church();
    final retreat = CalendarEvent(
      id: 'retreat',
      title: '青年退修會',
      start: DateTime(2026, 9, 19, 9),
      end: DateTime(2026, 9, 19, 17),
      group: 'service:youth',
    );
    b.calendarEvents['grace']!.add(retreat);
    b.rosters['grace']![Roster.idForEvent('retreat')] = eventRoster(
      retreat,
      duties: const [
        Duty(role: '司琴', people: ['陳志豪'], uids: {'陳志豪': 'hao'}),
      ],
    ).copyWith(saved: true);
    await pumpApp(tester, b);
    await go(tester, '/calendar');
    await tester.tap(find.byTooltip('上個月'));
    await settle(tester);
    expect(find.text('青年退修會'), findsWidgets, reason: "青年崇拜's, but he played 司琴");
  });

  testWidgets('a group picked, then deleted, leaves 跟我有關的', (tester) async {
    final b = church();
    await pumpApp(tester, b);
    await go(tester, '/calendar');
    await tapText(tester, '跟我有關的');
    await tapText(tester, '敬拜團');
    expect(find.text('同工會'), findsNothing);
    b.ministries['grace'] = const MinistrySettings(ministries: [], ids: ['worship']);
    b.notify();
    await settle(tester);
    expect(find.text('跟我有關的'), findsOneWidget);
    expect(find.text('同工會'), findsWidgets);
  });
}
