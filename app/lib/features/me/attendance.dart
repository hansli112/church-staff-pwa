import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../domain/day.dart';
import '../../domain/limits.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/attendance.dart';
import '../../state/providers.dart';
import '../common/errors.dart';
import '../common/labels.dart';
import '../rosters/format.dart';

/// 人數 (回報人數, #85) on a group's page: its meetings from
/// [attendanceWeeks] back, newest first, each with what was filled in or
/// 未填 (never 0), and whether it is paused. Who fills them in taps one to fill it in
/// or change it (補填). Nothing with 回報人數 off, or for who may not see it.
class AttendanceSection extends ConsumerWidget {
  const AttendanceSection({super.key, required this.group});

  final AttendanceGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final since = ref.watch(churchProvider.select((c) => c.value?.attendanceSince));
    final me = ref.watch(meProvider).value;
    if (since == null || me == null || !me.readsAttendance(group.group)) {
      return const SizedBox.shrink();
    }
    final writes = me.writesAttendance(group.group);
    final record = ref.watch(attendanceProvider(group.group.key)).value;
    if (record == null) return const SizedBox.shrink();
    final today = ref.watch(todayProvider);
    final days = attendanceDays(group, since: since, pauses: record.pauses, filled: record.days.keys, today: today);
    final pause = record.pauseOn(today);
    final paused = pause != null;
    return ListSection(
      header: l10n.attendanceHeader,
      footer: writes && !paused ? l10n.attendancePauseFooter : null,
      children: [
        if (paused)
          ListRow(
            title: l10n.attendancePausedUntil(dayLabel(l10n, pause.until, today)),
            leading: const Icon(Symbols.pause_circle_rounded),
            chevron: false,
            trailing: writes
                ? RowButton(
                    label: l10n.attendanceResume,
                    onPressed: () => _setPauses(context, ref, record.resumed(today)),
                  )
                : null,
          )
        else if (writes)
          ListRow(
            title: l10n.attendancePause,
            leading: const Icon(Symbols.pause_circle_rounded),
            onTap: () => _pause(context, ref, record, today),
          ),
        if (days.isEmpty) ListRow(title: l10n.attendanceNoDays, chevron: false),
        for (final day in days)
          ListRow(
            title: dayLabel(l10n, day, today),
            value: switch (record.days[day]) {
              null => l10n.attendanceMissing,
              AttendanceDay(none: true) => l10n.attendanceNone,
              AttendanceDay(:final count?) => l10n.attendanceCount(count),
              _ => l10n.attendanceMissing,
            },
            subtitle: switch (record.days[day]?.note) {
              final note? when note.isNotEmpty => note,
              _ => null,
            },
            onTap: writes ? () => fillAttendance(context, ref, group, day, record.days[day]) : null,
          ),
      ],
    );
  }

  Future<void> _pause(BuildContext context, WidgetRef ref, AttendanceRecord record, Day today) async {
    final picked = await pickDay(
      context,
      title: L10n.of(context).attendancePauseUntil,
      initial: today.addDays(7).midnight,
      first: today.addDays(1).midnight,
      last: today.addDays(366).midnight,
    );
    if (picked == null || !context.mounted) return;
    await _setPauses(context, ref, record.pausedUntil(today, Day(picked.year, picked.month, picked.day)));
  }

  Future<void> _setPauses(BuildContext context, WidgetRef ref, List<AttendancePause> pauses) async {
    try {
      await ref.churchData.setAttendancePauses(group.group.key, pauses);
    } catch (e) {
      if (context.mounted) showToast(context, saveErrorText(L10n.of(context), e));
    }
  }
}

/// Fills in [group]'s 人數 of [day], [was] what it had: how many came and a
/// note, or 這次沒聚會.
Future<void> fillAttendance(
  BuildContext context,
  WidgetRef ref,
  AttendanceGroup group,
  Day day,
  AttendanceDay? was,
) async {
  final l10n = L10n.of(context);
  final value = await showAppSheet<AttendanceDay>(
    context,
    builder: (_) => _FillSheet(
      title: [group.name, dayLabel(l10n, day, ref.read(todayProvider))].join(l10n.dotSeparator),
      was: was,
    ),
  );
  if (value == null || !context.mounted) return;
  try {
    await ref.churchData.setAttendance(group.group.key, day, value);
    if (context.mounted) showToast(context, l10n.attendanceSaved);
  } catch (e) {
    if (context.mounted) showToast(context, saveErrorText(l10n, e));
  }
}

class _FillSheet extends StatefulWidget {
  const _FillSheet({required this.title, required this.was});

  final String title;
  final AttendanceDay? was;

  @override
  State<_FillSheet> createState() => _FillSheetState();
}

