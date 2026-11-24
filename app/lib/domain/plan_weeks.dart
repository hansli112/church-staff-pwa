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

/// The first day of the month [months] after [month]'s.
Day addMonths(Day month, int months) => Day(month.year, month.month + months, 1);

/// [service]'s days in the [months] months from [month] (its first day),
/// from [today] on: every one on its weekdays, saved or a draft, and any
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
  for (final w in service.weekdays) {
    for (var d = start.nextOnOrAfter(w); d.isBefore(end); d = d.addDays(7)) {
      days.putIfAbsent(d, () => draftRoster(service, d));
    }
  }
  final byMonth = <Day, List<Roster>>{};
  for (final d in days.keys.toList()..sort()) {
    (byMonth[Day(d.year, d.month, 1)] ??= []).add(days[d]!);
  }
  return [for (final MapEntry(key: m, value: inMonth) in byMonth.entries) (month: m, days: inMonth)];
}

/// Whether [days], a month of a service, is 已排好 for who arranges
/// [arranges]: it has a day, and every duty of each day they arrange has
/// someone. A duty taken off a day (這一天沒有這項服事) is not on it.
bool monthArranged(Iterable<Roster> days, Arranges arranges) {
  var any = false;
  for (final day in days) {
    // 沒有聚會: nobody to arrange.
    if (day.noService) continue;
    for (final d in day.duties) {
      if (!arranges.has(d.role)) continue;
      if (d.people.isEmpty) return false;
      any = true;
    }
  }
  return any;
}
