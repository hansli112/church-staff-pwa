import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../domain/day.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import 'format.dart';
import 'roster_card.dart';

/// The days an event's roster is on, as its heading says them.
String eventDaysLabel(L10n l10n, Roster r, Day today) => r.lastDay == r.day
    ? dayLabel(l10n, r.day, today)
    : '${dayLabel(l10n, r.day, today)} – ${dayLabel(l10n, r.lastDay, today)}';

/// A calendar event's roster (活動的服事表), where a push or 我的服事
/// opens it.
class EventRosterScreen extends ConsumerWidget {
  const EventRosterScreen({super.key, required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final today = ref.watch(todayProvider);
    final rosters = ref.watch(savedRostersProvider);
    final roster = rosters.value?.where((r) => r.id == Roster.idForEvent(eventId)).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(roster?.forEvent?.title ?? '')),
      body: switch (rosters) {
        AsyncValue(hasValue: false, hasError: false) => const SizedBox.shrink(),
        AsyncValue(hasValue: false) => ErrorRetry(
          message: l10n.loadFailed,
          onRetry: () => ref.invalidate(savedRostersProvider),
        ),
        _ when roster == null => EmptyState(message: l10n.eventRosterGone),
        _ => ListView(
          padding: const EdgeInsets.only(bottom: Space.xl),
          children: [
            RosterDayView(
              roster: roster,
              title: eventDaysLabel(l10n, roster, today),
              highlightUid: ref.watch(uidProvider),
              highlightName: ref.watch(meProvider.select((m) => m.value?.name)),
            ),
          ],
        ),
      },
    );
  }
}
