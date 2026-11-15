import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../data/backend.dart' show WarmUp;
import '../../domain/day.dart';
import '../../domain/limits.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../domain/text.dart' show matchesSearch;
import '../../state/attendance.dart';
import '../../state/church_writes.dart';
import '../../state/providers.dart';
import '../common/errors.dart';
import '../common/labels.dart';
import '../rosters/format.dart';
import '../rosters/future_changes.dart' show runWithUndo;
import 'groups_screen.dart' show attendancePage;
import '../../state/session.dart';

/// 人數 on a group's page (回報人數, #85), one row since #95: its latest
/// meeting's, or when it next meets, opening its 人數 page. Nothing with
/// 回報人數 off, or for who may not see them.
class GroupAttendanceRow extends ConsumerWidget {
  const GroupAttendanceRow({super.key, required this.group});

  final AttendanceGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final since = ref.watch(churchProvider.select((c) => c.value?.attendanceSince));
    final me = ref.watch(meProvider).value;
    if (since == null || me == null || !me.readsAttendance(group.group)) {
      return const SizedBox.shrink();
    }
    final record = ref.watch(attendanceProvider(group.group.key)).value;
    if (record == null) return const SizedBox.shrink();
    final today = ref.watch(todayProvider);
    final latest = latestAttendanceDay(group, since: since, record: record, today: today);
    return ListSection(
      children: [
        ListRow(
          title: l10n.attendanceHeader,
          value: latest == null ? null : attendanceValue(l10n, record.days[latest], attendanceGroupName(ref)),
          subtitle: switch (latest) {
            final day? => dayLabel(l10n, day, today),
            // A 小組's page says its 聚會時間 a row above.
            null when group.group is SmallGroup => null,
            null => attendanceNotYet(l10n, attendanceTimeOf(ref, group.group)),
          },
          onTap: () => context.push(attendancePage(group.group)),
        ),
      ],
    );
  }
}

/// A group's 人數 page (#95), from its page, 人數總覽 or 填寫人數: its
/// 回報人數 switch (off for a break), 聚會時間 and 負責回報, which who sets
/// them changes here; its meetings from [attendanceWeeks] back, newest
/// first, each with what was filled in or 未填 (never 0). Who fills them
/// in taps one to fill it in or change it (補填), and fills in a day it
/// met off its 聚會時間. A 其他聚會's is all it has: its name, and 刪除.
class GroupAttendanceScreen extends ConsumerWidget {
  const GroupAttendanceScreen({super.key, required this.group});

