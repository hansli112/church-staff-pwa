import 'models.dart';

/// The calendar's events still to come or under way at [now], from the
/// months read ([months]), soonest first: one over two months is in both,
/// and listed once, by its ID; one not saved yet has none.
List<CalendarEvent> upcomingEvents(Iterable<List<CalendarEvent>> months, {required DateTime now}) => {
  for (final month in months)
    for (final event in month) event.id ?? event: event,
}.values.where((event) => event.end.isAfter(now)).toList()..sort((a, b) => a.start.compareTo(b.start));
