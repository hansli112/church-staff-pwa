import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backend.dart';
import '../data/cache/calendar_read_cache.dart';
import '../env.dart';
import '../domain/models.dart';
import 'connectivity.dart';
import 'app_update.dart';
import 'calendar_months.dart';
import 'providers.dart';

export 'calendar_months.dart' show CalendarReadStatus;

final calendarSettingsProvider = StreamProvider<CalendarSettings>((ref) {
  if (!ref.watch(churchOpenProvider)) return Stream.value(const CalendarSettings());
  return openChurch(ref).calendarSettings();
});

typedef _CalendarScope = ({ChurchData data, String uid, String? calendarId, String? revision});

/// No retained month survives a change of account, church, access or calendar.
final _calendarScopeProvider = Provider<_CalendarScope?>((ref) {
  final uid = ref.watch(uidProvider);
  final data = ref.watch(churchDataProvider);
  final open = ref.watch(churchOpenProvider);
  final member = ref.watch(meProvider.select((m) => m.hasError || m.isLoading ? null : m.value?.uid));
  final settings = ref.watch(
    calendarSettingsProvider.select(
      (s) => s.hasError || s.isLoading
          ? null
          : (ready: s.value?.ready ?? false, calendarId: s.value?.calendarId, revision: s.value?.revision),
    ),
  );
  if (uid == null || data == null || !open || member != uid || !(settings?.ready ?? false)) {
    return null;
  }
  return (data: data, uid: uid, calendarId: settings!.calendarId, revision: settings.revision);
});

CalendarCacheScope? _cacheScope(_CalendarScope? scope) {
  if (scope == null || scope.calendarId == null || scope.revision == null) return null;
  return CalendarCacheScope(
    project: '${Env.current.name}:${firebaseOptionsFor(Env.current).projectId}',
    uid: scope.uid,
    churchId: scope.data.churchId,
    calendarId: scope.calendarId!,
    revision: scope.revision!,
  );
}

final _calendarCacheProvider = Provider<CalendarReadCache>((ref) => CalendarReadCache(ref.watch(prefsProvider)));

/// Loading a restored session is not an observed loss of access. Actual
/// account/church/membership/calendar changes discard the previous scope.
final calendarCacheLifecycleProvider = Provider<CalendarReadCache>((ref) {
  final cache = ref.watch(_calendarCacheProvider);
  final scope = ref.watch(_calendarScopeProvider);
  final auth = ref.watch(authUserProvider);
  final uid = ref.watch(uidProvider);
  final data = ref.watch(churchDataProvider);
  final member = ref.watch(meProvider);
  final church = ref.watch(churchProvider);
  final settings = ref.watch(calendarSettingsProvider);
  final previous = cache.scope;
  final changedIdentity = previous != null && (uid != previous.uid || data?.churchId != previous.churchId);
  final accessLost =
      (!auth.isLoading && uid == null) ||
      (data != null && !member.isLoading && (member.hasError || member.value?.uid != uid)) ||
      (data != null && !church.isLoading && (church.hasError || !(church.value?.isActive ?? false))) ||
      (ref.watch(churchOpenProvider) &&
          member.value?.uid == uid &&
          !settings.isLoading &&
          (settings.hasError || !(settings.value?.ready ?? false)));
  if (changedIdentity || accessLost) cache.select(null);
  if (scope != null) cache.select(_cacheScope(scope));
  return cache;
});

/// Alongside the existing events interface, so callers never mistake an
/// offline persisted month for a new successful server read.
final calendarReadStatusProvider = Provider.autoDispose.family<CalendarReadStatus, String>((ref, month) {
  ref.watch(calendarEventsProvider(month));
  final online = ref.watch(onlineProvider);
  final status = ref.watch(_calendarMonthsProvider)?.status(month) ?? const CalendarReadStatus();
  return CalendarReadStatus(
    cached: status.cached || !online,
    fetchedAt: status.fetchedAt,
    refreshError: status.refreshError,
  );
});

/// The months of the calendar the reader may see now; none without access.
final _calendarMonthsProvider = Provider<CalendarMonths?>((ref) {
  final scope = ref.watch(_calendarScopeProvider);
  final cache = ref.watch(calendarCacheLifecycleProvider);
  if (scope == null) return null;
  final months = CalendarMonths(
    key: (uid: scope.uid, churchId: scope.data.churchId, calendarId: scope.calendarId, revision: scope.revision),
    read: scope.data.calendarEvents,
    cache: cache,
    cacheScope: _cacheScope(scope),
    clock: ref.watch(clockProvider),
  );
  ref.onDispose(months.close);
  return months;
});

/// A month's events, from [CalendarMonths]: reused for a minute after the
/// read, shared while read; a refresh or invalidation reads the complete
/// month again.
final calendarEventsProvider = AsyncNotifierProvider.autoDispose.family<_CalendarEvents, List<CalendarEvent>, String>(
  _CalendarEvents.new,
);

class _CalendarEvents extends AsyncNotifier<List<CalendarEvent>> implements CalendarMonthView {
  _CalendarEvents(this.month);

  final String month;
  CalendarMonths? _months;
  bool _built = false;

