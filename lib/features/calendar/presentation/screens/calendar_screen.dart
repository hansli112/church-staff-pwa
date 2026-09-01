import 'dart:convert';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/config/google_calendar_config.dart';
import '../../../auth/presentation/providers/session_provider.dart';
import '../../data/calendar_write_service.dart';
import '../widgets/_calendar_models.dart';
import '../widgets/_day_cell.dart';
import '../widgets/_day_events_sheet.dart';
import '../widgets/_event_detail_sheet.dart';
import '../widgets/_event_form_sheet.dart';

class CalendarScreen extends StatefulWidget {
  /// Injected by tests. Left null in the app so the default service picks up
  /// the same-origin endpoint and the real Firebase token.
  final CalendarWriteService? writeService;

  const CalendarScreen({super.key, this.writeService});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  static const int _initialMonthPage = 12000;
  static const Duration _monthSwitchDuration = Duration(milliseconds: 260);
  static const double _calendarMainAxisSpacing = 6;

  /// How much of the viewport the outgoing month may still cover while the
  /// grid collapses onto the shorter month underneath it. Small on purpose:
  /// the strip that loses its last row is on its way off screen.
  static const double _rowCollapseWindow = 0.3;
  static final _monthHeaderFormat = DateFormat('yyyy年MM月', 'zh_TW');

  late final DateTime _anchorMonth;
  late final PageController _monthPageController;
  int _currentMonthPage = _initialMonthPage;

  /// 同一個月在這段時間內不重抓。沒有這道閘門的話，每次左右換頁都會對
  /// 當月 + 前後月各打一次 Google Calendar API，來回滑幾次就燒掉配額。
  static const Duration _monthFreshness = Duration(minutes: 10);

  /// SharedPreferences 只保留距今前後這麼多個月的快取，避免 key 無限累積。
  static const int _cacheKeepMonths = 12;
  static const String _cacheKeyPrefix = 'calendar_events_';

  late DateTime _focusedMonth;
  final ValueNotifier<DateTime?> _selectedDay = ValueNotifier<DateTime?>(null);
  final Map<String, List<CalendarEvent>> _eventsByMonth = {};
  final Set<String> _loadingMonths = {};
  final Map<String, String?> _errorsByMonth = {};
  final Map<String, DateTime> _fetchedAtByMonth = {};

  // 每月的 segment 佈局是 O(事件數 × 42) 的計算，而 PageView 同時有 3 頁在
  // 樹上，任何一次 setState 都會讓三頁重算。事件沒變就直接用上次的結果。
  final Map<String, Map<int, List<DayEventSegment>>> _layoutCache = {};

  late final CalendarWriteService _writeService =
      widget.writeService ?? CalendarWriteService();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _anchorMonth = DateTime(now.year, now.month, 1);
    _focusedMonth = _anchorMonth;
    _selectedDay.value = DateUtils.dateOnly(now);

    _monthPageController = PageController(initialPage: _initialMonthPage);

