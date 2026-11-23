part of 'memory_backend.dart';

/// [CalendarData] of a [MemoryChurchData]. Google Calendar itself is
/// scripted: [MemoryBackend.connectCalendar], the calendars [choices]
/// offers and the events in [MemoryBackend.calendarEvents]. Public for
/// tests that hold or fail its reads and writes.
class MemoryCalendarData implements CalendarData {
  MemoryCalendarData(this._c);

  final MemoryChurchData _c;

  @override
  Stream<CalendarSettings> settings() => _c._b.watch(() {
    _c._requireMember();
    return _c._b.calendars[_c.churchId] ?? const CalendarSettings();
  });

  @override
  Future<Uri> authUrl() async {
    _c._functionAdmin();
    return Uri.parse('https://accounts.google.com/o/oauth2/v2/auth?state=memory');
  }

  @override
  Future<List<CalendarChoice>> choices() async {
    _c._functionAdmin();
    return _c._b.calendarChoices;
  }

  @override
  Future<void> select(String calendarId, String calendarName) async {
    _c._functionAdmin();
    await _c._b.calendarSelectHeld?.future;
    _c._b.calendars[_c.churchId] = CalendarSettings(
      connected: true,
      calendarName: calendarName,
      calendarId: calendarId,
      revision: 'memory:${++_c._b._calendarRevision}',
    );
    _c._b.notify();
  }

  @override
  Future<void> disconnect() async {
    _c._functionAdmin();
    _c._b.calendars.remove(_c.churchId);
    _c._b.calendarEvents.remove(_c.churchId);
    _c._b.notify();
  }

  @override
  Future<List<CalendarEvent>> events(String month) async {
    _c._b.requireNetwork();
    _c._b.functionAccess(_c.churchId);
    if (_c._b.calendars[_c.churchId]?.needsReconnect ?? false) {
      throw const CloudException(CloudErrorCode.unknown, reason: CloudReason.reconnect);
    }
    await _c._b.calendarEventsHeld?.future;
    // Like Google: every event that overlaps the month, including one that
    // began the month before.
    final first = Day.parse('$month-01');
    final last = first.lastOfMonth;
    return [
      for (final e in _c._b.calendarEvents[_c.churchId] ?? const <CalendarEvent>[])
        if (e.daysWithin(first, last) != null) e,
    ]..sort((a, b) => a.start.compareTo(b.start));
  }

  @override
  Future<CalendarEvent> save(CalendarEvent event, {CalendarEvent? previous, String? restoreRosterOf}) async {
    _c._requireEventWrite(() => _c._groupNow(event.id), event.group ?? '');
    _c._requireRestore(restoreRosterOf);
    await _c._b.calendarSaveHeld?.future;
    final saved = event.id == null
        ? CalendarEvent(
            id: _c._b.newEventId(),
            title: event.title,
            start: event.start,
            end: event.end,
            allDay: event.allDay,
            location: event.location,
            description: event.description,
            group: event.group,
            colorId: event.colorId,
          )
        : event;
    await _c._b.write(() {
      _c._requireEventWrite(() => _c._groupNow(event.id), event.group ?? '');
      _c._requireRestore(restoreRosterOf);
      _c._requireChangeable(event.id);
      final list = _c._b.calendarEvents.putIfAbsent(_c.churchId, () => []);
      final was = list.where((e) => e.id == saved.id).firstOrNull?.group;
      list.removeWhere((e) => e.id == saved.id);
      list.add(saved);
      // A day of a recurring event given to another group: the series goes
      // with it (重複活動照系列存).
      final series = saved.recurringEventId;
      if (series != null && was != saved.group) {
        for (final (i, e) in list.indexed.toList()) {
          if (e.recurringEventId == series && e.group != saved.group) list[i] = e.copyWith(group: () => saved.group);
        }
      }
      // The roster and calendar change become visible together.
      final rosters = _c._b.rosters[_c.churchId]!;
      final from = rosters[Roster.idForEvent(restoreRosterOf ?? saved.id!)];
      final change = restoreRosterOf == null ? EventChange.edited : EventChange.restored;
      if (from != null && eventRosterFate(change, from) != EventRosterFate.nothing) {
        final moved = eventRoster(
          saved,
          duties: from.duties,
          calendarId: from.forEvent!.calendarId,
        ).copyWith(saved: true);
        if (restoreRosterOf != null) rosters.remove(from.id);
        rosters[moved.id] = moved;
      }
    });
    return saved;
  }

  @override
  Future<void> delete(CalendarEvent event) async {
    _c._requireEventWrite(() => _c._groupNow(event.id), null);
    await _c._b.write(() {
      _c._requireEventWrite(() => _c._groupNow(event.id), null);
      _c._requireChangeable(event.id);
      _c._b.calendarEvents[_c.churchId]?.removeWhere((e) => e.id == event.id);
      final rosters = _c._b.rosters[_c.churchId]!;
      final r = rosters[Roster.idForEvent(event.id!)];
      if (eventRosterFate(EventChange.deleted, r) == EventRosterFate.cancelled) {
        rosters[r!.id] = r.copyWith(forEvent: r.forEvent!.copyWith(cancelled: true));
      }
    });
  }
}
