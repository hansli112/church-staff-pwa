import 'dart:async';

import '../data/backend.dart';
import '../data/cache/calendar_read_cache.dart';
import '../domain/models.dart';

/// Whose calendar a [CalendarMonths] holds: one account, church, calendar
/// and connection. Months never outlive it.
typedef CalendarKey = ({String uid, String churchId, String? calendarId, String? revision});

/// How a month on screen came to be: a server read, or this device's copy
/// when offline.
class CalendarReadStatus {
  const CalendarReadStatus({this.cached = false, this.fetchedAt, this.refreshError});
  final bool cached;
  final DateTime? fetchedAt;
  final Object? refreshError;
}

/// What shows one month, told when its events change under it.
abstract interface class CalendarMonthView {
  /// A write was applied to the month's events.
  void show(List<CalendarEvent> events);

  /// The month must be read again in full.
  void reload();

  /// Access to the calendar was refused: nothing of it may stay on screen.
  void deny(Object error, StackTrace stack);
}

/// The church calendar a month at a time, as one [CalendarKey] may read it.
///
/// A month read under a minute ago ([retention]) is shown again without a
/// read, and a month asked for while it is read shares that read; a
/// refresh always reads the complete month. Of the months no longer on
/// screen only the [maxIdle] left most recently are kept. A refusal drops
/// every month. Writes go through [write], which applies the reply to every
/// month holding the event; when that cannot be known, the month is read
/// again instead of guessed.
class CalendarMonths {
  CalendarMonths({
    required this.key,
    required Future<List<CalendarEvent>> Function(String month) read,
    required CalendarReadCache cache,
    required CalendarCacheScope? cacheScope,
    required DateTime Function() clock,
  }) : _readMonth = read,
       _cache = cache,
       _cacheScope = cacheScope,
       _clock = clock;

  static const retention = Duration(seconds: 60);
  static const maxIdle = 6;

  final CalendarKey key;
  final Future<List<CalendarEvent>> Function(String month) _readMonth;
  final CalendarReadCache _cache;

  /// Where this device keeps months to show offline; null keeps none.
  final CalendarCacheScope? _cacheScope;
  final DateTime Function() _clock;

  final _months = <String, _Month>{};

  /// Months no longer on screen, the one left longest ago first.
  final _idle = <String>{};
  final _mutations = <Object, _Mutation>{};
  bool _closed = false;

  /// Bumped by a refusal: reads begun before it fail with it.
  int _generation = 0;
  Object? _refusal;
  StackTrace? _refusalStack;

  CalendarReadStatus status(String month) => _months[month]?.status ?? const CalendarReadStatus();

  /// [view] shows [month] now.
  void show(String month, CalendarMonthView view) {
    (_months[month] ??= _Month()).view = view;
    _idle.remove(month);
  }

  /// [month] is off screen for now, but [view] still holds it.
  void pause(String month) => _leave(month);

  /// [view] no longer shows [month].
  void release(String month, CalendarMonthView view) {
    final m = _months[month];
    if (m == null || !identical(m.view, view)) return;
    m.view = null;
    _leave(month);
  }

  void _leave(String month) {
    _idle
      ..remove(month)
      ..add(month);
    // After the current work: a view rebuilding shows the month again first.
    scheduleMicrotask(() {
      while (_idle.length > maxIdle) {
        final oldest = _idle.first;
        _idle.remove(oldest);
        final m = _months[oldest];
        if (m == null) continue;
        if (m.view == null) {
          _months.remove(oldest);
        } else {
          m.forget();
        }
      }
    });
  }

  /// Whether [month] would be shown again without a read: it was read
  /// under a minute ago, or is being read.
  bool fresh(String month) {
    final m = _months[month];
    if (m == null) return false;
    if (m.reading != null) return true;
    final until = m.until;
    return until != null && _clock().isBefore(until) && (m.events != null || m.error != null);
  }

  /// [month]'s events: those read under a minute ago, or the read under way;
  /// with [refresh], or when there are none, the complete month read anew.
  FutureOr<List<CalendarEvent>> events(String month, {bool refresh = false}) {
    final m = _months[month] ??= _Month();
    if (!refresh) {
      if (m.reading case final reading?) return reading;
      if (fresh(month)) {
        if (m.error case final error?) Error.throwWithStackTrace(error, m.stack!);
        return m.events!;
      }
    }
    return m.reading = _read(month, m);
  }

