import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backend.dart';
import '../domain/models.dart';
import 'providers.dart';

final calendarSettingsProvider = StreamProvider<CalendarSettings>((ref) {
  if (!ref.watch(churchOpenProvider)) return Stream.value(const CalendarSettings());
  return openChurch(ref).calendarSettings();
});

typedef _CalendarScope = ({ChurchData data, String uid, String? calendarId});

/// No retained month survives a change of account, church, access or calendar.
final _calendarScopeProvider = Provider<_CalendarScope?>((ref) {
  final uid = ref.watch(uidProvider);
  final data = ref.watch(churchDataProvider);
  final open = ref.watch(churchOpenProvider);
  final member = ref.watch(meProvider.select((m) => m.hasError || m.isLoading ? null : m.value?.uid));
  final settings = ref.watch(
    calendarSettingsProvider.select(
      (s) => s.hasError || s.isLoading ? null : (ready: s.value?.ready ?? false, calendarId: s.value?.calendarId),
    ),
  );
  if (uid == null || data == null || !open || member != uid || !(settings?.ready ?? false)) {
    return null;
  }
  return (data: data, uid: uid, calendarId: settings!.calendarId);
});

bool _accessRefused(Object error) =>
    error is CloudException &&
    (error.code == CloudErrorCode.permissionDenied ||
        error.code == CloudErrorCode.churchClosed ||
        error.reason == CloudReason.reconnect);

const _retention = Duration(seconds: 60);
const _maxIdleMonths = 6;

final _calendarMonthsProvider = Provider<_CalendarMonths?>((ref) {
  final scope = ref.watch(_calendarScopeProvider);
  if (scope == null) return null;
  final months = _CalendarMonths(scope);
  ref.onDispose(months.close);
  return months;
});

/// Only idle months count towards the bound; a month on screen is not evicted.
class _CalendarMonths {
  _CalendarMonths(this.scope);

  final _CalendarScope scope;
  final entries = <String, _CalendarEvents>{};
  final _keepers = <String, void Function()>{};
  final _idle = <String>{};
  final _mutations = <Object, _CalendarMutation>{};
  int generation = 0;
  Object? refusal;
  StackTrace? refusalStack;

  void revoke(Object error, StackTrace stack) {
    generation++;
    refusal = error;
    refusalStack = stack;
    for (final entry in entries.values.toList()) {
      entry.deny(error, stack);
    }
  }

  _CalendarWrite begin(CalendarEvent event, CalendarEvent? previous) {
    final key = event.id ?? Object();
    final mutation = _mutations.putIfAbsent(key, _CalendarMutation.new);
    mutation.events.addAll([event, ?previous]);
    mutation.pending++;
    if (mutation.pending > 1) mutation.overlapped = true;
    return _CalendarWrite(key, mutation, ++mutation.order, generation);
  }

  void finish(_CalendarWrite write) {
    final mutation = write.mutation;
    if (--mutation.pending != 0) return;
    _mutations.remove(write.key);
    if (!mutation.overlapped) return;
    // Calendar replies have no revision: after overlapping writes, only a
    // complete read can tell which change the server committed last.
    for (final entry in entries.values.toList()) {
      if (entry.affectedBy(mutation.events)) entry.reload();
    }
  }

  void idle(String month) {
    _idle.remove(month);
    _idle.add(month);
    while (_idle.length > _maxIdleMonths) {
      final oldest = _idle.first;
      _idle.remove(oldest);
      _keepers.remove(oldest)?.call();
    }
  }

  void remove(String month, _CalendarEvents events) {
    if (!identical(entries[month], events)) return;
    entries.remove(month);
    _keepers.remove(month);
    _idle.remove(month);
  }

  void close() {
    for (final release in _keepers.values.toList()) {
      release();
    }
    _keepers.clear();
    _idle.clear();
    entries.clear();
  }
}

class _CalendarMutation {
  final events = <CalendarEvent>[];
  int pending = 0;
  int order = 0;
  bool overlapped = false;
}

class _CalendarWrite {
  _CalendarWrite(this.key, this.mutation, this.order, this.generation);

  final Object key;
  final _CalendarMutation mutation;
  final int order;
  final int generation;

  bool get latest => order == mutation.order;
}

