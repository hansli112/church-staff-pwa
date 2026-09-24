import 'package:flutter/material.dart' show DateUtils;

import '../../domain/entities/calendar_event.dart';
import '../widgets/_calendar_models.dart';

/// Where every event bar goes in one month's grid.
///
/// Pure on purpose: no widgets, no provider, just the month and its events in,
/// the per-day bars out. The screen caches the result per month because it is
/// O(events × days) and the PageView keeps three months on the tree at once.
///
/// The grid is Sunday-first, one row per week the month touches. Days outside
/// the month are left blank, so an event that runs across a month boundary is
/// drawn only on the days that belong to this month, and its title goes on the
/// first of those — not on a start day the user cannot see.
class MonthEventLayout {
  final Map<int, List<DayEventSegment>> _segmentsByDay;

  const MonthEventLayout._(this._segmentsByDay);

  /// How many week rows [month] occupies: the blanks before the 1st plus its
  /// days, rounded up to whole weeks. Four for a February that starts on a
  /// Sunday, six for a month like 2026/08.
  static int weekRowsFor(DateTime month) {
    final startOffset = DateTime(month.year, month.month, 1).weekday % 7;
    final totalDays = DateUtils.getDaysInMonth(month.year, month.month);
    return ((startOffset + totalDays) / 7).ceil();
  }

  /// The bars drawn in [day]'s cell, top lane first.
  List<DayEventSegment> segmentsOn(DateTime day) =>
      _segmentsByDay[_dayKey(day)] ?? const <DayEventSegment>[];

  static int _dayKey(DateTime date) =>
      (date.year * 10000) + (date.month * 100) + date.day;

  factory MonthEventLayout.compute(
    DateTime month,
    Iterable<CalendarEvent> events,
  ) {
    final year = month.year;
    final monthValue = month.month;
    final firstDay = DateTime(year, monthValue, 1);
    final totalDays = DateUtils.getDaysInMonth(year, monthValue);
    final monthStart = DateUtils.dateOnly(firstDay);
    final monthEnd = DateUtils.dateOnly(DateTime(year, monthValue, totalDays));
    final overlappingEvents =
        events
            .where((event) => !event.endDay.isBefore(monthStart))
            .where((event) => !event.startDay.isAfter(monthEnd))
            .toList()
          ..sort((a, b) {
            final byStart = a.startTime.compareTo(b.startTime);
            if (byStart != 0) return byStart;
            return a.title.compareTo(b.title);
          });

    final firstLabelDayByEvent = <String, DateTime>{};
    for (final event in overlappingEvents) {
      final firstVisible = event.startDay.isBefore(monthStart)
          ? monthStart
          : event.startDay;
      firstLabelDayByEvent[event.identity] = firstVisible;
    }

    final result = <int, List<DayEventSegment>>{};
    final firstWeekOffset = firstDay.weekday % 7;
    final weekCount = weekRowsFor(firstDay);

    for (var week = 0; week < weekCount; week++) {
      final weekDays = List<DateTime?>.generate(7, (weekday) {
        final dayNumber = week * 7 + weekday - firstWeekOffset + 1;
        if (dayNumber < 1 || dayNumber > totalDays) return null;
        return DateUtils.dateOnly(DateTime(year, monthValue, dayNumber));
      });

      final weekSegments = <WeekEventSegment>[];
      for (final event in overlappingEvents) {
        int? startIndex;
        int? endIndex;
        for (var i = 0; i < 7; i++) {
          final day = weekDays[i];
          if (day == null || !event.occursOnDate(day)) continue;
          startIndex ??= i;
          endIndex = i;
        }
        if (startIndex == null || endIndex == null) continue;
        weekSegments.add(
          WeekEventSegment(
            event: event,
            startIndex: startIndex,
            endIndex: endIndex,
          ),
        );
      }

      // Lanes are per week: a bar that ended on Tuesday frees its lane for
      // anything starting later that week, and the next week starts over.
      // Longer bars first among those starting the same day, so they claim the
      // top lanes and the short ones stack underneath rather than splitting
      // them.
      final laneOccupancy = <List<bool>>[];
      weekSegments.sort((a, b) {
        final byStart = a.startIndex.compareTo(b.startIndex);
        if (byStart != 0) return byStart;
        final byEnd = b.endIndex.compareTo(a.endIndex);
        if (byEnd != 0) return byEnd;
        return a.event.startTime.compareTo(b.event.startTime);
      });

      for (final segment in weekSegments) {
        final segmentStartDay = weekDays[segment.startIndex];
        final segmentStartPrevDay = segment.startIndex > 0
            ? weekDays[segment.startIndex - 1]
            : null;
        final segmentStartsFromPreviousDay =
            segmentStartDay != null &&
            segmentStartPrevDay != null &&
            segment.event.occursOnDate(segmentStartPrevDay);
        final startLeadingInset = segmentStartsFromPreviousDay ? 0.0 : 2.0;
        final startTextInset =
            startLeadingInset + (segmentStartsFromPreviousDay ? 0.0 : 1.0);

        var lane = 0;
        while (true) {
          if (lane == laneOccupancy.length) {
            laneOccupancy.add(List<bool>.filled(7, false));
          }
          final occupied = laneOccupancy[lane];
          final hasConflict = occupied
              .sublist(segment.startIndex, segment.endIndex + 1)
              .any((value) => value);
          if (!hasConflict) break;
          lane++;
        }

        for (var i = segment.startIndex; i <= segment.endIndex; i++) {
          laneOccupancy[lane][i] = true;
          final day = weekDays[i];
          if (day == null) continue;
          final dayKey = _dayKey(day);
          result.putIfAbsent(dayKey, () => []);
          final previousDay = i > 0 ? weekDays[i - 1] : null;
          final nextDay = i < 6 ? weekDays[i + 1] : null;
          result[dayKey]!.add(
            DayEventSegment(
              event: segment.event,
              lane: lane,
              showTitle: DateUtils.isSameDay(
                day,
                firstLabelDayByEvent[segment.event.identity],
              ),
              titleShiftDays: i - segment.startIndex,
              startTextInset: startTextInset,
              continuesLeft:
                  previousDay != null &&
                  segment.event.occursOnDate(previousDay),
              continuesRight:
                  nextDay != null && segment.event.occursOnDate(nextDay),
            ),
          );
        }
      }
    }

    for (final segments in result.values) {
      segments.sort((a, b) => a.lane.compareTo(b.lane));
    }
    return MonthEventLayout._(result);
  }
}
