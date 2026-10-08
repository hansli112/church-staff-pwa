import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../domain/day.dart';
import '../../domain/event_roster.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/roster_actions.dart';
import '../calendar/calendar_screen.dart';
import '../common/errors.dart';
import 'format.dart';
import 'roster_card.dart';
import 'roster_day_screen.dart';

/// The days an event's roster is on, as its heading says them.
String eventDaysLabel(L10n l10n, Roster r, Day today) => r.lastDay == r.day
    ? dayLabel(l10n, r.day, today)
    : '${dayLabel(l10n, r.day, today)} – ${dayLabel(l10n, r.lastDay, today)}';

/// The saved roster of calendar event [eventId], if it has one on or after
/// today.
final _eventRosterProvider = Provider.autoDispose.family<Roster?, String>(
  (ref, eventId) => ref.watch(
    savedRostersProvider.select((v) => v.value?.where((r) => r.id == Roster.idForEvent(eventId)).firstOrNull),
  ),
);

/// The roles a new roster for a day of a recurring event starts with: the
/// latest earlier day's (預設沿用上一次). Read once, from every event's
/// roster; none for a one-off event.
final _seriesRolesProvider = FutureProvider.autoDispose.family<List<String>, CalendarEvent>((ref, e) async {
  if (e.recurringEventId == null) return const [];
  return previousInSeries(e, await ref.churchData.eventRosters());
});

/// Whether this member may arrange events' rosters: admins and every roster
/// editor, in no 牧區.
final _canArrangeProvider = Provider.autoDispose<bool>(
  (ref) => ref.watch(meProvider.select((m) => m.value?.inGroup(Group.rosterEditors) ?? false)),
);

/// Opens [e]'s roster, which [e] lets the page start before it is saved.
void openEventRoster(BuildContext context, CalendarEvent e) =>
    GoRouter.of(context).push('/rosters/event/${e.id}', extra: e);

/// The 服事表 row on a calendar event: how many serve, for everyone; or
/// 安排服事 for those who may arrange it while it has none. Nothing once
/// the event is over: only rosters still to come are loaded. [onOpen]
/// opens it, closing the sheet first.
class EventRosterRow extends ConsumerWidget {
  const EventRosterRow({super.key, required this.event, required this.onOpen});

  final CalendarEvent event;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final id = event.id;
    if (id == null) return const SizedBox.shrink();
    final roster = ref.watch(_eventRosterProvider(id));
    final people = {
      for (final d in roster?.duties ?? const <Duty>[]) ...d.people,
    };
    if (roster != null) {
      return ListSection(
        children: [
          ListRow(
            title: l10n.eventRoster,
            leading: const Icon(Icons.people_outline),
            value: l10n.eventRosterPeople(people.length),
            onTap: onOpen,
          ),
        ],
      );
    }
    final ended = eventDays(event).last.isBefore(ref.watch(todayProvider));
    if (ended || !ref.watch(_canArrangeProvider)) return const SizedBox.shrink();
    return ListSection(
      children: [
        ListRow(
          title: l10n.arrangeEventRoster,
          leading: const Icon(Icons.person_add_alt),
          onTap: onOpen,
        ),
      ],
    );
  }
}

/// A calendar event's roster (活動的服事表). Everyone can look; admins and
/// roster editors arrange it like a service's day: pick people per duty,
/// add duties, or copy them from another event (沿用). The first change
/// saves it. Opened with no [event] (a push, 我的服事, a reload of the
/// page) it shows the saved roster only.
class EventRosterScreen extends ConsumerWidget {
  const EventRosterScreen({super.key, required this.eventId, this.event});

