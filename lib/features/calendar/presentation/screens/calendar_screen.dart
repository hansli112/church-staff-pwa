import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../core/config/google_calendar_config.dart';
import '../../../../core/time/church_time.dart';
import '../../../auth/presentation/providers/session_provider.dart';
import '../../data/calendar_month_store.dart';
import '../../data/calendar_write_service.dart';
import '../../domain/entities/calendar_event.dart';
import '../layout/month_event_layout.dart';
import '../widgets/_day_cell.dart';
import '../widgets/_day_events_sheet.dart';
import '../widgets/_event_detail_sheet.dart';
import '../widgets/_event_form_sheet.dart';

class CalendarScreen extends StatefulWidget {
  /// Injected by tests. Left null in the app so the default service picks up
  /// the same-origin endpoint and the real Firebase token.
  final CalendarWriteService? writeService;

  /// Injected by tests to stand in for the Google read. Left null in the app,
  /// which reads Google with the public API key.
  final CalendarMonthFetcher? fetchMonth;

  const CalendarScreen({super.key, this.writeService, this.fetchMonth});

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

  late DateTime _focusedMonth;
  final ValueNotifier<DateTime?> _selectedDay = ValueNotifier<DateTime?>(null);

  late final CalendarMonthStore _months = CalendarMonthStore(
    fetchMonth: widget.fetchMonth,
  );

  /// See [_layoutForMonth]. Keyed by the first of the month.
  final Map<DateTime, ({List<CalendarEvent> events, MonthEventLayout layout})>
  _layoutCache = {};

  late final CalendarWriteService _writeService =
      widget.writeService ?? CalendarWriteService();

  @override
  void initState() {
    super.initState();
    final now = ChurchTime.now();
    _anchorMonth = DateTime.utc(now.year, now.month, 1);
    _focusedMonth = _anchorMonth;
    _selectedDay.value = ChurchTime.dateOnly(now);

    _monthPageController = PageController(initialPage: _initialMonthPage);

    _months.addListener(_onMonthsChanged);
    _loadMonthBundle(_focusedMonth);
    _loadMonthBundle(_monthFromPage(_initialMonthPage - 1));
    _loadMonthBundle(_monthFromPage(_initialMonthPage + 1));
  }

  @override
  void dispose() {
    _months.removeListener(_onMonthsChanged);
    _months.dispose();
    _monthPageController.dispose();
    _selectedDay.dispose();
    super.dispose();
  }

  DateTime _monthFromPage(int page) {
    final delta = page - _initialMonthPage;
    return DateTime.utc(_anchorMonth.year, _anchorMonth.month + delta, 1);
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
    final now = ChurchTime.now();
    final inSameMonth = month.year == now.year && month.month == now.month;
    _selectedDay.value = inSameMonth ? ChurchTime.dateOnly(now) : null;

    _loadMonthBundle(month);
    _loadMonthBundle(_monthFromPage(page - 1));
    _loadMonthBundle(_monthFromPage(page + 1));
  }

  void _loadMonthBundle(DateTime month) {
    if (!GoogleCalendarConfig.isEnabled) return;
    _months.ensureLoaded(month);
  }

  void _onMonthsChanged() {
    if (mounted) setState(() {});
  }

  String? get _focusedError => _months.errorForMonth(_focusedMonth);

  @override
  Widget build(BuildContext context) {
    if (!GoogleCalendarConfig.isEnabled) {
      return Scaffold(
        appBar: AppBar(title: const Text('行事曆')),
        body: const Center(child: Text('行事曆未啟用或設定不完整')),
      );
    }
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
      MonthEventLayout.weekRowsFor(_monthFromPage(nearestPage)),
      cellHeight,
    );

    final distance = (page - nearestPage).abs();
    if (distance == 0) return nearestHeight;

    final otherHeight = _gridHeightForRows(
      MonthEventLayout.weekRowsFor(
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
    final firstDay = DateTime.utc(year, month, 1);
    final totalDays = DateUtils.getDaysInMonth(year, month);
    final startOffset = firstDay.weekday % 7;
    final cellWidth = cellHeight * cellAspectRatio;
    final totalCells = MonthEventLayout.weekRowsFor(displayedMonth) * 7;
    final layout = _layoutForMonth(firstDay);

    return GridView.builder(
      key: ValueKey<DateTime>(firstDay),
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

        final date = DateTime.utc(year, month, dayNumber);
        final dateOnly = ChurchTime.dateOnly(date);
        final isToday = DateUtils.isSameDay(dateOnly, ChurchTime.now());
        final daySegments = layout.segmentsOn(dateOnly);
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

  bool get _canEdit =>
      GoogleCalendarConfig.isEnabled &&
      context.read<SessionProvider>().canEditCalendar;

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

    final monthEvents = _months.eventsForMonth(day) ?? const [];
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
        _months.applyWrite(added: created);
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
        _months.applyWrite(removed: event, added: updated);
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

    _months.applyWrite(removed: event);
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

  /// The month's bars, recomputed only when its event list is replaced.
  ///
  /// 每月的 segment 佈局是 O(事件數 × 42) 的計算，而 PageView 同時有 3 頁在
  /// 樹上，任何一次 setState 都會讓三頁重算。[CalendarMonthStore] 每次
  /// 改動都換一份新 List，所以 identical() 就能判斷事件有沒有變。
  MonthEventLayout _layoutForMonth(DateTime month) {
    final events = _months.eventsForMonth(month) ?? const <CalendarEvent>[];
    final cached = _layoutCache[month];
    if (cached != null && identical(cached.events, events)) {
      return cached.layout;
    }
    final layout = MonthEventLayout.compute(month, events);
    _layoutCache[month] = (events: events, layout: layout);
    return layout;
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
