import 'package:flutter/foundation.dart';

import 'day.dart';

/// 回報人數 (#85): with it on (Church.attendanceSince), the leads of each
/// group fill in how many came to its meetings, and whoever else it asks
/// to. A group is a service, a 小組 or a 其他聚會, by its key
/// (ChurchGroup.key); functions/src/attendance.ts reminds them, by the
/// same rules.

/// When a group meets. A service, unless its 聚會時間 says otherwise: on
/// its [weekday] when that day has a roster ([roster], whether it has);
/// with one from [startsOn], by its rosters before then.
/// Else on [weekday], every [every] weeks from [startsOn], a day it met;
/// or, with [monthWeeks], those weeks of each month (第 1、3 個週五), from
/// [startsOn] on.
@immutable
class Meets {
  const Meets({this.weekday, this.roster, this.every = 1, this.startsOn, this.monthWeeks = const []});

  final int? weekday;

  /// Null for one that meets with or without a roster.
  final bool? roster;
  final int every;
  final Day? startsOn;
  final List<int> monthWeeks;
}

/// Which [weekday] of its month [day] is: 1 for the first … 5 for a fifth.
int weekOfMonth(Day day) => (day.day - 1) ~/ 7 + 1;

/// 聚會時間 (回報人數): on [weekday] (1 = Monday … 7 = Sunday) every
/// [every] weeks (1 or 2) from [startsOn], a day it met; or, with
/// [monthWeeks] (1–4), those weeks of each month (第 1、3 個週五) from
/// [startsOn] on. A 小組's or a 其他聚會's; a service's when not by its
/// rosters, its [weekday] the service's.
@immutable
class MeetingTime {
  const MeetingTime({this.weekday, this.every = 1, this.startsOn, this.monthWeeks = const []});

  final int? weekday;
  final int every;
  final Day? startsOn;
  final List<int> monthWeeks;

  /// When it meets, for [attendanceDue]; [weekday] for a service's.
  Meets meets({int? weekday}) =>
      Meets(weekday: weekday ?? this.weekday, every: every, startsOn: startsOn, monthWeeks: monthWeeks);

  @override
  bool operator ==(Object other) =>
      other is MeetingTime &&
      other.weekday == weekday &&
      other.every == every &&
      other.startsOn == startsOn &&
      listEquals(other.monthWeeks, monthWeeks);

  @override
  int get hashCode => Object.hash(weekday, every, startsOn, Object.hashAll(monthWeeks));
}

/// A 其他聚會 (churches/{cid}/gatherings/{id}): a group whose 人數 are
/// asked for and nothing else, like 禱告會 or 長者共餐, by [time]; those
/// asked to fill them in are its [AttendanceRecord.fillers].
@immutable
class Gathering {
  const Gathering({required this.id, required this.name, this.time = const MeetingTime()});

  /// Empty for one not made yet.
  final String id;
  final String name;
  final MeetingTime time;

  Gathering copyWith({String? name, MeetingTime? time}) =>
      Gathering(id: id, name: name ?? this.name, time: time ?? this.time);

  @override
  bool operator ==(Object other) => other is Gathering && other.id == id && other.name == name && other.time == time;

  @override
  int get hashCode => Object.hash(id, name, time);
}

/// One of a group's pauses (暫停到某一天): no meeting is asked for from
/// [from] until, not including, [until]. Kept once over, so the weeks it
/// covered never turn 未填. Only older apps set them: a lead now marks
/// each meeting ahead 這次沒聚會 (upcomingAttendanceDays).
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
/// before [since] (回報人數 turned on), nor while one of [pauses] covers it
/// (testdata/church_rules.json, attendanceDue).
bool attendanceDue(
  Meets meets, {
  required Day since,
  List<AttendancePause> pauses = const [],
  required Day day,
}) {
  if (day.isBefore(since) || pauses.any((p) => p.covers(day))) return false;
  if (meets.weekday == null || day.weekday != meets.weekday) return false;
  final start = meets.startsOn;
  // A service by its rosters, or, on a 聚會時間 of its own, before it began.
  if (meets.roster != null && (start == null || day.isBefore(start))) return meets.roster!;
  if (start != null && day.isBefore(start)) return false;
  if (meets.monthWeeks.isNotEmpty) return meets.monthWeeks.contains(weekOfMonth(day));
  if (start == null) return meets.every != 2;
  return (start.daysUntil(day) ~/ 7) % (meets.every == 2 ? 2 : 1) == 0;
}

/// One meeting's 人數: [count] who came, with a [note]; or [none], 這次沒聚會;
/// or, a 小組 that met with another (聯合小組, #93), [withGroup], the key of
/// the one whose 人數 they are. The one filled in names the others it met
/// with, [together].
@immutable
class AttendanceDay {
  const AttendanceDay.count(int this.count, {this.note = '', this.together = const []})
    : none = false,
      withGroup = null;
  const AttendanceDay.none({this.together = const []}) : count = null, note = '', none = true, withGroup = null;
  const AttendanceDay.joined(String this.withGroup) : count = null, note = '', none = false, together = const [];

  final int? count;
  final String note;
  final bool none;
  final List<String> together;
  final String? withGroup;

  @override
  bool operator ==(Object other) =>
      other is AttendanceDay &&
      other.count == count &&
      other.note == note &&
      other.none == none &&
      other.withGroup == withGroup &&
      listEquals(other.together, together);

  @override
  int get hashCode => Object.hash(count, note, none, withGroup, Object.hashAll(together));
}

/// A group's 回報人數: its pauses, the 人數 of each meeting filled in, who
/// else fills them in ([fillers], uids: 誰填人數), and, a service, its
/// 聚會時間 when not by its rosters ([time]; every week was 每週都填人數,
/// #93).
@immutable
class AttendanceRecord {
  const AttendanceRecord({this.pauses = const [], this.days = const {}, this.time, this.fillers = const []});

  final List<AttendancePause> pauses;
  final Map<Day, AttendanceDay> days;
  final MeetingTime? time;
  final List<String> fillers;

  /// The pause [day] is in, if any.
  AttendancePause? pauseOn(Day day) => pauses.where((p) => p.covers(day)).firstOrNull;

  AttendanceRecord copyWith({
    List<AttendancePause>? pauses,
    Map<Day, AttendanceDay>? days,
    MeetingTime? Function()? time,
    List<String>? fillers,
  }) => AttendanceRecord(
    pauses: pauses ?? this.pauses,
    days: days ?? this.days,
    time: time == null ? this.time : time(),
    fillers: fillers ?? this.fillers,
  );

  @override
  bool operator ==(Object other) =>
      other is AttendanceRecord &&
      listEquals(other.pauses, pauses) &&
      mapEquals(other.days, days) &&
      other.time == time &&
      listEquals(other.fillers, fillers);

  @override
  int get hashCode => Object.hash(
    time,
    Object.hashAll(fillers),
    Object.hashAll(pauses),
    Object.hashAllUnordered(days.entries.map((e) => Object.hash(e.key, e.value))),
  );
}
