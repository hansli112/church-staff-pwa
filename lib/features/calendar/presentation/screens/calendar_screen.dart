import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/config/google_calendar_config.dart';
import '../widgets/_calendar_models.dart';
import '../widgets/_day_cell.dart';
import '../widgets/_day_events_sheet.dart';
import '../widgets/_event_detail_sheet.dart';

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
  final ValueNotifier<DateTime?> _selectedDay = ValueNotifier<DateTime?>(null);
  final Map<String, List<CalendarEvent>> _eventsByMonth = {};
  final Set<String> _loadingMonths = {};
  final Map<String, String?> _errorsByMonth = {};

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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
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
                if (hasEvents) {
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

  Future<void> _showEventDetails(CalendarEvent event) async {
    _selectedDay.value = event.startDay;
    if (!mounted) return;
    await showEventDetailSheet(context, event);
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
      onSelectDay: (selectedDay) {
        _selectedDay.value = selectedDay;
      },
    );
  }

  int _dayKey(DateTime date) =>
      (date.year * 10000) + (date.month * 100) + date.day;

  Map<int, List<DayEventSegment>> _buildMonthEventLayout(DateTime month) {
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
    final prefs = await SharedPreferences.getInstance();
    final key = _cacheKeyForMonth(month);
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
      final events = <CalendarEvent>[];

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
            CalendarEvent(
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
        } catch (e, st) {
          debugPrint('Skipping malformed calendar item #$i: $e');
          debugPrintStack(stackTrace: st);
        }
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
