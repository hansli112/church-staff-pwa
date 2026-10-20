import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/day.dart';
import '../domain/models.dart';
import 'providers.dart';

/// 回報人數 (#85): which meetings ask for their 人數, and what was filled in.

/// How far back a group's page lists its meetings.
const attendanceWeeks = 12;

/// Group [key]'s pauses and 人數 filled in.
final attendanceProvider = StreamProvider.autoDispose.family<AttendanceRecord, String>(
  (ref, key) => openChurch(ref).attendance(key),
);

/// Rosters from [attendanceWeeks] back on: which days a service met.
final _recentRostersProvider = StreamProvider.autoDispose<List<Roster>>((ref) {
  final today = ref.watch(todayProvider);
  return openChurch(ref).rosters(from: today.addDays(-7 * attendanceWeeks));
});

/// A group 回報人數 is about: a service or a 小組, its name, and when it meets.
typedef AttendanceGroup = ({String key, String name, String? smallGroupService, Meets Function(Day day) meetsOn});

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
        key: ServiceGroup(s.id).key,
        name: s.name,
        smallGroupService: null,
        meetsOn: (Day day) => Meets(weekday: s.weekday, roster: held.contains((s.id, day))),
      ),
    for (final g in smallGroups)
      (key: g.group.key, name: g.name, smallGroupService: g.service, meetsOn: (Day _) => g.meets),
  ];
});

/// The meetings of [group] from [attendanceWeeks] back to today that ask
/// for their 人數, newest first: none with 回報人數 off. [filled] (days with
/// 人數) are listed too, though the group no longer meets on them.
List<Day> attendanceDays(
  AttendanceGroup group, {
  required Day? since,
  List<AttendancePause> pauses = const [],
  Iterable<Day> filled = const [],
  required Day today,
}) {
  if (since == null) return const [];
  final from = today.addDays(-7 * attendanceWeeks);
  final kept = {
    for (final d in filled)
      if (!d.isBefore(from) && !d.isAfter(today)) d,
  };
  return [
    for (var d = today; !d.isBefore(from); d = d.addDays(-1))
      if (kept.contains(d) || attendanceDue(group.meetsOn(d), since: since, pauses: pauses, day: d)) d,
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
      if (mine.contains(g.key))
        if (ref.watch(attendanceProvider(g.key)).value case final record?)
          if (attendanceDays(g, since: since, pauses: record.pauses, today: today).firstOrNull case final day?
              when !record.days.containsKey(day))
            (group: g, day: day),
  ];
});
