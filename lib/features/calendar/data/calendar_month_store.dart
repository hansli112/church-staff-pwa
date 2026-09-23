import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/entities/calendar_event.dart';
import 'google_calendar_month_reader.dart';

/// Reads one month of events. [GoogleCalendarMonthReader.fetchMonth] in the
/// app; tests hand in their own so they control what arrives and when.
typedef CalendarMonthFetcher =
    Future<List<CalendarEvent>> Function(DateTime month);

/// The events the calendar screen shows, one month at a time.
///
/// Owns everything between "the user paged to October" and "October's events
/// are on screen": the SharedPreferences copy that paints instantly, the Google
/// read behind it, the freshness gate that keeps paging from burning API quota,
/// and patching the lists after an admin write so the grid does not wait for a
/// round trip.
///
/// Every change to a month replaces its list rather than editing it in place,
/// so `identical()` on [eventsForMonth] is enough to tell whether a cached
/// layout is still good.
class CalendarMonthStore with ChangeNotifier {
  /// 同一個月在這段時間內不重抓。沒有這道閘門的話，每次左右換頁都會對
  /// 當月 + 前後月各打一次 Google Calendar API，來回滑幾次就燒掉配額。
  static const Duration monthFreshness = Duration(minutes: 10);

  /// SharedPreferences 只保留距今前後這麼多個月的快取，避免 key 無限累積。
  static const int _cacheKeepMonths = 12;
  static const String _cacheKeyPrefix = 'calendar_events_';

  final CalendarMonthFetcher _fetchMonth;
  final DateTime Function() _now;
  final Future<SharedPreferences> Function() _prefs;

  final Map<String, List<CalendarEvent>> _eventsByMonth = {};
  final Set<String> _loadingMonths = {};
  final Map<String, String?> _errorsByMonth = {};
  final Map<String, DateTime> _fetchedAtByMonth = {};

  // 每個月的寫入世代。寫入時 +1；fetch 開始時記下當時的值，回來時若已經
  // 不同，代表這份回應是在寫入之前發出去的 —— 它不知道那筆寫入，套上去會
  // 蓋掉本地 patch 還蓋上新鮮戳記，錯的資料會掛十分鐘。所以丟掉，重抓。
  final Map<String, int> _writeGeneration = {};

  bool _disposed = false;

  /// [prefs] exists so a test can hand in storage that fails, the way a full
  /// localStorage does on a phone.
  CalendarMonthStore({
    CalendarMonthFetcher? fetchMonth,
    DateTime Function()? now,
    Future<SharedPreferences> Function()? prefs,
  }) : _fetchMonth = fetchMonth ?? GoogleCalendarMonthReader().fetchMonth,
       _now = now ?? DateTime.now,
       _prefs = prefs ?? SharedPreferences.getInstance;

  /// The month's events, or null if nothing has arrived for it yet — neither
  /// from the device cache nor from Google.
  List<CalendarEvent>? eventsForMonth(DateTime month) =>
      _eventsByMonth[_keyFor(month)];

  /// Why the month failed to load, ready to show; null when it did not fail.
  String? errorForMonth(DateTime month) => _errorsByMonth[_keyFor(month)];

  /// Puts [month] on screen as soon as possible and refreshes it if due.
  ///
  /// The device cache and Google are asked at the same time: the cache paints
  /// the month straight away, Google replaces it when it answers. A month read
  /// from Google within [monthFreshness] is left alone.
  Future<void> ensureLoaded(DateTime month) =>
      Future.wait([_loadCached(month), _fetch(month)]);

  /// An admin write went through: patch what is on screen now, then refetch
  /// every month either version of the event touches.
  ///
  /// The server has already accepted the change, so the patch is not
  /// optimistic — it only saves the user from watching the old event sit there
  /// for a round trip. The refetch is what makes the cache authoritative again.
  void applyWrite({CalendarEvent? removed, CalendarEvent? added}) {
    if (_disposed) return;
    final touched = <String>{};

    if (removed != null) {
      // Scans every loaded month rather than only the ones the event spans:
      // an edit that moves an event has to clear it out of wherever it used
      // to sit, and that span is not always the span being passed in.
      for (final entry in _eventsByMonth.entries) {
        if (!entry.value.any((existing) => existing.id == removed.id)) {
          continue;
        }
        _eventsByMonth[entry.key] = List.unmodifiable(
          entry.value.where((existing) => existing.id != removed.id),
        );
        touched.add(entry.key);
      }
    }

    if (added != null) {
      for (final month in monthsSpannedBy(added)) {
        final key = _keyFor(month);
        // A month that was never loaded has nothing to patch; it will fetch
        // the event normally when the user pages to it.
        final events = _eventsByMonth[key];
        if (events == null) continue;
        _eventsByMonth[key] = List.unmodifiable([
          ...events.where((existing) => existing.id != added.id),
          added,
        ]);
        touched.add(key);
      }
    }

    if (touched.isNotEmpty) notifyListeners();

    // The old span matters too: moving an event out of a month has to refresh
    // the month it left, not only the one it landed in.
    final toRefresh = <String, DateTime>{
      for (final event in [?removed, ?added])
        for (final month in monthsSpannedBy(event)) _keyFor(month): month,
    };
    for (final entry in toRefresh.entries) {
      _writeGeneration[entry.key] = (_writeGeneration[entry.key] ?? 0) + 1;
      // Clearing the freshness stamp is what lets the refetch through; without
      // it [_fetch] would sit on the patched copy for the next ten minutes.
      _fetchedAtByMonth.remove(entry.key);
      unawaited(_fetch(entry.value));
    }
  }

