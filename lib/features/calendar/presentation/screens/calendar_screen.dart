import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/config/google_calendar_config.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  static const int _initialMonthPage = 12000;
  static const Duration _monthSwitchDuration = Duration(milliseconds: 260);
  static const double _calendarMainAxisSpacing = 6;

  late final DateTime _anchorMonth;
  late final PageController _monthPageController;
  int _currentMonthPage = _initialMonthPage;

  late DateTime _focusedMonth;
  DateTime? _selectedDay;
  final Map<String, List<_CalendarEvent>> _eventsByMonth = {};
  final Set<String> _loadingMonths = {};
  final Map<String, String?> _errorsByMonth = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _anchorMonth = DateTime(now.year, now.month, 1);
    _focusedMonth = _anchorMonth;
    _selectedDay = DateUtils.dateOnly(now);

    _monthPageController = PageController(initialPage: _initialMonthPage);

    _loadMonthBundle(_focusedMonth);
    _loadMonthBundle(_monthFromPage(_initialMonthPage - 1));
    _loadMonthBundle(_monthFromPage(_initialMonthPage + 1));
  }

  @override
  void dispose() {
    _monthPageController.dispose();
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
      final now = DateTime.now();
      final inSameMonth = month.year == now.year && month.month == now.month;
      _selectedDay = inSameMonth ? DateUtils.dateOnly(now) : null;
    });

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

    return Scaffold(
      appBar: AppBar(title: const Text('行事曆'), centerTitle: true, elevation: 0),
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
                          const SizedBox(height: 8),
                          if (_focusedError != null) ...[
                            Text(
                              _focusedError!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                fontSize: 12,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          _buildWeekdayHeader(),
                          const SizedBox(height: 8),
                          Expanded(child: _buildMonthPager()),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Card(
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
                            const SizedBox(height: 8),
                            if (_focusedError != null) ...[
                              Text(
                                _focusedError!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            _buildWeekdayHeader(),
                            const SizedBox(height: 8),
                            _buildMonthPager(),
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

  Widget _buildMonthHeader() {
    final text = DateFormat('yyyy年MM月', 'zh_TW').format(_focusedMonth);
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () => _changeMonth(-1),
        ),
        Expanded(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.6,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
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

  Widget _buildMonthPager() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellAspectRatio = _calendarAspectRatioForWidth(
          constraints.maxWidth,
          availableHeight: constraints.hasBoundedHeight
              ? constraints.maxHeight
              : null,
        );
        final cellWidth = constraints.maxWidth / 7;
        final cellHeight = cellWidth / cellAspectRatio;
        final gridHeight = (cellHeight * 6) + (_calendarMainAxisSpacing * 5);

        return SizedBox(
          height: gridHeight,
          child: PageView.builder(
            controller: _monthPageController,
            onPageChanged: _onMonthPageChanged,
            itemBuilder: (context, index) {
              final month = _monthFromPage(index);
              return _buildCalendarGrid(month, cellAspectRatio, cellHeight);
            },
          ),
        );
      },
    );
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
  ) {
    final year = displayedMonth.year;
    final month = displayedMonth.month;
    final firstDay = DateTime(year, month, 1);
    final totalDays = DateUtils.getDaysInMonth(year, month);
    final startOffset = firstDay.weekday % 7;
    final cellWidth = cellHeight * cellAspectRatio;
    const totalCells = 42;
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
        final isSelected = DateUtils.isSameDay(_selectedDay, dateOnly);
        final isToday = DateUtils.isSameDay(dateOnly, DateTime.now());

        final daySegments =
            eventSegmentsByDay[_dayKey(dateOnly)] ?? const <_DayEventSegment>[];
        final hasEvents = daySegments.isNotEmpty;
        final maxVisibleEvents = _maxVisibleEventsForCellHeight(cellHeight);
        final visibleEvents = daySegments.take(maxVisibleEvents).toList();
        final overflowCount = daySegments.length - visibleEvents.length;
        const maxLinesPerEvent = 2;

        return InkWell(
          onTap: () async {
            setState(() {
              _selectedDay = dateOnly;
            });
            if (hasEvents && MediaQuery.sizeOf(context).width < 900) {
              await _showSelectedDayEventsSheet(dateOnly);
            }
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: isSelected
                  ? Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.12)
                  : isToday
                  ? Theme.of(
                      context,
                    ).colorScheme.secondary.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    '$dayNumber',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: visibleEvents
                        .map(
                          (segment) => _buildEventLine(
                            segment,
                            maxLinesPerEvent,
                            cellWidth,
                          ),
                        )
                        .toList(),
                  ),
                ),
                if (overflowCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '+$overflowCount',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.black54,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEventLine(
    _DayEventSegment segment,
    int maxLines,
    double cellWidth,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final isMultiDay = segment.event.spansMultipleDays;
    final textStyle = TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w500,
      color: colorScheme.onPrimaryContainer,
    );
    final leadingInset = segment.continuesLeft ? 0.0 : 2.0;
    final trailingInset = segment.continuesRight ? 0.0 : 2.0;
    final leftTextInset = segment.continuesLeft ? 0.0 : 1.0;
    final rightTextInset = segment.continuesRight ? 0.0 : 1.0;
    final currentTextInset = leadingInset + leftTextInset;
    final borderRadius = BorderRadius.only(
      topLeft: Radius.circular(segment.continuesLeft ? 0 : 4),
      bottomLeft: Radius.circular(segment.continuesLeft ? 0 : 4),
      topRight: Radius.circular(segment.continuesRight ? 0 : 4),
      bottomRight: Radius.circular(segment.continuesRight ? 0 : 4),
    );
    final textWidget = Text(
      segment.event.title,
      maxLines: isMultiDay ? 1 : maxLines,
      softWrap: !isMultiDay,
      overflow: isMultiDay ? TextOverflow.visible : TextOverflow.ellipsis,
      style: textStyle,
    );
    final shouldShowTitle = segment.showTitle || isMultiDay;

    Widget content;
    if (shouldShowTitle) {
      if (isMultiDay) {
        final shift =
            (cellWidth * segment.titleShiftDays) +
            currentTextInset -
            segment.startTextInset;
        content = ClipRect(
          child: Transform.translate(
            offset: Offset(-shift, 0),
            child: textWidget,
          ),
        );
      } else {
        content = textWidget;
      }
    } else {
      content = Opacity(opacity: 0, child: textWidget);
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: () => _showEventDetails(segment.event),
        child: Container(
          width: double.infinity,
          margin: EdgeInsets.only(
            left: leadingInset,
            right: trailingInset,
            bottom: 3,
          ),
          padding: EdgeInsets.fromLTRB(leftTextInset, 2, rightTextInset, 2),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.8),
            borderRadius: borderRadius,
          ),
          child: content,
        ),
      ),
    );
  }

  Future<void> _showEventDetails(_CalendarEvent event) async {
    setState(() {
      _selectedDay = event.startDay;
    });

    final colorScheme = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              20 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                _EventDetailRow(
                  icon: Icons.schedule,
                  label: '時間',
                  value: _formatEventDateTime(event),
                ),
                if (event.location != null && event.location!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _EventDetailRow(
                    icon: Icons.place_outlined,
                    label: '地點',
                    value: event.location!,
                  ),
                ],
                if (event.description != null &&
                    event.description!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    '說明',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.45,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      event.description!,
                      style: const TextStyle(fontSize: 14, height: 1.5),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  List<_CalendarEvent>? _eventsForDay(DateTime? day) {
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
    final events = _eventsForDay(day) ?? const <_CalendarEvent>[];
    final title = DateFormat('yyyy/MM/dd (E)', 'zh_TW').format(day);
    final colorScheme = Theme.of(context).colorScheme;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              20 + MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '當天活動 ${events.length} 筆',
                  style: TextStyle(fontSize: 13, color: colorScheme.primary),
                ),
                const SizedBox(height: 12),
                if (events.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text('當天沒有活動'),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: events.length,
                      separatorBuilder: (_, index) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final event = events[index];
                        return Material(
                          color: colorScheme.surfaceContainerHighest.withValues(
                            alpha: 0.32,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () async {
                              Navigator.of(sheetContext).pop();
                              await _showEventDetails(event);
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    event.title,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatEventTimeSummary(event),
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  if (event.location != null &&
                                      event.location!.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      event.location!,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatEventDateTime(_CalendarEvent event) {
    if (event.isAllDay) {
      final startText = DateFormat(
        'yyyy/MM/dd (E)',
        'zh_TW',
      ).format(event.startDay);
      if (!event.spansMultipleDays) {
        return '全天 | $startText';
      }
      final endText = DateFormat(
        'yyyy/MM/dd (E)',
        'zh_TW',
      ).format(event.endDay);
      return '全天 | $startText - $endText';
    }

    final sameDay = DateUtils.isSameDay(event.startTime, event.endTime);
    final startText = DateFormat(
      'yyyy/MM/dd (E) HH:mm',
      'zh_TW',
    ).format(event.startTime);
    if (sameDay) {
      final endText = DateFormat('HH:mm', 'zh_TW').format(event.endTime);
      return '$startText - $endText';
    }

    final endText = DateFormat(
      'yyyy/MM/dd (E) HH:mm',
      'zh_TW',
    ).format(event.endTime);
    return '$startText - $endText';
  }

  String _formatEventTimeSummary(_CalendarEvent event) {
    if (event.isAllDay) {
      return event.spansMultipleDays ? '全天，多日活動' : '全天';
    }

    final sameDay = DateUtils.isSameDay(event.startTime, event.endTime);
    if (sameDay) {
      final startText = DateFormat('HH:mm', 'zh_TW').format(event.startTime);
      final endText = DateFormat('HH:mm', 'zh_TW').format(event.endTime);
      return '$startText - $endText';
    }

    final startText = DateFormat(
      'MM/dd HH:mm',
      'zh_TW',
    ).format(event.startTime);
    final endText = DateFormat('MM/dd HH:mm', 'zh_TW').format(event.endTime);
    return '$startText - $endText';
  }

  int _dayKey(DateTime date) =>
      (date.year * 10000) + (date.month * 100) + date.day;

  Map<int, List<_DayEventSegment>> _buildMonthEventLayout(DateTime month) {
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

    final result = <int, List<_DayEventSegment>>{};
    final firstWeekOffset = firstDay.weekday % 7;
    final weekCount = ((firstWeekOffset + totalDays) / 7).ceil();

    for (var week = 0; week < weekCount; week++) {
      final weekDays = List<DateTime?>.generate(7, (weekday) {
        final dayNumber = week * 7 + weekday - firstWeekOffset + 1;
        if (dayNumber < 1 || dayNumber > totalDays) return null;
        return DateUtils.dateOnly(DateTime(year, monthValue, dayNumber));
      });

      final weekSegments = <_WeekEventSegment>[];
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
          _WeekEventSegment(
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
            _DayEventSegment(
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
    final prefs = await SharedPreferences.getInstance();
    final key = _cacheKeyForMonth(month);
    final cached = prefs.getString(key);
    if (cached == null || cached.isEmpty) return;

    try {
      final data = jsonDecode(cached) as List<dynamic>;
      final events = data
          .map((raw) => _CalendarEvent.fromJson(raw as Map<String, dynamic>))
          .toList();
      if (!mounted) return;
      setState(() {
        _eventsByMonth[key] = events;
      });
    } catch (_) {
      // Ignore corrupted cache.
    }
  }

  Future<void> _saveCachedEventsForMonth(
    DateTime month,
    List<_CalendarEvent> events,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _cacheKeyForMonth(month);
    final payload = jsonEncode(events.map((e) => e.toJson()).toList());
    await prefs.setString(key, payload);
  }

  Future<void> _loadEventsForMonth(DateTime month) async {
    final key = _cacheKeyForMonth(month);
    if (_loadingMonths.contains(key)) return;

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
      final events = <_CalendarEvent>[];

      for (var i = 0; i < items.length; i++) {
        try {
          final raw = items[i] as Map<String, dynamic>;
          if (raw['status'] == 'cancelled') continue;
          final start = raw['start'] as Map<String, dynamic>?;
          final end = raw['end'] as Map<String, dynamic>?;
          final startRaw = start?['dateTime'] ?? start?['date'];
          if (startRaw is! String) continue;
          final endRaw = end?['dateTime'] ?? end?['date'];
          final startTime = DateTime.parse(startRaw).toLocal();
          final endTime = endRaw is String
              ? DateTime.parse(endRaw).toLocal()
              : startTime;
          final isAllDay =
              start?['dateTime'] == null &&
              start?['date'] is String &&
              end?['dateTime'] == null;
          final title = (raw['summary'] as String?)?.trim();
          final location = (raw['location'] as String?)?.trim();
          final description = (raw['description'] as String?)?.trim();
          final eventId = (raw['id'] as String?)?.trim();
          events.add(
            _CalendarEvent(
              id: eventId == null || eventId.isEmpty
                  ? 'fallback_${i}_${startTime.toIso8601String()}_${title ?? ''}'
                  : eventId,
              startTime: startTime,
              endTime: endTime,
              isAllDay: isAllDay,
              title: title == null || title.isEmpty ? '未命名活動' : title,
              location: location == null || location.isEmpty ? null : location,
              description: description == null || description.isEmpty
                  ? null
                  : description,
            ),
          );
        } catch (_) {}
      }

      await _saveCachedEventsForMonth(month, events);
      if (!mounted) return;
      setState(() {
        _eventsByMonth[key] = events;
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

class _CalendarEvent {
  final String id;
  final DateTime startTime;
  final DateTime endTime;
  final bool isAllDay;
  final String title;
  final String? location;
  final String? description;

  const _CalendarEvent({
    required this.id,
    required this.startTime,
    required this.endTime,
    required this.isAllDay,
    required this.title,
    this.location,
    this.description,
  });

  String get identity => '$id|${startTime.toIso8601String()}';

  DateTime get startDay => DateUtils.dateOnly(startTime);

  DateTime get endDay {
    final normalizedEnd = endTime.isBefore(startTime) ? startTime : endTime;
    final adjustedEnd = normalizedEnd.subtract(const Duration(microseconds: 1));
    final endDayOnly = DateUtils.dateOnly(adjustedEnd);
    return endDayOnly.isBefore(startDay) ? startDay : endDayOnly;
  }

  bool get spansMultipleDays => endDay.isAfter(startDay);

  bool occursOnDate(DateTime date) {
    final day = DateUtils.dateOnly(date);
    if (day.isBefore(startDay)) return false;
    return !day.isAfter(endDay);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'startTime': startTime.toIso8601String(),
    'endTime': endTime.toIso8601String(),
    'isAllDay': isAllDay,
    'title': title,
    'location': location,
    'description': description,
  };

  factory _CalendarEvent.fromJson(Map<String, dynamic> json) {
    final start = DateTime.parse(json['startTime'] as String).toLocal();
    final endRaw = json['endTime'];
    final end = endRaw is String ? DateTime.parse(endRaw).toLocal() : start;
    final idRaw = json['id'];
    return _CalendarEvent(
      id: idRaw is String && idRaw.isNotEmpty
          ? idRaw
          : 'legacy_${start.toIso8601String()}_${json['title'] as String? ?? ''}',
      startTime: start,
      endTime: end,
      isAllDay: json['isAllDay'] as bool? ?? false,
      title: json['title'] as String,
      location: (json['location'] as String?)?.trim(),
      description: (json['description'] as String?)?.trim(),
    );
  }
}

class _EventDetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _EventDetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 18, color: colorScheme.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontSize: 14, height: 1.45)),
            ],
          ),
        ),
      ],
    );
  }
}

class _DayEventSegment {
  final _CalendarEvent event;
  final int lane;
  final bool showTitle;
  final int titleShiftDays;
  final double startTextInset;
  final bool continuesLeft;
  final bool continuesRight;

  const _DayEventSegment({
    required this.event,
    required this.lane,
    required this.showTitle,
    required this.titleShiftDays,
    required this.startTextInset,
    required this.continuesLeft,
    required this.continuesRight,
  });
}

class _WeekEventSegment {
  final _CalendarEvent event;
  final int startIndex;
  final int endIndex;

  const _WeekEventSegment({
    required this.event,
    required this.startIndex,
    required this.endIndex,
  });
}
