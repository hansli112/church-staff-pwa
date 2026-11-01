import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../domain/day.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/attendance.dart';
import '../../state/providers.dart';
import '../common/errors.dart';
import '../rosters/format.dart';
import 'attendance.dart';

/// 回報人數, for admins and 行政. An admin turns it on here (#85), from
/// today, or off. Once on, each group's latest meeting in one list (#93),
/// oldest first, to copy into the week's bulletin by eye; how many are
/// still 未填 above, and 提醒 beside each. A row opens its group's page,
/// where its 人數 are filled in.
class AttendanceOverviewScreen extends ConsumerWidget {
  const AttendanceOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final rows = ref.watch(attendanceOverviewProvider);
    final today = ref.watch(todayProvider);
    final nameOf = attendanceGroupName(ref);
    final missing = rows?.where((r) => r.day != null && r.value == null).length ?? 0;
    final church = ref.watch(churchProvider).value;
    final on = church?.attendanceSince != null;
    final admin = ref.watch(meProvider).value?.isAdmin ?? false;
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
                if (on && rows != null)
                  ListSection(
                    header: rows.every((r) => r.day == null)
                        ? null
                        : missing > 0
                        ? l10n.attendanceOverviewMissing(missing)
                        : l10n.attendanceOverviewDone,
                    footer: l10n.attendanceOverviewFooter,
                    children: [
                      if (rows.isEmpty) ListRow(title: l10n.attendanceNoDays, chevron: false),
                      for (final r in rows)
                        ListRow(
                          title: r.group.name,
                          subtitle: switch (r.day) {
                            final day? => [
                              dayLabel(l10n, day, today),
                              ?attendanceDetail(l10n, r.value, nameOf),
                            ].join(l10n.dotSeparator),
                            null => attendanceNotYet(l10n, r.next, today),
                          },
                          value: r.day == null ? null : attendanceValue(l10n, r.value, nameOf),
                          trailing: r.day != null && r.value == null
                              ? RowButton(label: l10n.attendanceRemind, onPressed: () => _remind(context, ref, r))
                              : null,
                          onTap: () => context.push(
                            '/me/groups/${switch (r.group.group) {
                              SmallGroup() => 'small',
                              _ => 'service',
                            }}/${r.group.group.id}',
                          ),
                        ),
                    ],
                  ),
              ],
            ),
    );
  }

  Future<void> _remind(BuildContext context, WidgetRef ref, AttendanceLatest r) async {
    final l10n = L10n.of(context);
    try {
      final people = await ref.churchData.attendance.remind(r.group.group.key, r.day!);
      if (context.mounted) showToast(context, people > 0 ? l10n.attendanceRemindSent : l10n.attendanceRemindNobody);
    } catch (e) {
      if (context.mounted) showToast(context, saveErrorText(l10n, e));
    }
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
