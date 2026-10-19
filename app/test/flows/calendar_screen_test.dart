import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/core/design/components.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/features/calendar/month_grid.dart';

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

      await tapText(tester, '看整個月');
      expect(agendaEvent('詩班練習'), findsOneWidget);

      await tester.tap(monthDay(20));
      await settle(tester);
      expect(agendaEvent('同工會'), findsNothing);
      await tester.tap(monthDay(20));
      await settle(tester);
      expect(agendaEvent('同工會'), findsOneWidget, reason: 'the same day again shows the month');
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

    await tester.tap(find.byTooltip('只看列表'));
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

    await tester.tap(find.byTooltip('顯示月曆'));
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
}