  final ChurchGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final since = ref.watch(churchProvider.select((c) => c.value?.attendanceSince));
    final me = ref.watch(meProvider).value;
    final group = ref.watch(attendanceGroupsProvider).where((g) => g.group.key == this.group.key).firstOrNull;
    final record = group == null ? null : ref.watch(attendanceProvider(group.group.key)).value;
    if (since == null ||
        me == null ||
        group == null ||
        record == null ||
        !me.readsAttendance(group.group, record.fillers)) {
      return Scaffold(appBar: AppBar());
    }
    final writes = me.fillsAttendance(group.group, record.fillers);
    final manages = me.writesAttendance(group.group);
    final small = switch (group.group) {
      SmallGroup(:final id) => ref.watch(smallGroupsProvider).value?.byId(id),
      _ => null,
    };
    final gathering = switch (group.group) {
      GatheringGroup(:final id) => ref.watch(gatheringsProvider).value?.where((g) => g.id == id).firstOrNull,
      _ => null,
    };
    final service = switch (group.group) {
      ServiceGroup(:final id) => ref.watch(servicesProvider).value?.byId(id),
      _ => null,
    };
    // A 小組's 聚會時間 is set as its page sets it, its 小組長 too.
    final schedules = small != null ? me.schedulesSmallGroup(small.group) : manages;
    final today = ref.watch(todayProvider);
    final days = attendanceDays(group, since: since, record: record, today: today);
    final on = record.pauseOn(today) == null;
    final nameOf = attendanceGroupName(ref);
    final time = attendanceTimeOf(ref, group.group).time;
    final fillers = [...attendanceLeads(ref, group.group), ...attendanceFillerMembers(ref, record.fillers)];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.attendanceOf(group.name))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.xl),
        children: [
          ListSection(
            children: [
              // Off for a while (a break, 暑假): asks for nothing, and the
              // weeks it was off stay so once on again.
              if (manages)
                SwitchRow(
                  title: l10n.attendance,
                  value: on,
                  onChanged: (v) => _save(
                    context,
                    () => ref.churchData.attendance.savePauses(
                      group.group.key,
                      pausesTurned(record, on: v, today: today),
                    ),
                  ),
                ),
              if (gathering != null && manages)
                ListRow(
                  title: l10n.gatheringName,
                  value: gathering.name,
                  onTap: () => _renameGathering(context, ref, gathering),
                ),
              ListRow(
                title: l10n.smallGroupMeets,
                value: meetingTimeLabel(l10n, time, serviceWeekday: service?.weekday),
                chevron: schedules,
                onTap: schedules
                    ? () => _setTime(
                        context,
                        ref,
                        group.group,
                        time,
                        small: small,
                        gathering: gathering,
                        service: service,
                      )
                    : null,
              ),
              ListRow(
                title: l10n.attendanceFillers,
                value: fillers.isEmpty ? l10n.meetsNotSet : fillers.map((m) => m.name).join(l10n.listSeparator),
                chevron: manages,
                onTap: manages ? () => _pickFillers(context, ref, group.group, record.fillers) : null,
              ),
            ],
          ),
          if (days.isNotEmpty || writes)
            ListSection(
              children: [
                for (final day in days)
                  ListRow(
                    title: dayLabel(l10n, day, today),
                    dimmed: record.days[day]?.none ?? false,
                    value: attendanceValue(l10n, record.days[day], nameOf),
                    subtitle: attendanceDetail(l10n, record.days[day], nameOf),
                    onTap: writes ? () => fillAttendance(context, ref, group, day, record.days[day]) : null,
                  ),
                // A day it met though not on its 聚會時間, or before 回報人數 was on.
                if (writes)
                  ListRow(
                    title: l10n.attendanceOtherDay,
                    leading: const Icon(Symbols.edit_calendar_rounded),
                    onTap: () => _otherDay(context, ref, group, record, today),
                  ),
              ],
            ),
          if (gathering != null && manages)
            ListSection(
              children: [
                ListRow(
                  title: l10n.deleteGathering,
                  destructive: true,
                  chevron: false,
                  onTap: () => _deleteGathering(context, ref, gathering),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Sets its 聚會時間: a 小組's on it, a 其他聚會's on it, a service's on
  /// its 人數.
  Future<void> _setTime(
    BuildContext context,
    WidgetRef ref,
    ChurchGroup group,
    MeetingTime? time, {
    SmallGroupDetails? small,
    Gathering? gathering,
    Service? service,
  }) async {
    final picked = await pickMeetingTime(
      context,
      time: time,
      serviceWeekday: service?.weekday,
      today: ref.read(todayProvider),
    );
    if (picked == null || picked.time == time || !context.mounted) return;
    final writes = ref.read(churchWritesProvider);
    final attendance = ref.churchData.attendance;
    await _save(context, () async {
      if (small != null) {
        await writes.smallGroup(small, small.withTime(picked.time ?? const MeetingTime())).done;
      } else if (gathering != null) {
        await attendance.saveGathering(gathering.copyWith(time: picked.time ?? const MeetingTime()));
      } else {
        await attendance.saveTime(group.key, picked.time);
      }
    });
  }

  Future<void> _pickFillers(BuildContext context, WidgetRef ref, ChurchGroup group, List<String> was) async {
    final leads = attendanceLeads(ref, group);
    final picked = await showAppSheet<List<String>>(
      context,
      expand: true,
      builder: (_) => _FillersSheet(leads: leads, picked: was),
    );
    if (picked == null || listEquals(picked, was) || !context.mounted) return;
    final attendance = ref.churchData.attendance;
    await _save(context, () => attendance.saveFillers(group.key, picked));
  }

  Future<void> _renameGathering(BuildContext context, WidgetRef ref, Gathering gathering) async {
    final l10n = L10n.of(context);
    final name = await promptText(
      context,
      title: l10n.gatheringName,
      hint: l10n.gatheringName,
      initial: gathering.name,
      maxLength: TextLimits.profileName,
    );
    if (name == null || name == gathering.name || !context.mounted) return;
    final attendance = ref.churchData.attendance;
    await _save(context, () => attendance.saveGathering(gathering.copyWith(name: name)));
  }

  /// Deletes it, with 復原: its 人數 and who fills them in stay.
  Future<void> _deleteGathering(BuildContext context, WidgetRef ref, Gathering gathering) async {
    final attendance = ref.churchData.attendance;
    final ok = await runWithUndo(
      context,
      L10n.of(context).gatheringDeleted(gathering.name),
      () => (
        done: attendance.deleteGathering(gathering.id),
        undo: () => attendance.saveGathering(gathering).then((_) {}),
      ),
    );
    if (ok && context.mounted) context.pop();
  }

  Future<void> _save(BuildContext context, Future<void> Function() save) async {
    try {
      await save();
    } catch (e) {
      if (context.mounted) showToast(context, saveErrorText(L10n.of(context), e));
    }
  }

  /// 新增一次聚會: a day picked, back to a year ago, then 填寫人數 for it.
  Future<void> _otherDay(
    BuildContext context,
    WidgetRef ref,
    AttendanceGroup group,
    AttendanceRecord record,
    Day today,
  ) async {
    final picked = await pickDay(
      context,
      title: L10n.of(context).attendanceOtherDay,
      initial: today.midnight,
      first: today.addDays(-366).midnight,
      last: today.midnight,
    );
    if (picked == null || !context.mounted) return;
    final day = Day(picked.year, picked.month, picked.day);
    await fillAttendance(context, ref, group, day, record.days[day]);
  }
}

/// For a group with no meeting to fill in yet: its 聚會時間 ([attendanceTimeOf]), or that it is
/// not set.
String attendanceNotYet(L10n l10n, ({MeetingTime? time, int? serviceWeekday}) of) =>
    of.serviceWeekday == null && of.time?.weekday == null
    ? l10n.attendanceNoMeets
    : meetingTimeLabel(l10n, of.time, serviceWeekday: of.serviceWeekday);

/// [group]'s 聚會時間 as the church has it: a 小組's or a 其他聚會's own, a
/// service's on its 人數 (null: by its rosters), with the service's weekday.
({MeetingTime? time, int? serviceWeekday}) attendanceTimeOf(WidgetRef ref, ChurchGroup group) => switch (group) {
  SmallGroup(:final id) => (time: ref.watch(smallGroupsProvider).value?.byId(id)?.time, serviceWeekday: null),
  GatheringGroup(:final id) => (
    time: ref.watch(gatheringsProvider).value?.where((g) => g.id == id).firstOrNull?.time,
    serviceWeekday: null,
  ),
  ServiceGroup(:final id) => (
    time: ref.watch(attendanceProvider(group.key)).value?.time,
    serviceWeekday: ref.watch(servicesProvider).value?.byId(id)?.weekday,
  ),
  MinistryGroup() => (time: null, serviceWeekday: null),
};

/// The name of the group a key names, for 和○○一起.
String Function(String key) attendanceGroupName(WidgetRef ref) {
  final groups = ref.watch(churchGroupsProvider);
  return (key) => groups?.byKey(key)?.name ?? key.split(':').last;
}

/// What a meeting has, as its row says it: 120 人, 沒聚會, 和珍珠小組一起
/// (聯合小組, #93), or 未填, never 0.
String attendanceValue(L10n l10n, AttendanceDay? d, String Function(String key) nameOf) => switch (d) {
  AttendanceDay(withGroup: final host?) => l10n.attendanceWith(nameOf(host)),
  AttendanceDay(none: true) => l10n.attendanceNone,
  AttendanceDay(:final count?) => l10n.attendanceCount(count),
  _ => l10n.attendanceMissing,
};

/// Under it: the 小組 it met with, and its note.
String? attendanceDetail(L10n l10n, AttendanceDay? d, String Function(String key) nameOf) {
  final parts = [
    if (d != null && d.together.isNotEmpty) l10n.attendanceWith(d.together.map(nameOf).join(l10n.listSeparator)),
    if (d != null && d.note.isNotEmpty) d.note,
  ];
  return parts.isEmpty ? null : parts.join(l10n.dotSeparator);
}

/// Fills in [group]'s 人數 of [day], [was] what it had: how many came and a
/// note, or 這次沒聚會; a 小組, with the others of its service meeting that
/// day it met with (聯合小組, #93). With [linksPage], from 人數總覽 or 首頁, its last
/// row opens the group's 人數 page (#95).
Future<void> fillAttendance(
  BuildContext context,
  WidgetRef ref,
  AttendanceGroup group,
  Day day,
  AttendanceDay? was, {
  bool linksPage = false,
}) async {
  final l10n = L10n.of(context);
  final since = ref.read(churchProvider).value?.attendanceSince;
  final others = switch (group.group) {
    SmallGroup(:final id, :final service?) when since != null => [
      for (final g in ref.read(smallGroupsProvider).value ?? const <SmallGroupDetails>[])
        if (g.id != id && g.service == service && attendanceDue(g.meets, since: since, day: day))
          (key: g.group.key, name: g.name),
    ],
    _ => const <({String key, String name})>[],
  };
  // Filled in together through the backend; it starts while they type.
  if (others.isNotEmpty || (was?.together.isNotEmpty ?? false)) {
    ref.read(backendProvider).warmUp(WarmUp.attendanceTogether);
  }
  final title = [group.name, dayLabel(l10n, day, ref.read(todayProvider))].join(l10n.dotSeparator);
  // Set when its 人數 page is asked for; closing first asks to discard
  // what was typed, as any close does.
  final toPage = ValueNotifier(false);
  final value = await showAppSheet<AttendanceDay>(
    context,
    builder: (_) => _FillSheet(
      title: title,
      was: was,
      others: others,
      pageTitle: linksPage ? l10n.attendanceOf(group.name) : null,
      toPage: toPage,
    ),
  );
  if (!context.mounted) return;
  if (value == null) {
    if (toPage.value) unawaited(context.push(attendancePage(group.group)));
    return;
  }
  final attendance = ref.churchData.attendance;
  final telemetry = ref.read(telemetryProvider);
  try {
    if (value.together.isNotEmpty || (was?.together.isNotEmpty ?? false)) {
      await attendance.saveTogether(group.group.key, day, value);
    } else {
      await attendance.save(group.group.key, day, value);
    }
    telemetry.logEvent('attendance_report');
    if (context.mounted) showToast(context, l10n.saved);
  } catch (e) {
    if (context.mounted) showToast(context, saveErrorText(l10n, e));
  }
}

class _FillSheet extends StatefulWidget {
  const _FillSheet({
    required this.title,
    required this.was,
    required this.others,
    required this.pageTitle,
    required this.toPage,
  });

  final String title;
  final AttendanceDay? was;

  /// The last row's title, opening the group's 人數 page; null for none.
  final String? pageTitle;
  final ValueNotifier<bool> toPage;

  /// The 小組 it may have met with, by key.
  final List<({String key, String name})> others;

  @override
  State<_FillSheet> createState() => _FillSheetState();
}

class _FillSheetState extends State<_FillSheet> {
  late final _count = TextEditingController(text: widget.was?.count?.toString() ?? '');
  late final _note = TextEditingController(text: widget.was?.note ?? '');
  late final _together = {...?widget.was?.together};

  @override
  void dispose() {
    _count.dispose();
    _note.dispose();
    super.dispose();
  }

  int? get _value => switch (int.tryParse(_count.text.trim())) {
    final n? when n >= 0 && n <= Limits.attendanceCount => n,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final count = _value;
    return UnsavedChanges(
      changed: () =>
          _count.text.trim() != (widget.was?.count?.toString() ?? '') ||
          _note.text.trim() != (widget.was?.note ?? '') ||
          !setEquals(_together, {...?widget.was?.together}),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetBar(
              title: l10n.attendanceFill,
              actions: [
                SecondaryButton(
                  label: l10n.save,
                  onPressed: count == null
                      ? null
                      : () => Navigator.pop(
                          context,
                          AttendanceDay.count(count, note: _note.text.trim(), together: [..._together]),
                        ),
                ),
              ],
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom + Space.l),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.m),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            widget.title,
                            style: AppText.footnote.copyWith(color: AppColors.of(context).secondaryLabel),
                          ),
                          const SizedBox(height: Space.m),
                          TextField(
                            controller: _count,
                            autofocus: true,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(6),
                            ],
                            decoration: InputDecoration(labelText: l10n.attendanceCountField),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: Space.s),
                          TextField(
                            controller: _note,
                            maxLength: TextLimits.attendanceNote,
                            decoration: InputDecoration(labelText: l10n.attendanceNote),
                          ),
                        ],
                      ),
                    ),
                    // 聯合小組 (#93): the count is theirs too.
                    if (widget.others.isNotEmpty)
                      ListSection(
                        header: l10n.attendanceTogether,
                        children: [
                          for (final g in widget.others)
                            ListRow(
                              title: g.name,
                              selected: _together.contains(g.key),
                              onTap: () => setState(
                                () => _together.contains(g.key) ? _together.remove(g.key) : _together.add(g.key),
                              ),
                            ),
                        ],
                      )
                    else
                      const SizedBox(height: Space.s),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.m),
                      // Met with nobody, then: those it named are cleared.
                      child: SecondaryButton(
                        label: l10n.attendanceNoMeeting,
                        onPressed: () => Navigator.pop(context, const AttendanceDay.none()),
                      ),
                    ),
                    if (widget.pageTitle case final title?)
                      ListSection(
                        children: [
                          ListRow(
                            title: title,
                            onTap: () {
                              widget.toPage.value = true;
                              Navigator.pop(context);
                            },
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 聚會人數 on 首頁, for admins and 行政: how many meetings of the last two
/// weeks are still 未填, opening 回報人數.
class AttendanceMissingRow extends ConsumerWidget {
  const AttendanceMissingRow({super.key});

  /// Whether it has anything to show.
  static bool shown(WidgetRef ref) => (ref.watch(attendanceMissingCountProvider) ?? 0) > 0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final missing = ref.watch(attendanceMissingCountProvider) ?? 0;
    if (missing == 0) return const SizedBox.shrink();
    return ListSection(
      children: [
        ListRow(
          leading: const Icon(Symbols.groups_rounded),
          title: l10n.attendanceHeader,
          value: l10n.attendanceOverviewMissing(missing),
          onTap: () => context.push('/me/attendance'),
        ),
      ],
    );
  }
}

/// 填寫人數 on 首頁: each meeting of the last two weeks of a group I lead,
/// or that asked me to fill theirs in, still waiting for its 人數.
class AttendanceDueCard extends ConsumerWidget {
  const AttendanceDueCard({super.key});

  /// Whether it has anything to show.
  static bool shown(WidgetRef ref) => ref.watch(attendanceDueProvider).isNotEmpty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final due = ref.watch(attendanceDueProvider);
    final today = ref.watch(todayProvider);
    if (due.isEmpty) return const SizedBox.shrink();
    return ListSection(
      header: l10n.attendanceFill,
      children: [
        for (final d in due)
          ListRow(
            leading: const Icon(Symbols.groups_rounded),
            title: d.group.name,
            subtitle: dayLabel(l10n, d.day, today),
            onTap: () => fillAttendance(context, ref, d.group, d.day, null, linksPage: true),
          ),
      ],
    );
  }
}

/// Who is always asked to fill in [group]'s 人數, by 身分 (Member.remindedAttendance): a
/// service's 負責人, a 小組's 小組長; a 其他聚會 has none.
List<Member> attendanceLeads(WidgetRef ref, ChurchGroup group) => [
  for (final m in ref.watch(membersProvider).value ?? const <Member>[])
    if (m.remindedAttendance.contains(group.key)) m,
]..sort((a, b) => a.name.compareTo(b.name));

/// The members [uids] name, in that order; one gone is left out.
List<Member> attendanceFillerMembers(WidgetRef ref, List<String> uids) {
  final byUid = {for (final m in ref.watch(membersProvider).value ?? const <Member>[]) m.uid: m};
  return [for (final u in uids) ?byUid[u]];
}

/// 負責回報: anyone in the church ticked, besides [leads], who always are.
class _FillersSheet extends ConsumerStatefulWidget {
  const _FillersSheet({required this.leads, required this.picked});

  final List<Member> leads;
  final List<String> picked;

  @override
  ConsumerState<_FillersSheet> createState() => _FillersSheetState();
}

class _FillersSheetState extends ConsumerState<_FillersSheet> {
  late final _picked = [...widget.picked];
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final leads = {for (final m in widget.leads) m.uid};
    final everyone = [
      for (final m in ref.watch(membersProvider).value ?? const <Member>[])
        if (!leads.contains(m.uid)) m,
    ]..sort((a, b) => a.name.compareTo(b.name));
    final shown = [
      for (final m in everyone)
        if (_query.isEmpty || matchesSearch(m.name, _query)) m,
    ];
    final full = _picked.length >= Limits.attendanceFillers;
    return UnsavedChanges(
      changed: () => !listEquals(_picked, widget.picked),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetBar(
              title: l10n.attendanceFillers,
              actions: [SecondaryButton(label: l10n.done, onPressed: () => Navigator.pop(context, _picked))],
            ),
            if (everyone.length > 8)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.m),
                child: SearchField(hint: l10n.searchMembers, onChanged: (q) => setState(() => _query = q.trim())),
              ),
            Expanded(
              child: ListView(
                children: [
                  if (widget.leads.isNotEmpty && _query.isEmpty)
                    ListSection(
                      children: [
                        for (final m in widget.leads)
                          ListRow(title: m.name, value: _leadOf(l10n, m), selected: true, chevron: false),
                      ],
                    ),
                  ListSection(
                    children: [
                      for (final m in shown)
                        ListRow(
                          title: m.name,
                          selected: _picked.contains(m.uid),
                          onTap: !_picked.contains(m.uid) && full
                              ? null
                              : () => setState(
                                  () => _picked.contains(m.uid) ? _picked.remove(m.uid) : _picked.add(m.uid),
                                ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _leadOf(L10n l10n, Member m) =>
      m.identities.any((i) => i is SmallGroupLead) ? l10n.identitySmallGroupLead : l10n.identityLead;
}

/// A 聚會時間 as a page says it: 每週五, 隔週五, 每月第 1、3 個週五, or
/// 未設定; a service's, by its rosters (null [time]): 有服事表的週日.
String meetingTimeLabel(L10n l10n, MeetingTime? time, {int? serviceWeekday}) {
  final weekday = serviceWeekday ?? time?.weekday;
  if (weekday == null) return l10n.meetsNotSet;
  final w = weekdayLabel(l10n, weekday);
  return switch (time) {
    null => l10n.meetsWithRoster(w),
    MeetingTime(:final monthWeeks) when monthWeeks.isNotEmpty => l10n.meetsMonthly(
      monthWeeks.join(l10n.listSeparator),
      w,
    ),
    MeetingTime(every: 2) => l10n.meetsBiweekly(w),
    _ => l10n.meetsWeekly(w),
  };
}

/// When a 小組 meets, as its page says it: 每週五, 隔週五, or 未設定.
String smallGroupMeetsLabel(L10n l10n, SmallGroupDetails g) => meetingTimeLabel(l10n, g.time);

/// Picks when a 小組 meets. Returns [g] so changed.
Future<SmallGroupDetails?> pickSmallGroupMeets(BuildContext context, SmallGroupDetails g, Day today) async {
  final picked = await pickMeetingTime(context, time: g.time, today: today);
  return picked == null ? null : g.withTime(picked.time ?? const MeetingTime());
}

/// Picks a 聚會時間: every week or every other, or those weeks of each
/// month, on which weekday ([serviceWeekday], a service's, its own), and,
/// every other week, the next day it meets. A service's may also meet by
/// its rosters, a null time. Null when cancelled.
Future<({MeetingTime? time})?> pickMeetingTime(
  BuildContext context, {
  required MeetingTime? time,
  int? serviceWeekday,
  required Day today,
}) => showAppSheet<({MeetingTime? time})>(
  context,
  builder: (_) => _MeetsSheet(time: time, serviceWeekday: serviceWeekday, today: today),
);

/// How a 聚會時間 repeats, as the sheet picks it.
enum _Repeat { roster, weekly, biweekly, monthly }

class _MeetsSheet extends StatefulWidget {
  const _MeetsSheet({required this.time, required this.serviceWeekday, required this.today});

  final MeetingTime? time;
  final int? serviceWeekday;
  final Day today;

  @override
  State<_MeetsSheet> createState() => _MeetsSheetState();
}

class _MeetsSheetState extends State<_MeetsSheet> {
  late var _repeat = switch (widget.time) {
    null when widget.serviceWeekday != null => _Repeat.roster,
    MeetingTime(:final monthWeeks) when monthWeeks.isNotEmpty => _Repeat.monthly,
    MeetingTime(every: 2) => _Repeat.biweekly,
    _ => _Repeat.weekly,
  };
  late int? _weekday = widget.serviceWeekday ?? widget.time?.weekday;
  late final _weeks = {...?widget.time?.monthWeeks};

  /// Whether anything was tapped: only then may closing lose something.
  var _touched = false;

  @override
  void setState(VoidCallback fn) => super.setState(() {
    _touched = true;
    fn();
  });

  /// The next day it meets every other week, today or later: as it has
  /// met so far, or, on a day it did not meet on, the first such day.
  late Day? _next = switch ((widget.time?.startsOn, _weekday, widget.time?.every)) {
    (final start?, final w?, 2) when start.weekday == w => _upcoming(start, 2),
    _ => null,
  };

  /// The first of [start], [every] weeks apart, that is today or later.
  Day _upcoming(Day start, int every) {
    var d = start;
    while (d.isBefore(widget.today)) {
      d = d.addDays(7 * every);
    }
    return d;
  }

  /// The first day from today on that is the [weeks] of its month's [weekday].
  Day _firstMonthly(int weekday, Set<int> weeks) {
    var d = widget.today.nextOnOrAfter(weekday);
    while (!weeks.contains(weekOfMonth(d))) {
      d = d.addDays(7);
    }
    return d;
  }

  /// What was picked, null for by its rosters; null [MeetingTime] while
  /// it is not whole (no weekday, no week of the month).
  ({MeetingTime? time})? get _picked {
    final weekday = _weekday;
    if (_repeat == _Repeat.roster) return (time: null);
    if (weekday == null || (_repeat == _Repeat.monthly && _weeks.isEmpty)) return null;
    final had = widget.time;
    final first = widget.today.nextOnOrAfter(weekday);
    final service = widget.serviceWeekday != null;
    // As it was while it still meets so: the weeks it met keep asking.
    bool same(MeetingTime t) =>
        had != null &&
        (had.weekday ?? widget.serviceWeekday) == t.weekday &&
        had.every == t.every &&
        setEquals({...had.monthWeeks}, {...t.monthWeeks}) &&
        (had.startsOn == null || !had.startsOn!.isAfter(t.startsOn ?? first));
    final MeetingTime picked = switch (_repeat) {
      _Repeat.monthly => MeetingTime(
        weekday: weekday,
        monthWeeks: [..._weeks]..sort(),
        startsOn: _firstMonthly(weekday, _weeks),
      ),
      _Repeat.biweekly => MeetingTime(
        weekday: weekday,
        every: 2,
        startsOn: _next != null && _next!.weekday == weekday ? _next : first,
      ),
      _ => MeetingTime(weekday: weekday, startsOn: first),
    };
    final kept = same(picked)
        ? MeetingTime(weekday: weekday, every: picked.every, monthWeeks: picked.monthWeeks, startsOn: had!.startsOn)
        : picked;
    // A service's weekday is its own.
    return (
      time: service ? MeetingTime(every: kept.every, startsOn: kept.startsOn, monthWeeks: kept.monthWeeks) : kept,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final weekday = _weekday;
    final service = widget.serviceWeekday != null;
    final first = weekday == null ? null : widget.today.nextOnOrAfter(weekday);
    final next = first == null ? null : (_next != null && _next!.weekday == weekday ? _next! : first);
    final picked = _picked;
    return UnsavedChanges(
      changed: () => _touched && picked?.time != widget.time,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetBar(
              title: l10n.smallGroupMeets,
              actions: [
                SecondaryButton(
                  label: l10n.save,
                  onPressed: picked == null ? null : () => Navigator.pop(context, picked),
                ),
              ],
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(Space.m),
                      child: SegmentedButton<_Repeat>(
                        showSelectedIcon: false,
                        segments: [
                          if (service) ButtonSegment(value: _Repeat.roster, label: Text(l10n.meetsByRoster)),
                          ButtonSegment(value: _Repeat.weekly, label: Text(l10n.meetsEveryWeek)),
                          ButtonSegment(value: _Repeat.biweekly, label: Text(l10n.meetsEveryOtherWeek)),
                          ButtonSegment(value: _Repeat.monthly, label: Text(l10n.meetsEveryMonth)),
                        ],
                        selected: {_repeat},
                        onSelectionChanged: (v) => setState(() => _repeat = v.first),
                      ),
                    ),
                    if (!service)
                      ListSection(
                        children: [
                          for (var w = 1; w <= 7; w++)
                            ListRow(
                              title: weekdayLabel(l10n, w),
                              selected: weekday == w,
                              onTap: () => setState(() {
                                _weekday = w;
                                _next = widget.today.nextOnOrAfter(w);
                              }),
                            ),
                        ],
                      ),
                    if (_repeat == _Repeat.biweekly && next != null)
                      ListSection(
                        children: [
                          ListRow(
                            title: l10n.nextMeeting,
                            value: dayLabel(l10n, next, widget.today),
                            // The week after, for one that meets the other week.
                            onTap: () => setState(() => _next = next == first ? first!.addDays(7) : first),
                          ),
                        ],
                      ),
                    if (_repeat == _Repeat.monthly && weekday != null)
                      ListSection(
                        children: [
                          for (var n = 1; n <= Limits.monthWeeks; n++)
                            ListRow(
                              title: l10n.meetsWeekOfMonth(n, weekdayLabel(l10n, weekday)),
                              selected: _weeks.contains(n),
                              onTap: () => setState(() => _weeks.contains(n) ? _weeks.remove(n) : _weeks.add(n)),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
