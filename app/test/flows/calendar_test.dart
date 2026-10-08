import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/core/design/components.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/event_roster.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/features/calendar/month_grid.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/harness.dart';
import '../support/seed.dart';

Future<void> go(WidgetTester tester, String location) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
  await settle(tester);
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await settle(tester);
}

const calendarEditor = Member(uid: 'cal', name: '行事曆同工', groups: {Group.calendarEditors});

/// The day [n] on the month grid.
Finder gridDay(int n) => find.descendant(of: find.byType(MonthGrid), matching: find.text('$n'));

/// [text] in the agenda below the month grid.
Finder inAgenda(String text) => find.descendant(of: find.byType(ListSection), matching: find.text(text));

void main() {
  testWidgets('not connected: staff see one sentence, the admin gets a way to connect', (tester) async {
    await pumpApp(tester, seededChurch(as: staffMei));
    await go(tester, '/calendar');
    expect(find.text('教會還沒有連接行事曆'), findsOneWidget);
    expect(find.text('連接 Google 日曆'), findsNothing);
  });

  testWidgets('the admin is warned about the unverified screen before connecting', (tester) async {
    await pumpApp(tester, seededChurch());
    await go(tester, '/calendar');
    await tapText(tester, '連接 Google 日曆');
    expect(find.textContaining('這個應用程式未經驗證'), findsOneWidget);
  });

  testWidgets('after connecting, the admin picks a calendar and everyone sees events', (tester) async {
    final b = seededChurch();
    b.connectCalendar('grace');
    b.calendarEvents['grace'] = [
      CalendarEvent(id: 'e1', title: '同工會', start: DateTime(2026, 10, 10, 19, 30), end: DateTime(2026, 10, 10, 21)),
    ];
    await pumpApp(tester, b);
    await go(tester, '/me/calendar');
    await tapText(tester, '教會行事曆');
    expect(b.calendars['grace']!.calendarName, '教會行事曆');
    await go(tester, '/calendar');
    expect(inAgenda('同工會'), findsOneWidget);
    expect(find.text('19:30'), findsOneWidget);
  });

  testWidgets('staff have no edit entry; calendar editors add and delete with undo', (tester) async {
    final b = seededChurch(as: calendarEditor, extra: const [calendarEditor]);
    b.connectCalendar('grace', calendarName: '教會行事曆');
    b.calendarEvents['grace'] = [
      CalendarEvent(id: 'e1', title: '同工會', start: DateTime(2026, 10, 10), end: DateTime(2026, 10, 11), allDay: true),
    ];
    await pumpApp(tester, b);
    await go(tester, '/calendar');
    await tester.tap(find.byTooltip('新增活動'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, '禱告會');
    await tester.pump();
    await tapText(tester, '儲存');
    expect(b.calendarEvents['grace']!.map((e) => e.title), containsAll(['同工會', '禱告會']));

    await tapText(tester, '同工會');
    await tapText(tester, '刪除活動');
    expect(b.calendarEvents['grace']!.map((e) => e.title), ['禱告會']);
    await tapText(tester, '復原');
    expect(b.calendarEvents['grace']!.map((e) => e.title), containsAll(['同工會', '禱告會']));
  });

  testWidgets("an event's roster follows a rename, is cancelled with a delete, and comes back with undo", (
    tester,
  ) async {
    final b = seededChurch(as: calendarEditor, extra: const [calendarEditor]);
    b.connectCalendar('grace', calendarName: '教會行事曆');
    final camp = CalendarEvent(
      id: 'camp',
      title: '夏令營',
      start: DateTime(2026, 10, 9),
      end: DateTime(2026, 10, 12),
      allDay: true,
    );
    b.calendarEvents['grace'] = [camp];
    b.rosters['grace']![Roster.idForEvent('camp')] = eventRoster(
      camp,
      duties: const [
        Duty(role: '報到', people: ['李美玉']),
      ],
    ).copyWith(saved: true);
    await pumpApp(tester, b);
    await go(tester, '/calendar');
    await tapText(tester, '夏令營');
    await tester.enterText(find.byType(TextField).first, '秋令營');
    await tester.pump();
    await tapText(tester, '儲存');
    final renamed = b.rosters['grace']![Roster.idForEvent('camp')]!;
    expect((renamed.forEvent!.title, renamed.day, renamed.lastDay), ('秋令營', Day(2026, 10, 9), Day(2026, 10, 11)));

    await tapText(tester, '秋令營');
    await tapText(tester, '刪除活動');
    expect(b.rosters['grace']![Roster.idForEvent('camp')]!.forEvent!.cancelled, isTrue);
    await tapText(tester, '復原');
    final again = b.calendarEvents['grace']!.single;
    expect(b.rosters['grace']!.containsKey(Roster.idForEvent('camp')), isFalse);
    final back = b.rosters['grace']![Roster.idForEvent(again.id!)]!;
    expect(back.forEvent!.cancelled, isFalse);
    expect(back.duties.single.people, ['李美玉']);
  });

  testWidgets('renaming a three-day event keeps its three days', (tester) async {
    final b = seededChurch(as: calendarEditor, extra: const [calendarEditor]);
    b.connectCalendar('grace', calendarName: '教會行事曆');
    b.calendarEvents['grace'] = [
      CalendarEvent(id: 'camp', title: '夏令營', start: DateTime(2026, 10, 9), end: DateTime(2026, 10, 12), allDay: true),
    ];
    await pumpApp(tester, b);
    await go(tester, '/calendar');
    await tapText(tester, '夏令營');
    await tester.enterText(find.byType(TextField).first, '秋令營');
    await tester.pump();
    await tapText(tester, '儲存');
    final camp = b.calendarEvents['grace']!.single;
    expect(camp.title, '秋令營');
    expect(camp.end, DateTime(2026, 10, 12));
  });

  testWidgets('an event over the end of a month changes, and goes, in the month on screen too', (tester) async {
    final b = seededChurch(as: calendarEditor, extra: const [calendarEditor]);
    b.connectCalendar('grace', calendarName: '教會行事曆');
    b.calendarEvents['grace'] = [
      CalendarEvent(id: 'r', title: '退修會', start: DateTime(2026, 9, 30), end: DateTime(2026, 10, 3), allDay: true),
    ];
    await pumpApp(tester, b);
    await go(tester, '/calendar');
    expect(find.text('2026年10月'), findsOneWidget);
    await tapText(tester, '退修會');
    await tester.enterText(find.byType(TextField).first, '秋季退修會');
    await tester.pump();
    await tapText(tester, '儲存');
    expect(inAgenda('秋季退修會'), findsWidgets, reason: 'October, though the event began in September');

    await tapText(tester, '秋季退修會');
    await tapText(tester, '刪除活動');
    expect(inAgenda('秋季退修會'), findsNothing);
    await tapText(tester, '復原');
    expect(inAgenda('秋季退修會'), findsWidgets);
  });

  Future<void> pickDay(WidgetTester tester, String chip, int day, {bool end = false}) async {
    final f = find.text(chip);
    await tester.tap(end ? f.last : f.first);
    await settle(tester);
    await tester.tap(find.text('$day').last);
    await tester.pump();
    await tapText(tester, '確定');
  }

  testWidgets('an all-day event over several days is made with its first and last day', (tester) async {
    final b = seededChurch(as: calendarEditor, extra: const [calendarEditor]);
    b.connectCalendar('grace', calendarName: '教會行事曆');
    await pumpApp(tester, b);
    await go(tester, '/calendar');
    await tester.tap(find.byTooltip('新增活動'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, '秋季退修會');
    await tester.pump();
    await tapText(tester, '整天');
    await pickDay(tester, '10月1日 週四', 3, end: true);
    await tapText(tester, '儲存');
    final e = b.calendarEvents['grace']!.single;
    expect((e.allDay, e.start, e.end), (true, DateTime(2026, 10, 1), DateTime(2026, 10, 4)));
  });

  testWidgets('the end cannot be set before the start, and moves with it', (tester) async {
    final b = seededChurch(as: calendarEditor, extra: const [calendarEditor]);
    b.connectCalendar('grace', calendarName: '教會行事曆');
    await pumpApp(tester, b);
    await go(tester, '/calendar');
    await tester.tap(find.byTooltip('新增活動'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, '同工會');
    await tester.pump();
    await pickDay(tester, '10月1日 週四', 5);
    expect(find.text('10月5日 週一'), findsNWidgets(2), reason: 'the end moved with the start');

    await pickDay(tester, '10月5日 週一', 3, end: true);
    expect(find.text('10月5日 週一'), findsNWidgets(2), reason: 'days before the start cannot be picked');

    // End times on the start day: only after the start, each with its length.
    await tester.tap(find.textContaining('9:00'));
    await settle(tester);
    expect(find.textContaining('7:30'), findsOneWidget, reason: 'the start only, not offered as an end');
    expect(find.text('15 分鐘'), findsOneWidget);
    await tester.ensureVisible(find.text('30 分鐘'));
    await settle(tester);
    await tester.tap(find.text('30 分鐘'));
    await settle(tester);
    await tapText(tester, '儲存');
    final e = b.calendarEvents['grace']!.single;
    expect((e.start, e.end), (DateTime(2026, 10, 5, 19, 30), DateTime(2026, 10, 5, 20)));
  });

  testWidgets('其他時間 sets any minute; one before the start ends the next day', (tester) async {
    final b = seededChurch(as: calendarEditor, extra: const [calendarEditor]);
    b.connectCalendar('grace', calendarName: '教會行事曆');
    await pumpApp(tester, b);
    await go(tester, '/calendar');
    await tester.tap(find.byTooltip('新增活動'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, '禱告會');
    await tester.pump();

    // The clock is in 12 hours, starting from the end set now (下午).
    Future<void> otherTime(String shown, int hour, int minute) async {
      await tester.tap(find.textContaining(shown).last);
      await settle(tester);
      await tapText(tester, '其他時間…');
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await settle(tester);
      final fields = find.descendant(of: find.byType(Dialog), matching: find.byType(TextField));
      await tester.enterText(fields.at(0), '$hour');
      await tester.enterText(fields.at(1), '$minute'.padLeft(2, '0'));
      await tapText(tester, '確定');
    }

    await otherTime('9:00', 7, 40);
    expect(find.textContaining('7:40'), findsOneWidget);
    expect(find.text('10月1日 週四'), findsNWidgets(2), reason: 'still the same day');

    await otherTime('7:40', 6, 0);
    expect(find.text('10月2日 週五'), findsOneWidget, reason: 'the end moved to the next day');
    await tapText(tester, '儲存');
    final e = b.calendarEvents['grace']!.single;
    expect((e.start, e.end), (DateTime(2026, 10, 1, 19, 30), DateTime(2026, 10, 2, 18)));
  });

  testWidgets('an event begun the month before is listed under the 1st, with its whole span', (tester) async {
    final b = seededChurch(as: staffMei);
    b.connectCalendar('grace', calendarName: '教會行事曆');
    b.calendarEvents['grace'] = [
      CalendarEvent(title: '退修會', start: DateTime(2026, 9, 29), end: DateTime(2026, 10, 3), allDay: true),
      CalendarEvent(title: '守夜禱告', start: DateTime(2026, 10, 9, 22), end: DateTime(2026, 10, 10, 6)),
    ];
    await pumpApp(tester, b);
    await go(tester, '/calendar');
    expect(find.text('9/29–10/2'), findsOneWidget);
    expect(find.text('10/9 22:00 –\n10/10 06:00'), findsOneWidget);
    expect(find.textContaining('9月29日'), findsNothing, reason: 'listed under 10月1日');
  });

  testWidgets('staff cannot edit even when connected', (tester) async {
    final b = seededChurch(as: staffMei);
    b.connectCalendar('grace', calendarName: '教會行事曆');
    await pumpApp(tester, b);
    await go(tester, '/calendar');
    expect(find.byTooltip('新增活動'), findsNothing);
    expect(find.text('這個月沒有活動'), findsOneWidget);
  });

  testWidgets('a revoked grant asks the admin to reconnect', (tester) async {
    final b = seededChurch();
    b.calendars['grace'] = const CalendarSettings(connected: true, needsReconnect: true, calendarName: 'x');
    await pumpApp(tester, b);
    await go(tester, '/calendar');
    expect(find.text('行事曆的授權失效了'), findsOneWidget);
    expect(find.text('重新連接'), findsOneWidget);
  });

  testWidgets('the month grid marks every day an event covers, and tapping a day shows its events', (tester) async {
    final semantics = tester.ensureSemantics();
    final b = seededChurch(as: staffMei);
    b.connectCalendar('grace', calendarName: '教會行事曆');
    b.calendarEvents['grace'] = [
      CalendarEvent(
        id: 'retreat',
        title: '退修會',
        start: DateTime(2026, 9, 29),
        end: DateTime(2026, 10, 3),
        allDay: true,
      ),
      CalendarEvent(id: 'camp', title: '夏令營', start: DateTime(2026, 10, 9), end: DateTime(2026, 10, 12), allDay: true),
      for (var d = 13; d <= 28; d++)
        CalendarEvent(id: 'e$d', title: '活動$d', start: DateTime(2026, 10, d, 19), end: DateTime(2026, 10, d, 20)),
      CalendarEvent(id: 'end', title: '月底聚會', start: DateTime(2026, 10, 30, 23), end: DateTime(2026, 10, 31)),
    ];
    await pumpApp(tester, b);
    await go(tester, '/calendar');

    bool marked(int n) => find
        .bySemanticsLabel(
          RegExp(
            '(^| )10月$n日'
            r'[^\d，]*，(退修會|夏令營|活動\d+|月底聚會)$',
          ),
        )
        .evaluate()
        .isNotEmpty;
    expect(
      [
        for (var n = 1; n <= 31; n++)
          if (marked(n)) n,
      ],
      [
        1, 2, // the retreat that began in September
        9, 10, 11, // the camp, not the 12th its end falls on
        for (var d = 13; d <= 28; d++) d,
        30, // ends at midnight, so not the 31st
      ],
    );

    expect(inAgenda('月底聚會').hitTestable(), findsNothing);
    await tester.tap(gridDay(30));
    await settle(tester);
    expect(inAgenda('月底聚會').hitTestable(), findsOneWidget);

    await tester.tap(gridDay(10));
    await settle(tester);
    expect(inAgenda('夏令營').hitTestable(), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a new event starts on the day picked on the month grid', (tester) async {
    final b = seededChurch(as: calendarEditor, extra: const [calendarEditor]);
    b.connectCalendar('grace', calendarName: '教會行事曆');
    await pumpApp(tester, b);
    await go(tester, '/calendar');
    await tester.tap(gridDay(15));
    await settle(tester);
    await tester.tap(find.byTooltip('新增活動'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, '禱告會');
    await tester.pump();
    await tapText(tester, '儲存');
    expect(b.calendarEvents['grace']!.single.day.key, '2026-10-15');
  });

  testWidgets('swiping the month grid changes the month, and a new month has nothing picked', (tester) async {
    final semantics = tester.ensureSemantics();
    final b = seededChurch(as: staffMei);
    b.connectCalendar('grace', calendarName: '教會行事曆');
    await pumpApp(tester, b);
    await go(tester, '/calendar');
    await tester.tap(gridDay(15));
    await settle(tester);
    expect(tester.getSemantics(gridDay(15)).flagsCollection.isSelected, Tristate.isTrue);
    await tester.fling(find.byType(MonthGrid), const Offset(-300, 0), 1000);
    await settle(tester);
    expect(find.text('2026年11月'), findsOneWidget);
    expect(tester.getSemantics(gridDay(15)).flagsCollection.isSelected, isNot(Tristate.isTrue));
    await tester.fling(find.byType(MonthGrid), const Offset(300, 0), 1000);
    await settle(tester);
    expect(find.text('2026年10月'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('the month grid folds away and stays folded on this device', (tester) async {
    final b = seededChurch(as: staffMei);
    b.connectCalendar('grace', calendarName: '教會行事曆');
    await pumpApp(tester, b);
    await go(tester, '/calendar');
    expect(find.byType(MonthGrid), findsOneWidget);
    await tester.tap(find.byTooltip('只看列表'));
    await settle(tester);
    expect(find.byType(MonthGrid), findsNothing);
    expect(find.byTooltip('顯示月曆'), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getBool('calendar_month_grid'), isFalse);
  });

  testWidgets('folding the month grid away lets go of the picked day', (tester) async {
    final b = seededChurch(as: calendarEditor, extra: const [calendarEditor]);
    b.connectCalendar('grace', calendarName: '教會行事曆');
    await pumpApp(tester, b);
    await go(tester, '/calendar');
    await tester.tap(gridDay(15));
    await settle(tester);
    await tester.tap(find.byTooltip('只看列表'));
    await settle(tester);
    await tester.tap(find.byTooltip('新增活動'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, '禱告會');
    await tester.pump();
    await tapText(tester, '儲存');
    expect(b.calendarEvents['grace']!.single.day.key, '2026-10-01'); // today, as before the month grid
  });

  testWidgets('on a short screen the month grid scrolls with the agenda, and stays while a month loads or fails', (
    tester,
  ) async {
    final b = seededChurch(as: staffMei);
    b.connectCalendar('grace', calendarName: '教會行事曆');
    await pumpApp(tester, b);
    tester.view.physicalSize = const Size(852 * 3, 393 * 3); // a phone on its side
    await go(tester, '/calendar');
    final inScroll = find.descendant(of: find.byType(CustomScrollView), matching: find.byType(MonthGrid));
    expect(inScroll, findsOneWidget);

    b.calendarEventsHeld = Completer();
    await tester.fling(find.byType(MonthGrid), const Offset(-300, 0), 1000);
    await tester.pump();
    await tester.pump();
    expect(find.text('2026年11月'), findsOneWidget);
    expect(find.byType(MonthGrid), findsOneWidget);

    b.calendarEventsHeld!.completeError(StateError('offline'));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('重試'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('重試'), findsOneWidget);
    expect(find.byType(MonthGrid), findsOneWidget);
    b.calendarEventsHeld = null;
  });

  testWidgets('with very large text the month grid scrolls with the agenda instead of filling the screen', (
    tester,
  ) async {
    final b = seededChurch(as: staffMei);
    b.connectCalendar('grace', calendarName: '教會行事曆');
    final inScroll = find.descendant(of: find.byType(CustomScrollView), matching: find.byType(MonthGrid));

    await pumpApp(tester, b);
    await go(tester, '/calendar');
    expect(inScroll, findsNothing, reason: 'stays put at the usual size');

    await pumpApp(tester, b, textScale: 3);
    await go(tester, '/calendar');
    expect(inScroll, findsOneWidget);
  });

  testWidgets(
    'the month grid names each day\'s events, one bar for a multi-day event, and counts the rest on a full day',
    (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final b = seededChurch(as: staffMei);
      b.connectCalendar('grace', calendarName: '教會行事曆');
      b.calendarEvents['grace'] = [
        CalendarEvent(
          id: 'camp',
          title: '夏令營',
          start: DateTime(2026, 10, 13),
          end: DateTime(2026, 10, 16),
          allDay: true,
        ),
        CalendarEvent(id: 'a', title: '早禱', start: DateTime(2026, 10, 14, 6), end: DateTime(2026, 10, 14, 7)),
        CalendarEvent(id: 'b', title: '同工會', start: DateTime(2026, 10, 14, 19), end: DateTime(2026, 10, 14, 21)),
      ];
      await pumpApp(tester, b);
      await go(tester, '/calendar');
      Finder inGrid(String text) => find.descendant(of: find.byType(MonthGrid), matching: find.text(text));
      expect(inGrid('夏令營'), findsOneWidget);
      expect(inGrid('早禱'), findsNothing);
      expect(inGrid('同工會'), findsNothing);
      expect(inGrid('+2'), findsOneWidget);
      // A screen reader hears every event of the day, shown or not.
      expect(find.bySemanticsLabel(RegExp(r'10月14日.*，夏令營、早禱、同工會$')), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets('names show up to 1.3× text; beyond it the month grid marks days with a dot', (tester) async {
    final b = seededChurch(as: staffMei);
    b.connectCalendar('grace', calendarName: '教會行事曆');
    b.calendarEvents['grace'] = [
      CalendarEvent(id: 'e', title: '同工會', start: DateTime(2026, 10, 10, 19), end: DateTime(2026, 10, 10, 21)),
    ];
    final inGrid = find.descendant(of: find.byType(MonthGrid), matching: find.text('同工會'));

    await pumpApp(tester, b, textScale: 1.3);
    await go(tester, '/calendar');
    expect(inGrid, findsOneWidget);

    await pumpApp(tester, b, textScale: 1.35);
    await go(tester, '/calendar');
    expect(inGrid, findsNothing);
    expect(inAgenda('同工會'), findsOneWidget);
  });

  testWidgets('the month grid is as tall before its events arrive as after', (tester) async {
    final b = seededChurch(as: staffMei);
    b.connectCalendar('grace', calendarName: '教會行事曆');
    b.calendarEvents['grace'] = [
      for (final title in ['早禱', '同工會', '詩班'])
        CalendarEvent(id: title, title: title, start: DateTime(2026, 11, 14, 19), end: DateTime(2026, 11, 14, 20)),
    ];
    await pumpApp(tester, b);
    await go(tester, '/calendar');
    b.calendarEventsHeld = Completer();
    await tester.tap(find.byTooltip('下個月'));
    await tester.pump();
    await tester.pump();
    final loading = tester.getSize(find.byType(MonthGrid)).height;
    b.calendarEventsHeld!.complete();
    b.calendarEventsHeld = null;
    await settle(tester);
    expect(find.descendant(of: find.byType(MonthGrid), matching: find.text('+2')), findsOneWidget);
    expect(tester.getSize(find.byType(MonthGrid)).height, loading);
  });
}
