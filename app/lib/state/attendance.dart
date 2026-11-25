import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/day.dart';
import '../domain/export.dart';
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
/// A service's [Meets] depend on whether the day has a roster and on its
/// 聚會時間 of its own ([AttendanceRecord.time], [serviceMeets]).
typedef AttendanceGroup = ({ChurchGroup group, String name, Meets Function(Day day, {MeetingTime? time}) meetsOn});

/// The groups of the church that meet (its services, 小組 by when they
/// meet, and 其他聚會), in that order, as [AttendanceGroup]s; a service
/// meets as [serviceMeets] says.
final attendanceGroupsProvider = Provider.autoDispose<List<AttendanceGroup>>(
  (ref) => attendanceGroupsOf(
    services: ref.watch(servicesProvider).value?.services ?? const <Service>[],
    smallGroups: ref.watch(smallGroupsProvider).value ?? const <SmallGroupDetails>[],
    gatherings: ref.watch(gatheringsProvider).value ?? const <Gathering>[],
    rosters: ref.watch(_recentRostersProvider).value ?? const <Roster>[],
  ),
);

/// [services], [smallGroups] and [gatherings] as [AttendanceGroup]s, in
/// that order, a service meeting on the days of [rosters] it has.
List<AttendanceGroup> attendanceGroupsOf({
  required List<Service> services,
  required List<SmallGroupDetails> smallGroups,
  required List<Gathering> gatherings,
  required Iterable<Roster> rosters,
}) {
  final held = {
    for (final r in rosters)
      if (!r.isEvent) (r.type, r.day),
  };
  // 沒有聚會: no 人數 to fill in.
  final off = {
    for (final r in rosters)
      if (!r.isEvent && r.noService) (r.type, r.day),
  };
  return [
    for (final s in services)
      (
        group: ServiceGroup(s.id),
        name: s.name,
        meetsOn: (Day day, {MeetingTime? time}) => serviceMeets(
          s.weekdays,
          roster: held.contains((s.id, day)),
          noService: off.contains((s.id, day)),
          time: time,
          weeks: s.weeks,
        ),
      ),
    for (final g in smallGroups.inMeetingOrder([for (final s in services) s.id]))
      (group: g.group, name: g.name, meetsOn: (Day _, {MeetingTime? time}) => g.meets),
    for (final g in gatherings)
      (group: GatheringGroup(g.id), name: g.name, meetsOn: (Day _, {MeetingTime? time}) => g.time.meets()),
  ];
}

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
      group.meetsOn(day, time: record.time),
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

/// For admins and 行政 on 首頁: the week 回報人數 opens on, so the page
/// says the same: how many are still 未填 in it, or that today's is still
/// to fill in. Null for whoever does not oversee it, with it off, or until
/// read.
final attendanceHomeWeekProvider = Provider.autoDispose<AttendanceWeek?>((ref) {
  final me = ref.watch(meProvider).value;
  if (me == null || !me.overseesAttendance) return null;
  final since = ref.watch(churchProvider.select((c) => c.value?.attendanceSince));
  if (since == null) return null;
  final range = ref.watch(attendanceOverviewWeeksProvider);
  if (range == null) return null;
  return ref.watch(attendanceOverviewProvider(range.opens));
});

/// The Sunday of [day]'s week: 人數總覽 shows a week, Sunday to Saturday,
/// as a bulletin on Sunday reports the week just gone (#95).
Day weekOf(Day day) => day.addDays(-(day.weekday % 7));

/// A row of 人數總覽 (#93): a group's meeting on [day], and what it has
/// (null: 未填); or, this week, a group that has not met in it, with no
/// [day], and its [next] meeting (null: a 小組 with no 聚會時間).
typedef AttendanceRow = ({AttendanceGroup group, Day? day, AttendanceDay? value, Day? next});

/// One week of 人數總覽 (#95), from [sunday]: the meetings in it, and this
/// week the groups yet to meet in it, each group in the church's order
/// (attendanceGroupsProvider): a service before its 小組. Not added up:
/// people come to more than one, a service and their 小組, or two services.
@immutable
class AttendanceWeek {
  const AttendanceWeek(this.sunday, this.rows, {required this.today});

  final Day sunday;
  final List<AttendanceRow> rows;

  /// Its meetings today are not yet 未填, as on 首頁 (attendanceHomeWeekProvider).
  final Day today;

  /// Its rows by the service they are of, the service's own first, then
  /// its 小組', as [groups] has them; the 其他聚會 last, with no service.
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

  /// How many of its meetings are 未填: not today's, still to fill in.
  int get missing => rows.where((r) => r.day != null && r.day != today && r.value == null).length;

  /// Whether a meeting today is still to fill in.
  bool get waiting => rows.any((r) => r.day == today && r.value == null);

  /// Whether a meeting of it is listed, filled in or not.
  bool get met => rows.any((r) => r.day != null);

