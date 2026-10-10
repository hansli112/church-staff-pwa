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
}
