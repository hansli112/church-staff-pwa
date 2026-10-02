import 'day.dart';
import 'models.dart';

/// The rosters of [service] from [from] for [weeks] weeks, oldest first.
///
/// Roster documents are only written when someone edits a day. Every other
/// week shows a draft built from the service template on the service's
/// weekday, so nothing has to be pre-generated (self-host backfilled a
/// quarter of documents from the editor's device, which needed a
/// transaction over every day of each week to avoid duplicates).
///
/// A week that already has a saved roster gets no draft, even when the
/// service has since moved to another weekday.
List<Roster> upcomingRosters({
  required Service service,
  required Iterable<Roster> saved,
  required Day from,
  int weeks = 13,
}) {
  final end = from.weekStart.addDays(weeks * 7);
  final result = <Roster>[
    for (final roster in saved)
      if (roster.type == service.id &&
          !roster.day.isBefore(from) &&
          roster.day.isBefore(end))
        roster,
  ];
  if (service.enabled) {
    final taken = {for (final r in result) r.day.weekStart};
    for (var week = 0; week < weeks; week++) {
      final start = from.weekStart.addDays(week * 7);
      if (taken.contains(start)) continue;
      final day = start.nextOnOrAfter(service.weekday);
      if (day.isBefore(from)) continue;
      result.add(draftRoster(service, day));
    }
  }
  result.sort((a, b) => a.day.compareTo(b.day));
  return result;
}

/// An unsaved roster for [day] with the service template's duties.
Roster draftRoster(Service service, Day day) => Roster(
  type: service.id,
  day: day,
  duties: [for (final role in service.duties) Duty(role: role)],
  events: const [],
  saved: false,
);

class MyService {
  const MyService(this.roster, this.duties);

  final Roster roster;
  final List<String> duties;
}

/// The days in [rosters] where this person serves, with their duties.
///
/// Matches by uid; a name with no uid on that duty (typed in by hand, or a
/// name two members share) falls back to the name, so the right person
/// still sees it.
List<MyService> myServices(
  Iterable<Roster> rosters, {
  required String uid,
  required String name,
}) => [
  for (final roster in rosters)
    if (roster.dutiesOf(uid: uid, name: name) case final duties
        when duties.isNotEmpty)
      MyService(roster, duties),
];
