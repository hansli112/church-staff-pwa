import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
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
import '../rosters/format.dart';
import 'attendance.dart';
import 'groups_screen.dart' show attendancePage;

/// 回報人數, for admins and 行政, and a service's 負責人 and 牧者, theirs
/// (#95). Once on, a week of 人數總覽 (#93), Sunday to Saturday, to copy
/// into the bulletin by eye: how many are still 未填, with one 提醒 for
/// them all, not added up, as people come to more than one; each service,
/// then its 小組, in the church's order, the 其他聚會 last, where admins
/// and 行政 add one, and 編輯 them all. A row opens its 填寫人數, which
/// opens the group's 人數 page. Below, an admin turns it on (#85), from
/// today, or off: with it off, that is all there is.
class AttendanceOverviewScreen extends ConsumerStatefulWidget {
  const AttendanceOverviewScreen({super.key});

  @override
  ConsumerState<AttendanceOverviewScreen> createState() => _AttendanceOverviewScreenState();
}

class _AttendanceOverviewScreenState extends ConsumerState<AttendanceOverviewScreen> {
  /// The Sunday of the week turned to; null for the one it opens on.
  Day? _sunday;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final today = ref.watch(todayProvider);
    final church = ref.watch(churchProvider).value;
    final on = church?.attendanceSince != null;
    final admin = ref.watch(meProvider).value?.isAdmin ?? false;
    final range = ref.watch(attendanceOverviewWeeksProvider);
    final sunday = _sunday ?? range?.opens;
    final week = sunday == null ? null : ref.watch(attendanceOverviewProvider(sunday));
    final nameOf = attendanceGroupName(ref);
    final groups = ref.watch(attendanceGroupsProvider);
    final oversees = ref.watch(meProvider).value?.overseesAttendance ?? false;
    final summary = week == null ? null : _summary(l10n, week);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.attendance)),
      body: church == null
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.only(bottom: Space.xl),
              children: [
                if (on && range != null && week != null) ...[
                  _WeekBar(
                    sunday: week.sunday,
                    today: today,
                    onShift: (by) => setState(() => _sunday = week.sunday.addDays(7 * by)),
                    earlier: week.sunday.isAfter(range.first),
                    later: week.sunday.isBefore(range.last),
                  ),
                  if (summary != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: Space.s,
                        children: [
                          Text(
                            summary,
                            textAlign: TextAlign.center,
                            style: AppText.footnote.copyWith(color: AppColors.of(context).secondaryLabel),
                          ),
                          if (week.missing > 0)
                            RowButton(label: l10n.attendanceRemind, onPressed: () => _remind(context, week)),
                        ],
                      ),
                    ),
                  if (week.rows.isEmpty) ListSection(children: [ListRow(title: l10n.attendanceNoDays, chevron: false)]),
                  for (final section in _sections(week.sections(groups), gatherings: oversees))
                    ListSection(
                      header: switch (section) {
                        (service: final id?, rows: _, :final named) when named => nameOf('service:$id'),
                        (service: null, rows: _, named: _) => l10n.gatherings,
                        _ => null,
                      },
                      // All of them, the week listing only those that meet in it.
                      headerAction: section.service == null && oversees
                          ? (label: l10n.edit, onPressed: () => context.push('/me/attendance/gatherings'))
                          : null,
                      children: [
                        for (final r in section.rows) _row(context, r, today, nameOf),
                        if (section.service == null && oversees) _addGatheringRow(context, ref),
                      ],
                    ),
                ],
                // Set once, so below the week: with it off, alone on the page.
                if (admin)
                  ListSection(
                    footer: l10n.attendanceSub,
                    children: [
                      SwitchRow(
                        title: l10n.attendance,
                        value: on,
                        onChanged: (on) async {
                          try {
                            await ref.churchData.attendance.saveSince(on ? ref.read(todayProvider) : null);
                          } catch (e) {
                            if (context.mounted) showToast(context, saveErrorText(l10n, e));
                          }
                        },
                      ),
                    ],
                  ),
              ],
            ),
    );
  }

  /// [sections] as listed: a service with its 小組 under its name; those
  /// with no 小組 that week together, the row saying the name already. The
  /// 其他聚會 too when none meets that week, for [gatherings]: whoever sets
  /// them, to add one.
  List<({String? service, List<AttendanceRow> rows, bool named})> _sections(
    List<({String? service, List<AttendanceRow> rows})> sections, {
    required bool gatherings,
  }) {
    final out = <({String? service, List<AttendanceRow> rows, bool named})>[];
    for (final s in sections) {
      final named = s.service == null || s.rows.any((r) => r.group.group is! ServiceGroup);
      if (!named && out.isNotEmpty && !out.last.named && out.last.service != null) {
        out.last.rows.addAll(s.rows);
      } else {
        out.add((service: s.service, rows: [...s.rows], named: named));
      }
    }
    if (gatherings && !out.any((s) => s.service == null)) out.add((service: null, rows: [], named: true));
    return out;
  }

  Widget _addGatheringRow(BuildContext context, WidgetRef ref) => ListRow(
    title: L10n.of(context).addGathering,
    leading: const Icon(Symbols.add_rounded),
    chevron: false,
    onTap: () => _addGathering(context, ref),
  );

  /// A meeting of [week]: its 人數, 未填, or the day it next meets.
  Widget _row(BuildContext context, AttendanceRow r, Day today, String Function(String key) nameOf) {
    final l10n = L10n.of(context);
    return ListRow(
      title: r.group.name,
      dimmed: r.value?.none ?? false,
      subtitle: switch (r.day) {
        final day? => [dayLabel(l10n, day, today), ?attendanceDetail(l10n, r.value, nameOf)].join(l10n.dotSeparator),
        // The day, as the meetings already met say theirs; the rule is for
        // where it is set.
        null => switch (r.next) {
          final next? => dayLabel(l10n, next, today),
          null => attendanceNotYet(l10n, attendanceTimeOf(ref, r.group.group)),
        },
      },
      value: r.day == null ? null : attendanceValue(l10n, r.value, nameOf),
      onTap: switch (r.day) {
        final day? => () => fillAttendance(context, ref, r.group, day, r.value, linksPage: true),
        null => () => context.push(attendancePage(r.group.group)),
      },
    );
  }

  /// 「還有 2 個未填」, or 都填好了; today's not counted, as on 首頁.
  /// Nothing for a week with no meeting in it yet, nor with only today's
  /// still to fill in.
  String? _summary(L10n l10n, AttendanceWeek week) {
    if (!week.met) return null;
    if (week.missing > 0) return l10n.attendanceOverviewMissing(week.missing);
    return week.waiting ? null : l10n.attendanceOverviewDone;
  }

  /// 提醒: whoever fills in each group 未填 in [week] (not today's) is
  /// asked for its latest, a group once a day; then what came of it, the
  /// groups with nobody to ask by name.
  Future<void> _remind(BuildContext context, AttendanceWeek week) async {
    final l10n = L10n.of(context);
    final attendance = ref.churchData.attendance;
    final latest = <String, ({String name, Day day})>{};
    for (final r in week.rows) {
      if (r.day case final day? when day != week.today && r.value == null) {
        if (latest[r.group.group.key] case final was? when was.day.isAfter(day)) continue;
        latest[r.group.group.key] = (name: r.group.name, day: day);
      }
    }
    // Each on its own: one already reminded today does not stop the rest.
    final results = await Future.wait([
      for (final MapEntry(:key, :value) in latest.entries)
        attendance
            .remind(key, value.day)
            .then<Object>((told) => told > 0 ? true : value.name, onError: (Object e) => e),
    ]);
    if (!context.mounted) return;
    final nobody = results.whereType<String>().toList();
    final failed = results.where((r) => r is! bool && r is! String).toList();
    showToast(context, switch (results.contains(true)) {
      true when nobody.isNotEmpty => l10n.attendanceRemindSomeNobody(nobody.join(l10n.listSeparator)),
      true => l10n.attendanceRemindSent,
      false when failed.isNotEmpty => saveErrorText(l10n, failed.first),
      false => l10n.attendanceRemindNobody,
    });
  }
}

