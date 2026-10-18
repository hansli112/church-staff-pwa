import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
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
    final l10n = L10n.of(context);
    return RosterDayView(
      roster: roster,
      leading: dayBlock(l10n, roster.day, today),
      title: dayBesideBlock(l10n, roster.day, today),
      highlightUid: uid,
      onTap: onTap,
    );
  }
}

/// The content of a roster day: date, event tags, then each duty and its
/// people. My own name is bold so I find it at a glance; the accent colour
/// stays for actions and status.
class RosterDayView extends StatelessWidget {
  const RosterDayView({
    super.key,
    required this.roster,
    required this.title,
    this.leading,
    this.highlightUid,
    this.onTap,
  });

  final Roster roster;
  final String title;

  /// Before the title, e.g. the day as a [DateBlock].
  final Widget? leading;
  final String? highlightUid;
  final VoidCallback? onTap;

  bool _isMe(Duty duty, String name) => highlightUid != null && duty.uids[name] == highlightUid;

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
                    if (leading != null) ...[leading!, const SizedBox(width: 12)],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: AppText.headline),
                          if (roster.events.isNotEmpty) ...[
                            const SizedBox(height: Space.xs),
                            Wrap(
                              spacing: Space.xs,
                              runSpacing: Space.xs,
                              children: [
                                for (final e in roster.events) Tag.event(context, e.name, e.color),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (onTap != null)
                      Icon(
                        Symbols.chevron_right_rounded,
                        color: c.tertiaryLabel,
                        size: 22,
                      ),
                  ],
                ),
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
                                        if (i > 0) TextSpan(text: l10n.listSeparator),
                                        TextSpan(
                                          text: name,
                                          style: _isMe(duty, name)
                                              ? const TextStyle(fontWeight: FontWeight.w700)
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
