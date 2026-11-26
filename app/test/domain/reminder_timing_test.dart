import 'package:flutter_test/flutter_test.dart';
import 'package:martha/domain/models.dart';

void main() {
  test('weekly and days before are two choices that can both be on', () {
    expect(ReminderTiming.weekly.onMonday, isTrue);
    expect(ReminderTiming.weekly.daysBefore, isFalse);
    expect(ReminderTiming.dayBefore.onMonday, isFalse);
    expect(ReminderTiming.dayBefore.daysBefore, isTrue);
    expect(ReminderTiming.both.onMonday && ReminderTiming.both.daysBefore, isTrue);

    expect(ReminderTiming.weekly.turned(daysBefore: true), ReminderTiming.both);
    expect(ReminderTiming.both.turned(onMonday: false), ReminderTiming.dayBefore);
    expect(ReminderTiming.both.turned(daysBefore: false), ReminderTiming.weekly);
    expect(ReminderTiming.dayBefore.turned(onMonday: true), ReminderTiming.both);
  });

  test('the last one on stays on: turning it off is no choice', () {
    expect(ReminderTiming.weekly.turned(onMonday: false), isNull);
    expect(ReminderTiming.dayBefore.turned(daysBefore: false), isNull);
  });

  test('days before: 1 to 14, whole days', () {
    expect(ReminderDays.valid(1), isTrue);
    expect(ReminderDays.valid(14), isTrue);
    expect(ReminderDays.valid(0), isFalse);
    expect(ReminderDays.valid(15), isFalse);
    expect(ReminderDays.valid('3'), isFalse);
    expect(ReminderDays.parse(' 3 '), 3);
    expect(ReminderDays.parse(''), isNull);
    expect(ReminderDays.parse('20'), isNull);
  });
}
