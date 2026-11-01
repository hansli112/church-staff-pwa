import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/day.dart';
import '../domain/models.dart';
import 'providers.dart';

/// 回報人數 (#85): which meetings ask for their 人數, and what was filled in.

/// How far back a group's page lists its meetings.
const attendanceWeeks = 12;

/// Group [key]'s pauses and 人數 filled in.
final attendanceProvider = StreamProvider.autoDispose.family<AttendanceRecord, String>(
  (ref, key) => openChurch(ref).attendance.watch(key),
);

/// Rosters from [attendanceWeeks] back on: which days a service met.
final _recentRostersProvider = StreamProvider.autoDispose<List<Roster>>((ref) {
  final today = ref.watch(todayProvider);
  return openChurch(ref).rosters(from: today.addDays(-7 * attendanceWeeks));
});

/// A group 回報人數 is about: a service or a 小組 (with its service), its
/// name, and when it meets.
typedef AttendanceGroup = ({ChurchGroup group, String name, Meets Function(Day day) meetsOn});

/// The groups of the church that meet (its services and 小組), as
/// [AttendanceGroup]s; a service meets on its weekday when that day has a
/// roster.
final attendanceGroupsProvider = Provider.autoDispose<List<AttendanceGroup>>((ref) {
  final services = ref.watch(servicesProvider).value?.enabled ?? const <Service>[];
  final smallGroups = ref.watch(smallGroupsProvider).value ?? const <SmallGroupDetails>[];
  final rosters = ref.watch(_recentRostersProvider).value ?? const <Roster>[];
  final held = {
    for (final r in rosters)
      if (!r.isEvent) (r.type, r.day),
  };
  return [
    for (final s in services)
      (
        group: ServiceGroup(s.id),
        name: s.name,
        meetsOn: (Day day) => Meets(weekday: s.weekday, roster: held.contains((s.id, day))),
      ),
    for (final g in smallGroups) (group: g.group, name: g.name, meetsOn: (Day _) => g.meets),
  ];
});

/// The meetings of [group] from [attendanceWeeks] back to today that ask
/// for their 人數, newest first: none with 回報人數 off. Days [record] has
/// 人數 for are listed too, though the group no longer meets on them. A
/// service filled in every week ([AttendanceRecord.everyWeek], #93) meets
/// on its weekday, roster or not.
List<Day> attendanceDays(
  AttendanceGroup group, {
  required Day? since,
  AttendanceRecord record = const AttendanceRecord(),
  required Day today,
}) {
  if (since == null) return const [];
  final from = today.addDays(-7 * attendanceWeeks);
  Meets meetsOn(Day d) => switch (group.meetsOn(d)) {
    Meets(:final weekday, roster: _?) when record.everyWeek => Meets(weekday: weekday),
    final meets => meets,
  };
  return [
    for (var d = today; !d.isBefore(from); d = d.addDays(-1))
      if (record.days.containsKey(d) || attendanceDue(meetsOn(d), since: since, pauses: record.pauses, day: d)) d,
  ];
}

/// A meeting that waits for its 人數 on 首頁, for one who leads its group:
/// the latest one, until the next comes (首頁顯示「填寫人數」到下一次聚會為止).
typedef AttendanceDue = ({AttendanceGroup group, Day day});

/// Every [AttendanceDue] of the groups I am reminded of
/// (Member.remindedAttendance), for 首頁.
final attendanceDueProvider = Provider.autoDispose<List<AttendanceDue>>((ref) {
  final since = ref.watch(churchProvider.select((c) => c.value?.attendanceSince));
  final me = ref.watch(meProvider).value;
  if (since == null || me == null) return const [];
  final today = ref.watch(todayProvider);
  final mine = me.remindedAttendance.toSet();
  // Nobody else reads the weeks of rosters it takes.
  if (mine.isEmpty) return const [];
  return [
    for (final g in ref.watch(attendanceGroupsProvider))
      if (mine.contains(g.group.key))
        if (ref.watch(attendanceProvider(g.group.key)).value case final record?)
          // The latest it met, not a day filled in it no longer meets on.
          if (attendanceDays(
                g,
                since: since,
                record: AttendanceRecord(pauses: record.pauses, everyWeek: record.everyWeek),
                today: today,
              ).firstOrNull
              case final day? when !record.days.containsKey(day))
            (group: g, day: day),
  ];
});

/// A row of 人數總覽 (#93): a group's latest meeting, and what it has (null: 未填).
typedef AttendanceLatest = ({AttendanceGroup group, Day day, AttendanceDay? value});

/// 人數總覽 (#93), for admins and 行政 (Member.overseesAttendance): each
/// group's latest meeting, today's once filled in, oldest first, a day's
/// services before its 小組; none for a group paused today, nor for one
/// that has not met yet. Null until every group's 人數 are read.
final attendanceOverviewProvider = Provider.autoDispose<List<AttendanceLatest>?>((ref) {
  final since = ref.watch(churchProvider.select((c) => c.value?.attendanceSince));
  final me = ref.watch(meProvider).value;
  if (since == null || me == null || !me.overseesAttendance) return const [];
  final today = ref.watch(todayProvider);
  final rows = <AttendanceLatest>[];
  var read = true;
  for (final g in ref.watch(attendanceGroupsProvider)) {
    final record = ref.watch(attendanceProvider(g.group.key)).value;
    if (record == null) {
      read = false;
      continue;
    }
    if (record.pauseOn(today) != null) continue;
    final days = attendanceDays(g, since: since, record: record, today: today);
    if (days.where((d) => d != today || record.days.containsKey(d)).firstOrNull case final day?) {
      rows.add((group: g, day: day, value: record.days[day]));
    }
  }
  if (!read) return null;
  int kind(AttendanceLatest r) => r.group.group is ServiceGroup ? 0 : 1;
  return rows..sort(
    (a, b) => switch (a.day.compareTo(b.day)) {
      0 => switch (kind(a) - kind(b)) {
        0 => a.group.name.compareTo(b.group.name),
        final k => k,
      },
      final c => c,
    },
  );
});