class _FillSheetState extends State<_FillSheet> {
  late final _count = TextEditingController(text: widget.was?.count?.toString() ?? '');
  late final _note = TextEditingController(text: widget.was?.note ?? '');

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
          _count.text.trim() != (widget.was?.count?.toString() ?? '') || _note.text.trim() != (widget.was?.note ?? ''),
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
                      : () => Navigator.pop(context, AttendanceDay.count(count, note: _note.text.trim())),
                ),
              ],
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(Space.m, 0, Space.m, MediaQuery.viewInsetsOf(context).bottom + Space.l),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(widget.title, style: AppText.footnote.copyWith(color: AppColors.of(context).secondaryLabel)),
                    const SizedBox(height: Space.m),
                    TextField(
                      controller: _count,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                      decoration: InputDecoration(labelText: l10n.attendanceCountField),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: Space.s),
                    TextField(
                      controller: _note,
                      maxLength: TextLimits.attendanceNote,
                      decoration: InputDecoration(labelText: l10n.attendanceNote),
                    ),
                    const SizedBox(height: Space.s),
                    SecondaryButton(
                      label: l10n.attendanceNoMeeting,
                      onPressed: () => Navigator.pop(context, const AttendanceDay.none()),
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

/// 填寫人數 on 首頁: each meeting of a group I lead still waiting for its 人數.
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
            onTap: () => fillAttendance(context, ref, d.group, d.day, null),
          ),
      ],
    );
  }
}

/// When a 小組 meets, as its page says it: 每週五, 隔週五, or 未設定.
String smallGroupMeetsLabel(L10n l10n, SmallGroupDetails g) => switch (g.weekday) {
  null => l10n.meetsNotSet,
  final w when g.every == 2 => l10n.meetsBiweekly(weekdayLabel(l10n, w)),
  final w => l10n.meetsWeekly(weekdayLabel(l10n, w)),
};

/// Picks when a 小組 meets: every week or every other, on which weekday,
/// and, every other week, the next day it meets. Returns [g] so changed.
Future<SmallGroupDetails?> pickSmallGroupMeets(BuildContext context, SmallGroupDetails g, Day today) =>
    showAppSheet<SmallGroupDetails>(
      context,
      builder: (_) => _MeetsSheet(group: g, today: today),
    );

class _MeetsSheet extends StatefulWidget {
  const _MeetsSheet({required this.group, required this.today});

  final SmallGroupDetails group;
  final Day today;

  @override
  State<_MeetsSheet> createState() => _MeetsSheetState();
}

class _MeetsSheetState extends State<_MeetsSheet> {
  late var _every = widget.group.every;
  late int? _weekday = widget.group.weekday;

  /// The next day it meets, today or later: as it has met so far, or, on a
  /// day it did not meet on, the first such day.
  late Day? _next = switch ((widget.group.startsOn, widget.group.weekday)) {
    (final start?, final w?) when start.weekday == w => _upcoming(start, widget.group.every),
    _ => null,
  };

  /// [_next] as the sheet opened, to tell whether it was moved.
  late final Day? _nextAtOpen;

  @override
  void initState() {
    super.initState();
    _nextAtOpen = _next;
  }

  /// The first of [start], [every] weeks apart, that is today or later.
  Day _upcoming(Day start, int every) {
    var d = start;
    while (d.isBefore(widget.today)) {
      d = d.addDays(7 * every);
    }
    return d;
  }

  /// The day it starts from, as saved: the one it had, while it still meets
  /// as it did, so the weeks it met keep asking for their 人數; else [next].
  Day _startsOn(int weekday, Day next) {
    final had = widget.group.startsOn;
    final same =
        had != null &&
        had.weekday == weekday &&
        !had.isAfter(next) &&
        (_every == 1 || (had.daysUntil(next) ~/ 7).isEven);
    return same ? had : next;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final weekday = _weekday;
    final first = weekday == null ? null : widget.today.nextOnOrAfter(weekday);
    final next = first == null ? null : (_next != null && _next!.weekday == weekday ? _next! : first);
    final startsOn = weekday == null || next == null ? null : _startsOn(weekday, next);
    return UnsavedChanges(
      changed: () => _every != widget.group.every || weekday != widget.group.weekday || _next != _nextAtOpen,
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
                  onPressed: () => Navigator.pop(
                    context,
                    widget.group.copyWith(weekday: () => weekday, every: _every, startsOn: () => startsOn),
                  ),
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
                      child: SegmentedButton<int>(
                        segments: [
                          ButtonSegment(value: 1, label: Text(l10n.meetsEveryWeek)),
                          ButtonSegment(value: 2, label: Text(l10n.meetsEveryOtherWeek)),
                        ],
                        selected: {_every},
                        onSelectionChanged: (v) => setState(() => _every = v.first),
                      ),
                    ),
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
                    if (_every == 2 && next != null)
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
