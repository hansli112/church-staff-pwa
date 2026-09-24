import 'package:church_staff_pwa/features/calendar/presentation/layout/month_event_layout.dart';
import 'package:church_staff_pwa/features/calendar/domain/entities/calendar_event.dart';
import 'package:church_staff_pwa/features/calendar/presentation/widgets/_calendar_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where the bars go in a month grid, without pumping a single widget.
///
/// Every case is laid out in 2026/09, whose grid is:
///
///     Su Mo Tu We Th Fr Sa
///            1  2  3  4  5
///      6  7  8  9 10 11 12
///     ...
///     27 28 29 30
///
/// so the 1st sits under Tuesday with Sunday and Monday blank, and the 5th/6th
/// is the first week break.

final _september = DateTime(2026, 9);

/// An all-day event covering [firstDay]..[lastDay] inclusive. Google's end is
/// exclusive, so the stored end is the morning after [lastDay].
CalendarEvent _allDay(String id, DateTime firstDay, DateTime lastDay) =>
    CalendarEvent(
      id: id,
      startTime: firstDay,
      endTime: lastDay.add(const Duration(days: 1)),
      isAllDay: true,
      title: id,
    );

CalendarEvent _timed(String id, DateTime start, DateTime end) => CalendarEvent(
  id: id,
  startTime: start,
  endTime: end,
  isAllDay: false,
  title: id,
);

DateTime _sep(int day) => DateTime(2026, 9, day);

/// What one cell shows for one event, in the terms a test cares about.
class _Bar {
  final int lane;
  final bool title;
  final bool left;
  final bool right;
  final int shift;

  const _Bar({
    required this.lane,
    this.title = false,
    this.left = false,
    this.right = false,
    this.shift = 0,
  });

  factory _Bar.of(DayEventSegment s) => _Bar(
    lane: s.lane,
    title: s.showTitle,
    left: s.continuesLeft,
    right: s.continuesRight,
    shift: s.titleShiftDays,
  );

  @override
  bool operator ==(Object other) =>
      other is _Bar &&
      other.lane == lane &&
      other.title == title &&
      other.left == left &&
      other.right == right &&
      other.shift == shift;

  @override
  int get hashCode => Object.hash(lane, title, left, right, shift);

  @override
  String toString() =>
      '_Bar(lane: $lane, title: $title, left: $left, right: $right, '
      'shift: $shift)';
}

/// Every bar in the month, as `{day: {eventId: bar}}`, days without bars left
/// out — so an expectation also proves nothing was drawn anywhere else.
Map<int, Map<String, _Bar>> _barsByDay(List<CalendarEvent> events) {
  final layout = MonthEventLayout.compute(_september, events);
  final result = <int, Map<String, _Bar>>{};
  for (var day = 1; day <= 30; day++) {
    final segments = layout.segmentsOn(_sep(day));
    if (segments.isEmpty) continue;
    result[day] = {for (final s in segments) s.event.id: _Bar.of(s)};
  }
  return result;
}

typedef _Case = ({
  String name,
  List<CalendarEvent> events,
  Map<int, Map<String, _Bar>> expected,
});