/// 其他聚會, from 回報人數's 編輯, for admins and 行政: each opens its 人數 page
/// to set when it meets and who fills it in; dragged in order, and added.
/// One may not meet this week, so not only on the week's list.
class GatheringsScreen extends ConsumerWidget {
  const GatheringsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final gatherings = ref.watch(gatheringsProvider).value ?? const <Gathering>[];
    // Kept up to date here, the 回報人數 below being out of sight: a new
    // one's page, opened from here, reads them, and would otherwise bring
    // them up to date while it builds, which riverpod refuses.
    ref.watch(attendanceGroupsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.gatherings)),
      body: CustomScrollView(
        slivers: [
          ReorderableSection<Gathering>(
            items: gatherings,
            keyOf: (g) => g.id,
            row: (g, handle) => ListRow(
              title: g.name,
              value: meetingTimeLabel(l10n, g.time),
              trailing: handle,
              chevron: true,
              onTap: () => context.push(attendancePage(GatheringGroup(g.id))),
            ),
            onReorder: (next) async {
              try {
                await ref.churchData.attendance.orderGatherings([for (final g in next) g.id]);
              } catch (e) {
                if (context.mounted) showToast(context, saveErrorText(l10n, e));
              }
            },
            after: [
              ListRow(
                title: l10n.addGathering,
                leading: const Icon(Symbols.add_rounded),
                chevron: false,
                onTap: () => _addGathering(context, ref),
              ),
            ],
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: Space.xl)),
        ],
      ),
    );
  }
}

