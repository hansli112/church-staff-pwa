import 'models.dart';

/// What someone already serves around a day, for the picker (#90): how
/// many other days in its month, anywhere in the church, and what else on
/// that day.
class ServingAround {
  const ServingAround({this.inMonth = 0, this.sameDay = const []});

  /// Other days in the month they serve on, by roster: a service's day, or
  /// an event counted on its first day.
  final int inMonth;

  /// Elsewhere on the day: each service's or event's name and their duties
  /// there.
  final List<({String name, List<String> duties})> sameDay;

  bool get isEmpty => inMonth == 0 && sameDay.isEmpty;
}

/// Per uid, what they serve around [roster]'s day on [rosters] (the
/// church's, every service and event; one listed twice counts once), not
/// counting [roster] itself. [nameOf] names a service's day or an event.
Map<String, ServingAround> servingAround(
  Roster roster,
  Iterable<Roster> rosters, {
  required String Function(Roster) nameOf,
}) {
  final day = roster.day;
  final inMonth = <String, int>{};
  final sameDay = <String, List<({String name, List<String> duties})>>{};
  final seen = {roster.id};
  for (final r in rosters) {
    if (!seen.add(r.id)) continue;
    final uids = {
      for (final d in r.duties)
        for (final e in d.uids.entries)
          if (d.people.contains(e.key)) e.value,
    };
    final onDay = !day.isBefore(r.day) && !r.lastDay.isBefore(day);
    final thisMonth = r.day.year == day.year && r.day.month == day.month;
    for (final uid in uids) {
      if (thisMonth) inMonth[uid] = (inMonth[uid] ?? 0) + 1;
      if (onDay) (sameDay[uid] ??= []).add((name: nameOf(r), duties: r.dutiesOf(uid: uid)));
    }
  }
  return {
    for (final uid in {...inMonth.keys, ...sameDay.keys})
      uid: ServingAround(inMonth: inMonth[uid] ?? 0, sameDay: sameDay[uid] ?? const []),
  };
}