/// A month's events, retained for up to a minute after the backend read.
/// At most six idle months are kept; quick revisits also share pending reads.
/// Refresh/invalidate still requests the complete backend list.
final calendarEventsProvider = AsyncNotifierProvider.autoDispose.family<_CalendarEvents, List<CalendarEvent>, String>(
  _CalendarEvents.new,
);

class _CalendarEvents extends AsyncNotifier<List<CalendarEvent>> {
  _CalendarEvents(this.month);

  final String month;
  _CalendarScope? _scope;

  @override
  FutureOr<List<CalendarEvent>> build() {
    final months = ref.watch(_calendarMonthsProvider);
    final scope = months?.scope;
    if (_scope != scope && _scope != null) {
      state = const AsyncData([]);
      state = const AsyncLoading();
    }
    _scope = scope;
    if (months == null) return const [];
    final clock = ref.watch(clockProvider);
    final requestRef = ref;
    final keep = ref.keepAlive();
    months.entries[month] = this;
    months._keepers[month] = keep.close;
    Timer? expiry;
    DateTime? idleUntil;
    DateTime? freshUntil;
    void expireWhenIdle() {
      expiry?.cancel();
      if (idleUntil == null) return;
      final until = freshUntil != null && freshUntil!.isBefore(idleUntil!) ? freshUntil! : idleUntil!;
      final wait = until.difference(clock());
      expiry = Timer(wait > Duration.zero ? wait : Duration.zero, keep.close);
    }

    ref.onCancel(() {
      idleUntil = clock().add(_retention);
      expireWhenIdle();
      months.idle(month);
    });
    ref.onResume(() {
      expiry?.cancel();
      months._idle.remove(month);
      final until = freshUntil ?? idleUntil;
      if (until != null && !clock().isBefore(until)) {
        scheduleMicrotask(() {
          if (requestRef.mounted) requestRef.invalidateSelf();
        });
      }
      idleUntil = null;
    });
    ref.onDispose(() {
      expiry?.cancel();
      months.remove(month, this);
    });
    final generation = months.generation;
    return months.scope.data
        .calendarEvents(month)
        .then(
          (events) {
            if (generation != months.generation) {
              Error.throwWithStackTrace(months.refusal!, months.refusalStack!);
            }
            if (requestRef.mounted) {
              freshUntil = clock().add(_retention);
              expireWhenIdle();
            }
            return events;
          },
          onError: (Object error, StackTrace stack) {
            if (requestRef.mounted) {
              freshUntil = clock().add(_retention);
              expireWhenIdle();
              if (_accessRefused(error)) months.revoke(error, stack);
            }
            Error.throwWithStackTrace(error, stack);
          },
        );
  }

  void deny(Object error, StackTrace stack) {
    // Riverpod preserves previous data on AsyncError/AsyncLoading. Replace it
    // first: even the month grid must no longer show unauthorized events.
    // Fail any pending .future before replacing previous data. Riverpod
    // otherwise completes that read with the empty list instead of its error.
    state = AsyncError(error, stack);
    state = const AsyncData([]);
    state = AsyncError(error, stack);
  }

  void reload() => ref.invalidateSelf();

  bool affectedBy(Iterable<CalendarEvent> events) =>
      state.isLoading ||
      events.any(
        (event) =>
            event.months.contains(month) || (event.id != null && (state.value?.any((e) => e.id == event.id) ?? false)),
      );

  void delete(CalendarEvent event) {
    final loaded = state.value;
    if (loaded == null || state.hasError || event.id == null) {
      ref.invalidateSelf();
      return;
    }
    final reading = state.isLoading;
    state = AsyncData([
      for (final e in loaded)
        if (e.id != event.id) e,
    ]);
    if (reading) ref.invalidateSelf();
  }

  void save(CalendarEvent saved, CalendarEvent? previous) {
    final loaded = state.value;
    if (loaded == null || state.hasError || saved.id == null) {
      ref.invalidateSelf();
      return;
    }
    final reading = state.isLoading;
    state = AsyncData(
      [
        for (final e in loaded)
          if (e.id != saved.id && (previous?.id == null || e.id != previous!.id)) e,
        if (saved.months.contains(month)) saved,
      ]..sort((a, b) => a.start.compareTo(b.start)),
    );
    if (reading) ref.invalidateSelf();
  }
}

/// Changes to the church's Google Calendar. After backend success, every
/// already fetched copy is patched immediately. Unknown or racing reads are
/// reconciled with a complete list instead of inventing a partial month.
class CalendarActions {
  CalendarActions(this._ref);

