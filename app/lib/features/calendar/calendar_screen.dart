import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/dates.dart';
import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../data/backend.dart';
import '../../domain/day.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/calendar.dart';
import '../../state/providers.dart';
import '../common/calendar_read_notice.dart';
import '../common/time_zones.dart';
import '../rosters/format.dart';
import 'event_sheet.dart';
import 'month_grid.dart';

export '../../state/calendar.dart' show calendarSettingsProvider;

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
              icon: Icon(gridShown ? Symbols.view_list_rounded : Symbols.calendar_view_month_rounded),
              onPressed: () => ref.read(monthGridShownProvider.notifier).toggle(),
            ),
          if (canEdit)
            IconButton(
              tooltip: l10n.calNewEvent,
              icon: const Icon(Symbols.add_rounded),
              onPressed: () => editEvent(context, ref, null, month: month, day: ref.read(calendarSelectedDayProvider)),
            ),
        ],
      ),
      body: switch (settings) {
        null => const SizedBox.shrink(),
        CalendarSettings(connected: false) => EmptyState(
          icon: Symbols.calendar_month_rounded,
          message: l10n.calNotConnected,
          actionLabel: (me?.isAdmin ?? false) ? l10n.calConnect : null,
          onAction: () => context.push('/me/calendar'),
        ),
        CalendarSettings(needsReconnect: true) => EmptyState(
          icon: Symbols.calendar_month_rounded,
          message: (me?.isAdmin ?? false) ? l10n.calNeedsReconnect : l10n.calNeedsReconnectStaff,
          actionLabel: (me?.isAdmin ?? false) ? l10n.calReconnect : null,
          onAction: () => context.push('/me/calendar'),
        ),
        CalendarSettings(calendarName: null) => EmptyState(
          icon: Symbols.calendar_month_rounded,
          message: l10n.calNoCalendarYet,
          actionLabel: (me?.isAdmin ?? false) ? l10n.calPickCalendar : null,
          onAction: () => context.push('/me/calendar'),
        ),
        _ => _Agenda(month: month, canEdit: canEdit),
      },
    );
  }
}

