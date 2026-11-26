import 'dart:math';

import 'package:flutter/cupertino.dart';
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
import '../rosters/day_block.dart';
import '../rosters/format.dart';
import '../common/saving_indicator.dart';
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

  /// [month]'s month, picked from its name.
  void show(DateTime month) => state = DateTime(month.year, month.month);
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

/// Which events the calendar shows (#84): `mine` (跟我有關的), `all` or one
/// service's or 事工's ([ChurchGroup.key]).
/// Remembered per church on this device; at first `all` for admins and 行政,
/// who look after the whole church, and `mine` for everyone else.
class CalendarFilter extends Notifier<String> {
  String get _key => 'calendar_filter/${ref.read(currentChurchIdProvider)}';

  @override
  String build() {
    ref.watch(currentChurchIdProvider);
    ref.watch(meProvider.select((m) => m.value?.inGroup(Group.calendarEditors)));
    return ref.read(prefsProvider).getString(_key) ?? first;
  }

  /// The one this member starts on.
  String get first => (ref.read(meProvider).value?.inGroup(Group.calendarEditors) ?? false) ? 'all' : 'mine';

  void pick(String filter) {
    state = filter;
    ref.read(prefsProvider).setString(_key, filter);
  }
}

final calendarFilterProvider = NotifierProvider<CalendarFilter, String>(CalendarFilter.new);

/// The filters to pick from, with their names: 跟我有關的, 全部 and each
/// service's and 事工's. Not each 小組's: a church may have twenty, and
/// theirs are under 全部 and, for their people, 跟我有關的. Not 全教會 alone:
/// 跟我有關的 has the church's, and it read the same as 全部.
final _calendarFiltersProvider = Provider<List<(String, String)>?>((ref) {
  final groups = ref.watch(churchGroupsProvider);
  if (groups == null) return null;
  return [
    ('mine', ''),
    ('all', ''),
    for (final g in groups.all)
      if (g.group is! SmallGroup) (g.group.key, g.name),
  ];
});

/// The filter in effect: the one picked, unless it is no longer offered (a
/// group gone, or a 小組 or 全教會 picked before they left the menu), which
/// shows what this member starts on instead.
final shownCalendarFilterProvider = Provider<String>((ref) {
  final filter = ref.watch(calendarFilterProvider);
  final filters = ref.watch(_calendarFiltersProvider);
  if (filters == null || filters.any((f) => f.$1 == filter)) return filter;
  return ref.read(calendarFilterProvider.notifier).first;
});

/// Whether [filter] shows [e] for [me]. 跟我有關的: the church's events, my
/// groups' (the services I am in or lead, the 事工 of [ministries] whose
/// duties' lists I am on or that I lead, #94), and those whose roster has
/// me ([servedAt], event ids).
bool calendarShows(
  String filter,
  CalendarEvent e,
  Member? me,
  Set<String> servedAt, {
  List<Ministry> ministries = const [],
}) => switch (filter) {
  'all' => true,
  'mine' =>
    e.group == null ||
        servedAt.contains(e.id) ||
        (me != null &&
            switch (ChurchGroup.parse(e.group!)) {
              final g? => me.isIn(g, ministries: ministries) || me.leadsGroup(g),
              null => false,
            }),
  final group => e.group == group,
};

/// Every event's roster, read once: for 跟我有關的 in a month gone by,
/// which the rosters still to come do not cover.
final _eventRostersProvider = FutureProvider<List<Roster>>((ref) {
  ref.watch(churchDataProvider);
  return ref.churchData.eventRosters();
});

