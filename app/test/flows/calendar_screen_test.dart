import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/core/design/components.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/features/calendar/month_grid.dart';

import '../support/calendar.dart';
import '../support/harness.dart';
import '../support/seed.dart';

Future<void> openCalendar(WidgetTester tester) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/calendar');
  await settle(tester);
}

Finder agendaEvent(String title) => find.descendant(of: find.byType(ListRow), matching: find.text(title));
Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await settle(tester);
}

Finder monthDay(int day) => find.descendant(of: find.byType(MonthGrid), matching: find.text('$day'));

void main() {
  testWidgets('month grid brings a distant day into view after variable-height events and back again', (tester) async {
    final b = seededChurch(as: staffMei);
    b.connectCalendar('grace', calendarName: '教會行事曆');
    b.calendarEvents['grace'] = [
      for (var day = 1; day <= 30; day++)
        for (var i = 0; i < 16; i++)
          CalendarEvent(
            id: '$day-$i',
            title: i == 0 ? '活動$day' : '同工一起參加聚會與練習準備並討論各項服事安排' * 3,
            location: i == 0 ? null : '教會副堂及同工休息室' * 4,
            start: DateTime(2026, 10, day, 19),
            end: DateTime(2026, 10, day, 20),
          ),
    ];
    await pumpApp(tester, b);
    await openCalendar(tester);
    await tester.tap(monthDay(30));
    await settle(tester);
    expect(agendaEvent('活動30').hitTestable(), findsOneWidget);
    await tester.tap(monthDay(2));
    await settle(tester);
    expect(agendaEvent('活動2').hitTestable(), findsOneWidget);
  });
  testWidgets("this month opens on today's events, what is past above them", (tester) async {
    final b = seededChurch(as: staffMei, clock: () => testNow.add(const Duration(days: 19)));
    b.connectCalendar('grace', calendarName: '教會行事曆');
    b.calendarEvents['grace'] = [
      for (var day = 1; day <= 30; day++)
        CalendarEvent(
          id: '$day',
          title: '活動$day',
          start: DateTime(2026, 10, day, 19),
          end: DateTime(2026, 10, day, 20),
        ),
    ];
    await pumpApp(tester, b);
    await openCalendar(tester);
    final list = find.byType(CustomScrollView);
    final top = tester.getTopLeft(list).dy;
    expect(tester.getTopLeft(agendaEvent('活動20')).dy, lessThan(top + 60), reason: 'today first');
    expect(agendaEvent('活動19').hitTestable(), findsNothing);

    await swipeMonth(tester, 1);
    await settle(tester);
    await swipeMonth(tester, -1);
    await settle(tester);
    expect(tester.getTopLeft(agendaEvent('活動20')).dy, lessThan(top + 60), reason: 'back to this month, today again');
  });

  testWidgets("an event begun before today and still on is today's first row", (tester) async {
    final b = seededChurch(as: staffMei, clock: () => testNow.add(const Duration(days: 19)));
    b.connectCalendar('grace', calendarName: '教會行事曆');
    b.calendarEvents['grace'] = [
      for (var day = 1; day <= 30; day++)
        CalendarEvent(
          id: '$day',
          title: '活動$day',
          start: DateTime(2026, 10, day, 19),
          end: DateTime(2026, 10, day, 20),
        ),
      CalendarEvent(id: '退修會', title: '退修會', start: DateTime(2026, 10, 19), end: DateTime(2026, 10, 22), allDay: true),
    ];
    await pumpApp(tester, b);
    await openCalendar(tester);
    expect(agendaEvent('退修會').hitTestable(), findsOneWidget);
    expect(agendaEvent('活動18').hitTestable(), findsNothing);
  });

  testWidgets("today's row comes up under the notices, not over them", (tester) async {
    final b = seededChurch(as: staffMei, clock: () => testNow.add(const Duration(days: 19)));
    b.connectCalendar('grace', calendarName: '教會行事曆');
    b.calendarEvents['grace'] = [
      for (var day = 1; day <= 30; day++)
        CalendarEvent(
          id: '$day',
          title: '活動$day',
          start: DateTime(2026, 10, day, 19),
          end: DateTime(2026, 10, day, 20),
        ),
    ];
    // A phone away from the church: the page says whose time it shows.
    await pumpApp(tester, b, phoneOffset: const Duration(hours: -7));
    await openCalendar(tester);
    final notice = find.text('教會當地時間（台北）');
    expect(notice, findsOneWidget, reason: 'shown');
    expect(notice.hitTestable(), findsOneWidget);
    expect(agendaEvent('活動20').hitTestable(), findsOneWidget);
    expect(agendaEvent('活動19').hitTestable(), findsNothing);
  });

  testWidgets('a month other than this one opens on its first day', (tester) async {
    final b = seededChurch(as: staffMei, clock: () => testNow.add(const Duration(days: 19)));
    b.connectCalendar('grace', calendarName: '教會行事曆');
    b.calendarEvents['grace'] = [
      for (var day = 1; day <= 30; day++)
        CalendarEvent(
          id: '$day',
          title: '十一月$day',
          start: DateTime(2026, 11, day, 19),
          end: DateTime(2026, 11, day, 20),
        ),
    ];
    await pumpApp(tester, b);
    await openCalendar(tester);
    await swipeMonth(tester, 1);
    await settle(tester);
    expect(agendaEvent('十一月1').hitTestable(), findsOneWidget);
  });

  testWidgets('with no events from today on, this month opens at its top', (tester) async {
    final b = seededChurch(as: staffMei, clock: () => testNow.add(const Duration(days: 19)));
    b.connectCalendar('grace', calendarName: '教會行事曆');
    b.calendarEvents['grace'] = [
      for (var day = 1; day <= 10; day++)
        CalendarEvent(
          id: '$day',
          title: '活動$day',
          start: DateTime(2026, 10, day, 19),
          end: DateTime(2026, 10, day, 20),
        ),
    ];
    await pumpApp(tester, b);
    await openCalendar(tester);
    expect(agendaEvent('活動1').hitTestable(), findsOneWidget);
  });

  testWidgets('a grid that scrolls with the events stays in view on opening', (tester) async {
    final b = seededChurch(as: staffMei, clock: () => testNow.add(const Duration(days: 19)));
    b.connectCalendar('grace', calendarName: '教會行事曆');
    b.calendarEvents['grace'] = [
      for (var day = 1; day <= 30; day++)
        CalendarEvent(
          id: '$day',
          title: '活動$day',
          start: DateTime(2026, 10, day, 19),
          end: DateTime(2026, 10, day, 20),
        ),
    ];
    // Large text: the month grid scrolls with the list.
    await pumpApp(tester, b, textScale: 2);
    await openCalendar(tester);
    expect(monthDay(1).hitTestable(), findsOneWidget);
  });

  group('a picked day', () {
    CalendarEvent event(String id, int day, {int days = 1}) => CalendarEvent(
      id: id,
      title: id,
      start: DateTime(2026, 10, day),
      end: DateTime(2026, 10, day + days),
      allDay: true,
    );

    testWidgets("shows that day's events only, those over several days too, then the month again", (tester) async {
      final b = seededChurch(as: staffMei);
      b.connectCalendar('grace', calendarName: '教會行事曆');
      b.calendarEvents['grace'] = [event('退修會', 9, days: 3), event('同工會', 10), event('詩班練習', 20)];
      await pumpApp(tester, b);
      await openCalendar(tester);
      expect(agendaEvent('詩班練習'), findsOneWidget);

      await tester.tap(monthDay(10));
      await settle(tester);
      expect(agendaEvent('退修會'), findsOneWidget);
      expect(agendaEvent('同工會'), findsOneWidget);
      expect(agendaEvent('詩班練習'), findsNothing);

      await tester.tap(monthDay(10));
      await settle(tester);
      expect(agendaEvent('詩班練習'), findsOneWidget, reason: 'the same day again shows the month');

      await tester.tap(monthDay(20));
      await settle(tester);
      expect(agendaEvent('同工會'), findsNothing);
      await tester.tap(monthDay(20));
      await settle(tester);
      expect(agendaEvent('同工會'), findsOneWidget);
    });

    testWidgets('with nothing on says so', (tester) async {
      final b = seededChurch(as: staffMei);
      b.connectCalendar('grace', calendarName: '教會行事曆');
      b.calendarEvents['grace'] = [event('同工會', 10)];
      await pumpApp(tester, b);
      await openCalendar(tester);
      await tester.tap(monthDay(15));
      await settle(tester);
      expect(find.text('這天沒有活動'), findsOneWidget);
      expect(find.text('新增活動'), findsNothing, reason: 'staff do not edit the calendar');
    });

    testWidgets('offers a new event on it to those who may add one', (tester) async {
      final admin = seededChurch();
      admin.connectCalendar('grace', calendarName: '教會行事曆');
      await pumpApp(tester, admin);
      await openCalendar(tester);
      await tester.tap(monthDay(15));
      await settle(tester);
      // The picked day's heading says 10月15日 too: the editor adds to it.
      final before = find.textContaining('10月15日').evaluate().length;
      await tapText(tester, '新增活動');
      expect(
        find.textContaining('10月15日').evaluate().length,
        greaterThan(before),
        reason: 'the new event is on the picked day',
      );
    });
  });

  testWidgets('the month grid folds shut and open rather than vanishing', (tester) async {
    final b = seededChurch(as: staffMei);
    b.connectCalendar('grace', calendarName: '教會行事曆');
    await pumpApp(tester, b);
    await openCalendar(tester);
    final open = tester.getSize(find.byType(MonthGrid)).height;

    await pickInCalendarMenu(tester, '只看列表');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final folding = tester.getSize(
      find.ancestor(of: find.byType(MonthGrid), matching: find.byType(SizeTransition)).first,
    );
    expect(folding.height, inExclusiveRange(0, open));
    await tester.tap(monthDay(15), warnIfMissed: false);
    await settle(tester);
    expect(find.text('這天沒有活動'), findsNothing, reason: 'a grid folding away takes no taps');
    expect(find.byType(MonthGrid), findsNothing);

    await pickInCalendarMenu(tester, '月曆和列表');
    await tester.pump();
    expect(find.byType(MonthGrid), findsOneWidget);
    await settle(tester);
    expect(tester.getSize(find.byType(MonthGrid)).height, open);
  });
  testWidgets('a picked day comes into view under a grid that scrolls with it', (tester) async {
    final b = seededChurch(as: staffMei);
    b.connectCalendar('grace', calendarName: '教會行事曆');
    b.calendarEvents['grace'] = [
      CalendarEvent(
        id: '詩班練習',
        title: '詩班練習',
        start: DateTime(2026, 10, 28),
        end: DateTime(2026, 10, 29),
        allDay: true,
      ),
    ];
    // Large text: the month grid no longer stays put above the list.
    await pumpApp(tester, b, textScale: 2);
    await openCalendar(tester);
    await tester.tap(monthDay(28));
    await settle(tester);
    expect(agendaEvent('詩班練習').hitTestable(), findsOneWidget);
  });

  testWidgets('the month is the title, no 行事曆 over it; a swipe goes month by month, the list alone too', (
    tester,
  ) async {
    final b = seededChurch(as: staffMei);
    b.connectCalendar('grace', calendarName: '教會行事曆');
    b.calendarEvents['grace'] = [
      CalendarEvent(id: 'n', title: '感恩節', start: DateTime(2026, 11, 26, 19), end: DateTime(2026, 11, 26, 21)),
    ];
    await pumpApp(tester, b);
    await openCalendar(tester);
    expect(calendarMonth('10月 2026'), findsOneWidget);
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('行事曆')), findsNothing);
    expect(find.byTooltip('上個月'), findsNothing);

    await pickInCalendarMenu(tester, '只看列表');
    await settle(tester);
    await swipeMonth(tester, 1);
    await settle(tester);
    expect(calendarMonth('11月 2026'), findsOneWidget);
    expect(agendaEvent('感恩節'), findsOneWidget);
    await swipeMonth(tester, -1);
    await settle(tester);
    expect(calendarMonth('10月 2026'), findsOneWidget);
  });

  testWidgets('the month tapped, wheels pick another; 這個月 comes back to today', (tester) async {
    final b = seededChurch(as: staffMei);
    b.connectCalendar('grace', calendarName: '教會行事曆');
    await pumpApp(tester, b);
    await openCalendar(tester);
    await tester.tap(calendarMonth('10月 2026'));
    await settle(tester);
    expect(find.text('選月份'), findsOneWidget);
    final wheels = find.byType(CupertinoDatePicker);
    await tester.drag(find.descendant(of: wheels, matching: find.textContaining('2026')).first, const Offset(0, -40));
    await settle(tester);
    await tapText(tester, '完成');
    expect(calendarMonth('10月 2027'), findsOneWidget);

    await tester.tap(calendarMonth('10月 2027'));
    await settle(tester);
    await tapText(tester, '這個月');
    expect(calendarMonth('10月 2026'), findsOneWidget);

    final semantics = tester.ensureSemantics();
    tester.semantics.tap(find.semantics.byLabel('2026年10月'));
    await settle(tester);
    expect(find.text('選月份'), findsOneWidget, reason: 'a screen reader opens it too');
    semantics.dispose();
  });

  testWidgets('顯示與篩選 stands out while not every event shows', (tester) async {
    final b = seededChurch(as: staffMei);
    b.connectCalendar('grace', calendarName: '教會行事曆');
    await pumpApp(tester, b);
    await openCalendar(tester);
    Finder soft() => find.descendant(of: find.byTooltip('顯示與篩選'), matching: find.byType(DecoratedBox));
    expect(await calendarFilterShown(tester), '跟我有關的');
    expect(soft(), findsOneWidget);
    await pickInCalendarMenu(tester, '全部');
    await settle(tester);
    expect(soft(), findsNothing);
  });
}
