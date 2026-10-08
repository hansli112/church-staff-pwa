import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/firebase/codec.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/event_roster.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/domain/staff_order.dart';

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

  group('arranging an event', () {
    const sunday = Service(id: 'sunday', name: '主日崇拜', weekday: 7, duties: ['司會', '司琴', '招待']);
    const youth = Service(id: 'youth', name: '青年崇拜', weekday: 6, duties: ['司琴', '音控']);

    test('offers every duty the services use, each once, in their order', () {
      expect(eventDutySuggestions(const [sunday, youth]), ['司會', '司琴', '招待', '音控']);
    });

    test('a member serves a duty there when any 牧區 of theirs has it', () {
      const m = Member(
        uid: 'a',
        name: '小明',
        zones: [
          Zone(serviceType: 'youth', duties: ['音控']),
        ],
      );
      expect(servesAnywhere(m, '音控'), isTrue);
      expect(servesAnywhere(m, '司琴'), isFalse);
    });

    test('the staff order of the first service ranking the duty', () {
      final order = eventStaffOrder(
        const [sunday, youth],
        {
          'sunday': StaffOrder({
            '司琴': ['美玉', '志豪'],
          }),
          'youth': StaffOrder({
            '司琴': ['志豪', '小華'],
            '音控': ['小華'],
          }),
        },
      );
      expect(order.rankingOf('司琴'), ['美玉', '志豪']);
      expect(order.rankingOf('音控'), ['小華']);
      expect(order.rankingOf('招待'), isEmpty);
    });
  });

  group('a day of a recurring event', () {
    Roster day(String id, String series, Day d, List<String> roles) => Roster(
      type: '',
      day: d,
      duties: [for (final r in roles) Duty(role: r)],
      forEvent: RosterEvent(eventId: id, title: '禱告會', lastDay: d, recurringEventId: series),
    );
    final next = CalendarEvent(
      id: 'pray_20261224',
      title: '禱告會',
      start: DateTime.utc(2026, 12, 24, 11),
      end: DateTime.utc(2026, 12, 24, 12),
      recurringEventId: 'pray_R20261201',
    );

    test('starts with the duties of the latest earlier day of its series, split or not', () {
      final rosters = [
        day('pray_20261029', 'pray', Day(2026, 10, 29), ['領禱']),
        day('pray_20261126', 'pray', Day(2026, 11, 26), ['領禱', '司琴']),
        day('pray_20261231', 'pray_R20261201', Day(2026, 12, 31), ['之後的']),
        day('other_1', 'other', Day(2026, 12, 1), ['別的']),
      ];
      expect(previousInSeries(next, rosters), ['領禱', '司琴']);
    });

    test('a one-off event starts empty', () {
      final once = CalendarEvent(
        id: 'x',
        title: 'x',
        start: DateTime.utc(2026, 12, 24),
        end: DateTime.utc(2026, 12, 25),
      );
      expect(
        previousInSeries(once, [
          day('a', 'a', Day(2026, 1, 1), ['領禱']),
        ]),
        isEmpty,
      );
    });
  });
}
