import 'day.dart';
import 'models.dart';

/// The rosters of [service] from [from] for [weeks] weeks, oldest first.
///
/// Roster documents are only written when someone edits a day. Every other
/// day shows a draft built from the service template on each of the
/// service's weekdays (on its weeks: Service.meetsOn), so nothing has to be pre-generated (self-host
/// backfilled a quarter of documents from the editor's device, which needed
/// a transaction over every day of each week to avoid duplicates).
///
/// A day saved on one of its weekdays takes that day's place. One saved
/// off it takes its week's place too when the service meets on one day
/// (it has since moved to another weekday); one on several has each of
/// them still, as 安排服事 does (planMonths), a day dropped keeping only
/// what was saved on it.
List<Roster> upcomingRosters({
  required Service service,
  required Iterable<Roster> saved,
  required Day from,
  int weeks = 13,
}) {
  final result = <Roster>[
    for (final roster in saved)
      if (roster.type == service.id && !roster.day.isBefore(from)) roster,
  ];
  final byWeek = <Day, List<Day>>{};
  for (final r in result) {
    (byWeek[r.day.weekStart] ??= []).add(r.day);
  }
  for (var week = 0; week < weeks; week++) {
    final start = from.weekStart.addDays(week * 7);
    final taken = byWeek[start] ?? const <Day>[];
    final free = [
      for (final w in service.weekdays)
        if (start.nextOnOrAfter(w) case final day when !taken.contains(day) && service.meetsOn(day)) day,
    ];
    if (service.weekdays.length == 1 && taken.isNotEmpty) free.clear();
    result.addAll([
      for (final day in free)
        if (!day.isBefore(from)) draftRoster(service, day),
    ]);
  }
  result.sort((a, b) => a.day.compareTo(b.day));
  return result;
}

/// [roster]'s duties in its service's order, [template]: the order of the
/// 服事項目 is the roster's. A saved day keeps the order it was saved in, and
/// one added to it later comes last, so without this a reordered template
/// would not reach it. Duties the service no longer has follow, as saved.
List<Duty> dutiesInOrder(Roster roster, List<String> template) {
  int rank(Duty d) {
    final i = template.indexOf(d.role);
    return i < 0 ? template.length : i;
  }

  final indexed = roster.duties.indexed.toList()
    ..sort((a, b) {
      final byTemplate = rank(a.$2).compareTo(rank(b.$2));
      return byTemplate != 0 ? byTemplate : a.$1.compareTo(b.$1);
    });
  return [for (final (_, d) in indexed) d];
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

/// The days explicitly assigned to [uid], with their duties. Names are
/// display text only: unbound guest names never identify a member.
List<MyService> myServices(Iterable<Roster> rosters, {required String uid}) => [
  for (final roster in rosters)
    if (roster.dutiesOf(uid: uid) case final duties when duties.isNotEmpty) MyService(roster, duties),
];