  Future<List<CalendarEvent>> _read(String month, _Month m) async {
    final id = ++m.readId;
    final generation = _generation;
    final authorized = _cacheScope;
    final cached = authorized != null && authorized == _cache.scope ? _cache.read(month) : null;
    // A newer read, a refusal or a forgotten month leaves this one's reply
    // to its own caller only.
    bool current() => !_closed && generation == _generation && identical(_months[month], m) && id == m.readId;
    try {
      final events = await _readMonth(month);
      if (generation != _generation) Error.throwWithStackTrace(_refusal!, _refusalStack!);
      if (current()) {
        final fetched = _clock();
        m
          ..events = events
          ..error = null
          ..until = fetched.add(retention)
          ..status = CalendarReadStatus(fetchedAt: fetched);
        if (authorized != null) unawaited(_cache.save(authorized, month, events, fetchedAt: fetched));
      }
      return events;
    } catch (error, stack) {
      if (!_closed && generation == _generation) {
        if (calendarAccessRefused(error)) {
          _revoke(error, stack);
        } else if (error is CloudException && error.code == CloudErrorCode.unavailable) {
          if (current()) {
            m.status = CalendarReadStatus(
              cached: true,
              fetchedAt: cached?.fetchedAt ?? m.status.fetchedAt,
              refreshError: error,
            );
          }
          if (cached != null && authorized == _cache.scope) {
            if (current()) {
              m
                ..events = cached.events
                ..error = null
                ..until = _clock().add(retention);
            }
            return cached.events;
          }
        }
        if (current()) {
          m
            ..error = error
            ..stack = stack
            ..until = _clock().add(retention);
        }
      }
      Error.throwWithStackTrace(error, stack);
    } finally {
      if (id == m.readId) m.reading = null;
    }
  }

  /// Access was refused: every month is dropped, everything showing one is
  /// told, and reads begun before now fail with [error].
  void _revoke(Object error, StackTrace stack) {
    _generation++;
    _refusal = error;
    _refusalStack = stack;
    _cache.select(null);
    _idle.clear();
    _months.removeWhere((_, m) => m.view == null);
    final views = [for (final m in _months.values) m..forget()];
    for (final m in views) {
      m.view?.deny(error, stack);
    }
  }

  /// Sends one write with [send]: [event] saved over [previous], answered
  /// with the event as the server saved it, or deleted, answered with null.
  /// Every month holding the event then shows the reply; one that cannot
  /// know is read again. Calendar replies have no revision: after
  /// overlapping writes to one event only a complete read tells which the
  /// server committed last, so every month holding it is read again.
  ///
  /// [now] is the months the app reads at the moment. A write that outlasts
  /// these (another account, church or calendar, and back) is never applied
  /// to months read since: they read the month again instead. A refusal has
  /// the months now read for the same calendar read again: a calendar
  /// editor may lose write access but still read.
  Future<CalendarEvent?> write(
    CalendarEvent event, {
    CalendarEvent? previous,
    required Future<CalendarEvent?> Function() send,
    required CalendarMonths? Function() now,
  }) async {
    bool current({int? generation}) => identical(now(), this) && (generation == null || generation == _generation);
    CalendarMonths? sameKey() => switch (now()) {
      final months? when months.key == key => months,
      _ => null,
    };
    final edit = _begin(event, previous);
    try {
      final saved = await send();
      if (saved != null) edit._mutation.events.add(saved);
      if (!current(generation: edit.generation)) {
        // A trip away and back may have read before this write completed.
        // Read again in the current context; never transplant old data.
        sameKey()?._reload([event, ?saved, ?previous]);
      } else if (edit.latest) {
        saved == null ? _deleted(event) : _saved(event, saved, previous);
      }
      return saved;
    } catch (error) {
      // Only a refusal from a read may drop the months the reader can read.
      if (calendarAccessRefused(error)) sameKey()?._reloadAll();
      rethrow;
    } finally {
      if (current()) _finish(edit);
    }
  }