    _loadMonthBundle(_focusedMonth);
    _loadMonthBundle(_monthFromPage(_initialMonthPage - 1));
    _loadMonthBundle(_monthFromPage(_initialMonthPage + 1));
  }

  @override
  void dispose() {
    _monthPageController.dispose();
    _selectedDay.dispose();
    super.dispose();
  }

  DateTime _monthFromPage(int page) {
    final delta = page - _initialMonthPage;
    return DateTime(_anchorMonth.year, _anchorMonth.month + delta, 1);
  }

  void _changeMonth(int offset) {
    final targetPage = _currentMonthPage + offset;
    _monthPageController.animateToPage(
      targetPage,
      duration: _monthSwitchDuration,
      curve: Curves.easeOutCubic,
    );
  }

  void _onMonthPageChanged(int page) {
    final month = _monthFromPage(page);
    setState(() {
      _currentMonthPage = page;
      _focusedMonth = month;
    });
    final now = DateTime.now();
    final inSameMonth = month.year == now.year && month.month == now.month;
    _selectedDay.value = inSameMonth ? DateUtils.dateOnly(now) : null;

    _loadMonthBundle(month);
    _loadMonthBundle(_monthFromPage(page - 1));
    _loadMonthBundle(_monthFromPage(page + 1));
  }

  void _loadMonthBundle(DateTime month) {
    _loadCachedEventsForMonth(month);
    _loadEventsForMonth(month);
  }

  String? get _focusedError => _errorsByMonth[_cacheKeyForMonth(_focusedMonth)];

  @override
  Widget build(BuildContext context) {
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final isDesktopLayout = viewportWidth >= 900;
    final maxContentWidth = viewportWidth >= 900
        ? (viewportWidth * 0.94).clamp(1100.0, 1600.0)
        : double.infinity;
    final canEdit = context.select<SessionProvider, bool>(
      (s) => s.canEditCalendar,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('行事曆'), centerTitle: true, elevation: 0),
      floatingActionButton: canEdit
          ? FloatingActionButton(
              onPressed: () => _addEvent(_selectedDay.value ?? _focusedMonth),
              tooltip: '新增活動',
              child: const Icon(Icons.add),
            )
          : null,
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (isDesktopLayout) {
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContentWidth),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 16,
                  ),
                  child: Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildMonthHeader(),
                          const SizedBox(height: 4),
                          if (_focusedError != null) ...[
                            Text(
                              _focusedError!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                fontSize: 12,
                              ),
                            ),
                          ],
                          const SizedBox(height: 6),
                          _buildWeekdayHeader(),
                          const SizedBox(height: 8),
                          Expanded(child: _buildMonthPager(canEdit)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }

          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxContentWidth),
              child: SingleChildScrollView(
                // Tight at the top on purpose: the AppBar already says 行事曆,
                // so the month header does not need to be pushed away from it.
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildMonthHeader(),
                            const SizedBox(height: 4),
                            if (_focusedError != null) ...[
                              Text(
                                _focusedError!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                            const SizedBox(height: 6),
                            _buildWeekdayHeader(),
                            const SizedBox(height: 8),
                            _buildMonthPager(canEdit),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Deliberately compact: on a phone a six-week month already runs past the
  /// bottom of the screen, and the month label only needs to say which month
  /// you are looking at — it does not need a full IconButton's worth of height
  /// on either side of it.
  Widget _buildMonthHeader() {
    final text = _monthHeaderFormat.format(_focusedMonth);
    return Row(
      children: [
        _MonthArrow(
          icon: Icons.chevron_left,
          tooltip: '上個月',
          onPressed: () => _changeMonth(-1),
        ),
        Expanded(
          child: Text(
            text,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
        ),
        _MonthArrow(
          icon: Icons.chevron_right,
          tooltip: '下個月',
          onPressed: () => _changeMonth(1),
        ),
      ],
    );
  }

  Widget _buildWeekdayHeader() {
    const labels = ['日', '一', '二', '三', '四', '五', '六'];
    return Row(
      children: labels
          .map(
            (label) => Expanded(
              child: Center(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildMonthPager(bool canEdit) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Cell height is still derived from six rows so a cell is the same
        // size in every month — only how many rows get drawn changes.
        final cellAspectRatio = _calendarAspectRatioForWidth(
          constraints.maxWidth,
          availableHeight: constraints.hasBoundedHeight
              ? constraints.maxHeight
              : null,
        );
        final cellWidth = constraints.maxWidth / 7;
        final cellHeight = cellWidth / cellAspectRatio;

        final pager = PageView.builder(
          controller: _monthPageController,
          onPageChanged: _onMonthPageChanged,
          itemBuilder: (context, index) {
            final month = _monthFromPage(index);
            return _buildCalendarGrid(
              month,
              cellAspectRatio,
              cellHeight,
              canEdit,
            );
          },
        );

        // Every page in a PageView is the same height, so the box is driven
        // straight off the scroll position — see [_gridHeightForPage].
        return AnimatedBuilder(
          animation: _monthPageController,
          builder: (context, child) =>
              SizedBox(height: _gridHeightForPage(cellHeight), child: child),
          child: pager,
        );
      },
    );
  }

  /// The height of the pager for wherever the swipe currently is.
  ///
  /// Two months share the box mid-swipe and both have to fit, so the naive
  /// answer is "as tall as the taller of the two, until the swipe lands".
  /// That reads as a lag: the height only starts coming down once the page
  /// animation has already finished, so switching months takes two animations
  /// end to end rather than one.
  ///
  /// Instead the height follows the scroll position and lands exactly when the
  /// page does — no second animation afterwards. The taller month gets the
  /// full box for all but the last [_rowCollapseWindow] of its width, eased on
  /// top of that, so the only thing ever short of a row is a narrow strip at
  /// the edge of the screen — the tail of the month leaving, or the very first
  /// sliver of a taller one arriving, which fills in as it comes in.
  double _gridHeightForPage(double cellHeight) {
    final page = _monthPageController.hasClients
        ? (_monthPageController.page ?? _currentMonthPage.toDouble())
        : _currentMonthPage.toDouble();

    final nearestPage = page.round();
    final nearestHeight = _gridHeightForRows(
      _weekRowsForMonth(_monthFromPage(nearestPage)),
      cellHeight,
    );

    final distance = (page - nearestPage).abs();
    if (distance == 0) return nearestHeight;

    final otherHeight = _gridHeightForRows(
      _weekRowsForMonth(
        _monthFromPage(page > nearestPage ? nearestPage + 1 : nearestPage - 1),
      ),
      cellHeight,
    );
    // The neighbour is the shorter one: it simply has room to spare, and the
    // month taking over the screen gets its full height immediately.
    if (otherHeight <= nearestHeight) return nearestHeight;

    final progress = ((_rowCollapseWindow - distance) / _rowCollapseWindow)
        .clamp(0.0, 1.0);
    return lerpDouble(
      otherHeight,
      nearestHeight,
      Curves.easeInQuad.transform(progress),
    )!;
  }

  double _gridHeightForRows(int rows, double cellHeight) =>
      (cellHeight * rows) + (_calendarMainAxisSpacing * (rows - 1));

  /// How many week rows a month occupies: the blanks before the 1st plus its
  /// days, rounded up to whole weeks. Four for a February that starts on a
  /// Sunday, six for a month like 2026/08.
  static int _weekRowsForMonth(DateTime month) {
    final startOffset = DateTime(month.year, month.month, 1).weekday % 7;
    final totalDays = DateUtils.getDaysInMonth(month.year, month.month);
    return ((startOffset + totalDays) / 7).ceil();
  }

  double _calendarAspectRatioForWidth(double width, {double? availableHeight}) {
    if (availableHeight != null && availableHeight > 0) {
      final targetGridHeight = (availableHeight - 1).clamp(220.0, 800.0);
      final targetCellHeight =
          (targetGridHeight - (_calendarMainAxisSpacing * 5)) / 6;
      final cellWidth = width / 7;
      return (cellWidth / targetCellHeight).clamp(0.8, 2.6);
    }

    if (width >= 1200) return 1.3;
    if (width >= 900) return 1.0;
    if (width >= 700) return 0.75;
    return 0.5;
  }

  int _maxVisibleEventsForCellHeight(double cellHeight) {
    const reservedHeaderHeight = 24.0;
    const overflowIndicatorHeight = 14.0;
    const eventRowHeight = 19.0;

    final usableHeight =
        cellHeight - reservedHeaderHeight - overflowIndicatorHeight;
    final estimatedCount = (usableHeight / eventRowHeight).floor();
    return estimatedCount.clamp(1, 6).toInt();
  }

  Widget _buildCalendarGrid(
    DateTime displayedMonth,
    double cellAspectRatio,
    double cellHeight,
    bool canEdit,
  ) {
    final year = displayedMonth.year;
    final month = displayedMonth.month;
    final firstDay = DateTime(year, month, 1);
    final totalDays = DateUtils.getDaysInMonth(year, month);
    final startOffset = firstDay.weekday % 7;
    final cellWidth = cellHeight * cellAspectRatio;
    final totalCells = _weekRowsForMonth(displayedMonth) * 7;
    final eventSegmentsByDay = _buildMonthEventLayout(displayedMonth);

    return GridView.builder(
      key: ValueKey<String>(_cacheKeyForMonth(displayedMonth)),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: _calendarMainAxisSpacing,
        crossAxisSpacing: 0,
        childAspectRatio: cellAspectRatio,
      ),
      itemCount: totalCells,
      itemBuilder: (context, index) {
        final dayNumber = index - startOffset + 1;
        final inMonth = dayNumber >= 1 && dayNumber <= totalDays;
        if (!inMonth) {
          return const SizedBox.shrink();
        }

        final date = DateTime(year, month, dayNumber);
        final dateOnly = DateUtils.dateOnly(date);
        final isToday = DateUtils.isSameDay(dateOnly, DateTime.now());
        final daySegments =
            eventSegmentsByDay[_dayKey(dateOnly)] ?? const <DayEventSegment>[];
        final hasEvents = daySegments.isNotEmpty;
        final maxVisibleEvents = _maxVisibleEventsForCellHeight(cellHeight);

        return ValueListenableBuilder<DateTime?>(
          valueListenable: _selectedDay,
          builder: (context, selectedDay, _) {
            final isSelected = DateUtils.isSameDay(selectedDay, dateOnly);
            return DayCell(
              dayNumber: dayNumber,
              date: dateOnly,
              isSelected: isSelected,
              isToday: isToday,
              segments: daySegments,
              maxVisibleEvents: maxVisibleEvents,
              cellWidth: cellWidth,
              onTap: () async {
                _selectedDay.value = dateOnly;
                // For a member an empty day has nothing to show, so tapping it
                // only moves the selection. For an editor the empty sheet is
                // the way in to "新增活動" on that exact day.
                if (hasEvents || canEdit) {
                  await _showSelectedDayEventsSheet(dateOnly);
                }
              },
              onEventTap: (event) => _showEventDetails(event),
            );
          },
        );
      },
    );
  }

  bool get _canEdit => context.read<SessionProvider>().canEditCalendar;

  Future<void> _showEventDetails(CalendarEvent event) async {
    _selectedDay.value = event.startDay;
    if (!mounted) return;
    final canEdit = _canEdit;
    await showEventDetailSheet(
      context,
      event,
      onEdit: canEdit ? _editEvent : null,
      onDuplicate: canEdit ? _duplicateEvent : null,
      onDelete: canEdit ? _deleteEvent : null,
    );
  }

  List<CalendarEvent>? _eventsForDay(DateTime? day) {
    if (day == null) return null;

    final monthEvents = _eventsByMonth[_cacheKeyForMonth(day)] ?? const [];
    final events =
        monthEvents.where((event) => event.occursOnDate(day)).toList()
          ..sort((a, b) {
            if (a.isAllDay != b.isAllDay) {
              return a.isAllDay ? -1 : 1;
            }
            final byStart = a.startTime.compareTo(b.startTime);
            if (byStart != 0) return byStart;
            return a.title.compareTo(b.title);
          });
    return events;
  }

  Future<void> _showSelectedDayEventsSheet(DateTime day) async {
    final events = _eventsForDay(day) ?? const <CalendarEvent>[];
    if (!mounted) return;
    await showDayEventsSheet(
      context,
      day: day,
      events: events,
      onOpenEvent: _showEventDetails,
      onAddEvent: _canEdit ? _addEvent : null,
    );
  }

  // ---------------------------------------------------------------------------
  // Admin writes
  //
  // The browser reads the calendar with a public API key, which cannot write.
  // These go through the app's own same-origin /api/calendar endpoints, which
  // hold the service account credential — see worker/google_calendar.js.
  // ---------------------------------------------------------------------------

  Future<void> _addEvent(DateTime day) =>
      _createEvent(heading: '新增活動', initial: CalendarEventDraft.forDay(day));

  /// Same event again, at a different time.
  ///
  /// A repeating pattern belongs in a recurring event, but the common case here
  /// is a handful of runs of the same thing at times that follow no rule — three
  /// identical rehearsals, say. Retyping the title, location and description for
  /// each one is where the typos come from, so this opens the *add* form with
  /// everything already filled in and leaves the user only the time to change.
  Future<void> _duplicateEvent(CalendarEvent event) => _createEvent(
    heading: '複製活動',
    initial: CalendarEventDraft.fromEvent(event),
  );

  Future<void> _createEvent({
    required String heading,
    required CalendarEventDraft initial,
  }) async {
    if (!mounted) return;
    final saved = await showEventFormSheet(
      context,
      heading: heading,
      initial: initial,
      onSubmit: (draft) async {
        final created = await _writeService.create(draft);
        _applyLocalChange(added: created);
        _refreshMonths(_monthsSpannedBy(created));
      },
    );
    if (saved) _showMessage('已新增活動');
  }

  Future<void> _editEvent(CalendarEvent event) async {
    if (!mounted) return;
    final saved = await showEventFormSheet(
      context,
      heading: '編輯活動',
      initial: CalendarEventDraft.fromEvent(event),
      onSubmit: (draft) async {
        final updated = await _writeService.update(event.id, draft);
        _applyLocalChange(removed: event, added: updated);
        // The old span matters too: moving an event out of a month has to
        // refresh the month it left, not only the one it landed in.
        _refreshMonths([
          ..._monthsSpannedBy(event),
          ..._monthsSpannedBy(updated),
        ]);
      },
    );
    if (saved) _showMessage('已更新活動');
  }

  Future<void> _deleteEvent(CalendarEvent event) async {
    if (!mounted) return;
    if (!await confirmDeleteEvent(context, event.title)) return;

    try {
      await _writeService.delete(event.id);
    } catch (error) {
      _showMessage(
        error is CalendarWriteException ? error.message : '刪除失敗，請稍後再試',
        isError: true,
      );
      return;
    }

    _applyLocalChange(removed: event);
    _refreshMonths(_monthsSpannedBy(event));
    _showMessage('已刪除活動');
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  /// Applies a confirmed write to what is already on screen.
  ///
  /// The server has already accepted the change at this point, so this is not
  /// optimistic — it is here so the calendar updates in the same frame instead
  /// of after the round trip in [_refreshMonthsForDays].
  void _applyLocalChange({CalendarEvent? removed, CalendarEvent? added}) {
    if (!mounted) return;
    setState(() {
      final touched = <String>{};

      if (removed != null) {
        // Scans every loaded month rather than only the ones the event spans:
        // an edit that moves an event has to clear it out of wherever it used
        // to sit, and that span is not always the span being passed in.
        for (final entry in _eventsByMonth.entries) {
          final before = entry.value.length;
          entry.value.removeWhere((existing) => existing.id == removed.id);
          if (entry.value.length != before) touched.add(entry.key);
        }
      }

      if (added != null) {
        for (final month in _monthsSpannedBy(added)) {
          final key = _cacheKeyForMonth(month);
          // A month that was never loaded has nothing to patch; it will fetch
          // the event normally when the user pages to it.
          final events = _eventsByMonth[key];
          if (events == null) continue;
          events.removeWhere((existing) => existing.id == added.id);
          events.add(added);
          touched.add(key);
        }
      }

      for (final key in touched) {
        _layoutCache.remove(key);
      }
    });
  }

  /// Refetches the given months from Google.
  ///
  /// Clearing the freshness stamp is the part that matters: without it
  /// [_loadEventsForMonth] returns early for the next ten minutes and both the
  /// in-memory list and the SharedPreferences copy stay stale until then.
  void _refreshMonths(Iterable<DateTime> months) {
    final byKey = <String, DateTime>{};
    for (final month in months) {
      byKey[_cacheKeyForMonth(month)] = DateTime(month.year, month.month, 1);
    }
    for (final entry in byKey.entries) {
      _fetchedAtByMonth.remove(entry.key);
      _loadEventsForMonth(entry.value);
    }
  }

  /// Every month an event touches, so a span across a month boundary refreshes
  /// both sides rather than only where it starts.
  List<DateTime> _monthsSpannedBy(CalendarEvent event) {
    final months = <DateTime>[];
    var cursor = DateTime(event.startDay.year, event.startDay.month, 1);
    final last = DateTime(event.endDay.year, event.endDay.month, 1);
    while (!cursor.isAfter(last)) {
      months.add(cursor);
      cursor = DateTime(cursor.year, cursor.month + 1, 1);
    }
    return months;
  }

  int _dayKey(DateTime date) =>
      (date.year * 10000) + (date.month * 100) + date.day;

  Map<int, List<DayEventSegment>> _buildMonthEventLayout(DateTime month) {
    final cacheKey = _cacheKeyForMonth(month);
    final cachedLayout = _layoutCache[cacheKey];
    if (cachedLayout != null) return cachedLayout;

    final layout = _computeMonthEventLayout(month);
    _layoutCache[cacheKey] = layout;
    return layout;
  }

  Map<int, List<DayEventSegment>> _computeMonthEventLayout(DateTime month) {
    final year = month.year;
    final monthValue = month.month;
    final firstDay = DateTime(year, monthValue, 1);
    final totalDays = DateUtils.getDaysInMonth(year, monthValue);
    final monthStart = DateUtils.dateOnly(firstDay);
    final monthEnd = DateUtils.dateOnly(DateTime(year, monthValue, totalDays));
    final monthEvents = _eventsByMonth[_cacheKeyForMonth(firstDay)] ?? [];
    final overlappingEvents =
        monthEvents
            .where((event) => !event.endDay.isBefore(monthStart))
            .where((event) => !event.startDay.isAfter(monthEnd))
            .toList()
          ..sort((a, b) {
            final byStart = a.startTime.compareTo(b.startTime);
            if (byStart != 0) return byStart;
            return a.title.compareTo(b.title);
          });

    final firstLabelDayByEvent = <String, DateTime>{};
    for (final event in overlappingEvents) {
      final firstVisible = event.startDay.isBefore(monthStart)
          ? monthStart
          : event.startDay;
      firstLabelDayByEvent[event.identity] = firstVisible;
    }

    final result = <int, List<DayEventSegment>>{};
    final firstWeekOffset = firstDay.weekday % 7;
    final weekCount = ((firstWeekOffset + totalDays) / 7).ceil();

    for (var week = 0; week < weekCount; week++) {
      final weekDays = List<DateTime?>.generate(7, (weekday) {
        final dayNumber = week * 7 + weekday - firstWeekOffset + 1;
        if (dayNumber < 1 || dayNumber > totalDays) return null;
        return DateUtils.dateOnly(DateTime(year, monthValue, dayNumber));
      });

      final weekSegments = <WeekEventSegment>[];
      for (final event in overlappingEvents) {
        int? startIndex;
        int? endIndex;
        for (var i = 0; i < 7; i++) {
          final day = weekDays[i];
          if (day == null || !event.occursOnDate(day)) continue;
          startIndex ??= i;
          endIndex = i;
        }
        if (startIndex == null || endIndex == null) continue;
        weekSegments.add(
          WeekEventSegment(
            event: event,
            startIndex: startIndex,
            endIndex: endIndex,
          ),
        );
      }

      final laneOccupancy = <List<bool>>[];
      weekSegments.sort((a, b) {
        final byStart = a.startIndex.compareTo(b.startIndex);
        if (byStart != 0) return byStart;
        final byEnd = b.endIndex.compareTo(a.endIndex);
        if (byEnd != 0) return byEnd;
        return a.event.startTime.compareTo(b.event.startTime);
      });

      for (final segment in weekSegments) {
        final segmentStartDay = weekDays[segment.startIndex];
        final segmentStartPrevDay = segment.startIndex > 0
            ? weekDays[segment.startIndex - 1]
            : null;
        final segmentStartsFromPreviousDay =
            segmentStartDay != null &&
            segmentStartPrevDay != null &&
            segment.event.occursOnDate(segmentStartPrevDay);
        final startLeadingInset = segmentStartsFromPreviousDay ? 0.0 : 2.0;
        final startTextInset =
            startLeadingInset + (segmentStartsFromPreviousDay ? 0.0 : 1.0);

        var lane = 0;
        while (true) {
          if (lane == laneOccupancy.length) {
            laneOccupancy.add(List<bool>.filled(7, false));
          }
          final occupied = laneOccupancy[lane];
          final hasConflict = occupied
              .sublist(segment.startIndex, segment.endIndex + 1)
              .any((value) => value);
          if (!hasConflict) break;
          lane++;
        }

        for (var i = segment.startIndex; i <= segment.endIndex; i++) {
          laneOccupancy[lane][i] = true;
          final day = weekDays[i];
          if (day == null) continue;
          final dayKey = _dayKey(day);
          result.putIfAbsent(dayKey, () => []);
          final previousDay = i > 0 ? weekDays[i - 1] : null;
          final nextDay = i < 6 ? weekDays[i + 1] : null;
          result[dayKey]!.add(
            DayEventSegment(
              event: segment.event,
              lane: lane,
              showTitle: DateUtils.isSameDay(
                day,
                firstLabelDayByEvent[segment.event.identity],
              ),
              titleShiftDays: i - segment.startIndex,
              startTextInset: startTextInset,
              continuesLeft:
                  previousDay != null &&
                  segment.event.occursOnDate(previousDay),
              continuesRight:
                  nextDay != null && segment.event.occursOnDate(nextDay),
            ),
          );
        }
      }
    }

    for (final segments in result.values) {
      segments.sort((a, b) => a.lane.compareTo(b.lane));
    }
    return result;
  }

  String _cacheKeyForMonth(DateTime month) {
    return 'calendar_events_${month.year}_${month.month.toString().padLeft(2, '0')}';
  }

  Future<void> _loadCachedEventsForMonth(DateTime month) async {
    final key = _cacheKeyForMonth(month);
    // 記憶體裡已經有這個月了就不要再讀 disk：重讀會 jsonDecode 整個月、
    // setState、並清掉 layout 快取，等於每次換頁都把三個月的版面重算一次 ——
    // 正是 layout 快取想消除的那段卡頓。
    if (_eventsByMonth.containsKey(key)) return;

    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(key);
    if (cached == null || cached.isEmpty) return;

    try {
      final data = jsonDecode(cached) as List<dynamic>;
      final events = data
          .map((raw) => CalendarEvent.fromJson(raw as Map<String, dynamic>))
          .toList();
      if (!mounted) return;
      setState(() {
        _eventsByMonth[key] = events;
        _layoutCache.remove(key);
      });
    } catch (_) {
      // Ignore corrupted cache.
    }
  }

  Future<void> _saveCachedEventsForMonth(
    DateTime month,
    List<CalendarEvent> events,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _cacheKeyForMonth(month);
    final payload = jsonEncode(events.map((e) => e.toJson()).toList());
    await prefs.setString(key, payload);
    await _pruneCachedMonths(prefs);
  }

  /// 每瀏覽一個新月份就多一筆 key，永遠不清的話 localStorage 會一直長大。
  /// 只留距今 [_cacheKeepMonths] 個月內的月份，其餘刪掉。
  Future<void> _pruneCachedMonths(SharedPreferences prefs) async {
    final now = DateTime.now();
    final nowIndex = now.year * 12 + now.month;

    for (final key in prefs.getKeys().toList()) {
      if (!key.startsWith(_cacheKeyPrefix)) continue;
      final parts = key.substring(_cacheKeyPrefix.length).split('_');
      if (parts.length != 2) continue;
      final year = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      if (year == null || month == null) continue;

      final distance = (year * 12 + month) - nowIndex;
      if (distance.abs() > _cacheKeepMonths) {
        await prefs.remove(key);
      }
    }
  }

  Future<void> _loadEventsForMonth(DateTime month) async {
    final key = _cacheKeyForMonth(month);
    if (_loadingMonths.contains(key)) return;

    final fetchedAt = _fetchedAtByMonth[key];
    if (fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < _monthFreshness) {
      return; // 這個月剛抓過，直接用記憶體裡的資料
    }

    setState(() {
      _loadingMonths.add(key);
      _errorsByMonth.remove(key);
    });

    final monthStart = DateTime.utc(month.year, month.month, 1);
    final monthEnd = DateTime.utc(
      month.year,
      month.month + 1,
      1,
    ).subtract(const Duration(seconds: 1));

    final uri =
        Uri.https('www.googleapis.com', '', {
          'key': GoogleCalendarConfig.apiKey,
          'singleEvents': 'true',
          'orderBy': 'startTime',
          'maxResults': '250',
          'timeMin': monthStart.toIso8601String(),
          'timeMax': monthEnd.toIso8601String(),
          'timeZone': GoogleCalendarConfig.timeZone,
        }).replace(
          pathSegments: [
            'calendar',
            'v3',
            'calendars',
            GoogleCalendarConfig.calendarId,
            'events',
          ],
        );

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (!mounted) return;

      if (response.statusCode != 200) {
        String? message;
        try {
          final errorBody = jsonDecode(response.body) as Map<String, dynamic>;
          message =
              (errorBody['error'] as Map<String, dynamic>?)?['message']
                  as String?;
        } catch (_) {}
        setState(() {
          _errorsByMonth[key] = message == null || message.isEmpty
              ? '載入失敗（${response.statusCode}）'
              : '載入失敗（${response.statusCode}）：$message';
        });
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final items = data['items'] as List<dynamic>? ?? [];
      final events = <CalendarEvent>[];

      for (var i = 0; i < items.length; i++) {
        try {
          final event = calendarEventFromGoogleItem(
            items[i] as Map<String, dynamic>,
            fallbackIndex: i,
          );
          if (event != null) events.add(event);
        } catch (e, st) {
          debugPrint('Skipping malformed calendar item #$i: $e');
          debugPrintStack(stackTrace: st);
        }
      }

      await _saveCachedEventsForMonth(month, events);
      if (!mounted) return;
      setState(() {
        _eventsByMonth[key] = events;
        _layoutCache.remove(key);
        _fetchedAtByMonth[key] = DateTime.now();
      });
    } catch (_) {
      if (!mounted) return;
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(key);
      if (cached == null) {
        setState(() {
          _errorsByMonth[key] = '離線或連線逾時，且沒有快取資料';
        });
      } else {
        setState(() {
          _errorsByMonth[key] = null;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingMonths.remove(key);
        });
      }
    }
  }
}

/// A month-stepping chevron sized down from the 48px default. The tap target
/// stays 40x36 — comfortable on a phone — instead of eating the header's height.
class _MonthArrow extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _MonthArrow({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon),
      iconSize: 22,
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 36),
      onPressed: onPressed,
    );
  }
}
