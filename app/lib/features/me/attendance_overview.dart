import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../domain/day.dart';
import '../../l10n/app_localizations.dart';
import '../../state/attendance.dart';
import '../../state/providers.dart';
import '../common/errors.dart';
import '../rosters/format.dart';
import 'attendance.dart';
import 'groups_screen.dart' show attendancePage;

/// 回報人數, for admins and 行政, and a service's 負責人 and 牧者, theirs
/// (#95). An admin turns it on here (#85), from today, or off. Once on, a
/// week of 人數總覽 (#93), Monday to Sunday, to copy into the bulletin by
/// eye: the services and the 小組 added up apart, how many are still 未填,
/// and 提醒 beside each. A row opens its 填寫人數, which opens the group's
/// 人數 page.
class AttendanceOverviewScreen extends ConsumerStatefulWidget {
  const AttendanceOverviewScreen({super.key});

  @override
  ConsumerState<AttendanceOverviewScreen> createState() => _AttendanceOverviewScreenState();
}

class _AttendanceOverviewScreenState extends ConsumerState<AttendanceOverviewScreen> {
  /// The Monday of the week turned to; null for the one it opens on.
  Day? _monday;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final today = ref.watch(todayProvider);
    final church = ref.watch(churchProvider).value;
    final on = church?.attendanceSince != null;
    final admin = ref.watch(meProvider).value?.isAdmin ?? false;
    final range = ref.watch(attendanceOverviewWeeksProvider);
    final monday = _monday ?? range?.opens;
    final week = monday == null ? null : ref.watch(attendanceOverviewProvider(monday));
    final nameOf = attendanceGroupName(ref);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.attendance)),
      body: church == null
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.only(bottom: Space.xl),
              children: [
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
                if (on && range != null && week != null) ...[
                  _WeekBar(
                    monday: week.monday,
                    today: today,
                    onShift: (by) => setState(() => _monday = week.monday.addDays(7 * by)),
                    earlier: week.monday.isAfter(range.first),
                    later: week.monday.isBefore(range.last),
                  ),
                  ListSection(
                    header: _summary(l10n, week),
                    children: [
                      if (week.rows.isEmpty) ListRow(title: l10n.attendanceNoDays, chevron: false),
                      for (final r in week.rows)
                        ListRow(
                          title: r.group.name,
                          dimmed: r.value?.none ?? false,
                          subtitle: switch (r.day) {
                            final day? => [
                              dayLabel(l10n, day, today),
                              ?attendanceDetail(l10n, r.value, nameOf),
                            ].join(l10n.dotSeparator),
                            null => attendanceNotYet(l10n, r.next, today),
                          },
                          value: r.day == null ? null : attendanceValue(l10n, r.value, nameOf),
                          trailing: r.day != null && r.value == null
                              ? RowButton(label: l10n.attendanceRemind, onPressed: () => _remind(context, r))
                              : null,
                          onTap: switch (r.day) {
                            final day? => () => fillAttendance(context, ref, r.group, day, r.value, linksPage: true),
                            null => () => context.push(attendancePage(r.group.group)),
                          },
                        ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }

  /// 「聚會 150 人 · 小組 60 人 · 還有 2 個未填」, or 都填好了; nothing for a
  /// week with no meeting in it yet.
  String? _summary(L10n l10n, AttendanceWeek week) {
    if (!week.met) return null;
    return [
      if (week.services case final n?) l10n.attendanceServicesTotal(n),
      if (week.smallGroups case final n?) l10n.attendanceSmallGroupsTotal(n),
      week.missing > 0 ? l10n.attendanceOverviewMissing(week.missing) : l10n.attendanceOverviewDone,
    ].join(l10n.dotSeparator);
  }

  Future<void> _remind(BuildContext context, AttendanceRow r) async {
    final l10n = L10n.of(context);
    try {
      final people = await ref.churchData.attendance.remind(r.group.group.key, r.day!);
      if (context.mounted) showToast(context, people > 0 ? l10n.attendanceRemindSent : l10n.attendanceRemindNobody);
    } catch (e) {
      if (context.mounted) showToast(context, saveErrorText(l10n, e));
    }
  }
}

/// 「‹ 11月3日 – 11月9日 ›」: the week shown, and the ones beside it.
class _WeekBar extends StatelessWidget {
  const _WeekBar({
    required this.monday,
    required this.today,
    required this.onShift,
    required this.earlier,
    required this.later,
  });

  final Day monday;
  final Day today;
  final void Function(int by) onShift;
  final bool earlier;
  final bool later;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final sunday = monday.addDays(6);
    final f = sunday.year == today.year ? DateFormat.MMMd() : DateFormat.yMMMd();
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
                '${f.format(monday.midnight)} – ${f.format(sunday.midnight)}',
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
      final record = group != null && me != null && me.writesAttendance(group.group)
          ? ref.watch(attendanceProvider(key)).value
          : null;
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