  _Edit _begin(CalendarEvent event, CalendarEvent? previous) {
    unawaited(_cache.invalidate({...event.months, ...?previous?.months}));
    final key = event.id ?? Object();
    final mutation = _mutations.putIfAbsent(key, _Mutation.new);
    mutation.events.addAll([event, ?previous]);
    mutation.pending++;
    if (mutation.pending > 1) mutation.overlapped = true;
    return _Edit(key, mutation, ++mutation.order, _generation);
  }

  void _finish(_Edit edit) {
    final mutation = edit._mutation;
    if (--mutation.pending != 0) return;
    _mutations.remove(edit.key);
    if (mutation.overlapped) _reload(mutation.events);
  }

  /// [saved] was saved for [event], over [previous]: every month holding
  /// any of them shows it now.
  void _saved(CalendarEvent event, CalendarEvent saved, CalendarEvent? previous) {
    for (final (month, m) in _holding([event, saved, ?previous])) {
      _patch(
        month,
        m,
        known: saved.id != null,
        (loaded) => [
          for (final e in loaded)
            if (e.id != saved.id && (previous?.id == null || e.id != previous!.id)) e,
          if (saved.months.contains(month)) saved,
        ]..sort((a, b) => a.start.compareTo(b.start)),
      );
    }
  }

  /// [event] was deleted from every month holding it.
  void _deleted(CalendarEvent event) {
    for (final (month, m) in _holding([event])) {
      _patch(
        month,
        m,
        known: event.id != null,
        (loaded) => [
          for (final e in loaded)
            if (e.id != event.id) e,
        ],
      );
    }
  }

  /// The months holding any of [events] are read again.
  void _reload(Iterable<CalendarEvent> events) {
    for (final (month, m) in _holding(events)) {
      _stale(month, m);
    }
  }

  /// Every month is read again.
  void _reloadAll() {
    for (final MapEntry(key: month, value: m) in _months.entries.toList()) {
      _stale(month, m);
    }
  }

  List<(String, _Month)> _holding(Iterable<CalendarEvent> events) => [
    for (final MapEntry(key: month, value: m) in _months.entries)
      if (m.reading != null ||
          events.any(
            (event) =>
                event.months.contains(month) || (event.id != null && (m.events?.any((e) => e.id == event.id) ?? false)),
          ))
        (month, m),
  ];

  void _patch(
    String month,
    _Month m,
    List<CalendarEvent> Function(List<CalendarEvent> loaded) change, {
    required bool known,
  }) {
    final loaded = m.events;
    if (loaded == null || m.error != null || !known) return _stale(month, m);
    final next = change(loaded);
    m.events = next;
    m.view?.show(next);
    if (m.reading != null) _stale(month, m);
  }

  void _stale(String month, _Month m) {
    if (m.view case final view?) {
      view.reload();
    } else {
      _months.remove(month);
      _idle.remove(month);
    }
  }

  void close() {
    _closed = true;
    _months.clear();
    _idle.clear();
  }
}

/// Whether [error] says the reader may not read the calendar (any more).
bool calendarAccessRefused(Object error) =>
    error is CloudException &&
    (error.code == CloudErrorCode.permissionDenied ||
        error.code == CloudErrorCode.churchClosed ||
        error.reason == CloudReason.reconnect);

class _Month {
  CalendarMonthView? view;
  List<CalendarEvent>? events;
  Object? error;
  StackTrace? stack;

  /// Until when [events] or [error] are shown again without a read.
  DateTime? until;
  Future<List<CalendarEvent>>? reading;
  int readId = 0;
  CalendarReadStatus status = const CalendarReadStatus();

  /// Drops what was read; a read under way no longer counts.
  void forget() {
    events = null;
    error = null;
    stack = null;
    until = null;
    reading = null;
    readId++;
    status = const CalendarReadStatus();
  }
}

class _Mutation {
  final events = <CalendarEvent>[];
  int pending = 0;
  int order = 0;
  bool overlapped = false;
}

/// One change to an event while it is sent, from [CalendarMonths._begin]
/// to [CalendarMonths._finish].
class _Edit {
  _Edit(this.key, this._mutation, this._order, this.generation);

  final Object key;
  final _Mutation _mutation;
  final int _order;

  /// [CalendarMonths._generation] when it began.
  final int generation;

  /// Whether no later write to the same event began since.
  bool get latest => _order == _mutation.order;
}
