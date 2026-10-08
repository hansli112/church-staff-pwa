import 'package:flutter_test/flutter_test.dart';
import 'package:martha/domain/models.dart';

void main() {
  test('an event shows in every month from its first day to its last', () {
    CalendarEvent allDay(DateTime start, DateTime end) =>
        CalendarEvent(title: '營會', start: start, end: end, allDay: true);
    expect(allDay(DateTime(2026, 9, 30), DateTime(2026, 10, 3)).months, ['2026-09', '2026-10']);
    expect(allDay(DateTime(2026, 9, 29), DateTime(2026, 10, 1)).months, ['2026-09'], reason: 'the end is exclusive');
    expect(allDay(DateTime(2026, 12, 31), DateTime(2027, 2, 2)).months, ['2026-12', '2027-01', '2027-02']);
    final night = CalendarEvent(title: '守夜', start: DateTime(2026, 10, 31, 22), end: DateTime(2026, 11, 1, 2));
    expect(night.months, ['2026-10', '2026-11']);
  });
}
