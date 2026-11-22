import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../domain/day.dart';
import '../../domain/models.dart';
import '../../domain/swap.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/roster_actions.dart';
import '../../state/roster_day.dart';
import 'editable_roster.dart';
import 'event_sheet.dart';
import 'format.dart';
import 'future_changes.dart';
import 'roster_card.dart';
import 'roster_note.dart';
import 'swap_asking.dart';
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
    final service = ref.watch(servicesProvider.select((s) => s.value?.byId(serviceType)));
    final page = day == null ? null : ref.watch(rosterDayProvider((serviceType, day)));
    if (day == null || service == null || page == null) {
      return Scaffold(appBar: AppBar(), body: const SizedBox.shrink());
    }
    if (!page.hasValue) {
      return Scaffold(
        appBar: AppBar(title: Text(service.name)),
        body: page.hasError
            ? ErrorRetry(
                message: l10n.loadFailed,
                onRetry: () => ref.invalidate(pastRosterProvider((serviceType, day))),
              )
            : const SizedBox.shrink(),
      );
    }
    final RosterDay(:roster, :past, arranges: led, :addable, :canEdit, :wholeDay) = page.requireValue;
    final today = ref.watch(todayProvider);
    final title = dayLabel(l10n, day, today);
    // From the day's tags, or 「＋ 特別活動」, for who changes the whole day.
    final editEvents = wholeDay ? () => _editEvents(context, ref, roster, service) : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(service.name),
        actions: savingActions(const []),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.xl),
        children: [
          if (!past) DayAsks(roster: roster),
          if (!canEdit)
            RosterDayView(
              roster: roster,
              title: title,
              highlightUid: ref.watch(uidProvider),
              // Mine to ask about only from today on, and not an event's.
              onMyDuty: roster.isEvent || roster.day.isBefore(today)
                  ? null
                  : (duty) => showMyDutyMenu(context, ref, roster, duty.role),
              asked: {
                for (final r in ref.watch(myOpenSwapRequestsProvider).value ?? const <SwapRequest>[])
                  if (r.rosterId == roster.id) r.duty: myOpenAskTag(l10n, r),
              },
            )
          else
            EditableRoster(
              roster: roster,
              title: title,
              arranges: led,
              onEditEvents: editEvents,
              onAddDuty: wholeDay || addable.isNotEmpty
                  ? () => _addDuty(context, ref, roster, addable, any: wholeDay)
                  : null,
            ),
          RosterNoteSection(rosterId: roster.id, canEdit: canEdit),
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
    final events = await showAppSheet<List<EventTag>>(
      context,
      builder: (context) => EventSheet(options: service.events, selected: roster.events),
    );
    // Ticking a tag off and on again only moves it to the end.
    if (events == null || !context.mounted || setEquals(events.toSet(), roster.events.toSet())) return;
    await runWithUndo(
      context,
      l10n.eventsUpdated,
      () => ref.read(rosterActionsProvider).setEvents(roster, events),
    );
  }
}
