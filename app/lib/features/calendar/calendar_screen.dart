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
import '../../state/calendar.dart';
import '../../state/providers.dart';
import '../rosters/format.dart';
import 'event_sheet.dart';
import 'month_grid.dart';

final calendarSettingsProvider = StreamProvider<CalendarSettings>((ref) {
  if (!ref.watch(churchOpenProvider)) return Stream.value(const CalendarSettings());
  return openChurch(ref).calendarSettings();
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

/// Whether the month grid shows above the agenda. Remembered on this device.
class MonthGridShown extends Notifier<bool> {
  static const _key = 'calendar_month_grid';

  @override
  bool build() => ref.read(prefsProvider).getBool(_key) ?? true;

  void toggle() {
    state = !state;
    ref.read(prefsProvider).setBool(_key, state);
  }
}

final monthGridShownProvider = NotifierProvider<MonthGridShown, bool>(MonthGridShown.new);

/// 行事曆: the church's Google Calendar month by month, a month grid above
/// an agenda of the days with events.
class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(calendarSettingsProvider).value;
    final me = ref.watch(meProvider).value;
    final month = ref.watch(calendarMonthProvider);
    final canEdit = (me?.inGroup(Group.calendarEditors) ?? false) && (settings?.ready ?? false);
    final gridShown = ref.watch(monthGridShownProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tabCalendar),
        actions: [
          if (settings?.ready ?? false)
            IconButton(
              tooltip: gridShown ? l10n.calHideMonth : l10n.calShowMonth,
              icon: Icon(gridShown ? Icons.view_list_outlined : Icons.calendar_view_month_outlined),
              onPressed: () => ref.read(monthGridShownProvider.notifier).toggle(),
            ),
          if (canEdit)
            IconButton(
              tooltip: l10n.calNewEvent,
              icon: const Icon(Icons.add),
              onPressed: () => editEvent(context, ref, null, month: month, day: ref.read(calendarSelectedDayProvider)),
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

/// The day picked on the month grid, if any. Cleared when the month
/// changes and when the month grid is shown or folded away.
class CalendarSelectedDay extends Notifier<Day?> {
  @override
  Day? build() {
    ref.watch(calendarMonthProvider);
    ref.watch(monthGridShownProvider);
    return null;
  }

  void select(Day? day) => state = day;
}

final calendarSelectedDayProvider = NotifierProvider<CalendarSelectedDay, Day?>(CalendarSelectedDay.new);

class _Agenda extends ConsumerStatefulWidget {
  const _Agenda({required this.month, required this.canEdit});

  final DateTime month;
  final bool canEdit;

  @override
  ConsumerState<_Agenda> createState() => _AgendaState();
}

class _AgendaState extends ConsumerState<_Agenda> {
  final _scroll = ScrollController();
  final _sections = <Day, GlobalKey>{};

  @override
  void didUpdateWidget(_Agenda old) {
    super.didUpdateWidget(old);
    if (old.month != widget.month) {
      _sections.clear();
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Selects [day] and brings the events covering it into view.
  void _select(Day day, Map<Day, Day> anchors) {
    ref.read(calendarSelectedDayProvider.notifier).select(day);
    final target = _sections[anchors[day]]?.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  /// Room the agenda keeps below a month grid that stays put, at the usual
  /// text size; it grows with the text. With less (a small phone, a phone
  /// on its side, very large text) the month scrolls with the agenda
  /// instead. Decided for a six-week month, so it is the same every month.
  static const _agendaMinHeight = 200.0;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final month = widget.month;
    final shownMonth = Day(month.year, month.month, 1);
    final canEdit = widget.canEdit;
    final events = ref.watch(calendarEventsProvider(monthKey(month)));
    final today = ref.watch(todayProvider);
    final selected = ref.watch(calendarSelectedDayProvider);
    final gridShown = ref.watch(monthGridShownProvider);
    final title = DateFormat.yMMMM('zh_TW').format(month);
    final loaded = events.value ?? const <CalendarEvent>[];
    final anchors = agendaAnchors(loaded, from: shownMonth, to: shownMonth.lastOfMonth);
    void shift(int months) => ref.read(calendarMonthProvider.notifier).shift(months);

    final header = Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.s),
      child: Row(
        children: [
          IconButton(
            tooltip: l10n.calPrevMonth,
            icon: const Icon(Icons.chevron_left),
            onPressed: () => shift(-1),
          ),
          Expanded(
            child: Text(title, textAlign: TextAlign.center, style: AppText.headline),
          ),
          IconButton(
            tooltip: l10n.calNextMonth,
            icon: const Icon(Icons.chevron_right),
            onPressed: () => shift(1),
          ),
        ],
      ),
    );
    final grid = gridShown
        ? MonthGrid(
            month: shownMonth,
            today: today,
            events: loaded,
            selected: selected,
            onSelect: (d) => _select(d, anchors),
            onShift: shift,
          )
        : null;

    // Each event under its first day in this month, as [agendaAnchors].
    final byDay = <Day, List<CalendarEvent>>{};
    for (final e in loaded) {
      final listed = e.daysWithin(shownMonth, shownMonth.lastOfMonth)?.first;
      if (listed != null) byDay.putIfAbsent(listed, () => []).add(e);
    }
    final days = byDay.keys.toList()..sort();
    final agenda = [
      for (final d in days)
        ListSection(
          key: _sections.putIfAbsent(d, GlobalKey.new),
          header: dayLabel(l10n, d, today),
          children: [
            for (final e in byDay[d]!)
              ListRow(
                title: e.title,
                subtitle: e.location,
                trailing: Text(
                  _when(l10n, e),
                  textAlign: TextAlign.end,
                  style: AppText.body.copyWith(color: AppColors.of(context).secondaryLabel),
                ),
                chevron: canEdit,
                onTap: () => canEdit ? editEvent(context, ref, e, month: month) : showEventDetail(context, e),
              ),
          ],
        ),
    ];
    // In place of the agenda, centred in the room left: loading, an error,
    // or a month with nothing on.
    final Widget? instead = events.when(
      skipLoadingOnReload: true,
      loading: () => const CircularProgressIndicator.adaptive(),
      error: (e, _) => ErrorRetry(
        message: e is CloudException && e.reason == CloudReason.reconnect
            ? l10n.calNeedsReconnectStaff
            : l10n.loadFailed,
        onRetry: () => ref.invalidate(calendarEventsProvider(monthKey(month))),
      ),
      data: (list) => list.isEmpty ? EmptyState(message: l10n.calNoEvents) : null,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final headerHeight = Space.minTap(Theme.of(context).platform);
        final pinned =
            grid != null &&
            constraints.maxHeight - headerHeight - MonthGrid.tallest(context) >=
                MediaQuery.textScalerOf(context).scale(_agendaMinHeight);
        return Column(
          children: [
            header,
            if (pinned) ...[
              grid,
              Divider(height: 0.5, thickness: 0.5, color: AppColors.of(context).separator),
            ],
            Expanded(
              child: RefreshIndicator.adaptive(
                onRefresh: () => ref.refresh(calendarEventsProvider(monthKey(month)).future),
                child: CustomScrollView(
                  controller: _scroll,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    if (grid != null && !pinned) SliverToBoxAdapter(child: grid),
                    if (instead != null)
                      SliverFillRemaining(hasScrollBody: false, child: Center(child: instead))
                    else
                      SliverPadding(
                        padding: const EdgeInsets.only(bottom: Space.xl),
                        // Every section is built, so a tapped day can scroll to one.
                        sliver: SliverToBoxAdapter(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: agenda),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// When an event is, beside its title: all day or its start time, or for
/// one over several days the whole span, on two lines when it has times.
String _when(L10n l10n, CalendarEvent e) {
  final time = DateFormat.Hm('zh_TW');
  final day = DateFormat.Md('zh_TW');
  if (e.lastDay == e.day) return e.allDay ? l10n.calAllDay : time.format(e.start);
  if (e.allDay) return '${day.format(e.start)}–${day.format(DateTime(e.lastDay.year, e.lastDay.month, e.lastDay.day))}';
  return '${day.format(e.start)} ${time.format(e.start)} –\n${day.format(e.end)} ${time.format(e.end)}';
}
