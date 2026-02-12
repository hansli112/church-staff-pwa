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
    return Scaffold(
      appBar: AppBar(title: const Text('行事曆'), centerTitle: true, elevation: 0),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 16),
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
        final cellWidth = constraints.maxWidth / 7;
        final cellHeight = cellWidth / 0.5;
        final gridHeight = (cellHeight * 6) + (_calendarMainAxisSpacing * 5);

        return SizedBox(
          height: gridHeight,
          child: PageView.builder(
            controller: _monthPageController,
            onPageChanged: _onMonthPageChanged,
            itemBuilder: (context, index) {
              final month = _monthFromPage(index);
              return _buildCalendarGrid(month);
            },
          ),
        );
      },
    );
  }

  Widget _buildCalendarGrid(DateTime displayedMonth) {
    final year = displayedMonth.year;
    final month = displayedMonth.month;
    final firstDay = DateTime(year, month, 1);
    final totalDays = DateUtils.getDaysInMonth(year, month);
    final startOffset = firstDay.weekday % 7;
    const totalCells = 42;

    return GridView.builder(
      key: ValueKey<String>(_cacheKeyForMonth(displayedMonth)),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: _calendarMainAxisSpacing,
        crossAxisSpacing: 0,
        childAspectRatio: 0.5,
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

        final events = _eventsForDay(dateOnly);
        final visibleEvents = events.take(2).toList();
        final overflowCount = events.length - visibleEvents.length;
        final maxLinesPerEvent = visibleEvents.length > 1 ? 2 : 3;

        return InkWell(
          onTap: () {
            setState(() {
              _selectedDay = dateOnly;
            });
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.fromLTRB(2, 4, 2, 4),
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
                Text(
                  '$dayNumber',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: ClipRect(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: visibleEvents
                          .map(
                            (event) => _buildEventLine(event, maxLinesPerEvent),
                          )
                          .toList(),
                    ),
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

  Widget _buildEventLine(_CalendarEvent event, int maxLines) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        event.title,
        maxLines: maxLines,
        softWrap: true,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }

  List<_CalendarEvent> _eventsForDay(DateTime date) {
    final key = _cacheKeyForMonth(DateTime(date.year, date.month, 1));
    final monthEvents = _eventsByMonth[key] ?? const <_CalendarEvent>[];
    return monthEvents
        .where((event) => DateUtils.isSameDay(event.startTime, date))
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
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
          final startRaw = start?['dateTime'] ?? start?['date'];
          if (startRaw is! String) continue;
          final startTime = DateTime.parse(startRaw).toLocal();
          final title = (raw['summary'] as String?)?.trim();
          events.add(
            _CalendarEvent(
              startTime: startTime,
              title: title == null || title.isEmpty ? '未命名活動' : title,
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
  final DateTime startTime;
  final String title;

  const _CalendarEvent({required this.startTime, required this.title});

  Map<String, dynamic> toJson() => {
    'startTime': startTime.toIso8601String(),
    'title': title,
  };

  factory _CalendarEvent.fromJson(Map<String, dynamic> json) {
    return _CalendarEvent(
      startTime: DateTime.parse(json['startTime'] as String),
      title: json['title'] as String,
    );
  }
}
