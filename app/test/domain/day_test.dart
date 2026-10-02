import 'package:flutter_test/flutter_test.dart';
import 'package:martha/domain/day.dart';

void main() {
  test('round-trips its key', () {
    expect(Day.parse('2026-10-04').key, '2026-10-04');
    expect(Day(2026, 1, 5).key, '2026-01-05');
  });

  test('rejects malformed and impossible dates', () {
    expect(() => Day.parse('2026-2-3'), throwsFormatException);
    expect(() => Day.parse('2026-02-30'), throwsFormatException);
    expect(Day.tryParse('nope'), isNull);
  });

  test('adds days across month and year ends', () {
    expect(Day(2026, 12, 29).addDays(7).key, '2027-01-05');
    expect(Day(2028, 2, 28).addDays(1).key, '2028-02-29');
  });

  test('finds week start and next weekday', () {
    final thursday = Day(2026, 10, 1);
    expect(thursday.weekday, DateTime.thursday);
    expect(thursday.weekStart.key, '2026-09-28');
    expect(thursday.nextOnOrAfter(DateTime.sunday).key, '2026-10-04');
    expect(thursday.nextOnOrAfter(DateTime.thursday), thursday);
  });

  test('orders chronologically', () {
    final days = [Day(2026, 3, 1), Day(2025, 12, 31), Day(2026, 1, 1)]..sort();
    expect(days.map((d) => d.key), ['2025-12-31', '2026-01-01', '2026-03-01']);
  });
}
