import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models.dart';
import '../firebase/codec.dart';

class CalendarCacheScope {
  const CalendarCacheScope({
    required this.project,
    required this.uid,
    required this.churchId,
    required this.calendarId,
    required this.revision,
  });
  final String project;
  final String uid;
  final String churchId;
  final String calendarId;
  final String revision;

  String get key => jsonEncode([project, uid, churchId, calendarId, revision]);
  @override
  bool operator ==(Object other) => other is CalendarCacheScope && key == other.key;
  @override
  int get hashCode => key.hashCode;
}

class CachedCalendarMonth {
  const CachedCalendarMonth({required this.events, required this.fetchedAt});
  final List<CalendarEvent> events;
  final DateTime fetchedAt;
}

/// A single authorized account/church/calendar/revision, never a bag of old
/// accounts that could reappear after their observed access was lost. Only
/// complete, successfully fetched months belong here; this is not a write queue.
class CalendarReadCache {
  CalendarReadCache(this._prefs);
  final SharedPreferences _prefs;
  static const _key = 'martha.calendar.read.v1';
  static const _maxMonths = 6;
  CalendarCacheScope? _scope;
  final _months = <String, CachedCalendarMonth>{};
  final _discarded = <String>{};
  int _generation = 0;
  Future<void> _pending = Future.value();

  CalendarCacheScope? get scope => _scope;

  void select(CalendarCacheScope? scope) {
    if (_scope == scope && scope != null) return;
    _generation++;
    if (_scope != null) _discarded.add(_scope!.key);
    _scope = scope;
    _months.clear();
    Object? raw;
    try {
      final encoded = _prefs.getString(_key);
      raw = encoded == null ? null : jsonDecode(encoded);
      if (raw is Map && raw['scope'] is String && raw['scope'] != scope?.key) {
        _discarded.add(raw['scope'] as String);
      }
    } catch (_) {
      /* Unavailable or malformed storage has no readable cache. */
    }
    if (scope != null) {
      try {
        if (!_discarded.contains(scope.key) &&
            raw is Map &&
            raw['schema'] == 1 &&
            raw['scope'] == scope.key &&
            raw['months'] is Map) {
          for (final entry in (raw['months'] as Map).entries) {
            if (entry.key is! String || !_validMonth(entry.key as String) || entry.value is! Map) {
              throw const FormatException();
            }
            final month = entry.value as Map;
            final when = DateTime.parse(month['fetchedAt'] as String);
            final events = <CalendarEvent>[];
            for (final value in month['events'] as List) {
              final event = calendarEventFromJson(value);
              if (event == null) throw const FormatException();
              events.add(event);
            }
            _months[entry.key as String] = CachedCalendarMonth(events: List.unmodifiable(events), fetchedAt: when);
          }
          while (_months.length > _maxMonths) {
            _months.remove(_months.keys.first);
          }
          return;
        }
      } catch (_) {
        // Malformed or unavailable device storage is never readable data.
        _months.clear();
      }
    }
    _persist();
  }

  CachedCalendarMonth? read(String month) => _scope == null ? null : _months[month];

  Future<void> save(CalendarCacheScope scope, String month, List<CalendarEvent> events, {required DateTime fetchedAt}) {
    if (scope != _scope || !_validMonth(month)) return Future.value();
    _months.remove(month);
    _months[month] = CachedCalendarMonth(events: List.unmodifiable(events), fetchedAt: fetchedAt.toUtc());
    while (_months.length > _maxMonths) {
      _months.remove(_months.keys.first);
    }
    return _persist();
  }

  Future<void> invalidate(Iterable<String> months) {
    for (final month in months) {
      _months.remove(month);
    }
    return _persist();
  }

  Future<void> _persist() {
    final generation = _generation;
    final encoded = _scope == null || _months.isEmpty
        ? null
        : jsonEncode({
            'schema': 1,
            'scope': _scope!.key,
            'months': {
              for (final entry in _months.entries)
                entry.key: {
                  'fetchedAt': entry.value.fetchedAt.toUtc().toIso8601String(),
                  'events': [
                    for (final event in entry.value.events)
                      {
                        ...calendarEventToJson(event),
                        'recurringEventId': ?event.recurringEventId,
                        'originalStart': ?event.originalStart,
                      },
                  ],
                },
            },
          });
    _pending = _pending.then((_) async {
      if (generation != _generation) return;
      try {
        if (encoded == null) {
          await _prefs.remove(_key);
        } else {
          await _prefs.setString(_key, encoded);
        }
      } catch (_) {
        // A read-only cache must not turn a successful live read into failure.
      }
    });
    return _pending;
  }
}

bool _validMonth(String month) => RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(month);