/// The day picked on the month grid, if any: the agenda shows its events
/// only, and a new event starts on it. Cleared when the month changes and
/// when the month grid is shown or folded away.
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

  /// The month whose neighbours were last read ahead.
  DateTime? _readAheadOf;

  @override
  void didUpdateWidget(_Agenda old) {
    super.didUpdateWidget(old);
    if (old.month != widget.month && _scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Shows only [day]'s events below the month; the same day again, the
  /// whole month.
  void _select(Day day) {
    final picked = ref.read(calendarSelectedDayProvider);
    ref.read(calendarSelectedDayProvider.notifier).select(picked == day ? null : day);
    if (_scroll.hasClients) _scroll.jumpTo(0);
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
    if (_readAheadOf != month) {
      _readAheadOf = month;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) readAhead(ref, month);
      });
    }
    final readStatus = ref.watch(calendarReadStatusProvider(monthKey(month)));
    final today = ref.watch(todayProvider);
    final selected = ref.watch(calendarSelectedDayProvider);
    final gridShown = ref.watch(monthGridShownProvider);
    final title = DateFormat.yMMMM().format(month);
    final loaded = events.value ?? const <CalendarEvent>[];
    void shift(int months) => ref.read(calendarMonthProvider.notifier).shift(months);

    final header = Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.s),
      child: Row(
        children: [
          IconButton(
            tooltip: l10n.calPrevMonth,
            icon: const Icon(Symbols.chevron_left_rounded),
            onPressed: () => shift(-1),
          ),
          Expanded(
            child: Text(title, textAlign: TextAlign.center, style: AppText.headline),
          ),
          IconButton(
            tooltip: l10n.calNextMonth,
            icon: const Icon(Symbols.chevron_right_rounded),
            onPressed: () => shift(1),
          ),
        ],
      ),
    );
    final grid = MonthGrid(
      month: shownMonth,
      today: today,
      events: loaded,
      selected: selected,
      onSelect: _select,
      onShift: shift,
    );

    Widget row(CalendarEvent e) => ListRow(
      title: e.title,
      subtitle: e.location,
      trailing: Text(
        _when(l10n, e),
        textAlign: TextAlign.end,
        style: AppText.body.copyWith(color: AppColors.of(context).secondaryLabel),
      ),
      // Opens the event either way: to edit, or to read. A new one shows
      // while it is saved, and opens once it has an id.
      chevron: true,
      onTap: e.id == null
          ? null
          : () => canEdit ? editEvent(context, ref, e, month: month) : showEventDetail(context, e),
    );

    final List<Widget> agenda;
    if (selected != null) {
      // One day picked: its events only, every one that covers it.
      final onDay = [
        for (final e in loaded)
          if (e.daysWithin(selected, selected) != null) e,
      ];
      agenda = [
        ListSection(
          header: dayLabel(l10n, selected, today),
          children: [
            for (final e in onDay) row(e),
            if (onDay.isEmpty) ListRow(title: l10n.calNoEventsThatDay),
            if (canEdit)
              ListRow(
                leading: const Icon(Symbols.add_rounded),
                title: l10n.calNewEvent,
                onTap: () => editEvent(context, ref, null, month: month, day: selected),
              ),
          ],
        ),
        ListSection(
          children: [
            ListRow(
              leading: const Icon(Symbols.calendar_view_month_rounded),
              title: l10n.calWholeMonth,
              onTap: () => ref.read(calendarSelectedDayProvider.notifier).select(null),
            ),
          ],
        ),
      ];
    } else {
      // Each event under its first day in this month.
      final byDay = <Day, List<CalendarEvent>>{};
      for (final e in loaded) {
        final listed = e.daysWithin(shownMonth, shownMonth.lastOfMonth)?.first;
        if (listed != null) byDay.putIfAbsent(listed, () => []).add(e);
      }
      agenda = [
        for (final d in byDay.keys.toList()..sort())
          ListSection(
            header: dayLabel(l10n, d, today),
            children: [for (final e in byDay[d]!) row(e)],
          ),
      ];
    }
    // In place of the agenda, centred in the room left: loading, an error,
    // or a month with nothing on (a picked day says so itself).
    final Widget? instead = events.when(
      skipLoadingOnReload: true,
      loading: () => const CircularProgressIndicator.adaptive(),
      error: (e, _) => ErrorRetry(
        message: e is CloudException && e.reason == CloudReason.reconnect
            ? l10n.calNeedsReconnectStaff
            : l10n.loadFailed,
        onRetry: () => ref.invalidate(calendarEventsProvider(monthKey(month))),
      ),
      data: (list) => list.isEmpty && selected == null ? EmptyState(message: l10n.calNoEvents) : null,
    );
    final divider = Divider(height: 0.5, thickness: 0.5, color: AppColors.of(context).separator);

    return LayoutBuilder(
      builder: (context, constraints) {
        final headerHeight = Space.minTap(Theme.of(context).platform);
        final pinned =
            constraints.maxHeight - headerHeight - MonthGrid.tallest(context) >=
            MediaQuery.textScalerOf(context).scale(_agendaMinHeight);
        return Column(
          children: [
            header,
            if (pinned)
              _Folding(
                shown: gridShown,
                child: Column(children: [grid, divider]),
              ),
            Expanded(
              child: RefreshIndicator.adaptive(
                onRefresh: () => ref.refresh(calendarEventsProvider(monthKey(month)).future),
                child: CustomScrollView(
                  controller: _scroll,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(child: CalendarReadNotice(status: readStatus)),
                    const SliverToBoxAdapter(child: ChurchClockNotice()),
                    if (!pinned)
                      SliverToBoxAdapter(
                        child: _Folding(shown: gridShown, child: grid),
                      ),
                    if (instead != null)
                      SliverFillRemaining(hasScrollBody: false, child: Center(child: instead))
                    else
                      SliverPadding(
                        padding: const EdgeInsets.only(bottom: Space.xl),
                        sliver: SliverList.list(children: agenda),
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

/// The month grid folding open and shut under the month's name, as the
/// button above it shows or hides it; at once when the phone asks for less
/// motion.
class _Folding extends StatelessWidget {
  const _Folding({required this.shown, required this.child});

  final bool shown;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 250),
    switchInCurve: Curves.easeInOut,
    switchOutCurve: Curves.easeInOut,
    layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
    transitionBuilder: (child, animation) => SizeTransition(
      sizeFactor: animation,
      axisAlignment: -1,
      child: FadeTransition(opacity: animation, child: child),
    ),
    child: shown
        ? KeyedSubtree(key: const ValueKey(true), child: child)
        : const SizedBox(key: ValueKey(false), width: double.infinity),
  );
}

/// When an event is, beside its title: all day or its start time, or for
/// one over several days the whole span, on two lines when it has times.
String _when(L10n l10n, CalendarEvent e) {
  final time = DateFormat.Hm();
  final day = shortMonthDay(l10n);
  if (e.lastDay == e.day) return e.allDay ? l10n.calAllDay : time.format(e.start);
  if (e.allDay) return '${day.format(e.start)}–${day.format(e.lastDay.midnight)}';
  return '${day.format(e.start)} ${time.format(e.start)} –\n${day.format(e.end)} ${time.format(e.end)}';
}
