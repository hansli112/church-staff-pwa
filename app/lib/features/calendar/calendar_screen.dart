import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../data/backend.dart';
import '../../domain/day.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../rosters/format.dart';
import 'event_sheet.dart';

final calendarSettingsProvider = StreamProvider<CalendarSettings>((ref) {
  if (!ref.watch(churchOpenProvider)) return Stream.value(const CalendarSettings());
  return ref.watch(churchDataProvider)!.calendarSettings();
});

/// The month on screen, as `YYYY-MM`.
class CalendarMonth extends Notifier<DateTime> {
  @override
  DateTime build() {
    final t = ref.watch(todayProvider);
    return DateTime(t.year, t.month);
  }

  void shift(int months) => state = DateTime(state.year, state.month + months);
}

final calendarMonthProvider = NotifierProvider<CalendarMonth, DateTime>(CalendarMonth.new);

String monthKey(DateTime m) => '${m.year.toString().padLeft(4, '0')}-${m.month.toString().padLeft(2, '0')}';

/// Events of a month, read through the backend's shared cache.
final calendarEventsProvider = FutureProvider.autoDispose.family<List<CalendarEvent>, String>((ref, month) {
  final cid = ref.watch(currentChurchIdProvider);
  if (cid == null) return const [];
  return ref.watch(backendProvider).cloud.calendarEvents(cid, month);
});

/// 行事曆: the church's Google Calendar as an agenda, month by month.
class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(calendarSettingsProvider).value;
    final me = ref.watch(meProvider).value;
    final month = ref.watch(calendarMonthProvider);
    final canEdit = (me?.inGroup(Group.calendarEditors) ?? false) && (settings?.ready ?? false);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tabCalendar),
        actions: [
          if (canEdit)
            IconButton(
              tooltip: l10n.calNewEvent,
              icon: const Icon(Icons.add),
              onPressed: () => editEvent(context, ref, null, month: month),
            ),
        ],
      ),
      body: switch (settings) {
        null => const SizedBox.shrink(),
        CalendarSettings(connected: false) => EmptyState(
          message: l10n.calNotConnected,
          actionLabel: (me?.isAdmin ?? false) ? l10n.calConnect : null,
          onAction: () => context.push('/me/calendar'),
        ),
        CalendarSettings(needsReconnect: true) => EmptyState(
          message: (me?.isAdmin ?? false) ? l10n.calNeedsReconnect : l10n.calNeedsReconnectStaff,
          actionLabel: (me?.isAdmin ?? false) ? l10n.calReconnect : null,
          onAction: () => context.push('/me/calendar'),
        ),
        CalendarSettings(calendarName: null) => EmptyState(
          message: l10n.calNoCalendarYet,
          actionLabel: (me?.isAdmin ?? false) ? l10n.calPickCalendar : null,
          onAction: () => context.push('/me/calendar'),
        ),
        _ => _Agenda(month: month, canEdit: canEdit),
      },
    );
  }
}

class _Agenda extends ConsumerWidget {
  const _Agenda({required this.month, required this.canEdit});

  final DateTime month;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final events = ref.watch(calendarEventsProvider(monthKey(month)));
    final today = ref.watch(todayProvider);
    final title = DateFormat.yMMMM('zh_TW').format(month);
    final time = DateFormat.Hm('zh_TW');
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.s),
          child: Row(
            children: [
              IconButton(
                tooltip: l10n.calPrevMonth,
                icon: const Icon(Icons.chevron_left),
                onPressed: () => ref.read(calendarMonthProvider.notifier).shift(-1),
              ),
              Expanded(
                child: Text(title, textAlign: TextAlign.center, style: AppText.headline),
              ),
              IconButton(
                tooltip: l10n.calNextMonth,
                icon: const Icon(Icons.chevron_right),
                onPressed: () => ref.read(calendarMonthProvider.notifier).shift(1),
              ),
            ],
          ),
        ),
        Expanded(
          child: events.when(
            skipLoadingOnReload: true,
            loading: () => const Center(child: CircularProgressIndicator.adaptive()),
            error: (e, _) => ErrorRetry(
              message: e is CloudException && e.detail == 'reconnect' ? l10n.calNeedsReconnectStaff : l10n.loadFailed,
              onRetry: () => ref.invalidate(calendarEventsProvider(monthKey(month))),
            ),
            data: (list) {
              if (list.isEmpty) return EmptyState(message: l10n.calNoEvents);
              final byDay = <Day, List<CalendarEvent>>{};
              for (final e in list) {
                byDay.putIfAbsent(e.day, () => []).add(e);
              }
              final days = byDay.keys.toList()..sort();
              return RefreshIndicator.adaptive(
                onRefresh: () => ref.refresh(calendarEventsProvider(monthKey(month)).future),
                child: ListView(
                  padding: const EdgeInsets.only(bottom: Space.xl),
                  children: [
                    for (final d in days)
                      ListSection(
                        header: dayLabel(l10n, d, today),
                        children: [
                          for (final e in byDay[d]!)
                            ListRow(
                              title: e.title,
                              subtitle: e.location,
                              value: e.allDay ? l10n.calAllDay : time.format(e.start),
                              chevron: canEdit,
                              onTap: () =>
                                  canEdit ? editEvent(context, ref, e, month: month) : showEventDetail(context, e),
                            ),
                        ],
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
