import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/domain/event_roster.dart';

import '../support/harness.dart';
import '../support/seed.dart';

Future<void> go(WidgetTester tester, String location) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
  await settle(tester);
}

Future<void> tapText(WidgetTester tester, String text) async {
  final target = find.text(text).last;
  await tester.ensureVisible(target);
  await tester.tap(target);
  await settle(tester);
}

Finder field(String hint) => find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == hint);

void main() {
  testWidgets('a calendar editor adds, changes and clears an event description', (tester) async {
    final b = seededChurch();
    b.connectCalendar('grace', calendarName: '教會行事曆');
    await pumpApp(tester, b);
    await go(tester, '/calendar');
    await tester.tap(find.byTooltip('新增活動'));
    await settle(tester);
    await tester.enterText(field('活動名稱'), '同工會');
    await tester.enterText(field('活動說明'), '請帶服事表\n一起預備');
    await tester.pump();
    await tapText(tester, '儲存');
    final data = b.church('grace');
    final id = (await data.calendarEvents('2026-10')).single.id;
    expect((await data.calendarEvents('2026-10')).single.description, '請帶服事表\n一起預備');

    await tapText(tester, '同工會');
    await tester.enterText(field('活動說明'), '  改到二樓  ');
    await tapText(tester, '儲存');
    expect((await data.calendarEvents('2026-10')).single.id, id);
    expect((await data.calendarEvents('2026-10')).single.description, '改到二樓');

    await tapText(tester, '同工會');
    await tester.enterText(field('活動說明'), '');
    await tapText(tester, '儲存');
    expect((await data.calendarEvents('2026-10')).single.description, '');
  });

  testWidgets('duplicating opens a new draft and saves a separate event without recurrence or roster', (tester) async {
    final b = seededChurch();
    b.connectCalendar('grace', calendarName: '教會行事曆');
    final original = CalendarEvent(
      id: 'retreat',
      title: '同工退修會',
      start: DateTime(2026, 10, 9),
      end: DateTime(2026, 10, 12),
      allDay: true,
      location: '山上',
      description: '帶聖經',
      recurringEventId: 'series',
      originalStart: '2026-10-09',
    );
    b.calendarEvents['grace'] = [original];
    final roster = eventRoster(
      original,
      duties: const [
        Duty(role: '招待', people: ['李美玉']),
      ],
    ).copyWith(saved: true);
    b.rosters['grace']![roster.id] = roster;
    await pumpApp(tester, b);
    await go(tester, '/calendar');
    await tapText(tester, '同工退修會');
    await tester.ensureVisible(find.text('複製活動').last);
    await tester.pump();
    await tapText(tester, '複製活動');
    expect(find.text('新增活動'), findsOneWidget);
    expect(find.text('刪除活動'), findsNothing);
    expect(find.descendant(of: find.byType(BottomSheet).last, matching: find.text('服事表')), findsNothing);
    expect(find.text('安排服事'), findsOneWidget, reason: 'a new event, whose roster is its own');
    expect(
      (await b.church('grace').calendarEvents('2026-10')).length,
      1,
      reason: 'the copy is only a draft until saved',
    );
    await tester.enterText(field('活動名稱'), '青年退修會');
    await tapText(tester, '儲存');

    final events = await b.church('grace').calendarEvents('2026-10');
    final copied = events.singleWhere((e) => e.title == '青年退修會');
    expect(copied.id, isNotNull);
    expect(copied.id, isNot(original.id));
    expect((copied.start, copied.end, copied.allDay), (original.start, original.end, true));
    expect((copied.location, copied.description), ('山上', '帶聖經'));
    expect((copied.recurringEventId, copied.originalStart), (null, null));
    final rosters = await b.church('grace').eventRosters();
    expect(rosters, [roster], reason: 'copying never carries roster assignments into the new event');
    expect(events.singleWhere((e) => e.id == original.id).title, '同工退修會');
  });

  testWidgets('opening the roster saves a description-only edit and preserves the recurring occurrence identity', (
    tester,
  ) async {
    final b = seededChurch();
    b.connectCalendar('grace', calendarName: '教會行事曆');
    b.calendarEvents['grace'] = [
      CalendarEvent(
        id: 'meeting',
        title: '同工會',
        start: DateTime(2026, 10, 10, 19),
        end: DateTime(2026, 10, 10, 21),
        description: '帶服事表',
        recurringEventId: 'series',
        originalStart: '2026-10-10T19:00:00+08:00',
      ),
    ];
    await pumpApp(tester, b);
    await go(tester, '/calendar');
    await tapText(tester, '同工會');
    await tester.enterText(field('活動說明'), '帶聖經');
    await tapText(tester, '安排服事');
    final saved = (await b.church('grace').calendarEvents('2026-10')).single;
    expect(saved.description, '帶聖經');
    expect((saved.recurringEventId, saved.originalStart), ('series', '2026-10-10T19:00:00+08:00'));
    expect(find.byType(TextField), findsNothing, reason: 'the event editor has closed for the roster');
  });

  testWidgets('dismissing a duplicate draft leaves the original event untouched', (tester) async {
    final b = seededChurch();
    b.connectCalendar('grace', calendarName: '教會行事曆');
    b.calendarEvents['grace'] = [
      CalendarEvent(id: 'meeting', title: '同工會', start: DateTime(2026, 10, 10, 19), end: DateTime(2026, 10, 10, 21)),
    ];
    await pumpApp(tester, b);
    await go(tester, '/calendar');
    await tapText(tester, '同工會');
    await tester.ensureVisible(find.text('複製活動').last);
    await tester.pump();
    await tapText(tester, '複製活動');
    await tester.enterText(field('活動名稱'), '不要儲存這份');
    Navigator.of(tester.element(field('活動名稱'))).pop();
    await settle(tester);
    final events = await b.church('grace').calendarEvents('2026-10');
    expect(events.length, 1);
    expect((events.single.id, events.single.title), ('meeting', '同工會'));
  });
}
