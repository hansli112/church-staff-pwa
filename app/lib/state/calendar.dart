import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backend.dart';
import '../data/cache/calendar_read_cache.dart';
import '../domain/models.dart';
import '../env.dart';
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
    project: deviceCacheProject(),
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

/// Reads the months either side of [month] ahead, so moving to one shows
/// it at once.
void readAhead(WidgetRef ref, DateTime month) {
  final months = ref.read(_calendarMonthsProvider);
  if (months == null) return;
  for (final step in const [-1, 1]) {
    months.prefetch(monthKey(DateTime(month.year, month.month + step)));
  }
}

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

/// Changes to the church's Google Calendar, sent through the months read
/// now ([CalendarMonths.write]), so every fetched copy shows them at once.
class CalendarActions {
  CalendarActions(this._ref);

  final Ref _ref;

  CalendarMonths? _months() => _ref.mounted ? _ref.read(_calendarMonthsProvider) : null;

  /// Saves [event], new or changed from [previous], and returns it as the
  /// server saved it: a new one with its id.
  Future<CalendarEvent> save(CalendarEvent event, {CalendarEvent? previous}) => withEditLock(_ref, () async {
    Future<CalendarEvent> send() => _ref.churchData.calendarSave(event, previous: previous);
    // write answers null only for a deletion.
    return (await (_months()?.write(event, previous: previous, send: send, now: _months) ?? send()))!;
  });

  /// Deletes [event], which cancels its roster. The returned undo creates it
  /// again, as a new event, with the roster back on it.
  Future<Future<void> Function()> delete(CalendarEvent event) => withEditLock(_ref, () async {
    final data = _ref.churchData;
    final months = _months();
    Future<CalendarEvent?> send() async {
      await data.calendarDelete(event);
      return null;
    }

    await (months?.write(event, deleting: true, send: send, now: _months) ?? send());
    return () => withEditLock(_ref, () async {
      // The backend writes to the currently selected calendar, so an old
      // undo must not recreate its event in a different one.
      if (months == null || !identical(_months(), months)) throw const CloudException(CloudErrorCode.unavailable);
      await months.write(
        event.anew,
        send: () => data.calendarSave(event.anew, restoreRosterOf: event.id),
        now: _months,
      );
    });
  });
}

final calendarActionsProvider = Provider<CalendarActions>(CalendarActions.new);