/// 新增其他聚會: named, then its 人數 page, to set when it meets and who fills it in.
Future<void> _addGathering(BuildContext context, WidgetRef ref) async {
  final l10n = L10n.of(context);
  final name = await promptText(
    context,
    title: l10n.addGathering,
    hint: l10n.gatheringName,
    maxLength: TextLimits.profileName,
    action: l10n.add,
  );
  if (name == null || !context.mounted) return;
  try {
    final id = await ref.churchData.attendance.saveGathering(Gathering(id: '', name: name));
    if (context.mounted) unawaited(context.push(attendancePage(GatheringGroup(id))));
  } catch (e) {
    if (context.mounted) showToast(context, saveErrorText(l10n, e));
  }
}

/// 「‹ 11月2日 – 11月8日 ›」: the week shown, and the ones beside it.
class _WeekBar extends StatelessWidget {
  const _WeekBar({
    required this.sunday,
    required this.today,
    required this.onShift,
    required this.earlier,
    required this.later,
  });

  final Day sunday;
  final Day today;
  final void Function(int by) onShift;
  final bool earlier;
  final bool later;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final saturday = sunday.addDays(6);
    final f = saturday.year == today.year ? DateFormat.MMMd() : DateFormat.yMMMd();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.s),
      child: Row(
        children: [
          IconButton(
            tooltip: l10n.attendancePrevWeek,
            icon: const Icon(Symbols.chevron_left_rounded),
            onPressed: earlier ? () => onShift(-1) : null,
          ),
          Expanded(
            child: Semantics(
              header: true,
              liveRegion: true,
              child: Text(
                '${f.format(sunday.midnight)} – ${f.format(saturday.midnight)}',
                textAlign: TextAlign.center,
                style: AppText.headline,
              ),
            ),
          ),
          IconButton(
            tooltip: l10n.attendanceNextWeek,
            icon: const Icon(Symbols.chevron_right_rounded),
            onPressed: later ? () => onShift(1) : null,
          ),
        ],
      ),
    );
  }
}

/// Opens 填寫人數 for group [fill]'s meeting on [day], from a reminder's
/// link (`/home?fill=service:sunday&day=2026-11-01`, functions/src/attendance.ts
/// fillLink), once the group and its 人數 are read; for who fills them in.
class FillFromLink extends ConsumerStatefulWidget {
  const FillFromLink({super.key, required this.fill, required this.day, required this.child});

  final String? fill;
  final String? day;
  final Widget child;

  @override
  ConsumerState<FillFromLink> createState() => _FillFromLinkState();
}

class _FillFromLinkState extends ConsumerState<FillFromLink> {
  /// The link last opened, so a rebuild opens it once.
  String? _opened;

  @override
  Widget build(BuildContext context) {
    final key = widget.fill;
    final day = Day.tryParse(widget.day);
    final link = '$key ${widget.day}';
    if (key == null || day == null) {
      _opened = null;
    } else if (_opened != link) {
      final group = ref.watch(attendanceGroupsProvider).where((g) => g.group.key == key).firstOrNull;
      final me = ref.watch(meProvider).value;
      final fills = group == null ? null : ref.watch(fillsAttendanceProvider(group.group));
      final record = me != null && (fills ?? false) ? ref.watch(attendanceProvider(key)).value : null;
      if (group != null && record != null) {
        _opened = link;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          await fillAttendance(context, ref, group, day, record.days[day]);
          // The same link again, from another reminder, opens it again.
          if (context.mounted) context.go('/home');
        });
      }
    }
    return widget.child;
  }
}