  /// Whether a meeting of it was filled in or is 未填: not 沒聚會 marked
  /// ahead, for a break, nor today's still to fill in.
  bool get reported => rows.any(
    (r) => switch ((r.day, r.value)) {
      (null, _) => false,
      (_, final v?) => !v.none,
      (final day?, null) => day != today,
    },
  );
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
/// opens on the latest with anything filled in or 未填, so not on a
/// Monday's week of nothing yet; or on this one with a meeting today still
/// to fill in, unless the week before still has some 未填. Null until read.
final attendanceOverviewWeeksProvider = Provider.autoDispose<({Day first, Day last, Day opens})?>((ref) {
  final since = ref.watch(churchProvider.select((c) => c.value?.attendanceSince));
  final records = ref.watch(_overviewRecordsProvider);
  if (since == null || records == null) return null;
  final today = ref.watch(todayProvider);
  final last = weekOf(today);
  final back = weekOf(today.addDays(-7 * (attendanceWeeks - 1)));
  final first = weekOf(since).isBefore(back) ? back : weekOf(since);
  for (var w = last; !w.isBefore(first); w = w.addDays(-7)) {
    final week = attendanceWeek(records, sunday: w, since: since, today: today);
    if (week.reported) return (first: first, last: last, opens: w);
    if (w == last &&
        week.waiting &&
        attendanceWeek(records, sunday: w.addDays(-7), since: since, today: today).missing == 0) {
      return (first: first, last: last, opens: w);
    }
  }
  return (first: first, last: last, opens: last);
});

/// The week of 人數總覽 from [sunday] (#95); null until read.
final attendanceOverviewProvider = Provider.autoDispose.family<AttendanceWeek?, Day>((ref, sunday) {
  final since = ref.watch(churchProvider.select((c) => c.value?.attendanceSince));
  final records = ref.watch(_overviewRecordsProvider);
  if (since == null || records == null) return null;
  return attendanceWeek(records, sunday: sunday, since: since, today: ref.watch(todayProvider));
});

/// The week of [records] from [sunday]: what [AttendanceWeek] lists, in
/// the order of [records], so the same each week; a group's meetings by
/// day. A meeting today is listed 未填 till filled in; this week, one yet
/// to meet is listed as when it next meets. None for a service with no
/// roster ahead, nor, but those filled in, for a group an older app paused.
AttendanceWeek attendanceWeek(
  List<AttendanceOf> records, {
  required Day sunday,
  required Day since,
  required Day today,
}) {
  final rows = <AttendanceRow>[];
  for (final (group: g, :record) in records) {
    var listed = false;
    for (var d = sunday; d.isBefore(sunday.addDays(7)) && !d.isAfter(today); d = d.addDays(1)) {
      final value = record.days[d];
      if (value == null && !_due(g, since: since, record: record, day: d)) continue;
      rows.add((group: g, day: d, value: value, next: null));
      listed = true;
    }
    if (listed || sunday != weekOf(today) || record.pauseOn(today) != null) continue;
    // Only what is still to meet this week: one that does not (隔週, no
    // roster, 這次沒聚會) is not listed.
    if (nextAttendanceDay(g, since: since, record: record, today: today) case final next?) {
      if (next.isBefore(sunday.addDays(7))) rows.add((group: g, day: null, value: null, next: next));
    } else if (meetsUnset(g, today)) {
      rows.add((group: g, day: null, value: null, next: null));
    }
  }
  return AttendanceWeek(sunday, rows, today: today);
}

/// 聚會人數.csv's meetings (匯出): those of [records] from the day
/// 回報人數 came on ([since]), or the first filled in, to [today], oldest
/// first, a day's in the order of [records]: each filled in, and, within
/// [attendanceWeeks], each that asked for its 人數, 未填 till filled in,
/// today's too. [nameOf] names
/// the 小組 one met with.
List<AttendanceLine> attendanceLines(
  List<AttendanceOf> records, {
  required Day since,
  required Day today,
  required String Function(String key) nameOf,
}) {
  // 未填 only as far back as the pages list them: before, a pause may be
  // gone (pausesTurned) and a 小組 may have met on another day.
  final asked = today.addDays(-7 * attendanceWeeks);
  var from = since;
  for (final (group: _, :record) in records) {
    for (final d in record.days.keys) {
      if (d.isBefore(from)) from = d;
    }
  }
  return [
    for (var d = from; !d.isAfter(today); d = d.addDays(1))
      for (final (group: g, :record) in records)
        if (record.days[d] != null || !d.isBefore(asked) && _due(g, since: since, record: record, day: d))
          (
            day: d,
            group: g.name,
            value: record.days[d],
            withName: switch (record.days[d]?.withGroup) {
              final key? => nameOf(key),
              null => null,
            },
          ),
  ];
}

/// Reads, once, the 人數 of every group 人數總覽 lists for me and makes
/// [attendanceLines] of them, the days each service met by all its
/// rosters since; null with 回報人數 off.
Future<List<AttendanceLine>?> loadAttendanceLines(WidgetRef ref) async {
  final since = ref.read(churchProvider).value?.attendanceSince;
  final me = ref.read(meProvider).value;
  if (since == null || me == null) return null;
  final today = ref.read(todayProvider);
  final data = ref.churchData;
  final (services, smallGroups, gatherings) = (
    ref.read(servicesProvider.future),
    ref.read(smallGroupsProvider.future),
    ref.read(gatheringsProvider.future),
  );
  final (settings, small, others, rosters) = await (
    services,
    smallGroups,
    gatherings,
    data.pastRosters(from: since, before: today.addDays(1)),
  ).wait;
  final groups = attendanceGroupsOf(
    services: settings.services,
    smallGroups: small,
    gatherings: others,
    rosters: rosters,
  );
  final mine = [
    for (final g in groups)
      if (me.writesAttendance(g.group)) g,
  ];
  final records = await Future.wait([for (final g in mine) data.attendance.watch(g.group.key).first]);
  final names = {for (final g in groups) g.group.key: g.name};
  return attendanceLines(
    [for (final (i, g) in mine.indexed) (group: g, record: records[i])],
    since: since,
    today: today,
    nameOf: (key) => names[key] ?? key.split(':').last,
  );
}
