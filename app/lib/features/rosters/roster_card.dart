import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/components.dart';
import '../../core/perf.dart';
import '../../core/design/tokens.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import 'format.dart';

/// Counts card builds, so tests can check that a change rebuilds only the
/// card it touched.
@visibleForTesting
final rosterCardBuilds = <String, int>{};

/// One day of one service. Watches only its own roster, so a change to
/// another day does not rebuild it.
class RosterCard extends ConsumerWidget {
  const RosterCard({
    super.key,
    required this.serviceType,
    required this.rosterId,
    this.onTap,
  });

  final String serviceType;
  final String rosterId;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roster = ref.watch(
      serviceRostersProvider(serviceType).select((v) {
        for (final r in v.value ?? const <Roster>[]) {
          if (r.id == rosterId) return r;
        }
        return null;
      }),
    );
    if (roster == null) return const SizedBox.shrink();
    perfMark('roster-visible');
    if (kDebugMode) {
      rosterCardBuilds.update(rosterId, (n) => n + 1, ifAbsent: () => 1);
    }
    final today = ref.watch(todayProvider);
    final uid = ref.watch(uidProvider);
    final myName = ref.watch(meProvider.select((m) => m.value?.name));
    return RosterDayView(
      roster: roster,
      title: dayLabel(L10n.of(context), roster.day, today),
      highlightUid: uid,
      highlightName: myName,
      onTap: onTap,
    );
  }
}

/// The content of a roster day: date, event tags, then each duty and its
/// people. My own name is in the accent colour so I find it at a glance.
class RosterDayView extends StatelessWidget {
  const RosterDayView({
    super.key,
    required this.roster,
    required this.title,
    this.highlightUid,
    this.highlightName,
    this.onTap,
  });

  final Roster roster;
  final String title;
  final String? highlightUid;
  final String? highlightName;
  final VoidCallback? onTap;

  bool _isMe(Duty duty, String name) {
    final uid = duty.uids[name];
    if (uid != null) return uid == highlightUid;
    return name == highlightName;
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final l10n = L10n.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.s),
      child: Material(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.m),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, 12, Space.m, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(title, style: AppText.headline)),
                    if (onTap != null)
                      Icon(
                        Icons.chevron_right,
                        color: c.tertiaryLabel,
                        size: 22,
                      ),
                  ],
                ),
                if (roster.events.isNotEmpty) ...[
                  const SizedBox(height: Space.s),
                  Wrap(
                    spacing: Space.xs,
                    runSpacing: Space.xs,
                    children: [
                      for (final e in roster.events) Tag.event(context, e.name, e.color),
                    ],
                  ),
                ],
                const SizedBox(height: Space.s),
                for (final duty in roster.duties)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 96,
                          child: Text(
                            duty.role,
                            style: AppText.subheadline.copyWith(
                              color: c.secondaryLabel,
                            ),
                          ),
                        ),
                        const SizedBox(width: Space.s),
                        Expanded(
                          child: duty.people.isEmpty
                              ? Text(
                                  l10n.nobodyYet,
                                  style: AppText.body.copyWith(
                                    color: c.secondaryLabel,
                                  ),
                                )
                              : Text.rich(
                                  TextSpan(
                                    children: [
                                      for (final (i, name) in duty.people.indexed) ...[
                                        if (i > 0) const TextSpan(text: '、'),
                                        TextSpan(
                                          text: name,
                                          style: _isMe(duty, name)
                                              ? TextStyle(
                                                  color: c.accent,
                                                  fontWeight: FontWeight.w600,
                                                )
                                              : null,
                                        ),
                                      ],
                                    ],
                                  ),
                                  style: AppText.body,
                                ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
