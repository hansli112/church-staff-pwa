import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../domain/day.dart';
import '../../domain/models.dart';
import '../../domain/roster_edit.dart';
import '../../domain/schedule.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/roster_actions.dart';
import 'editable_roster.dart';
import 'event_sheet.dart';
import 'format.dart';
import 'future_changes.dart';
import 'roster_card.dart';
import '../common/saving_indicator.dart';

/// One service on one day. Everyone can look; people who may arrange this
/// service's rosters (admin, or roster-editors holding its zone) tap a duty
/// to pick people, a name to swap or remove it, and use the menu for duties
/// and special events. Every change saves once made (the picker's with
/// its 完成) and can be undone.
class RosterDayScreen extends ConsumerWidget {
  const RosterDayScreen({
    super.key,
    required this.serviceType,
    required this.dayKey,
  });

  final String serviceType;
  final String dayKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final day = Day.tryParse(dayKey);
    final service = ref.watch(
      servicesProvider.select((s) => s.value?.byId(serviceType)),
    );
    final rosters = ref.watch(serviceRostersProvider(serviceType));
    final today = ref.watch(todayProvider);
    if (day == null || service == null) {
      return Scaffold(appBar: AppBar(), body: const SizedBox.shrink());
    }
    final roster = rosters.value?.where((r) => r.day == day).firstOrNull ?? draftRoster(service, day);
    // A 事工's 負責人 arranges only the duties it leads (#82).
    final led = ref.watch(arrangesProvider(serviceType));
    final whole = led.all;
    final canEdit = led.any;
    // Keeps what editing reads loaded, so the picker opens at once and
    // writes see the church as it is.
    final editable = canEdit && ref.watch(rosterEditingProvider(serviceType));
    final title = dayLabel(l10n, day, today);
    final addable = addableDuties(roster, service.duties, led);
    // From the menu or the day's tags, for who changes the whole day.
    final editEvents = whole ? () => _editEvents(context, ref, roster, service) : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(service.name),
        actions: savingActions([
          if (canEdit && (whole || addable.isNotEmpty))
            PopupMenuButton<String>(
              enabled: editable,
              tooltip: l10n.edit,
              icon: const Icon(Symbols.more_horiz_rounded),
              onSelected: (v) => switch (v) {
                'duty' => _addDuty(context, ref, roster, addable, any: whole),
                'events' => editEvents?.call(),
                _ => null,
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'duty', child: Text(l10n.addDuty)),
                if (editEvents != null) PopupMenuItem(value: 'events', child: Text(l10n.events)),
              ],
            ),
        ]),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.xl),
        children: [
          if (!canEdit)
            RosterDayView(
              roster: roster,
              title: title,
              highlightUid: ref.watch(uidProvider),
            )
          else
            EditableRoster(
              roster: roster,
              title: title,
              arranges: led,
              onEditEvents: editEvents,
            ),
        ],
      ),
    );
  }

  /// Adds a duty to [roster]: one of [suggestions], or, with [any], one
  /// typed in.
  Future<void> _addDuty(
    BuildContext context,
    WidgetRef ref,
    Roster roster,
    List<String> suggestions, {
    required bool any,
  }) async {
    final l10n = L10n.of(context);
    final present = {for (final d in roster.duties) d.role};
    final role = await showAppSheet<String>(
      context,
      builder: (context) => AddDutySheet(suggestions: suggestions, typed: any),
    );
    if (role == null || role.trim().isEmpty || present.contains(role.trim())) {
      return;
    }
    if (!any && !suggestions.contains(role.trim())) return;
    if (!context.mounted) return;
    await runWithUndo(
      context,
      l10n.dutyUpdated(role.trim()),
      () => ref.read(rosterActionsProvider).addDuty(roster, role.trim()),
    );
  }

  Future<void> _editEvents(
    BuildContext context,
    WidgetRef ref,
    Roster roster,
    Service service,
  ) async {
    final l10n = L10n.of(context);
    final editsSettings = ref.read(meProvider).value?.editsServiceSettings ?? false;
    final result = await showAppSheet<EventSheetResult>(
      context,
      builder: (context) => EventSheet(
        options: service.events,
        selected: roster.events,
        canAddToCommon: editsSettings,
      ),
    );
    if (result == null || !context.mounted) return;
    // Ticking a tag off and on again only moves it to the end.
    if (result.addToCommon.isEmpty && setEquals(result.events.toSet(), roster.events.toSet())) return;
    if (!context.mounted) return;
    await runWithUndo(
      context,
      l10n.eventsUpdated,
      () => ref.read(rosterActionsProvider).setEvents(roster, result.events, addToCommon: result.addToCommon),
    );
  }
}