void main() {
  group('MonthEventLayout.weekRowsFor', () {
    final cases = <(DateTime, int, String)>[
      (DateTime(2026, 2), 4, '28 days starting on a Sunday'),
      (DateTime(2026, 9), 5, 'starts on a Tuesday'),
      (DateTime(2026, 8), 6, '31 days starting on a Saturday'),
    ];
    for (final (month, rows, why) in cases) {
      test('${month.year}/${month.month} has $rows rows ($why)', () {
        expect(MonthEventLayout.weekRowsFor(month), rows);
      });
    }
  });

  group('MonthEventLayout.compute', () {
    final cases = <_Case>[
      (
        name: 'a one-day event is one titled bar',
        events: [_allDay('a', _sep(15), _sep(15))],
        expected: {
          15: {'a': _Bar(lane: 0, title: true)},
        },
      ),
      (
        // The start day is in August, off this grid, so the title goes on the
        // first day the user can actually see.
        name: 'an event from last month is labelled on the 1st',
        events: [_allDay('a', DateTime(2026, 8, 30), _sep(2))],
        expected: {
          1: {'a': _Bar(lane: 0, title: true, right: true)},
          2: {'a': _Bar(lane: 0, left: true, shift: 1)},
        },
      ),
      (
        name: 'an event running into next month stops at the 30th',
        events: [_allDay('a', _sep(29), DateTime(2026, 10, 2))],
        expected: {
          29: {'a': _Bar(lane: 0, title: true, right: true)},
          30: {'a': _Bar(lane: 0, left: true, shift: 1)},
        },
      ),
      (
        // Saturday to Monday: the bar breaks at the row end and restarts on
        // Sunday, and only the very first cell carries the title.
        name: 'a multi-week event splits at the week boundary',
        events: [_allDay('a', _sep(5), _sep(7))],
        expected: {
          5: {'a': _Bar(lane: 0, title: true)},
          6: {'a': _Bar(lane: 0, right: true)},
          7: {'a': _Bar(lane: 0, left: true, shift: 1)},
        },
      ),
      (
        // b sits beside a, not under it — a's lane is free again by Thursday.
        name: 'a lane is reused once the earlier bar has ended',
        events: [
          _allDay('a', _sep(7), _sep(8)),
          _allDay('b', _sep(10), _sep(10)),
        ],
        expected: {
          7: {'a': _Bar(lane: 0, title: true, right: true)},
          8: {'a': _Bar(lane: 0, left: true, shift: 1)},
          10: {'b': _Bar(lane: 0, title: true)},
        },
      ),
      (
        name: 'overlapping bars stack into separate lanes',
        events: [
          _allDay('a', _sep(7), _sep(9)),
          _allDay('b', _sep(8), _sep(8)),
        ],
        expected: {
          7: {'a': _Bar(lane: 0, title: true, right: true)},
          8: {
            'a': _Bar(lane: 0, left: true, right: true, shift: 1),
            'b': _Bar(lane: 1, title: true),
          },
          9: {'a': _Bar(lane: 0, left: true, shift: 2)},
        },
      ),
      (
        // Same start day: the longer bar takes the top lane even though the
        // short one starts earlier in the day, so the long one stays unbroken.
        name: 'of two bars starting the same day the longer goes on top',
        events: [
          _timed('short', DateTime(2026, 9, 14, 9), DateTime(2026, 9, 14, 10)),
          _timed('long', DateTime(2026, 9, 14, 10), DateTime(2026, 9, 16, 12)),
        ],
        expected: {
          14: {
            'long': _Bar(lane: 0, title: true, right: true),
            'short': _Bar(lane: 1, title: true),
          },
          15: {'long': _Bar(lane: 0, left: true, right: true, shift: 1)},
          16: {'long': _Bar(lane: 0, left: true, shift: 2)},
        },
      ),
      (
        // Belt and braces: a bucket can hold an event that does not touch the
        // month at all (a stale cache, a wide fetch window). It draws nothing.
        name: 'an event outside the month draws nothing',
        events: [_allDay('a', DateTime(2026, 10, 1), DateTime(2026, 10, 1))],
        expected: {},
      ),
      (
        name: 'a timed event at 00:30 on the 1st is on the 1st',
        events: [
          _timed('a', DateTime(2026, 9, 1, 0, 30), DateTime(2026, 9, 1, 1, 30)),
        ],
        expected: {
          1: {'a': _Bar(lane: 0, title: true)},
        },
      ),
    ];

    for (final c in cases) {
      test(c.name, () {
        expect(_barsByDay(c.events), c.expected);
      });
    }

    test('each day lists its bars top lane first', () {
      final layout = MonthEventLayout.compute(_september, [
        _allDay('a', _sep(7), _sep(9)),
        _allDay('b', _sep(8), _sep(8)),
        _allDay('c', _sep(9), _sep(9)),
      ]);

      for (final day in [7, 8, 9]) {
        final lanes = layout.segmentsOn(_sep(day)).map((s) => s.lane).toList();
        expect(lanes, [...lanes]..sort(), reason: '9/$day');
      }
    });
  });
}
