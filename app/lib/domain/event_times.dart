import 'package:flutter/foundation.dart';

import 'models.dart';

/// A time of day, on the church's clock.
typedef ClockTime = ({int hour, int minute});

/// When an event being edited is (the calendar's event editor): its first
/// and last day, both included, and its times when not all day. An
/// all-day event keeps the usual times, for when it is switched to one
/// with times. Each change keeps the end after the start.
@immutable
class EventTimes {
  const EventTimes({
    required this.startDay,
    required this.endDay,
    required this.startTime,
    required this.endTime,
    required this.allDay,
  });

  /// [event]'s, or a new one's on [initialDay]: 19:30 to 21:00.
  factory EventTimes.of(CalendarEvent? event, {required DateTime initialDay}) {
    const evening = (hour: 19, minute: 30), late = (hour: 21, minute: 0);
    final timed = event != null && !event.allDay;
    return EventTimes(
      startDay: _dateOf(event?.start ?? initialDay),
      endDay: switch (event) {
        null => _dateOf(initialDay),
        final e when e.allDay => e.lastDay.midnight,
        final e => _dateOf(e.end),
      },
      startTime: timed ? _timeOf(event.start) : evening,
      endTime: timed ? _timeOf(event.end) : late,
      allDay: event?.allDay ?? false,
    );
  }

  final DateTime startDay;
  final DateTime endDay;
  final ClockTime startTime;
  final ClockTime endTime;
  final bool allDay;

  static DateTime _dateOf(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  static ClockTime _timeOf(DateTime d) => (hour: d.hour, minute: d.minute);

  static DateTime _at(DateTime day, ClockTime t) => DateTime.utc(day.year, day.month, day.day, t.hour, t.minute);

  DateTime get start => allDay ? startDay : _at(startDay, startTime);

  /// Exclusive, as the calendar keeps it: the day after the last for an
  /// all-day event.
  DateTime get end => allDay ? DateTime.utc(endDay.year, endDay.month, endDay.day + 1) : _at(endDay, endTime);

  /// Always true from the pickers, which offer no end before the start.
  bool get valid => end.isAfter(start);

  /// Whether it is under a day long: then its end time picks its day by
  /// the start ([setEndTime]).
  bool get withinDay => end.difference(start) < const Duration(days: 1);

  EventTimes _with({DateTime? startDay, DateTime? endDay, ClockTime? startTime, ClockTime? endTime, bool? allDay}) =>
      EventTimes(
        startDay: startDay ?? this.startDay,
        endDay: endDay ?? this.endDay,
        startTime: startTime ?? this.startTime,
        endTime: endTime ?? this.endTime,
        allDay: allDay ?? this.allDay,
      );

  EventTimes withAllDay(bool allDay) => _with(allDay: allDay);

  /// The start moved to [time] on [day]; the end moves with it, so the
  /// event keeps its length: all day, as many days; else as long, or an
  /// hour when it was not after its start.
  EventTimes moveStart(DateTime day, ClockTime time) {
    if (allDay) {
      final days = endDay.difference(startDay).inDays;
      return _with(
        startDay: _dateOf(day),
        startTime: time,
        endDay: DateTime.utc(day.year, day.month, day.day + (days < 0 ? 0 : days)),
      );
    }
    final length = _at(endDay, endTime).difference(_at(startDay, startTime));
    final end = _at(day, time).add(length > Duration.zero ? length : const Duration(hours: 1));
    return _with(startDay: _dateOf(day), startTime: time, endDay: _dateOf(end), endTime: _timeOf(end));
  }

  /// The end moved to [day]. On the start day an end time not after the
  /// start becomes an hour after it.
  EventTimes moveEndDay(DateTime day) {
    if (allDay || _at(day, endTime).isAfter(start)) return _with(endDay: _dateOf(day));
    final end = start.add(const Duration(hours: 1));
    return _with(endDay: _dateOf(end), endTime: _timeOf(end));
  }

  /// The end time set to [time]. [withinDay], as the event was when its
  /// end's wheels opened: the end is the first such time after the start,
  /// the next day for one not after the start time. Else it keeps its end
  /// day.
  EventTimes setEndTime(ClockTime time, {required bool withinDay}) {
    if (!withinDay) return _with(endTime: time);
    final sameDay = _at(startDay, time).isAfter(start);
    return _with(
      endTime: time,
      endDay: sameDay ? startDay : DateTime.utc(startDay.year, startDay.month, startDay.day + 1),
    );
  }
}
