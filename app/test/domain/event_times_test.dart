import 'package:flutter_test/flutter_test.dart';
import 'package:martha/domain/event_times.dart';
import 'package:martha/domain/models.dart';

final _day = DateTime.utc(2026, 11, 6);

void main() {
  test('a new event starts on the day picked, 19:30 to 21:00', () {
    final t = EventTimes.of(null, initialDay: _day);
    expect(t.start, DateTime.utc(2026, 11, 6, 19, 30));
    expect(t.end, DateTime.utc(2026, 11, 6, 21));
    expect(t.allDay, isFalse);
  });

  test('an all-day one ends the day after its last, as the calendar keeps it; its times stay for switching', () {
    final camp = CalendarEvent(title: '營會', start: _day, end: DateTime.utc(2026, 11, 8), allDay: true);
    final t = EventTimes.of(camp, initialDay: _day);
    expect(t.endDay, DateTime.utc(2026, 11, 7));
    expect(t.end, DateTime.utc(2026, 11, 8));
    expect(t.withAllDay(false).start, DateTime.utc(2026, 11, 6, 19, 30));
  });

  group('moving the start', () {
    final evening = EventTimes.of(
      CalendarEvent(title: '禱告會', start: DateTime.utc(2026, 11, 6, 19, 30), end: DateTime.utc(2026, 11, 6, 21)),
      initialDay: _day,
    );

    test('keeps its length', () {
      final t = evening.moveStart(_day, (hour: 20, minute: 0));
      expect(t.end, DateTime.utc(2026, 11, 6, 21, 30));
    });

    test('past midnight, the end goes to the next day', () {
      final t = evening.moveStart(_day, (hour: 23, minute: 0));
      expect(t.end, DateTime.utc(2026, 11, 7, 0, 30));
    });

    test('to another day, all day: as many days', () {
      final camp = EventTimes.of(
        CalendarEvent(title: '營會', start: _day, end: DateTime.utc(2026, 11, 9), allDay: true),
        initialDay: _day,
      );
      expect(camp.moveStart(DateTime.utc(2026, 11, 13), camp.startTime).endDay, DateTime.utc(2026, 11, 15));
    });
  });

  test('the end moved to the start day, not after the start, is an hour after it', () {
    final twoDays = EventTimes.of(
      CalendarEvent(title: '退修會', start: DateTime.utc(2026, 11, 6, 19), end: DateTime.utc(2026, 11, 7, 12)),
      initialDay: _day,
    );
    expect(twoDays.moveEndDay(_day).end, DateTime.utc(2026, 11, 6, 20));
  });

  group('the end time', () {
    final evening = EventTimes.of(null, initialDay: _day);

    test('within a day: the first such time after the start', () {
      expect(evening.setEndTime((hour: 1, minute: 0), withinDay: true).end, DateTime.utc(2026, 11, 7, 1));
      expect(evening.setEndTime((hour: 22, minute: 0), withinDay: true).end, DateTime.utc(2026, 11, 6, 22));
    });

    test('a longer one keeps its end day', () {
      final twoDays = evening.moveEndDay(DateTime.utc(2026, 11, 8));
      expect(twoDays.setEndTime((hour: 9, minute: 0), withinDay: false).end, DateTime.utc(2026, 11, 8, 9));
    });

    test('whether it is within a day', () {
      expect(evening.withinDay, isTrue);
      expect(evening.moveEndDay(DateTime.utc(2026, 11, 8)).withinDay, isFalse);
    });
  });
}
