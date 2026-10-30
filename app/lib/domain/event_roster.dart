import 'day.dart';
import 'limits.dart';
import 'models.dart';
import 'staff_order.dart';

/// The days of [e] as a roster keeps them. An event's times are already
/// the church's (its time zone, that of every dateKey), not the phone's.
({Day first, Day last}) eventDays(CalendarEvent e) => (first: e.day, last: e.lastDay);

/// A new, unsaved roster for calendar event [e] on calendar [calendarId],
/// with [duties].
Roster eventRoster(CalendarEvent e, {List<Duty> duties = const [], String? calendarId}) {
  final days = eventDays(e);
  return Roster(
    type: '',
    day: days.first,
    duties: duties,
    saved: false,
    forEvent: RosterEvent(
      eventId: e.id!,
      title: cutText(e.title, TextLimits.eventTitle),
      lastDay: days.last,
      calendarId: calendarId,
      recurringEventId: e.recurringEventId,
      originalStart: e.originalStart,
      group: e.group,
    ),
  );
}

/// A change of an event made in the app, as its roster takes it
/// (testdata/event_rosters.json, as functions/src/eventRosters.ts).
enum EventChange {
  edited,
  deleted,

  /// Made again by undoing its delete, under a new id.
  restored,
}

/// What an event's roster does when its event changes.
enum EventRosterFate {
  nothing,

  /// Takes the event's title, days and group.
  follows,

  /// Kept for 復原, shown nowhere and reminded of nothing.
  cancelled,

  /// Onto the event made again, under its id.
  movesOnto,
}

/// What [roster] (null: there is none) does when its event has [change]:
/// a cancelled one follows no edit, and only it moves onto the event a
/// delete undone makes again.
EventRosterFate eventRosterFate(EventChange change, Roster? roster) {
  final cancelled = roster?.forEvent?.cancelled;
  return switch ((change, cancelled)) {
    (_, null) => EventRosterFate.nothing,
    (EventChange.edited, false) => EventRosterFate.follows,
    (EventChange.deleted, _) => EventRosterFate.cancelled,
    (EventChange.restored, true) => EventRosterFate.movesOnto,
    _ => EventRosterFate.nothing,
  };
}

/// Whether the app may write [next] over [saved] (null: none yet), as
/// firestore.rules let it, whoever arranges it: an event's title, days and
/// group are the calendar's, set only when its roster is made; only the
/// backend cancels one; an event's roster never turns into a service's day
/// or back (testdata/event_rosters.json).
bool appMayWriteRoster(Roster? saved, Roster next) {
  if (saved == null) return !(next.forEvent?.cancelled ?? false);
  if (saved.isEvent != next.isEvent) return false;
  final (was, now) = (saved.forEvent, next.forEvent);
  if (was == null || now == null) return true;
  return !was.cancelled &&
      !now.cancelled &&
      was.title == now.title &&
      saved.day == next.day &&
      was.lastDay == now.lastDay &&
      was.group == now.group;
}

/// The duties to offer when arranging an event: every duty the services'
/// templates have, each once, in the services' order.
List<String> eventDutySuggestions(List<Service> services) => {
  for (final s in services) ...s.duties,
}.toList();

/// Whether [m] serves [duty] in any 牧區: an event is in none, so whoever
/// does it anywhere is listed first.
bool servesAnywhere(Member m, String duty) => m.zones.any((z) => z.duties.contains(duty));

/// The staff order for an event: per duty, the ranking of the first of
/// [services] that ranks it.
StaffOrder eventStaffOrder(List<Service> services, Map<String, StaffOrder> orders) {
  final byRole = <String, List<String>>{};
  for (final s in services) {
    for (final e in (orders[s.id] ?? StaffOrder()).rankingsByRole.entries) {
      byRole.putIfAbsent(e.key, () => e.value);
    }
  }
  return StaffOrder(byRole);
}

/// The roles of the roster to start [e] with: for a day of a recurring
/// event, those of the latest earlier day of its series that has one
/// (預設沿用上一次); else none. [rosters] are events' rosters.
List<String> previousInSeries(CalendarEvent e, Iterable<Roster> rosters) {
  final series = e.recurringEventId;
  if (series == null) return const [];
  String seriesOf(String id) => id.split('_R').first;
  final day = eventDays(e).first;
  Roster? latest;
  for (final r in rosters) {
    final s = r.forEvent?.recurringEventId;
    if (s == null || seriesOf(s) != seriesOf(series) || !r.day.isBefore(day) || r.duties.isEmpty) continue;
    if (latest == null || r.day.isAfter(latest.day)) latest = r;
  }
  return [for (final d in latest?.duties ?? const <Duty>[]) d.role];
}
