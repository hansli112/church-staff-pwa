import 'day.dart';
import 'models.dart';
import 'schedule.dart';

/// 安排服事 (#90): one service's days, a month at a time, as a table of
/// the duties I arrange.

/// The columns: the duties of [service]'s template I arrange, then any
/// other I arrange that [days] have, in the order first seen.
List<String> planDuties(Service service, Iterable<Roster> days, Arranges arranges) => {
  for (final role in service.duties)
    if (arranges.has(role)) role,
  for (final day in days)
    for (final d in day.duties)
      if (arranges.has(d.role)) d.role,
}.toList();

/// The month of the first of [days] where a duty of [duties] has nobody
/// yet, as its first day; null when every one has someone.
Day? firstGap(Iterable<Roster> days, List<String> duties) {
  for (final day in days) {
    if (day.duties.any((d) => duties.contains(d.role) && d.people.isEmpty)) return Day(day.day.year, day.day.month, 1);
  }
  return null;
}

/// The first day of the month [months] after [month]'s.
Day addMonths(Day month, int months) => Day(month.year, month.month + months, 1);

/// [service]'s days in the [months] months from [month] (its first day),
/// from [today] on: every one on its weekday, saved or a draft, and any
/// other saved. Unlike the 服事表 tab (upcomingRosters), a day saved off
/// the weekday does not take its week's place: a table has a row for it.
/// Months with none are left out.
List<({Day month, List<Roster> days})> planMonths({
  required Service service,
  required Iterable<Roster> saved,
  required Day today,
  required Day month,
  required int months,
}) {
  final end = addMonths(month, months);
  final start = today.isAfter(month) ? today : month;
  final days = <Day, Roster>{
    for (final r in saved)
      if (r.type == service.id && !r.isEvent && !r.day.isBefore(start) && r.day.isBefore(end)) r.day: r,
  };
  if (service.enabled) {
    for (var d = start.nextOnOrAfter(service.weekday); d.isBefore(end); d = d.addDays(7)) {
      days.putIfAbsent(d, () => draftRoster(service, d));
    }
  }
  final byMonth = <Day, List<Roster>>{};
  for (final d in days.keys.toList()..sort()) {
    (byMonth[Day(d.year, d.month, 1)] ??= []).add(days[d]!);
  }
  return [for (final MapEntry(key: m, value: inMonth) in byMonth.entries) (month: m, days: inMonth)];
}