  final String eventId;
  final CalendarEvent? event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final today = ref.watch(todayProvider);
    final rosters = ref.watch(savedRostersProvider);
    final saved = ref.watch(_eventRosterProvider(eventId));
    final e = event;
    final calendarId = ref.watch(calendarSettingsProvider.select((s) => s.value?.calendarId));
    final roles = e == null ? const <String>[] : ref.watch(_seriesRolesProvider(e)).value ?? const <String>[];
    final roster =
        saved ??
        (e != null && e.id == eventId
            ? eventRoster(
                e,
                duties: [for (final r in roles) Duty(role: r)],
                calendarId: calendarId,
              )
            : null);
    final canEdit = ref.watch(_canArrangeProvider);
    final editable = canEdit && ref.watch(eventEditingProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(roster?.forEvent?.title ?? ''),
        actions: [
          if (canEdit && roster != null)
            PopupMenuButton<String>(
              enabled: editable,
              tooltip: l10n.edit,
              icon: const Icon(Icons.more_horiz),
              onSelected: (v) => switch (v) {
                'duty' => _addDuty(context, ref, roster),
                'copy' => _copyDuties(context, ref, roster),
                _ => null,
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'duty', child: Text(l10n.addDuty)),
                PopupMenuItem(value: 'copy', child: Text(l10n.copyDuties)),
              ],
            ),
        ],
      ),
      body: switch (rosters) {
        AsyncValue(hasError: true, hasValue: false) => ErrorRetry(
          message: l10n.loadFailed,
          onRetry: () => ref.invalidate(savedRostersProvider),
        ),
        _ when roster != null => ListView(
          padding: const EdgeInsets.only(bottom: Space.xl),
          children: [
            if (canEdit)
              EditableRoster(
                roster: roster,
                title: eventDaysLabel(l10n, roster, today),
                whenEmpty: EmptyState(
                  message: l10n.eventRosterEmpty,
                  actionLabel: editable ? l10n.addDuty : null,
                  onAction: () => _addDuty(context, ref, roster),
                ),
              )
            else
              RosterDayView(
                roster: roster,
                title: eventDaysLabel(l10n, roster, today),
                highlightUid: ref.watch(uidProvider),
                highlightName: ref.watch(meProvider.select((m) => m.value?.name)),
              ),
          ],
        ),
        AsyncValue(hasValue: false) => const SizedBox.shrink(),
        _ => EmptyState(message: l10n.eventRosterGone),
      },
    );
  }

  Future<void> _addDuty(BuildContext context, WidgetRef ref, Roster roster) async {
    final l10n = L10n.of(context);
    final present = {for (final d in roster.duties) d.role};
    final services = ref.read(servicesProvider).value?.services ?? const <Service>[];
    final role = await showAppSheet<String>(
      context,
      builder: (context) => AddDutySheet(
        suggestions: [
          for (final d in eventDutySuggestions(services))
            if (!present.contains(d)) d,
        ],
      ),
    );
    final name = role?.trim() ?? '';
    if (name.isEmpty || present.contains(name) || !context.mounted) return;
    await runWithUndo(context, l10n.dutyUpdated(name), () => ref.read(rosterActionsProvider).addDuty(roster, name));
  }

  /// 沿用: adds the duties of an earlier event's roster, without its people.
  Future<void> _copyDuties(BuildContext context, WidgetRef ref, Roster roster) async {
    final l10n = L10n.of(context);
    final today = ref.read(todayProvider);
    final List<Roster> others;
    try {
      others = [
        for (final r in await ref.churchData.eventRosters())
          if (r.day.isBefore(roster.day) && r.duties.isNotEmpty) r,
      ];
    } catch (e) {
      if (context.mounted) showToast(context, errorText(l10n, e));
      return;
    }
    if (!context.mounted) return;
    final from = await showAppSheet<Roster>(
      context,
      expand: others.length > 6,
      builder: (context) => SafeArea(
        child: others.isEmpty
            ? SizedBox(height: 200, child: EmptyState(message: l10n.copyDutiesNone))
            : ListView(
                shrinkWrap: true,
                children: [
                  ListSection(
                    header: l10n.copyDutiesHeader,
                    children: [
                      for (final r in others)
                        ListRow(
                          title: r.forEvent!.title,
                          subtitle: [for (final d in r.duties) d.role].join('、'),
                          value: dayLabel(l10n, r.day, today),
                          onTap: () => Navigator.pop(context, r),
                        ),
                    ],
                  ),
                ],
              ),
      ),
    );
    if (from == null || !context.mounted) return;
    final present = {for (final d in roster.duties) d.role};
    final count = {for (final d in from.duties) d.role}.difference(present).length;
    if (count == 0) return;
    await runWithUndo(
      context,
      l10n.dutiesCopied(count),
      () => ref.read(rosterActionsProvider).addDuties(roster, [for (final d in from.duties) d.role]),
    );
  }
}
