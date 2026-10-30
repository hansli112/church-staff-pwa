import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/firebase/codec.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/event_roster.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/domain/staff_order.dart';

void main() {
  final lives = jsonDecode(File('../testdata/event_rosters.json').readAsStringSync()) as Map<String, dynamic>;

  group("what an event's roster does when its event changes in the app (testdata/event_rosters.json)", () {
    final rows = (lives['fates'] as List).cast<Map<String, dynamic>>().where((r) => r['by'] == 'app');
    Roster? roster(String state) => switch (state) {
      'none' => null,
      _ => Roster(
        type: '',
        day: Day(2030, 12, 24),
        forEvent: RosterEvent(
          eventId: 'e1',
          title: '聖誕晚會',
          lastDay: Day(2030, 12, 24),
          cancelled: state == 'cancelled',
        ),
      ),
    };
    for (final r in rows) {
      test(r['why'] as String, () {
        expect(
          eventRosterFate(EventChange.values.byName(r['change'] as String), roster(r['roster'] as String)).name,
          r['fate'],
        );
      });
    }
  });

  group('what the app may write over a roster (testdata/event_rosters.json, which firestore.rules runs too)', () {
    Roster? doc(Object? d) => d == null
        ? null
        : rosterFromJson({
            ...d as Map<String, dynamic>,
            if (d['cancelledAt'] == true) 'cancelledAt': DateTime(2030),
          });
    for (final r in (lives['appWrites'] as List).cast<Map<String, dynamic>>()) {
      test(r['why'] as String, () {
        expect(appMayWriteRoster(doc(r['saved']), doc(r['next'])!), r['may']);
      });
    }
  });

  group('the days, as calendarWrite works them out too (testdata/event_days.json)', () {
    final data = jsonDecode(File('../testdata/event_days.json').readAsStringSync()) as Map<String, dynamic>;
    for (final c in (data['cases'] as List).cast<Map<String, dynamic>>()) {
      test(c['name'] as String, () {
        final timeZone = ChurchTimeZone.of(c['timeZone'] as String?);
        // As the backend sends them: on the church's clock, with its offset.
        String sent(String t) {
          if (!t.contains('T')) return t;
          final at = DateTime.parse(t);
          final o = timeZone.offsetAt(at);
          final hh = o.inHours.abs().toString().padLeft(2, '0');
          final mm = (o.inMinutes.abs() % 60).toString().padLeft(2, '0');
          return '${timeZone.clock(at).toIso8601String().substring(0, 19)}${o.isNegative ? '-' : '+'}$hh:$mm';
        }

        final event = c['event'] as Map<String, dynamic>;
        final e = calendarEventFromJson({
          ...event,
          'start': sent(event['start'] as String),
          'end': sent(event['end'] as String),
          'id': 'x',
          'title': 't',
        })!;
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
        start: DateTime.utc(2026, 12, 24, 23, 30),
        end: DateTime.utc(2026, 12, 25, 1),
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
