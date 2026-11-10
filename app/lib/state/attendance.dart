import 'package:flutter/foundation.dart';
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
  return [
    for (var d = today; !d.isBefore(from); d = d.addDays(-1))
      if (record.days.containsKey(d) || _due(group, since: since, record: record, day: d)) d,
  ];
}

/// Whether [group] meets on [day] and asks for its 人數 then.
bool _due(AttendanceGroup group, {required Day since, required AttendanceRecord record, required Day day}) =>
    attendanceDue(
      switch (group.meetsOn(day)) {
        Meets(:final weekday, roster: _?) when record.everyWeek => Meets(weekday: weekday),
        final meets => meets,
      },
      since: since,
      pauses: record.pauses,
      day: day,
    );

/// [group]'s next meeting that asks for its 人數, from [today] on, within
/// [attendanceWeeks], not one marked 這次沒聚會 ahead; null if none is known
/// (a 小組 with no 聚會時間, a service with no roster ahead).
Day? nextAttendanceDay(
  AttendanceGroup group, {
  required Day? since,
  AttendanceRecord record = const AttendanceRecord(),
  required Day today,
}) {
  if (since == null) return null;
  for (var d = today; d.isBefore(today.addDays(7 * attendanceWeeks)); d = d.addDays(1)) {
    if (_due(group, since: since, record: record, day: d) && !(record.days[d]?.none ?? false)) return d;
  }
  return null;
}

/// [group]'s meetings after [today], within [attendanceWeeks], oldest
/// first: those its leads may mark 這次沒聚會 ahead (a break, 過年),
/// which then are not reminded of nor left 未填. Replaces the pauses of
/// before, which older apps may still set.
List<Day> upcomingAttendanceDays(
  AttendanceGroup group, {
  required Day? since,
  AttendanceRecord record = const AttendanceRecord(),
  required Day today,
}) => [
  if (since != null)
    for (var d = today.addDays(1); d.isBefore(today.addDays(7 * attendanceWeeks + 1)); d = d.addDays(1))
      if (_due(group, since: since, record: record, day: d)) d,
];

/// Whether [group] is a 小組 whose 聚會時間 is not set yet.
bool meetsUnset(AttendanceGroup group, Day today) => group.group is SmallGroup && group.meetsOn(today).weekday == null;

/// [group]'s latest meeting that asks for its 人數, or one filled in;
/// today's once filled in, else each morning would show 未填 (#95).
Day? latestAttendanceDay(
  AttendanceGroup group, {
  required Day since,
  required AttendanceRecord record,
  required Day today,
}) => attendanceDays(
  group,
  since: since,
  record: record,
  today: today,
).where((d) => d != today || record.days.containsKey(d)).firstOrNull;

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

/// The Monday of [day]'s week: 人數總覽 shows a week, Monday to Sunday,
/// its Sunday last, as a bulletin reports the week before (#95).
Day weekOf(Day day) => day.addDays(DateTime.monday - day.weekday);

/// A row of 人數總覽 (#93): a group's meeting on [day], and what it has
/// (null: 未填); or, this week, a group that has not met in it, with no
/// [day], and its [next] meeting (null: a 小組 with no 聚會時間).
typedef AttendanceRow = ({AttendanceGroup group, Day? day, AttendanceDay? value, Day? next});

/// One week of 人數總覽 (#95), from [monday]: the meetings in it, by day, a
/// day's services before its 小組, those 沒聚會 after; this week, the
/// groups yet to meet in it, by when, and a 小組 with no 聚會時間, last.
@immutable
class AttendanceWeek {
  const AttendanceWeek(this.monday, this.rows);

  final Day monday;
  final List<AttendanceRow> rows;

  /// Its services' 人數 added up, or null with none filled in.
  int? get services => _total(isService: true);

  /// Its 小組' 人數 added up, apart from the services: their people come
  /// to those too. One that met with another is counted once, with it.
  int? get smallGroups => _total(isService: false);

  int? _total({required bool isService}) {
    final counts = [
      for (final r in rows)
        if ((r.group.group is ServiceGroup) == isService) ?r.value?.count,
    ];
    return counts.isEmpty ? null : counts.reduce((a, b) => a + b);
  }

  /// How many of its meetings are 未填.
  int get missing => rows.where((r) => r.day != null && r.value == null).length;

  /// Whether a meeting of it is listed, filled in or not.
  bool get met => rows.any((r) => r.day != null);
}

/// A group and its 人數 filled in.
typedef AttendanceOf = ({AttendanceGroup group, AttendanceRecord record});