  /// Every month an event touches, so a span across a month boundary refreshes
  /// both sides rather than only where it starts.
  static List<DateTime> monthsSpannedBy(CalendarEvent event) {
    final months = <DateTime>[];
    var cursor = DateTime(event.startDay.year, event.startDay.month, 1);
    final last = DateTime(event.endDay.year, event.endDay.month, 1);
    while (!cursor.isAfter(last)) {
      months.add(cursor);
      cursor = DateTime(cursor.year, cursor.month + 1, 1);
    }
    return months;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // Also the SharedPreferences key, so it cannot change without orphaning
  // every copy already on people's phones.
  static String _keyFor(DateTime month) =>
      '$_cacheKeyPrefix${month.year}_${month.month.toString().padLeft(2, '0')}';

  Future<void> _loadCached(DateTime month) async {
    final key = _keyFor(month);
    // 記憶體裡已經有這個月了就不要再讀 disk：重讀會 jsonDecode 整個月、
    // 通知畫面、並讓 layout 快取失效，等於每次換頁都把三個月的版面重算一次。
    if (_eventsByMonth.containsKey(key)) return;

    try {
      final prefs = await _prefs();
      final cached = prefs.getString(key);
      if (cached == null || cached.isEmpty) return;

      final data = jsonDecode(cached) as List<dynamic>;
      final events = data
          .map((raw) => CalendarEvent.fromJson(raw as Map<String, dynamic>))
          .toList();
      // Checked again after the await: Google may have answered meanwhile,
      // and the disk copy is never newer than that.
      if (_disposed || _eventsByMonth.containsKey(key)) return;
      _eventsByMonth[key] = List.unmodifiable(events);
      _notify();
    } catch (_) {
      // Ignore corrupted or unreadable cache; Google will fill the month.
    }
  }

  /// Never throws. The month is already on screen by the time this runs, so a
  /// storage failure (localStorage full, private mode) only costs the next
  /// cold start its instant paint — it is not a failed load.
  Future<void> _saveCached(String key, List<CalendarEvent> events) async {
    try {
      final prefs = await _prefs();
      final payload = jsonEncode(events.map((e) => e.toJson()).toList());
      await prefs.setString(key, payload);
      await _pruneCachedMonths(prefs);
    } catch (error) {
      debugPrint('Could not cache $key: $error');
    }
  }

  Future<bool> _hasCachedCopy(String key) async {
    try {
      return (await _prefs()).getString(key) != null;
    } catch (_) {
      return false;
    }
  }

  /// 每瀏覽一個新月份就多一筆 key，永遠不清的話 localStorage 會一直長大。
  /// 只留距今 [_cacheKeepMonths] 個月內的月份，其餘刪掉。
  Future<void> _pruneCachedMonths(SharedPreferences prefs) async {
    final now = _now();
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

  Future<void> _fetch(DateTime month) async {
    final key = _keyFor(month);
    // Already on its way. If a write lands before it does, the generation
    // check below throws that answer away and asks again.
    if (_loadingMonths.contains(key)) return;

    final fetchedAt = _fetchedAtByMonth[key];
    if (fetchedAt != null && _now().difference(fetchedAt) < monthFreshness) {
      return; // 這個月剛抓過，直接用記憶體裡的資料
    }

    final generation = _writeGeneration[key] ?? 0;
    bool superseded() => (_writeGeneration[key] ?? 0) != generation;

    _loadingMonths.add(key);
    _errorsByMonth.remove(key);
    _notify();

    try {
      final events = await _fetchMonth(month);
      if (_disposed || superseded()) return;
      _eventsByMonth[key] = List.unmodifiable(events);
      _fetchedAtByMonth[key] = _now();
      _notify();
      await _saveCached(key, events);
    } on CalendarReadException catch (error) {
      if (_disposed || superseded()) return;
      _errorsByMonth[key] = error.message;
    } catch (_) {
      if (_disposed || superseded()) return;
      // Offline with a copy on disk is not worth an error: the month is
      // already showing that copy.
      _errorsByMonth[key] = await _hasCachedCopy(key)
          ? null
          : '離線或連線逾時，且沒有快取資料';
    } finally {
      _loadingMonths.remove(key);
      if (!_disposed) {
        _notify();
        if (superseded()) unawaited(_fetch(month));
      }
    }
  }
}
