import 'models.dart';

/// The changes an admin makes to a service's duties and 特別活動
/// (ServiceEdits), each as the service after it.
extension ServiceChanges on Service {
  /// With duty [name] last; as it is when it has it.
  Service withDuty(String name) => duties.contains(name) ? this : copyWith(duties: [...duties, name]);

  /// Without duty [name], nor its 多人服事. Arranged days and the 同工's
  /// lists keep it.
  Service withoutDuty(String name) => copyWith(
    duties: [
      for (final d in duties)
        if (d != name) d,
    ],
    manyDuties: manyDuties == null
        ? null
        : [
            for (final d in manyDuties!)
              if (d != name) d,
          ],
  );

  /// With duty [from] named [to] in its place, its 多人服事 with it
  /// (validDutyRename).
  Service withDutyRenamed(String from, String to) => copyWith(
    duties: [for (final d in duties) d == from ? to : d],
    manyDuties: manyDuties == null ? null : [for (final d in manyDuties!) d == from ? to : d],
  );

  /// With 多人服事 for duty [duty] on or off ([many]), set for every duty at
  /// once: the others as they stand ([now], RosterActions.manyDuties).
  Service withMany(String duty, bool many, {required List<String> now}) => copyWith(
    manyDuties: [
      for (final d in duties)
        if (d == duty ? many : now.contains(d)) d,
    ],
  );

  /// With 特別活動 [name] last, in the next of the six colors; as it is
  /// when it has one so named.
  Service withEvent(String name) => events.any((e) => e.name == name)
      ? this
      : copyWith(
          events: [
            ...events,
            EventTag(name: name, color: events.length % 6),
          ],
        );

  /// Without 特別活動 [name]; arranged days keep it.
  Service withoutEvent(String name) => copyWith(
    events: [
      for (final e in events)
        if (e.name != name) e,
    ],
  );

  /// With 特別活動 [from] named [to], its color and place kept.
  Service withEventRenamed(String from, String to) => copyWith(
    events: [for (final e in events) e.name == from ? EventTag(name: to, color: e.color) : e],
  );

  /// With 特別活動 [name] in [color].
  Service withEventColor(String name, int color) => copyWith(
    events: [for (final e in events) e.name == name ? EventTag(name: e.name, color: color) : e],
  );
}

/// Whether [service] may be saved as it is (testdata/church_rules.json,
/// serviceShape; functions/src/serviceSettings.ts validServiceShape): no
/// duty or 特別活動 name twice, each 特別活動 in one of the six colors, and
/// 多人服事 only of its duties, each once.
bool validServiceShape(Service service) {
  final duties = service.duties;
  final names = [for (final e in service.events) e.name];
  final many = service.manyDuties;
  return duties.toSet().length == duties.length &&
      names.toSet().length == names.length &&
      service.events.every((e) => e.color >= 0 && e.color <= 5) &&
      (many == null || (many.toSet().length == many.length && many.every(duties.contains)));
}
