import 'package:flutter_test/flutter_test.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/domain/month_weeks.dart';

CalendarEvent allDay(String title, Day from, Day to) => CalendarEvent(
  title: title,
  start: DateTime(from.year, from.month, from.day),
  end: DateTime(to.year, to.month, to.day + 1),
  allDay: true,
);

CalendarEvent at(String title, Day day, int hour) => CalendarEvent(
  title: title,
  start: DateTime(day.year, day.month, day.day, hour),
  end: DateTime(day.year, day.month, day.day, hour + 1),
);

void main() {
  final october = Day(2026, 10, 1); // a Thursday

  test('weeks start on the given weekday and cover the whole month', () {
    final sunday = monthWeeks(const [], month: october, firstWeekday: 0, lanes: 2);
    expect(sunday.map((w) => w.start.key), ['2026-09-27', '2026-10-04', '2026-10-11', '2026-10-18', '2026-10-25']);
    final monday = monthWeeks(const [], month: october, firstWeekday: 1, lanes: 2);
    expect(monday.first.start.key, '2026-09-28');
    expect(monday.last.start.key, '2026-10-26');
  });

  test('an event over a weekend breaks into a bar per week, each saying it goes on', () {
    final weeks = monthWeeks(
      [allDay('營會', Day(2026, 10, 9), Day(2026, 10, 12))],
      month: october,
      firstWeekday: 0,
      lanes: 2,
    );
    final first = weeks[1].bars.single;
    expect((first.from, first.to, first.continuesBefore, first.continuesAfter), (5, 6, false, true));
    final second = weeks[2].bars.single;
    expect((second.from, second.to, second.continuesBefore, second.continuesAfter), (0, 1, true, false));
  });

  test('bars stay inside the month', () {
    final weeks = monthWeeks(
      [allDay('退修會', Day(2026, 9, 29), Day(2026, 10, 2))],
      month: october,
      firstWeekday: 0,
      lanes: 2,
    );
    final bar = weeks.first.bars.single;
    expect((bar.from, bar.to, bar.continuesBefore), (4, 5, true));
  });

  test('a day with more events than lanes keeps its last lane for the count', () {
    final d = Day(2026, 10, 14);
    final weeks = monthWeeks(
      [at('早禱', d, 6), at('同工會', d, 19), allDay('特會', d, d.addDays(2)), at('詩班', d, 20)],
      month: october,
      firstWeekday: 0,
      lanes: 2,
    );
    final week = weeks[2];
    expect({for (final b in week.bars) b.event.title: b.lane}, {'特會': 0});
    expect(week.hidden, {3: 3});
  });

  test('a lane freed in the middle of the week is used again', () {
    final weeks = monthWeeks(
      [
        allDay('A', Day(2026, 10, 11), Day(2026, 10, 12)),
        allDay('B', Day(2026, 10, 11), Day(2026, 10, 11)),
        allDay('C', Day(2026, 10, 13), Day(2026, 10, 14)),
      ],
      month: october,
      firstWeekday: 0,
      lanes: 2,
    );
    expect({for (final b in weeks[2].bars) b.event.title: b.lane}, {'A': 0, 'B': 1, 'C': 0});
    expect(weeks[2].hasHidden, isFalse);
  });

  test('an event with no lane for all its days is drawn where there is room, and counted only where there is none', () {
    final weeks = monthWeeks(
      [
        allDay('A', Day(2026, 10, 11), Day(2026, 10, 12)),
        allDay('B', Day(2026, 10, 11), Day(2026, 10, 12)),
        allDay('C', Day(2026, 10, 12), Day(2026, 10, 14)),
      ],
      month: october,
      firstWeekday: 0,
      lanes: 2,
    );
    final bars = {for (final b in weeks[2].bars) b.event.title: (b.from, b.to, b.lane)};
    expect(bars, {'A': (0, 1, 0), 'B': (0, 0, 1), 'C': (2, 3, 0)});
    expect(weeks[2].bars.singleWhere((b) => b.event.title == 'C').continuesBefore, isTrue);
    expect(weeks[2].hidden, {1: 2});
  });

  test('with no lanes every day an event is on counts it', () {
    final weeks = monthWeeks(
      [allDay('營會', Day(2026, 10, 9), Day(2026, 10, 12)), at('同工會', Day(2026, 10, 10), 19)],
      month: october,
      firstWeekday: 0,
      lanes: 0,
    );
    expect(weeks[1].bars, isEmpty);
    expect(weeks[1].hidden, {5: 1, 6: 2});
    expect(weeks[2].hidden, {0: 1, 1: 1});
  });
}
