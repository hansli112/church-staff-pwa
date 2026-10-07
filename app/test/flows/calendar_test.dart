import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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

/// The day [n] on the small month.
Finder gridDay(int n) => find.descendant(of: find.byType(MonthGrid), matching: find.text('$n'));

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
    expect(find.text('同工會'), findsOneWidget);
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

  testWidgets('the small month marks every day an event covers, and tapping a day shows its events', (tester) async {
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
            r'[^\d].*，有活動$',
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

    expect(find.text('月底聚會').hitTestable(), findsNothing);
    await tester.tap(gridDay(30));
    await settle(tester);
    expect(find.text('月底聚會').hitTestable(), findsOneWidget);

    await tester.tap(gridDay(10));
    await settle(tester);
    expect(find.text('夏令營').hitTestable(), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a new event starts on the day picked on the small month', (tester) async {
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

  testWidgets('swiping the small month changes the month, and a new month has nothing picked', (tester) async {
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

  testWidgets('the small month folds away and stays folded on this device', (tester) async {
    final b = seededChurch(as: staffMei);
    b.connectCalendar('grace', calendarName: '教會行事曆');
    await pumpApp(tester, b);
    await go(tester, '/calendar');
    expect(find.byType(MonthGrid), findsOneWidget);
    await tester.tap(find.byTooltip('收起小月曆'));
    await settle(tester);
    expect(find.byType(MonthGrid), findsNothing);
    expect(find.byTooltip('顯示小月曆'), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getBool('calendar_month_grid'), isFalse);
  });

  testWidgets('folding the small month away lets go of the picked day', (tester) async {
    final b = seededChurch(as: calendarEditor, extra: const [calendarEditor]);
    b.connectCalendar('grace', calendarName: '教會行事曆');
    await pumpApp(tester, b);
    await go(tester, '/calendar');
    await tester.tap(gridDay(15));
    await settle(tester);
    await tester.tap(find.byTooltip('收起小月曆'));
    await settle(tester);
    await tester.tap(find.byTooltip('新增活動'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, '禱告會');
    await tester.pump();
    await tapText(tester, '儲存');
    expect(b.calendarEvents['grace']!.single.day.key, '2026-10-01'); // today, as before the small month
  });

  testWidgets('on a short screen the small month scrolls with the agenda, and stays while a month loads or fails', (
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

  testWidgets('with very large text the small month scrolls with the agenda instead of filling the screen', (
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
}
