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

/// The keys of the groups that asked me to fill in their 人數 (負責回報).
final myFillsProvider = StreamProvider.autoDispose<Set<String>>((ref) => openChurch(ref).attendance.mine());

/// Whether I fill in [group]'s 人數, as who sets it or one it asked to; null until read.
final fillsAttendanceProvider = Provider.autoDispose.family<bool?, ChurchGroup>((ref, group) {
  final me = ref.watch(meProvider).value;
  if (me == null) return null;
  if (me.writesAttendance(group)) return true;
  return ref.watch(myFillsProvider).value?.contains(group.key);
});

/// Rosters from [attendanceWeeks] back on: which days a service met.
final _recentRostersProvider = StreamProvider.autoDispose<List<Roster>>((ref) {
  final today = ref.watch(todayProvider);
  return openChurch(ref).rosters(from: today.addDays(-7 * attendanceWeeks));
});

/// A group 回報人數 is about: a service, a 小組 (with its service) or a
/// 其他聚會, its name, and when it meets.
typedef AttendanceGroup = ({ChurchGroup group, String name, Meets Function(Day day) meetsOn});

/// The groups of the church that meet (its services, 小組 and 其他聚會),
/// in that order, as [AttendanceGroup]s; a service meets on its weekday
/// when that day has a roster, unless its 聚會時間 says otherwise
/// (AttendanceRecord.time).
final attendanceGroupsProvider = Provider.autoDispose<List<AttendanceGroup>>((ref) {
  final services = ref.watch(servicesProvider).value?.enabled ?? const <Service>[];
  final smallGroups = ref.watch(smallGroupsProvider).value ?? const <SmallGroupDetails>[];
  final gatherings = ref.watch(gatheringsProvider).value ?? const <Gathering>[];
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
    for (final g in gatherings) (group: GatheringGroup(g.id), name: g.name, meetsOn: (Day _) => g.time.meets()),
  ];
});

/// The meetings of [group] from [attendanceWeeks] back to today that ask
/// for their 人數, newest first: none with 回報人數 off. Days [record] has
/// 人數 for are listed too, though the group no longer meets on them. A
/// service with a 聚會時間 of its own ([AttendanceRecord.time]) meets by
/// it, roster or not.
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
      switch ((group.meetsOn(day), record.time)) {
        // Before its own began, by its rosters as before.
        (Meets(:final weekday, :final roster?), final time?) => Meets(
          weekday: weekday,
          every: time.every,
          startsOn: time.startsOn,
          monthWeeks: time.monthWeeks,
          roster: time.startsOn == null ? null : roster,
        ),
        (final meets, _) => meets,
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

/// [record]'s pauses with its 回報人數 turned on ([on]) or off from
/// [today]: off, a pause from today on; on, the one covering today ends
/// today, or goes, begun today. The weeks it was off stay asked for
/// nothing; those ended before any page looks ([attendanceWeeks]) go,
/// so turning it off and on never fills the list.
List<AttendancePause> pausesTurned(AttendanceRecord record, {required bool on, required Day today}) {
  final kept = [
    for (final p in record.pauses)
      if (!p.until.isBefore(today.addDays(-7 * (attendanceWeeks + 1)))) p,
  ];
  return on
      ? [
          for (final p in kept)
            if (!p.covers(today)) p else if (p.from.isBefore(today)) AttendancePause(from: p.from, until: today),
        ]
      : [...kept, AttendancePause.off(today)];
}

/// Whether [group] is a 小組 or a 其他聚會 whose 聚會時間 is not set yet.
bool meetsUnset(AttendanceGroup group, Day today) =>
    group.group is! ServiceGroup && group.meetsOn(today).weekday == null;

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

/// How far back 首頁 asks for the 人數 still not filled in, today too.
const attendanceDueDays = 14;

/// A meeting that waits for its 人數 on 首頁, for one reminded of its
/// group's: each of the last [attendanceDueDays] days still without, until
/// filled in.
typedef AttendanceDue = ({AttendanceGroup group, Day day});

/// The meetings of [record]'s [group] from [attendanceDueDays] back to
/// [today] still without their 人數, newest first; today's with them.
List<Day> attendanceMissing(
  AttendanceGroup group, {
  required Day since,
  required AttendanceRecord record,
  required Day today,
}) => [
  for (final d in attendanceDays(
    group,
    since: since,
    record: record.copyWith(days: const {}),
    today: today,
  ))
    if (!d.isBefore(today.addDays(1 - attendanceDueDays)) && !record.days.containsKey(d)) d,
];

/// Every [AttendanceDue] of the groups I am reminded of
/// (Member.remindedAttendance, and those that asked me to fill theirs in),
/// for 首頁.
final attendanceDueProvider = Provider.autoDispose<List<AttendanceDue>>((ref) {
  final since = ref.watch(churchProvider.select((c) => c.value?.attendanceSince));
  final me = ref.watch(meProvider).value;
  if (since == null || me == null) return const [];
  final today = ref.watch(todayProvider);
  final mine = {...me.remindedAttendance, ...?ref.watch(myFillsProvider).value};
  // Nobody else reads the weeks of rosters it takes.
  if (mine.isEmpty) return const [];
  return [
    for (final g in ref.watch(attendanceGroupsProvider))
      if (mine.contains(g.group.key))
        if (ref.watch(attendanceProvider(g.group.key)).value case final record?)
          for (final day in attendanceMissing(g, since: since, record: record, today: today)) (group: g, day: day),
  ];
});

/// For admins and 行政 on 首頁: how many meetings of the last
/// [attendanceDueDays] days, before today, are still 未填; null until read.
final attendanceMissingCountProvider = Provider.autoDispose<int?>((ref) {
  final since = ref.watch(churchProvider.select((c) => c.value?.attendanceSince));
  final me = ref.watch(meProvider).value;
  if (since == null || me == null || !me.overseesAttendance) return 0;
  final records = ref.watch(_overviewRecordsProvider);
  if (records == null) return null;
  final today = ref.watch(todayProvider);
  return records.fold<int>(
    0,
    (n, r) =>
        n + attendanceMissing(r.group, since: since, record: r.record, today: today).where((d) => d != today).length,
  );
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

  /// Its 其他聚會' 人數 added up, apart from both.
  int? get gatherings => _total();

  int? _total({bool? isService}) {
    final counts = [
      for (final r in rows)
        if (switch (r.group.group) {
          ServiceGroup() => isService == true,
          SmallGroup() => isService == false,
          _ => isService == null,
        })
          ?r.value?.count,
    ];
    return counts.isEmpty ? null : counts.reduce((a, b) => a + b);
  }

  /// Its rows by the service they are of, a service's and its 小組',
  /// each in the order [rows] has them, as [groups] has the services;
  /// the 其他聚會 last, with no service.
  List<({String? service, List<AttendanceRow> rows})> sections(List<AttendanceGroup> groups) {
    String? serviceOf(AttendanceRow r) => switch (r.group.group) {
      ServiceGroup(:final id) => id,
      SmallGroup(:final service) => service,
      _ => null,
    };
    final order = [
      for (final g in groups)
        if (g.group case ServiceGroup(:final id)) id,
    ];
    final keys = {...order.where((id) => rows.any((r) => serviceOf(r) == id)), ...rows.map(serviceOf)};
    final sorted = [...keys.whereType<String>(), if (keys.contains(null)) null];
    return [
      for (final key in sorted) (service: key, rows: [...rows.where((r) => serviceOf(r) == key)]),
    ];
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
