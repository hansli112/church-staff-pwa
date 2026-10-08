import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/firebase/codec.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/event_roster.dart';
import 'package:martha/domain/models.dart';

void main() {
  group('the days, as calendarWrite works them out too (testdata/event_days.json)', () {
    final data = jsonDecode(File('../testdata/event_days.json').readAsStringSync()) as Map<String, dynamic>;
    for (final c in (data['cases'] as List).cast<Map<String, dynamic>>()) {
      test(c['name'] as String, () {
        final e = calendarEventFromJson({...c['event'] as Map<String, dynamic>, 'id': 'x', 'title': 't'})!;
        final days = eventDays(e);
        expect((days.first.key, days.last.key), (c['dateKey'], c['endDateKey']));
      });
    }
  });

  group('an event roster', () {
    test('takes a timed event’s days in UTC+8, wherever the phone is', () {
      final e = CalendarEvent(
        id: 'x1',
        title: '聖誕晚會',
        // 23:30–01:00 in Taipei: two days there, one day in UTC.
        start: DateTime.utc(2026, 12, 24, 15, 30),
        end: DateTime.utc(2026, 12, 24, 17),
      );
      final r = eventRoster(e);
      expect(r.id, 'ev_x1');
      expect(r.type, '');
      expect((r.day, r.lastDay), (Day(2026, 12, 24), Day(2026, 12, 25)));
      expect(r.forEvent!.title, '聖誕晚會');
      expect(r.saved, isFalse);
    });

    test('an event ending at midnight Taipei time does not reach the next day', () {
      final e = CalendarEvent(
        id: 'x2',
        title: '禱告會',
        start: DateTime.utc(2026, 12, 24, 11),
        end: DateTime.utc(2026, 12, 24, 16),
      );
      expect((eventRoster(e).day, eventRoster(e).lastDay), (Day(2026, 12, 24), Day(2026, 12, 24)));
    });

    test('takes an all-day event’s dates as they are, the end exclusive', () {
      final e = CalendarEvent(
        id: 'x3',
        title: '退修會',
        start: DateTime(2027, 1, 29),
        end: DateTime(2027, 2, 1),
        allDay: true,
      );
      final r = eventRoster(e, duties: const [Duty(role: '報到')]);
      expect((r.day, r.lastDay), (Day(2027, 1, 29), Day(2027, 1, 31)));
      expect(r.duties, const [Duty(role: '報到')]);
    });

    test('cuts a long title to 200 characters', () {
      final e = CalendarEvent(
        id: 'x4',
        title: '長' * 250,
        start: DateTime.utc(2026, 12, 24, 11),
        end: DateTime.utc(2026, 12, 24, 12),
      );
      expect(eventRoster(e).forEvent!.title.length, 200);
    });
  });
}
