import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../../core/config/google_calendar_config.dart';
import '../../../../core/services/external_link_service.dart';
import '../../../roster/domain/entities/service_roster.dart';
import '../../../roster/presentation/providers/roster_provider.dart';
import '../../../calendar/presentation/screens/calendar_screen.dart'
    deferred as calendar;

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const int _recentActivitiesLimit = 3;
  static const int _recentActivitiesFetchMax = 20;
  static const String _dailyVerseJsonUrl = '/daily-verse.json';
  static const String _dailyBreadUrl =
      'https://www.breadoflife.taipei/news/daily-bible/';
  static const _dailyBreadRangeFallback = '查看今日經文範圍';

  bool _isLoadingCalendar = false;
  bool _isLoadingDailyBreadRange = false;
  bool _isLoadingRecentActivities = false;
  String? _dailyBreadRange;
  String? _recentActivitiesError;
  List<_DashboardCalendarEvent> _recentActivities = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final rosterProvider = context.read<RosterProvider>();
      if (rosterProvider.rosters.isEmpty && !rosterProvider.isLoading) {
        rosterProvider.fetchInitialData();
      }
    });
    _loadDailyBreadRange();
    _loadRecentActivities();
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _displayName(
      context.watch<AuthProvider>().currentUser?.name,
    );
    final fullName = context.watch<AuthProvider>().currentUser?.name ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('教會同工中心'), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '歡迎回來，$displayName！',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            _buildFeatureCard(
              context,
              icon: Icons.menu_book_rounded,
              title: '每日靈糧',
              description: _dailyBreadDescription,
              color: Colors.orangeAccent,
              onTap: _openDailyBread,
            ),
            const SizedBox(height: 16),
            _buildCalendarFeatureCard(context),
            const SizedBox(height: 20),
            _buildSeasonServiceSection(context, fullName: fullName),
          ],
        ),
      ),
    );
  }

  String _displayName(String? fullName) {
    final name = fullName?.trim() ?? '';
    if (name.isEmpty) return '同工';

    final parts = name
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    final hasLatin = RegExp(r'[A-Za-z]').hasMatch(name);
    if (parts.length > 1) {
      return hasLatin ? parts.first : parts.last;
    }

    if (RegExp(r'[\u4E00-\u9FFF]').hasMatch(name)) {
      return name.length > 1 ? name.substring(1) : name;
    }

    return name;
  }

  Future<void> _openCalendar() async {
    if (_isLoadingCalendar) return;
    setState(() {
      _isLoadingCalendar = true;
    });

    var dialogVisible = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await calendar.loadLibrary();
      if (!mounted) return;
      if (dialogVisible) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogVisible = false;
      }
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => calendar.CalendarScreen()));
    } catch (error) {
      if (!mounted) return;
      if (dialogVisible) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogVisible = false;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('載入失敗: $error')));
    } finally {
      if (mounted) {
        if (dialogVisible) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        setState(() {
          _isLoadingCalendar = false;
        });
      }
    }
  }

  Future<void> _openDailyBread() async {
    final launched = await openExternalLink(_dailyBreadUrl);
    if (!launched && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('無法開啟每日靈糧頁面')));
    }
  }

  String get _dailyBreadDescription {
    final range = _dailyBreadRange?.trim();
    if (range != null && range.isNotEmpty) {
      return range;
    }
    if (_isLoadingDailyBreadRange) {
      return '載入今日經文範圍中...';
    }
    return _dailyBreadRangeFallback;
  }

  Future<void> _loadDailyBreadRange() async {
    if (mounted) {
      setState(() {
        _isLoadingDailyBreadRange = true;
      });
    }

    final cached = await _loadCachedDailyBreadRange();
    if (mounted && cached != null && cached.isNotEmpty) {
      setState(() {
        _dailyBreadRange = cached;
      });
    }

    try {
      final fetched = await _fetchDailyBreadRange();
      if (fetched != null && fetched.isNotEmpty) {
        await _saveCachedDailyBreadRange(fetched);
      }
      if (!mounted) return;
      setState(() {
        _dailyBreadRange = fetched ?? _dailyBreadRange;
      });
    } catch (_) {
      // Keep cached or fallback text when the source cannot be reached.
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingDailyBreadRange = false;
        });
      }
    }
  }

  String _cacheKeyForDailyBreadRange() {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return 'dashboard_daily_bread_range_$today';
  }

  Future<String?> _loadCachedDailyBreadRange() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_cacheKeyForDailyBreadRange());
    if (cached == null || cached.isEmpty) return null;
    return cached;
  }

  Future<void> _saveCachedDailyBreadRange(String range) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKeyForDailyBreadRange(), range);
  }

  Future<String?> _fetchDailyBreadRange() async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final uri = Uri.parse(_dailyVerseJsonUrl).replace(
      queryParameters: {'d': today},
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('daily_verse_fetch_failed_${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if ((data['date'] as String?) != today) return null;
    final raw = data['rawRange'] as String?;
    if (raw == null || raw.isEmpty) return null;
    return _normalizeBibleRange(raw);
  }

  String? _parseDailyBreadRange(String html) {
    final pattern = RegExp(
      r'(\d{4}-\d{2}-\d{2})\s*<span>\|</span>\s*<span>\s*([^<]+?)\s*</span>',
      caseSensitive: false,
      dotAll: true,
    );
    final match = pattern.firstMatch(html);
    if (match == null) return null;

    final dateText = match.group(1)?.trim();
    final rangeText = _normalizeBibleRange(match.group(2)?.trim());
    if (dateText == null || rangeText.isEmpty) return null;

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    if (dateText != today) return rangeText;
    return rangeText;
  }

  String _normalizeBibleRange(String? raw) {
    if (raw == null || raw.isEmpty) return '';

    final normalizedPunctuation = raw
        .replaceAll('：', ':')
        .replaceAll('，', ',')
        .trim();
    final singleRangePattern = RegExp(
      r'^(.+?)([零一二三四五六七八九十百千兩〇]+):(\d+)-([零一二三四五六七八九十百千兩〇]+):(\d+)$',
    );
    final singleChapterPattern = RegExp(
      r'^(.+?)([零一二三四五六七八九十百千兩〇]+):(\d+)-(\d+)$',
    );

    final singleRangeMatch = singleRangePattern.firstMatch(
      normalizedPunctuation,
    );
    if (singleRangeMatch != null) {
      final book = singleRangeMatch.group(1)!;
      final startChapter = _chineseNumberToArabic(singleRangeMatch.group(2)!);
      final startVerse = singleRangeMatch.group(3)!;
      final endChapter = _chineseNumberToArabic(singleRangeMatch.group(4)!);
      final endVerse = singleRangeMatch.group(5)!;

      if (startChapter == endChapter) {
        return '$book$startChapter:$startVerse-$endVerse';
      }
      return '$book$startChapter:$startVerse-$endChapter:$endVerse';
    }

    final singleChapterMatch = singleChapterPattern.firstMatch(
      normalizedPunctuation,
    );
    if (singleChapterMatch != null) {
      final book = singleChapterMatch.group(1)!;
      final chapter = _chineseNumberToArabic(singleChapterMatch.group(2)!);
      final startVerse = singleChapterMatch.group(3)!;
      final endVerse = singleChapterMatch.group(4)!;
      return '$book$chapter:$startVerse-$endVerse';
    }

    return normalizedPunctuation.replaceAllMapped(
      RegExp(r'[零一二三四五六七八九十百千兩〇]+'),
      (match) => _chineseNumberToArabic(match.group(0)!),
    );
  }

  String _chineseNumberToArabic(String value) {
    const digitMap = {
      '零': 0,
      '〇': 0,
      '一': 1,
      '二': 2,
      '兩': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
    };
    const unitMap = {'十': 10, '百': 100, '千': 1000};

    var result = 0;
    var section = 0;
    var number = 0;

    for (final rune in value.runes) {
      final char = String.fromCharCode(rune);
      final digit = digitMap[char];
      if (digit != null) {
        number = digit;
        continue;
      }

      final unit = unitMap[char];
      if (unit != null) {
        section += (number == 0 ? 1 : number) * unit;
        number = 0;
      }
    }

    result += section + number;
    return result == 0 && !value.contains('零') && !value.contains('〇')
        ? value
        : result.toString();
  }

  Future<void> _loadRecentActivities() async {
    if (mounted) {
      setState(() {
        _isLoadingRecentActivities = true;
        _recentActivitiesError = null;
      });
    }

    final cached = await _loadCachedRecentActivities();
    final cachedUpcoming = _mergeUpcomingEvents(cached);

    if (mounted && cachedUpcoming.isNotEmpty) {
      setState(() {
        _recentActivities = cachedUpcoming;
      });
    }

    try {
      final fetched = await _fetchRecentActivities();
      final fetchedUpcoming = _mergeUpcomingEvents(fetched);
      await _saveCachedRecentActivities(fetchedUpcoming);

      if (!mounted) return;
      setState(() {
        _recentActivities = fetchedUpcoming;
        _recentActivitiesError = null;
      });
    } catch (_) {
      if (!mounted) return;
      if (cachedUpcoming.isEmpty) {
        setState(() {
          _recentActivitiesError = '近期活動載入失敗';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingRecentActivities = false;
        });
      }
    }
  }

  List<_DashboardCalendarEvent> _mergeUpcomingEvents(
    List<_DashboardCalendarEvent> events,
  ) {
    final today = DateUtils.dateOnly(DateTime.now());
    final merged =
        events
            .where(
              (event) => event.isAllDay
                  ? !DateUtils.dateOnly(event.startTime).isBefore(today)
                  : !event.startTime.isBefore(DateTime.now()),
            )
            .toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime));

    if (merged.length <= _recentActivitiesLimit) return merged;
    return merged.take(_recentActivitiesLimit).toList();
  }

  String _cacheKeyForRecentActivities() {
    return 'dashboard_recent_activities_v1';
  }

  Future<List<_DashboardCalendarEvent>> _loadCachedRecentActivities() async {
    final prefs = await SharedPreferences.getInstance();
    final key = _cacheKeyForRecentActivities();
    final cached = prefs.getString(key);
    if (cached == null || cached.isEmpty) return const [];

    try {
      final data = jsonDecode(cached) as List<dynamic>;
      return data.map((raw) => _DashboardCalendarEvent.fromJson(raw)).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveCachedRecentActivities(
    List<_DashboardCalendarEvent> events,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _cacheKeyForRecentActivities();
    final payload = jsonEncode(events.map((event) => event.toJson()).toList());
    await prefs.setString(key, payload);
  }

  Future<List<_DashboardCalendarEvent>> _fetchRecentActivities() async {
    final now = DateTime.now();
    final todayStart = DateUtils.dateOnly(now).toUtc();

    final uri =
        Uri.https('www.googleapis.com', '', {
          'key': GoogleCalendarConfig.apiKey,
          'singleEvents': 'true',
          'orderBy': 'startTime',
          'maxResults': _recentActivitiesFetchMax.toString(),
          'timeMin': todayStart.toIso8601String(),
          'timeZone': GoogleCalendarConfig.timeZone,
          'fields': 'items(status,start,summary)',
        }).replace(
          pathSegments: [
            'calendar',
            'v3',
            'calendars',
            GoogleCalendarConfig.calendarId,
            'events',
          ],
        );

    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('calendar_fetch_failed_${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>? ?? [];
    final events = <_DashboardCalendarEvent>[];

    for (var i = 0; i < items.length; i++) {
      try {
        final raw = items[i] as Map<String, dynamic>;
        if (raw['status'] == 'cancelled') continue;
        final start = raw['start'] as Map<String, dynamic>?;
        final dateTimeRaw = start?['dateTime'];
        final dateRaw = start?['date'];
        final startRaw = dateTimeRaw ?? dateRaw;
        if (startRaw is! String) continue;
        final title = (raw['summary'] as String?)?.trim();
        events.add(
          _DashboardCalendarEvent(
            startTime: DateTime.parse(startRaw).toLocal(),
            title: title == null || title.isEmpty ? '未命名活動' : title,
            isAllDay: dateTimeRaw == null && dateRaw is String,
          ),
        );
      } catch (_) {}
    }

    return events;
  }

  Widget _buildCalendarFeatureCard(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.purpleAccent.withValues(alpha: 0.2),
              child: const Icon(
                Icons.calendar_month,
                color: Colors.purpleAccent,
              ),
            ),
            title: const Text(
              '行事曆',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text('教會年度活動一覽'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openCalendar,
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: _buildRecentActivitiesContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentActivitiesContent() {
    if (_isLoadingRecentActivities && _recentActivities.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (_recentActivitiesError != null && _recentActivities.isEmpty) {
      return Text(
        _recentActivitiesError!,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    }

    if (_recentActivities.isEmpty) {
      return const Text('近期暫無活動');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('近期活動', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        ..._recentActivities.map((event) {
          final dateText = event.isAllDay
              ? DateFormat('MM/dd (E)', 'zh_TW').format(event.startTime)
              : DateFormat('MM/dd (E) HH:mm', 'zh_TW').format(event.startTime);
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 110,
                  child: Text(
                    dateText,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    event.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSeasonServiceSection(
    BuildContext context, {
    required String fullName,
  }) {
    return Consumer<RosterProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading) {
          return _buildSectionCard(
            title: '本季服事',
            icon: Icons.volunteer_activism,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        if (provider.error != null) {
          return _buildSectionCard(
            title: '本季服事',
            icon: Icons.volunteer_activism,
            child: Text(provider.error!),
          );
        }

        final assignments = _seasonAssignments(
          rosters: provider.rosters,
          userName: fullName,
        );
        if (assignments.isEmpty) {
          final emptyText = fullName.trim().isEmpty ? '尚未登入同工資料' : '本季尚無排到服事';
          return _buildSectionCard(
            title: '本季服事',
            icon: Icons.volunteer_activism,
            child: Text(emptyText),
          );
        }

        return _buildSectionCard(
          title: '本季服事',
          icon: Icons.volunteer_activism,
          child: SizedBox(
            height: _seasonListHeight(assignments.length),
            child: Scrollbar(
              child: ListView.separated(
                itemCount: assignments.length,
                separatorBuilder: (_, itemIndex) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final assignment = assignments[index];
                  final dateText = DateFormat(
                    'MM/dd (E)',
                    'zh_TW',
                  ).format(assignment.roster.date);
                  final roleText = assignment.roles.join('、');
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 90,
                        child: Text(
                          dateText,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              assignment.roster.serviceName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(roleText),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  double _seasonListHeight(int itemCount) {
    const maxVisibleItems = 3;
    const rowHeight = 48.0;
    const separatorHeight = 8.0;
    final visibleCount = itemCount < maxVisibleItems
        ? itemCount
        : maxVisibleItems;
    if (visibleCount <= 0) return 0;
    return (visibleCount * rowHeight) + ((visibleCount - 1) * separatorHeight);
  }

  List<_UserServiceAssignment> _seasonAssignments({
    required List<ServiceRoster> rosters,
    required String userName,
  }) {
    final normalizedName = _normalizeName(userName);
    if (normalizedName.isEmpty) return [];

    final List<_UserServiceAssignment> results = [];
    final now = DateTime.now();
    final quarterStartMonth = ((now.month - 1) ~/ 3) * 3 + 1;
    final quarterStart = DateTime(now.year, quarterStartMonth, 1);
    final quarterEnd = DateTime(now.year, quarterStartMonth + 3, 0);
    final sorted = List<ServiceRoster>.from(rosters)
      ..sort((a, b) => a.date.compareTo(b.date));

    for (final roster in sorted) {
      if (roster.date.isBefore(quarterStart) ||
          roster.date.isAfter(quarterEnd)) {
        continue;
      }
      final roles = roster.duties
          .where(
            (duty) => duty.people.any(
              (person) => _normalizeName(person) == normalizedName,
            ),
          )
          .map((duty) => duty.role)
          .toList();
      if (roles.isEmpty) continue;
      results.add(_UserServiceAssignment(roster: roster, roles: roles));
    }

    return results;
  }

  String _normalizeName(String name) {
    return name.trim().toLowerCase();
  }

  Widget _buildSectionCard({
    required String title,
    required Widget child,
    IconData? icon,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.2),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(description),
        onTap:
            onTap ??
            () {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('此功能即將推出！')));
            },
      ),
    );
  }
}

class _UserServiceAssignment {
  final ServiceRoster roster;
  final List<String> roles;

  const _UserServiceAssignment({required this.roster, required this.roles});
}

class _DashboardCalendarEvent {
  final DateTime startTime;
  final String title;
  final bool isAllDay;

  const _DashboardCalendarEvent({
    required this.startTime,
    required this.title,
    required this.isAllDay,
  });

  Map<String, dynamic> toJson() => {
    'startTime': startTime.toIso8601String(),
    'title': title,
    'isAllDay': isAllDay,
  };

  factory _DashboardCalendarEvent.fromJson(dynamic raw) {
    final json = raw as Map<String, dynamic>;
    return _DashboardCalendarEvent(
      startTime: DateTime.parse(json['startTime'] as String).toLocal(),
      title: json['title'] as String,
      isAllDay: json['isAllDay'] as bool? ?? false,
    );
  }
}
