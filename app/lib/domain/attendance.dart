import 'package:flutter/foundation.dart';

import 'day.dart';

/// 回報人數 (#85): with it on (Church.attendanceSince), the leads of each
/// group fill in how many came to its meetings. A group is a service or a
/// 小組, by its key (ChurchGroup.key); functions/src/attendance.ts reminds
/// them, by the same rules.

/// When a group meets. A service: on its [weekday] when that day has a
/// roster ([roster], whether it has). A 小組: on [weekday], every [every]
/// weeks from [startsOn], a day it met.
@immutable
class Meets {
  const Meets({this.weekday, this.roster, this.every = 1, this.startsOn});

  final int? weekday;

  /// Null for a 小組, which meets with or without one.
  final bool? roster;
  final int every;
  final Day? startsOn;
}

/// A group's pause (暫停到某一天): no meeting is asked for from [from] until,
/// not including, [until].
@immutable
class AttendancePause {
  const AttendancePause({required this.from, required this.until});

  final Day from;
  final Day until;

  bool covers(Day day) => !day.isBefore(from) && day.isBefore(until);

  @override
  bool operator ==(Object other) => other is AttendancePause && other.from == from && other.until == until;

  @override
  int get hashCode => Object.hash(from, until);
}

/// Whether a group that [meets] so meets on [day] and is asked its 人數: not
/// before [since] (回報人數 turned on), nor while [pause] covers it
/// (testdata/church_rules.json, attendanceDue).
bool attendanceDue(Meets meets, {required Day since, AttendancePause? pause, required Day day}) {
  if (day.isBefore(since) || (pause?.covers(day) ?? false)) return false;
  if (meets.weekday == null || day.weekday != meets.weekday) return false;
  if (meets.roster != null) return meets.roster!;
  final start = meets.startsOn;
  if (start == null) return meets.every != 2;
  if (day.isBefore(start)) return false;
  return (start.daysUntil(day) ~/ 7) % (meets.every == 2 ? 2 : 1) == 0;
}

/// One meeting's 人數: [count] who came, with a [note]; or [none], 這次沒聚會.
@immutable
class AttendanceDay {
  const AttendanceDay.count(int this.count, {this.note = ''}) : none = false;
  const AttendanceDay.none() : count = null, note = '', none = true;

  final int? count;
  final String note;
  final bool none;

  @override
  bool operator ==(Object other) =>
      other is AttendanceDay && other.count == count && other.note == note && other.none == none;

  @override
  int get hashCode => Object.hash(count, note, none);
}

/// A group's 回報人數: its pause, and the 人數 of each meeting filled in.
@immutable
class AttendanceRecord {
  const AttendanceRecord({this.pause, this.days = const {}});

  final AttendancePause? pause;
  final Map<Day, AttendanceDay> days;

  @override
  bool operator ==(Object other) => other is AttendanceRecord && other.pause == pause && mapEquals(other.days, days);

  @override
  int get hashCode => Object.hash(pause, Object.hashAllUnordered(days.entries.map((e) => Object.hash(e.key, e.value))));
}
