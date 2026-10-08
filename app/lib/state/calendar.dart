import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models.dart';
import 'providers.dart';

/// Events of a month ([monthKey]), read through the backend's shared cache.
final calendarEventsProvider = FutureProvider.autoDispose.family<List<CalendarEvent>, String>((ref, month) {
  final church = ref.watch(churchDataProvider);
  if (church == null) return const [];
  return church.calendarEvents(month);
});

/// Changes to the church's Google Calendar. Each one reloads every month
/// the event was in or is now in, so an event over the end of a month
/// changes in both.
class CalendarActions {
  CalendarActions(this._ref);

  final Ref _ref;

  void _reload(Iterable<CalendarEvent> events) {
    for (final m in {for (final e in events) ...e.months}) {
      _ref.invalidate(calendarEventsProvider(m));
    }
  }

  /// Saves [event], new or changed from [previous].
  Future<void> save(CalendarEvent event, {CalendarEvent? previous}) async {
    await _ref.churchData.calendarSave(event, previous: previous);
    _reload([event, ?previous]);
  }

  /// Deletes [event]. The returned undo creates it again, as a new event.
  Future<Future<void> Function()> delete(CalendarEvent event) async {
    final data = _ref.churchData;
    await data.calendarDelete(event);
    _reload([event]);
    return () async {
      await data.calendarSave(event.anew);
      _reload([event]);
    };
  }
}

final calendarActionsProvider = Provider<CalendarActions>(CalendarActions.new);