/// The events whose roster I am on, by event id: for 跟我有關的. With
/// [past], those gone by as well.
final servedAtProvider = Provider.family<Set<String>, bool>((ref, past) {
  final uid = ref.watch(uidProvider);
  final rosters = [
    ...?ref.watch(savedRostersProvider).value,
    if (past) ...?ref.watch(_eventRostersProvider).value,
  ];
  return {
    for (final r in rosters)
      if (r.forEvent case final e? when uid != null && r.duties.any((d) => d.uids.containsValue(uid))) e.eventId,
  };
});

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
    // Admins, 行政 and any 負責人 make events (#84): whose, they pick.
    final canEdit = (me?.makesEvents ?? false) && (settings?.ready ?? false);
    final gridShown = ref.watch(monthGridShownProvider);
    final filter = ref.watch(shownCalendarFilterProvider);
    final filters = [
      for (final (key, name) in ref.watch(_calendarFiltersProvider) ?? const <(String, String)>[])
        (
          key,
          switch (key) {
            'mine' => l10n.calFilterMine,
            'all' => l10n.calFilterAll,
            _ => name,
          },
        ),
    ];
    final ready = settings?.ready ?? false;
    final c = AppColors.of(context);
    // Not the filter this member starts on (跟我有關的, or 全部 for those who
    // look after the whole church): the button stands out, so a calendar
    // missing events is not taken for the usual one. Where they start
    // is not marked, as a default sort is not (SAP Fiori's filter bar).
    final narrowed = filter != ref.read(calendarFilterProvider.notifier).first;
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: Space.m,
        // The month is the title, as on the iPhone's and Google's
        // calendars; 行事曆 is said by the tab below.
        // 行事曆 only where there is no month to show: not while loading.
        title: settings == null || ready ? _MonthTitle(month: month) : Text(l10n.tabCalendar),
        actions: savingActions([
          if (ready)
            PopupMenuButton<Object>(
              tooltip: l10n.calFilter,
              onSelected: (v) => switch (v) {
                _View(:final grid) => grid == gridShown ? null : ref.read(monthGridShownProvider.notifier).toggle(),
                final String key => ref.read(calendarFilterProvider.notifier).pick(key),
                _ => null,
              },
              itemBuilder: (_) => [
                CheckedPopupMenuItem(
                  value: const _View(grid: true),
                  checked: gridShown,
                  child: Text(l10n.calMonthAndList),
                ),
                CheckedPopupMenuItem(
                  value: const _View(grid: false),
                  checked: !gridShown,
                  child: Text(l10n.calHideMonth),
                ),
                const PopupMenuDivider(),
                for (final (key, label) in filters)
                  CheckedPopupMenuItem(value: key, checked: key == filter, child: Text(label)),
              ],
              // Said to a screen reader too, not by the colour alone.
              icon: narrowed
                  ? Semantics(
                      value: filters.where((f) => f.$1 == filter).firstOrNull?.$2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: c.accentSoft, shape: BoxShape.circle),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(Symbols.filter_list_rounded, color: c.accent),
                        ),
                      ),
                    )
                  : const Icon(Symbols.filter_list_rounded),
            ),
          if (canEdit)
            IconButton(
              tooltip: l10n.calNewEvent,
              icon: const Icon(Symbols.add_rounded),
              onPressed: () => editEvent(context, ref, null, month: month, day: ref.read(calendarSelectedDayProvider)),
            ),
        ]),
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

  /// The picked day's section, brought into view when the day is picked.
  final _pickedDay = GlobalKey();

  /// This month's first row of today or after (an event still on today,
  /// begun before it, too), brought up when the month opens.
  final _todayRow = GlobalKey();

  /// Whether this month was brought to [_todayRow] since it opened.
  bool _scrolledToToday = false;

  /// The month whose neighbours were last read ahead.
  DateTime? _readAheadOf;

  @override
  void didUpdateWidget(_Agenda old) {
    super.didUpdateWidget(old);
    if (old.month != widget.month) {
      _scrolledToToday = false;
      // After this build: a jump now tells the app bar mid-build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
      });
    }
  }

  /// This month opens on [_todayRow]: what is past is above, scrolled
  /// away. Once, when its events are first shown; not on a small screen,
  /// whose grid scrolls with the rows and would go out of view.
  void _scrollToToday() {
    _scrolledToToday = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final row = _todayRow.currentContext;
      if (!mounted || row == null) return;
      Scrollable.ensureVisible(row);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Shows only [day]'s events below the month, their heading brought to
  /// the top (past the grid, when the grid scrolls with them); the same day
  /// again, the whole month.
  void _select(Day day) {
    final picked = ref.read(calendarSelectedDayProvider) == day ? null : day;
    ref.read(calendarSelectedDayProvider.notifier).select(picked);
    if (picked == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final section = _pickedDay.currentContext;
      if (!mounted || section == null) return;
      Scrollable.ensureVisible(
        section,
        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
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
    final me = ref.watch(meProvider).value;
    final filter = ref.watch(shownCalendarFilterProvider);
    final servedAt = ref.watch(
      servedAtProvider(filter == 'mine' && month.isBefore(DateTime(today.year, today.month))),
    );
    final ministries = ref.watch(ministriesProvider).value?.ministries ?? const <Ministry>[];
    final loaded = [
      for (final e in events.value ?? const <CalendarEvent>[])
        if (calendarShows(filter, e, me, servedAt, ministries: ministries)) e,
    ];
    void shift(int months) => ref.read(calendarMonthProvider.notifier).shift(months);

    final grid = MonthGrid(
      month: shownMonth,
      today: today,
      events: loaded,
      selected: selected,
      onSelect: _select,
      onShift: shift,
    );

    Widget row(CalendarEvent e, {Key? key, Widget? leading}) {
      final place = e.location?.trim() ?? '';
      return ListRow(
        key: key,
        leading: leading,
        title: e.title,
        // When, always under the title, then where: one place for the time
        // whether it is one day or several (2026-11-19, the time beside a
        // day's event and under a span read as two layouts). One line: the
        // rest of a long address is on the event's page.
        subtitle: [_when(l10n, e), if (place.isNotEmpty) place].join(l10n.dotSeparator),
        subtitleLines: 1,
        // Opens the event either way: to edit, or to read. A new one shows
        // while it is saved, and opens once it has an id.
        chevron: true,
        onTap: e.id == null
            ? null
            : () {
                final edits = canEdit && (me?.editsEvent(e) ?? false);
                // Google's own (a birthday) only reads: it is changed there.
                if (edits && !e.googleOnly) {
                  editEvent(context, ref, e, month: month);
                } else {
                  showEventDetail(context, e, editInGoogle: edits);
                }
              },
      );
    }

    final List<Widget> agenda;
    if (selected != null) {
      // One day picked: its events only, every one that covers it.
      final onDay = [
        for (final e in loaded)
          if (e.daysWithin(selected, selected) != null) e,
      ];
      agenda = [
        ListSection(
          key: _pickedDay,
          header: dayLabel(l10n, selected, today),
          children: [
            for (final e in onDay) row(e),
            if (onDay.isEmpty) _NothingOn(l10n.calNoEventsThatDay),
            if (canEdit)
              ListRow(
                leading: const Icon(Symbols.add_rounded),
                title: l10n.calNewEvent,
                onTap: () => editEvent(context, ref, null, month: month, day: selected),
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
      // One list, the day beside its first event as on the 服事表 tab: a
      // heading and a card a day made a month of one-event days long.
      final days = byDay.keys.toList()..sort();
      final todayRow = days
          .where((d) => byDay[d]!.any((e) => e.daysWithin(today, shownMonth.lastOfMonth) != null))
          .firstOrNull;
      agenda = [
        ListSection(
          children: [
            for (final d in days)
              for (final (i, e) in byDay[d]!.indexed)
                row(
                  e,
                  key: i == 0 && d == todayRow ? _todayRow : null,
                  leading: i == 0 ? dayBlock(d, today, color: e.color) : const SizedBox(width: DateBlock.minWidth),
                ),
          ],
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
      data: (_) => loaded.isEmpty && selected == null ? EmptyState(message: l10n.calNoEvents) : null,
    );
    final notices = [CalendarReadNotice(status: readStatus), const ChurchClockNotice()];
    final divider = Divider(height: 0.5, thickness: 0.5, color: AppColors.of(context).separator);

    return LayoutBuilder(
      builder: (context, constraints) {
        final pinned =
            constraints.maxHeight - MonthGrid.tallest(context) >=
            MediaQuery.textScalerOf(context).scale(_agendaMinHeight);
        final thisMonth = month == DateTime(today.year, today.month);
        if (!_scrolledToToday && pinned && thisMonth && selected == null && events.hasValue) _scrollToToday();
        // Swiped, the month changes, the agenda too and with the grid
        // folded away; or from the month's name above.
        return GestureDetector(
          onHorizontalDragEnd: (details) {
            final v = details.primaryVelocity ?? 0;
            if (v.abs() >= 200) shift(v < 0 ? 1 : -1);
          },
          child: Column(
            children: [
              if (pinned) ...[
                _Folding(
                  shown: gridShown,
                  child: Column(children: [grid, divider]),
                ),
                // Above the rows, not scrolled away with what is past.
                ...notices,
              ],
              Expanded(
                child: RefreshIndicator.adaptive(
                  onRefresh: () => ref.refresh(calendarEventsProvider(monthKey(month)).future),
                  child: CustomScrollView(
                    controller: _scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      if (!pinned) ...notices.map((n) => SliverToBoxAdapter(child: n)),
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
          ),
        );
      },
    );
  }
}

/// A choice in the calendar's menu: the month grid above the agenda, or
/// the agenda alone.
class _View {
  const _View({required this.grid});

  final bool grid;
}

/// The month on screen, as the screen's title: its name large, the year
/// beside it. Tapped, wheels pick another; 這個月 comes back to today's.
/// With a screen reader, swiping up and down goes month by month.
class _MonthTitle extends ConsumerWidget {
  const _MonthTitle({required this.month});

  final DateTime month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final months = ref.read(calendarMonthProvider.notifier);
    final style = AppText.title2.copyWith(fontWeight: FontWeight.w700);
    Future<void> pick() async {
      final picked = await showAppSheet<DateTime>(
        context,
        builder: (_) => _MonthSheet(month: month, today: ref.read(todayProvider)),
      );
      if (picked != null) months.show(picked);
    }

    return Semantics(
      button: true,
      label: DateFormat.yMMMM().format(month),
      hint: l10n.calPickMonth,
      onIncrease: () => months.shift(1),
      onDecrease: () => months.shift(-1),
      // Its own tap: the gesture's below is left out with the words.
      onTap: pick,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: pick,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: Space.minTap(Theme.of(context).platform)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: DateFormat.MMMM().format(month)),
                      const TextSpan(text: ' '),
                      TextSpan(
                        text: '${month.year}',
                        style: TextStyle(fontWeight: FontWeight.w400, color: c.secondaryLabel),
                      ),
                    ],
                  ),
                  style: style,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Symbols.expand_more_rounded, color: c.accent),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wheels for the month and year, as the iPhone has them; 完成 shows the
/// month turned to, 這個月 today's.
class _MonthSheet extends StatefulWidget {
  const _MonthSheet({required this.month, required this.today});

  final DateTime month;
  final Day today;

  @override
  State<_MonthSheet> createState() => _MonthSheetState();
}

class _MonthSheetState extends State<_MonthSheet> {
  late DateTime _month = widget.month;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetBar(
            title: l10n.calPickMonth,
            leading: SecondaryButton(
              label: l10n.calThisMonth,
              onPressed: () => Navigator.pop(context, DateTime(widget.today.year, widget.today.month)),
            ),
            actions: [SecondaryButton(label: l10n.done, onPressed: () => Navigator.pop(context, _month))],
          ),
          SizedBox(
            // The iPhone's own wheels' height.
            height: 216,
            child: CupertinoDatePicker(
              mode: CupertinoDatePickerMode.monthYear,
              initialDateTime: DateTime(widget.month.year, widget.month.month),
              // A few years back and on, and wherever a swipe has gone.
              minimumYear: min(widget.today.year - 3, widget.month.year),
              maximumYear: max(widget.today.year + 2, widget.month.year),
              onDateTimeChanged: (d) => _month = DateTime(d.year, d.month),
            ),
          ),
        ],
      ),
    );
  }
}

/// A picked day with no event: said in the secondary colour, so it does
/// not read as an event of that name.
class _NothingOn extends StatelessWidget {
  const _NothingOn(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(minHeight: Space.minTap(Theme.of(context).platform)),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(text, style: AppText.body.copyWith(color: AppColors.of(context).secondaryLabel)),
      ),
    ),
  );
}

/// The month grid folding open and shut under the month's name, as the
/// button above it shows or hides it: from wherever it is, so pressing again
/// mid-way turns it back. While it folds away it takes no taps. At once when
/// the phone asks for less motion.
class _Folding extends StatefulWidget {
  const _Folding({required this.shown, required this.child});

  final bool shown;
  final Widget child;

  @override
  State<_Folding> createState() => _FoldingState();
}

class _FoldingState extends State<_Folding> with SingleTickerProviderStateMixin {
  late final _open = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
    value: widget.shown ? 1 : 0,
  );
  late final _eased = CurvedAnimation(parent: _open, curve: Curves.easeInOut);

  @override
  void didUpdateWidget(_Folding old) {
    super.didUpdateWidget(old);
    if (old.shown == widget.shown) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _open.value = widget.shown ? 1 : 0;
    } else {
      widget.shown ? _open.forward() : _open.reverse();
    }
  }

  @override
  void dispose() {
    _eased.dispose();
    _open.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _open,
    builder: (context, child) => _open.isDismissed
        ? const SizedBox(width: double.infinity)
        : SizeTransition(
            sizeFactor: _eased,
            axisAlignment: -1,
            child: FadeTransition(opacity: _eased, child: child),
          ),
    child: IgnorePointer(ignoring: !widget.shown, child: widget.child),
  );
}

/// When [e] is, under its title: 09:00 – 11:00, 整天, or over several
/// days the days, with the times when it has them.
String _when(L10n l10n, CalendarEvent e) {
  final time = DateFormat.Hm();
  if (e.lastDay == e.day) {
    return e.allDay ? l10n.calAllDay : '${time.format(e.start)} – ${time.format(e.end)}';
  }
  final day = shortMonthDay(l10n);
  if (e.allDay) return '${day.format(e.start)} – ${day.format(e.lastDay.midnight)}';
  return '${day.format(e.start)} ${time.format(e.start)} – ${day.format(e.end)} ${time.format(e.end)}';
}
