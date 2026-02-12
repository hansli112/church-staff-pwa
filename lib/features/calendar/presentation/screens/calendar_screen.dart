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
  late DateTime _focusedMonth;
  DateTime? _selectedDay;
  List<_CalendarEvent> _events = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _focusedMonth = DateTime(now.year, now.month, 1);
    _selectedDay = DateUtils.dateOnly(now);
    _loadCachedEventsForMonth();
    _loadEventsForMonth();
  }

  void _changeMonth(int offset) {
    setState(() {
      _focusedMonth = DateTime(
        _focusedMonth.year,
        _focusedMonth.month + offset,
        1,
      );
      final now = DateTime.now();
      final inSameMonth =
          _focusedMonth.year == now.year && _focusedMonth.month == now.month;
      _selectedDay = inSameMonth ? DateUtils.dateOnly(now) : null;
    });
    _loadCachedEventsForMonth();
    _loadEventsForMonth();
  }

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
                    if (_error != null) ...[
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _buildWeekdayHeader(),
                    const SizedBox(height: 8),
                    _buildCalendarGrid(),
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
                  style: TextStyle(
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

  Widget _buildCalendarGrid() {
    final year = _focusedMonth.year;
    final month = _focusedMonth.month;
    final firstDay = DateTime(year, month, 1);
    final totalDays = DateUtils.getDaysInMonth(year, month);
    final startOffset = firstDay.weekday % 7;
    final totalCells = 42;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 6,
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
        final isSelected = _selectedDay == dateOnly;
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
                  ? Theme.of(context).colorScheme.primary.withOpacity(0.12)
                  : isToday
                  ? Theme.of(context).colorScheme.secondary.withOpacity(0.12)
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
        color: colorScheme.primaryContainer.withOpacity(0.8),
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
    return _events
        .where((event) => DateUtils.isSameDay(event.startTime, date))
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  String _cacheKeyForMonth(DateTime month) {
    return 'calendar_events_${month.year}_${month.month.toString().padLeft(2, '0')}';
  }

  Future<void> _loadCachedEventsForMonth() async {
    final prefs = await SharedPreferences.getInstance();
    final key = _cacheKeyForMonth(_focusedMonth);
    final cached = prefs.getString(key);
    if (cached == null || cached.isEmpty) return;
    try {
      final data = jsonDecode(cached) as List<dynamic>;
      final events = data
          .map((raw) => _CalendarEvent.fromJson(raw as Map<String, dynamic>))
          .toList();
      if (!mounted) return;
      setState(() {
        _events = events;
      });
    } catch (_) {
      // Ignore corrupted cache.
    }
  }

  Future<void> _saveCachedEventsForMonth(List<_CalendarEvent> events) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _cacheKeyForMonth(_focusedMonth);
    final payload = jsonEncode(events.map((e) => e.toJson()).toList());
    await prefs.setString(key, payload);
  }

  Future<void> _loadEventsForMonth() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final monthStart = DateTime.utc(_focusedMonth.year, _focusedMonth.month, 1);
    final monthEnd = DateTime.utc(
      _focusedMonth.year,
      _focusedMonth.month + 1,
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
          _error = message == null || message.isEmpty
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

      await _saveCachedEventsForMonth(events);
      if (!mounted) return;
      setState(() {
        _events = events;
      });
    } catch (_) {
      if (!mounted) return;
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cacheKeyForMonth(_focusedMonth));
      if (cached == null) {
        setState(() {
          _error = '離線或連線逾時，且沒有快取資料';
        });
      } else {
        setState(() {
          _error = null;
        });
      }
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
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