/// The groups 人數總覽 lists for me with their 人數: every one, for admins
/// and 行政; a service's and its 小組', for its 負責人 and 牧者 (#95). Null
/// until all are read.
final _overviewRecordsProvider = Provider.autoDispose<List<AttendanceOf>?>((ref) {
  final me = ref.watch(meProvider).value;
  if (me == null || !me.seesAttendanceOverview) return const [];
  final out = <AttendanceOf>[];
  var read = true;
  for (final g in ref.watch(attendanceGroupsProvider)) {
    if (!me.writesAttendance(g.group)) continue;
    switch (ref.watch(attendanceProvider(g.group.key)).value) {
      case final record?:
        out.add((group: g, record: record));
      case null:
        read = false;
    }
  }
  return read ? out : null;
});

/// The weeks 人數總覽 turns through (#95): from the one 回報人數 came on in,
/// at most [attendanceWeeks] back, whose rosters are read, to this one; it
/// opens on the latest with anything filled in, so not on a Monday's week
/// of nothing yet. Null until read.
final attendanceOverviewWeeksProvider = Provider.autoDispose<({Day first, Day last, Day opens})?>((ref) {
  final since = ref.watch(churchProvider.select((c) => c.value?.attendanceSince));
  final records = ref.watch(_overviewRecordsProvider);
  if (since == null || records == null) return null;
  final today = ref.watch(todayProvider);
  final last = weekOf(today);
  final back = weekOf(today.addDays(-7 * (attendanceWeeks - 1)));
  final first = weekOf(since).isBefore(back) ? back : weekOf(since);
  for (var w = last; !w.isBefore(first); w = w.addDays(-7)) {
    final end = w.addDays(7);
    // 沒聚會 marked ahead, for a break, is not anyone filling in.
    bool filled(MapEntry<Day, AttendanceDay> e) =>
        !e.key.isBefore(w) && e.key.isBefore(end) && !e.key.isAfter(today) && !e.value.none;
    if (records.any((r) => r.record.days.entries.any(filled))) return (first: first, last: last, opens: w);
  }
  return (first: first, last: last, opens: last);
});

/// The week of 人數總覽 from [monday] (#95); null until read.
final attendanceOverviewProvider = Provider.autoDispose.family<AttendanceWeek?, Day>((ref, monday) {
  final since = ref.watch(churchProvider.select((c) => c.value?.attendanceSince));
  final records = ref.watch(_overviewRecordsProvider);
  if (since == null || records == null) return null;
  return attendanceWeek(records, monday: monday, since: since, today: ref.watch(todayProvider));
});

/// The week of [records] from [monday]: what [AttendanceWeek] lists. A
/// meeting today waits to be filled in before it is listed, else each
/// morning would open on 未填; this week lists it as when it next meets.
/// None for a service with no roster ahead, nor, but those filled in, for
/// a group an older app paused.
AttendanceWeek attendanceWeek(
  List<AttendanceOf> records, {
  required Day monday,
  required Day since,
  required Day today,
}) {
  final met = <AttendanceRow>[];
  final none = <AttendanceRow>[];
  final ahead = <AttendanceRow>[];
  for (final (group: g, :record) in records) {
    var listed = false;
    for (var d = monday; d.isBefore(monday.addDays(7)) && !d.isAfter(today); d = d.addDays(1)) {
      final value = record.days[d];
      if (value == null && (d == today || !_due(g, since: since, record: record, day: d))) continue;
      (value?.none ?? false ? none : met).add((group: g, day: d, value: value, next: null));
      listed = true;
    }
    if (listed || monday != weekOf(today) || record.pauseOn(today) != null) continue;
    // Only what is still to meet this week: one that does not (隔週, no
    // roster, 這次沒聚會) is not listed.
    if (nextAttendanceDay(g, since: since, record: record, today: today) case final next?) {
      if (next.isBefore(monday.addDays(7))) ahead.add((group: g, day: null, value: null, next: next));
    } else if (meetsUnset(g, today)) {
      ahead.add((group: g, day: null, value: null, next: null));
    }
  }
  int kind(AttendanceRow r) => r.group.group is ServiceGroup ? 0 : 1;
  int byDay(Day? a, Day? b) => switch ((a, b)) {
    (final a?, final b?) => a.compareTo(b),
    (null, null) => 0,
    (null, _) => 1,
    (_, null) => -1,
  };
  int order(AttendanceRow a, AttendanceRow b) => switch (byDay(a.day ?? a.next, b.day ?? b.next)) {
    0 => switch (kind(a) - kind(b)) {
      0 => a.group.name.compareTo(b.group.name),
      final k => k,
    },
    final c => c,
  };
  return AttendanceWeek(monday, [...met..sort(order), ...none..sort(order), ...ahead..sort(order)]);
}
