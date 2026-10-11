import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../data/backend.dart' show CloudException;
import '../../domain/day.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/roster_actions.dart';
import '../common/errors.dart';
import 'format.dart';

/// Runs an online write and offers its real, failure-reporting undo only
/// after it succeeds. A slow SDK response is not treated as an offline save.
Future<bool> runWithUndo(BuildContext context, String message, RosterWrite Function() write) async {
  final l10n = L10n.of(context);
  // A duty row may disappear before the server acknowledgment; keep the
  // feedback on its navigator rather than dropping it with that row.
  final feedbackContext = Navigator.of(context).context;
  try {
    final w = write();
    await w.done;
    if (feedbackContext.mounted) {
      Haptics.success();
      showToast(feedbackContext, message, onUndo: w.undo);
    }
    return context.mounted;
  } catch (error) {
    if (feedbackContext.mounted) {
      showToast(feedbackContext, error is CloudException ? errorText(l10n, error) : l10n.saveFailed);
    }
    return false;
  }
}

/// A shared, cancellable preview for explicit future service operations.
/// The apply action uses the exact baseline shown here, not a fresh replan.
Future<bool> showFutureRosterPreview(
  BuildContext context, {
  required String title,
  required RosterPreview preview,
  required Day today,
}) async =>
    await showAppSheet<bool>(
      context,
      expand: true,
      builder: (context) {
        final l10n = L10n.of(context);
        final plan = preview.plan;
        String changes(Roster before, Roster after) {
          final lines = <String>[];
          for (final duty in before.duties) {
            final next = after.duties.where((d) => d.role == duty.role).firstOrNull;
            if (next == duty) continue;
            // A renamed duty preserves its people in the preview.
            final renamed =
                next ?? after.duties.where((d) => !before.duties.any((old) => old.role == d.role)).firstOrNull;
            lines.add(
              l10n.rosterFutureDutyChange(
                duty.role,
                duty.people.join('、'),
                renamed?.role == duty.role ? renamed!.people.join('、') : renamed?.role ?? '',
              ),
            );
          }
          if (!listEquals(before.events, after.events)) {
            lines.add(
              l10n.rosterFutureEventChange(
                before.events.map((e) => e.name).join('、'),
                after.events.map((e) => e.name).join('、'),
              ),
            );
          }
          return lines.join('\n');
        }

        return SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: Space.s),
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: SecondaryButton(label: l10n.cancel, onPressed: () => Navigator.pop(context, false)),
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
                      child: Text(title, style: AppText.title3),
                    ),
                    if (plan.isEmpty && plan.conflicts.isEmpty)
                      EmptyState(message: L10n.of(context).rosterFutureChangesNone)
                    else
                      ListSection(
                        footer: L10n.of(context).rosterFutureChangesFooter,
                        children: [
                          for (final entry in plan.before.entries)
                            ListRow(
                              title: dayLabel(l10n, entry.value!.day, today),
                              subtitle: changes(entry.value!, plan.after[entry.key]!),
                              chevron: false,
                            ),
                          for (final r in plan.conflicts)
                            ListRow(
                              title: dayLabel(l10n, r.day, today),
                              subtitle: L10n.of(context).rosterFutureChangesConflict,
                              chevron: false,
                            ),
                        ],
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(Space.m),
                child: PrimaryButton(
                  label: L10n.of(context).rosterApplyFutureChanges,
                  onPressed: plan.isEmpty || plan.conflicts.isNotEmpty ? null : () => Navigator.pop(context, true),
                ),
              ),
            ],
          ),
        );
      },
    ) ??
    false;