  @override
  FutureOr<List<CalendarEvent>> build() {
    final months = ref.watch(_calendarMonthsProvider);
    final same = identical(_months, months);
    if (!same && _months != null) {
      // Another account, church or calendar: nothing of the old one stays.
      state = const AsyncData([]);
      state = const AsyncLoading();
    }
    // Built again on the same months: a refresh or an invalidation.
    final refresh = _built && same;
    _built = true;
    _months = months;
    if (months == null) return const [];
    months.show(month, this);
    final requestRef = ref;
    ref.onCancel(() => months.pause(month));
    ref.onResume(() {
      months.show(month, this);
      if (!months.fresh(month)) {
        scheduleMicrotask(() {
          if (requestRef.mounted) requestRef.invalidateSelf();
        });
      }
    });
    ref.onDispose(() => months.release(month, this));
    return months.events(month, refresh: refresh);
  }

  @override
  void show(List<CalendarEvent> events) => state = AsyncData(events);

  @override
  void reload() => ref.invalidateSelf();

  @override
  void deny(Object error, StackTrace stack) {
    // Riverpod preserves previous data on AsyncError/AsyncLoading. Replace it
    // first: even the month grid must no longer show unauthorized events.
    // Fail any pending .future before replacing previous data. Riverpod
    // otherwise completes that read with the empty list instead of its error.
    state = AsyncError(error, stack);
    state = const AsyncData([]);
    state = AsyncError(error, stack);
  }
}

/// Changes to the church's Google Calendar. After backend success, every
/// already fetched copy is patched immediately. Unknown or racing reads are
/// reconciled with a complete list instead of inventing a partial month.
class CalendarActions {
  CalendarActions(this._ref);

  final Ref _ref;

  bool _current(CalendarMonths? months, {int? generation}) =>
      _ref.mounted &&
      months != null &&
      identical(_ref.read(_calendarMonthsProvider), months) &&
      (generation == null || months.generation == generation);

  /// The months now read for the same account, church and calendar as
  /// [origin], after a trip away and back.
  CalendarMonths? _sameKey(CalendarMonths? origin) {
    if (!_ref.mounted || origin == null) return null;
    final current = _ref.read(_calendarMonthsProvider);
    return current?.key == origin.key ? current : null;
  }

  void _reconcileReturnedContext(CalendarMonths? origin, Iterable<CalendarEvent> events, {int? generation}) {
    if (_current(origin, generation: generation)) return;
    // A trip away and back may have fetched before this write completed.
    // Re-read in the current authorized context; never transplant old data.
    _sameKey(origin)?.reload(events);
  }

  /// A calendar editor may lose write access but remain a member who can
  /// read. Only a refusal from calendarEvents may purge readable months.
  void _recheckReadAccess(CalendarMonths? months) => _sameKey(months)?.reloadAll();

  void _saved(
    CalendarMonths? months,
    CalendarEvent event,
    CalendarEvent saved,
    CalendarEvent? previous, {
    int? generation,
  }) {
    if (!_current(months, generation: generation)) {
      _reconcileReturnedContext(months, [event, saved, ?previous], generation: generation);
      return;
    }
    months!.saved(event, saved, previous);
  }

  /// Saves [event], new or changed from [previous].
  Future<void> save(CalendarEvent event, {CalendarEvent? previous}) => withEditLock(_ref, () async {
    final months = _ref.read(_calendarMonthsProvider);
    final write = months?.begin(event, previous);
    try {
      final saved = await _ref.churchData.calendarSave(event, previous: previous);
      write?.savedAs(saved);
      if (write?.latest ?? true) {
        _saved(months, event, saved, previous, generation: write?.generation);
      } else {
        _reconcileReturnedContext(months, [event, saved, ?previous], generation: write?.generation);
      }
    } catch (error) {
      if (calendarAccessRefused(error)) _recheckReadAccess(months);
      rethrow;
    } finally {
      if (_current(months) && write != null) months!.finish(write);
    }
  });

  /// Deletes [event], which cancels its roster. The returned undo creates it
  /// again, as a new event, with the roster back on it.
  Future<Future<void> Function()> delete(CalendarEvent event) => withEditLock(_ref, () async {
    final data = _ref.churchData;
    final months = _ref.read(_calendarMonthsProvider);
    final write = months?.begin(event, null);
    try {
      await data.calendarDelete(event);
      if (_current(months, generation: write?.generation) && (write?.latest ?? true)) {
        months!.deleted(event);
      } else {
        _reconcileReturnedContext(months, [event], generation: write?.generation);
      }
    } catch (error) {
      if (calendarAccessRefused(error)) _recheckReadAccess(months);
      rethrow;
    } finally {
      if (_current(months) && write != null) months!.finish(write);
    }
    return () => withEditLock(_ref, () async {
      // The backend writes to the currently selected calendar, so an old
      // undo must not recreate its event in a different one.
      if (!_current(months)) throw const CloudException(CloudErrorCode.unavailable);
      final restoring = months!.begin(event.anew, null);
      try {
        final saved = await data.calendarSave(event.anew, restoreRosterOf: event.id);
        restoring.savedAs(saved);
        _saved(months, event, saved, null, generation: restoring.generation);
      } catch (error) {
        if (calendarAccessRefused(error)) _recheckReadAccess(months);
        rethrow;
      } finally {
        if (_current(months)) months.finish(restoring);
      }
    });
  });
}

final calendarActionsProvider = Provider<CalendarActions>(CalendarActions.new);