  final Ref _ref;

  bool _current(_CalendarMonths? months, {int? generation}) =>
      _ref.mounted &&
      months != null &&
      identical(_ref.read(_calendarMonthsProvider), months) &&
      (generation == null || months.generation == generation);

  _CalendarMonths? _sameCurrentContext(_CalendarMonths? origin) {
    if (!_ref.mounted || origin == null) return null;
    final current = _ref.read(_calendarMonthsProvider);
    if (current == null ||
        current.scope.uid != origin.scope.uid ||
        current.scope.data.churchId != origin.scope.data.churchId ||
        current.scope.calendarId != origin.scope.calendarId) {
      return null;
    }
    return current;
  }

  void _reconcileReturnedContext(_CalendarMonths? origin, Iterable<CalendarEvent> events, {int? generation}) {
    if (_current(origin, generation: generation)) return;
    final current = _sameCurrentContext(origin);
    if (current == null) return;
    // A trip away and back may have fetched before this write completed.
    // Re-read in the current authorized context; never transplant old data.
    for (final entry in current.entries.values.toList()) {
      if (entry.affectedBy(events)) entry.reload();
    }
  }

  void _recheckReadAccess(_CalendarMonths? months) {
    final current = _sameCurrentContext(months);
    if (current == null) return;
    // A calendar editor may lose write access but remain a member who can
    // read. Only a refusal from calendarEvents may purge readable months.
    for (final entry in current.entries.values.toList()) {
      entry.reload();
    }
  }

  void _saved(
    _CalendarMonths? months,
    CalendarEvent event,
    CalendarEvent saved,
    CalendarEvent? previous, {
    int? generation,
  }) {
    if (!_current(months, generation: generation)) {
      _reconcileReturnedContext(months, [event, saved, ?previous], generation: generation);
      return;
    }
    for (final entry in months!.entries.values.toList()) {
      if (entry.affectedBy([event, saved, ?previous])) entry.save(saved, previous);
    }
  }

  /// Saves [event], new or changed from [previous].
  Future<void> save(CalendarEvent event, {CalendarEvent? previous}) async {
    final months = _ref.read(_calendarMonthsProvider);
    final write = months?.begin(event, previous);
    try {
      final saved = await _ref.churchData.calendarSave(event, previous: previous);
      write?.mutation.events.add(saved);
      if (write?.latest ?? true) {
        _saved(months, event, saved, previous, generation: write?.generation);
      } else {
        _reconcileReturnedContext(months, [event, saved, ?previous], generation: write?.generation);
      }
    } catch (error) {
      if (_accessRefused(error)) _recheckReadAccess(months);
      rethrow;
    } finally {
      if (_current(months) && write != null) months!.finish(write);
    }
  }

  /// Deletes [event], which cancels its roster. The returned undo creates it
  /// again, as a new event, with the roster back on it.
  Future<Future<void> Function()> delete(CalendarEvent event) async {
    final data = _ref.churchData;
    final months = _ref.read(_calendarMonthsProvider);
    final write = months?.begin(event, null);
    try {
      await data.calendarDelete(event);
      if (_current(months, generation: write?.generation) && (write?.latest ?? true)) {
        for (final entry in months!.entries.values.toList()) {
          if (entry.affectedBy([event])) entry.delete(event);
        }
      } else {
        _reconcileReturnedContext(months, [event], generation: write?.generation);
      }
    } catch (error) {
      if (_accessRefused(error)) _recheckReadAccess(months);
      rethrow;
    } finally {
      if (_current(months) && write != null) months!.finish(write);
    }
    return () async {
      // The backend writes to the currently selected calendar, so an old
      // undo must not recreate its event in a different one.
      if (!_current(months)) throw const CloudException(CloudErrorCode.unavailable);
      final restoring = months!.begin(event.anew, null);
      try {
        final saved = await data.calendarSave(event.anew, restoreRosterOf: event.id);
        restoring.mutation.events.add(saved);
        _saved(months, event, saved, null, generation: restoring.generation);
      } catch (error) {
        if (_accessRefused(error)) _recheckReadAccess(months);
        rethrow;
      } finally {
        if (_current(months)) months.finish(restoring);
      }
    };
  }
}

final calendarActionsProvider = Provider<CalendarActions>(CalendarActions.new);
