import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/core/design/components.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/event_roster.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/features/calendar/month_grid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

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
    expect(findShownContaining('這個應用程式未經驗證'), findsOneWidget);
  });

  // Android's Custom Tab cannot be closed by the app; its page says to close it.
  testWidgets('in the iPhone app, Google opens in a sheet over the app, which closes once connected', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final launches = captureLaunches();
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/me/calendar');
      await tapText(tester, '連接 Google 日曆');
      expect(launches.opened.single, startsWith('https://accounts.google.com/'));
      expect(launches.modes.single, PreferredLaunchMode.inAppBrowserView);
      expect(launches.closed, 0);
      b.connectCalendar('grace');
      await settle(tester);
      expect(launches.closed, 1);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('opening the page of a connected church closes nothing', (tester) async {
    final launches = captureLaunches();
    final b = seededChurch()..connectCalendar('grace', calendarName: '教會行事曆');
    await pumpApp(tester, b);
    await go(tester, '/me/calendar');
    expect(launches.closed, 0);
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
    await tester.ensureVisible(find.text('刪除活動').last);
    await tester.pump();
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
    await tester.ensureVisible(find.text('刪除活動').last);
    await tester.pump();
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
    expect(camp.end, DateTime.utc(2026, 10, 12));
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
    await tester.ensureVisible(find.text('刪除活動').last);
    await tester.pump();
    await tapText(tester, '刪除活動');
    expect(inAgenda('秋季退修會'), findsNothing);
    await tapText(tester, '復原');
    expect(inAgenda('秋季退修會'), findsWidgets);
  });

  /// Taps a day chip and a day in the month that opens under it.
  Future<void> pickDay(WidgetTester tester, String chip, int day, {bool end = false}) async {
    final f = find.text(chip);
    await tester.tap(end ? f.last : f.first);
    await settle(tester);
    await tester.tap(find.descendant(of: find.byType(CalendarDatePicker), matching: find.text('$day')));
    await settle(tester);
  }

  /// Turns the wheel showing [shown] by [steps] items (up is later).
  Future<void> turn(WidgetTester tester, String shown, int steps) async {
    final wheel = find.ancestor(of: find.text(shown), matching: find.byType(CupertinoPicker)).first;
    await tester.drag(wheel, Offset(0, -32.0 * steps), warnIfMissed: false);
    await settle(tester);
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
    expect((e.allDay, e.start, e.end), (true, DateTime.utc(2026, 10, 1), DateTime.utc(2026, 10, 4)));
  });

  testWidgets('a day opens in place, with the keyboard put away, and the end moves with the start', (tester) async {
    final b = seededChurch(as: calendarEditor, extra: const [calendarEditor]);
    b.connectCalendar('grace', calendarName: '教會行事曆');
    await pumpApp(tester, b);
    await go(tester, '/calendar');
    await tester.tap(find.byTooltip('新增活動'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, '同工會');
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.text('10月1日 週四').first);
    await settle(tester);
    expect(tester.testTextInput.isVisible, isFalse, reason: 'the keyboard went');
    expect(find.byType(CalendarDatePicker), findsOneWidget, reason: 'in the sheet, not a dialog');
    expect(find.byType(Dialog), findsNothing);
    expect(
      tester.getRect(find.byType(CalendarDatePicker)).bottom,
      lessThanOrEqualTo(tester.view.physicalSize.height / tester.view.devicePixelRatio),
      reason: 'scrolled into sight',
    );
    await tester.tap(find.descendant(of: find.byType(CalendarDatePicker), matching: find.text('5')));
    await settle(tester);
    expect(find.byType(CalendarDatePicker), findsNothing, reason: 'one tap picks it and closes');
    expect(find.text('10月5日 週一'), findsNWidgets(2), reason: 'the end moved with the start');

    await pickDay(tester, '10月5日 週一', 3, end: true);
    expect(find.text('10月5日 週一'), findsNWidgets(2), reason: 'days before the start cannot be picked');
    await tester.tap(find.text('10月5日 週一').last);
    await settle(tester);
    expect(find.byType(CalendarDatePicker), findsNothing, reason: 'tapping its day again closes it');
  });

  testWidgets("picking a year turns the start's month to it; only a day picks", (tester) async {
    final b = seededChurch(as: calendarEditor, extra: const [calendarEditor]);
    b.connectCalendar('grace', calendarName: '教會行事曆');
    await pumpApp(tester, b);
    await go(tester, '/calendar');
    await tester.tap(find.byTooltip('新增活動'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, '跨年禱告會');
    await tester.pump();
    await tester.tap(find.text('10月1日 週四').first);
    await settle(tester);
    await tapText(tester, '2026年10月');
    await tapText(tester, '2027年');
    expect(find.byType(CalendarDatePicker), findsOneWidget, reason: 'still open');
    await tester.tap(find.descendant(of: find.byType(CalendarDatePicker), matching: find.text('5')));
    await settle(tester);
    await tapText(tester, '儲存');
    expect(b.calendarEvents['grace']!.single.start, DateTime.utc(2027, 10, 5, 19, 30));
  });

  testWidgets('time wheels open in place; an end before the start ends the next day', (tester) async {
    final b = seededChurch(as: calendarEditor, extra: const [calendarEditor]);
    b.connectCalendar('grace', calendarName: '教會行事曆');
    await pumpApp(tester, b);
    await go(tester, '/calendar');
    await tester.tap(find.byTooltip('新增活動'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, '禱告會');
    await tester.pump();
    expect(find.text('1 小時 30 分鐘'), findsOneWidget, reason: 'how long, under 結束');

    // 7:30 to 9:00 in the evening. The start's wheels first, then the
    // end's, which start from the end.
    await tester.tap(find.textContaining('7:30'));
    await settle(tester);
    expect(find.byType(CupertinoDatePicker), findsOneWidget);
    await tester.ensureVisible(find.textContaining('9:00'));
    await tester.pump();
    await tester.tap(find.textContaining('9:00'));
    await settle(tester);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(find.byType(CupertinoDatePicker), findsOneWidget);
    await turn(tester, '00', 6);
    expect(find.text('2 小時'), findsOneWidget);

    // Back to 6 o'clock, before the start: the next day.
    await turn(tester, '09', -3);
    expect(find.text('10月2日 週五'), findsOneWidget, reason: 'the end moved to the next day');
    // And 8, after it again: the start day.
    await turn(tester, '06', 2);
    expect(find.text('10月1日 週四'), findsNWidgets(2), reason: 'back on the start day');

    // Typing in a field closes the wheels.
    await tester.ensureVisible(find.byType(TextField).first);
    await tester.pump();
    await tester.tap(find.byType(TextField).first);
    await settle(tester);
    expect(find.byType(CupertinoDatePicker), findsNothing);
    await tapText(tester, '儲存');
    final e = b.calendarEvents['grace']!.single;
    expect((e.start, e.end), (DateTime.utc(2026, 10, 1, 19, 30), DateTime.utc(2026, 10, 1, 20, 30)));
  });

  testWidgets("a two-day event's end time turns on its own day", (tester) async {
    final b = seededChurch(as: calendarEditor, extra: const [calendarEditor]);
    b.connectCalendar('grace', calendarName: '教會行事曆');
    b.calendarEvents['grace'] = [
      CalendarEvent(id: 'c', title: '青年營', start: DateTime.utc(2026, 10, 3, 10), end: DateTime.utc(2026, 10, 4, 15)),
    ];
    await pumpApp(tester, b);
    await go(tester, '/calendar');
    await tapText(tester, '青年營');
    await tester.ensureVisible(find.textContaining('3:00'));
    await tester.pump();
    await tester.tap(find.textContaining('3:00'));
    await settle(tester);
    await turn(tester, '00', 1);
    expect(find.text('10月4日 週日'), findsOneWidget, reason: 'Sunday still, not 5 minutes after 10 on Saturday');
    // Down past the start's 10 o'clock and up again: Sunday all along.
    await turn(tester, '03', -6);
    await turn(tester, '09', 2);
    expect(find.text('10月4日 週日'), findsOneWidget);
    await tapText(tester, '儲存');
    expect(b.calendarEvents['grace']!.single.end, DateTime.utc(2026, 10, 4, 11, 5));
  });

  testWidgets('a time between fives turns a minute at a time, past a five too', (tester) async {
    final b = seededChurch(as: calendarEditor, extra: const [calendarEditor]);
    b.connectCalendar('grace', calendarName: '教會行事曆');
    b.calendarEvents['grace'] = [
      CalendarEvent(
        id: 'p',
        title: '禱告會',
        start: DateTime.utc(2026, 10, 3, 19, 33),
        end: DateTime.utc(2026, 10, 3, 21),
      ),
    ];
    await pumpApp(tester, b);
    await go(tester, '/calendar');
    await tapText(tester, '禱告會');
    await tester.tap(find.textContaining('7:33'));
    await settle(tester);
    // To 7:35, a five, and on: the wheel stays in minutes.
    await turn(tester, '33', 2);
    await turn(tester, '35', 1);
    await tapText(tester, '儲存');
    expect(b.calendarEvents['grace']!.single.start, DateTime.utc(2026, 10, 3, 19, 36));
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

  testWidgets('a permission ticked off on Google\'s screen: the admin is told to leave them all ticked', (
    tester,
  ) async {
    await pumpApp(tester, seededChurch());
    await go(tester, '/me/calendar?result=scopes');
    expect(findShown('沒有連接成功：Google 的授權畫面上，每個權限都要勾選'), findsOneWidget);
    expect(find.text('沒有連接成功，請再試一次'), findsNothing);
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

  testWidgets('a new event shows as soon as it is saved, and opens once the server has it', (tester) async {
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
    b.calendarSaveHeld = Completer();
    await tapText(tester, '儲存');
    expect(inAgenda('禱告會'), findsOneWidget, reason: 'before the server answers');
    await tester.tap(inAgenda('禱告會'));
    await settle(tester);
    expect(find.text('儲存'), findsNothing, reason: 'no id yet: editing it now would make a second one');

    b.calendarSaveHeld!.complete();
    await settle(tester);
    expect(inAgenda('禱告會'), findsOneWidget);
    await tester.tap(inAgenda('禱告會'));
    await settle(tester);
    expect(find.text('儲存'), findsOneWidget);
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

    // 首頁 has already read next month for its activities. Hold the one
    // after, which is read ahead while next month shows.
    b.calendarEventsHeld = Completer();
    await tester.fling(find.byType(MonthGrid), const Offset(-300, 0), 1000);
    await settle(tester);
    await tester.fling(find.byType(MonthGrid), const Offset(-300, 0), 1000);
    await tester.pump();
    await tester.pump();
    expect(find.text('2026年12月'), findsOneWidget);
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

  testWidgets('the next month shows at once: it was read while this one showed', (tester) async {
    final b = seededChurch()..connectCalendar('grace', calendarName: '教會行事曆');
    b.calendarEvents['grace'] = [
      CalendarEvent(id: 'd1', title: '聖誕晚會', start: DateTime(2026, 12, 24), end: DateTime(2026, 12, 25), allDay: true),
    ];
    await pumpApp(tester, b);
    await go(tester, '/calendar');
    await tester.tap(find.byTooltip('下個月'));
    await settle(tester);
    b.calendarEventsHeld = Completer();
    await tester.tap(find.byTooltip('下個月'));
    await tester.pump();
    expect(inAgenda('聖誕晚會'), findsOneWidget, reason: 'no read to wait for');
    b.calendarEventsHeld!.complete();
    await settle(tester);
  });
}
