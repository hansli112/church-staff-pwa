import 'day.dart';
import 'limits.dart';
import 'models.dart';
import 'staff_order.dart';

/// The days of [e] as a roster keeps them: in UTC+8, the time zone of every
/// dateKey (Taiwan, Hong Kong and Malaysia alike), not the phone's. An
/// all-day event's dates are taken as they are.
({Day first, Day last}) eventDays(CalendarEvent e) {
  if (e.allDay) return (first: e.day, last: e.lastDay);
  Day utc8(DateTime t) {
    final s = t.toUtc().add(const Duration(hours: 8));
    return Day(s.year, s.month, s.day);
  }

  final last = e.end.isAfter(e.start) ? e.end.subtract(const Duration(microseconds: 1)) : e.start;
  return (first: utc8(e.start), last: utc8(last));
}

/// A new, unsaved roster for calendar event [e], with [duties].
Roster eventRoster(CalendarEvent e, {List<Duty> duties = const []}) {
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
    ),
  );
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
