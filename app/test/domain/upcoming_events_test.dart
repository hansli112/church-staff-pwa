import 'package:flutter_test/flutter_test.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/domain/upcoming_events.dart';

CalendarEvent _event(String? id, String title, DateTime start, DateTime end) =>
    CalendarEvent(id: id, title: title, start: start, end: end);

void main() {
  final now = DateTime.utc(2026, 10, 30, 12);

  test('soonest first; one over two months is listed once', () {
    final retreat = _event('retreat', '退修會', DateTime(2026, 10, 31), DateTime(2026, 11, 2));
    final prayer = _event('prayer', '禱告會', DateTime(2026, 10, 30, 19), DateTime(2026, 10, 30, 21));
    final events = upcomingEvents([
      [retreat, prayer],
      [retreat],
    ], now: now);
    expect([for (final e in events) e.title], ['禱告會', '退修會']);
  });

  test('one under way stays; one over goes', () {
    final morning = _event('m', '晨禱', DateTime(2026, 10, 30, 6), DateTime(2026, 10, 30, 7));
    final camp = _event('c', '營會', DateTime(2026, 10, 29), DateTime(2026, 10, 31));
    expect(
      [
        for (final e in upcomingEvents([
          [morning, camp],
        ], now: now))
          e.title,
      ],
      ['營會'],
    );
  });

  test('one not saved yet, with no ID, is listed as it is', () {
    final a = _event(null, '新的', DateTime(2026, 11, 1), DateTime(2026, 11, 1, 1));
    final b = _event(null, '新的', DateTime(2026, 11, 1), DateTime(2026, 11, 1, 1));
    expect(
      upcomingEvents([
        [a],
        [b],
      ], now: now),
      hasLength(2),
    );
  });
}
