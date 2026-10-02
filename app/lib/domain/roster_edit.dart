import 'models.dart';
import 'staff_order.dart';

/// Name → uid for members whose name is unique in the church.
///
/// Two members with the same name get no uid: picking one would be a guess,
/// and a wrong guess sends the reminder to the other person with no sign
/// anything is off. Without a uid, "my services" falls back to the name and
/// both see it (from self-host StaffDirectory).
Map<String, String> uniqueNameIds(Iterable<Member> members) {
  final ids = <String, String>{};
  final duplicates = <String>{};
  for (final m in members) {
    final name = m.name.trim();
    if (name.isEmpty) continue;
    if (ids.containsKey(name)) duplicates.add(name);
    ids[name] = m.uid;
  }
  return {
    for (final e in ids.entries)
      if (!duplicates.contains(e.key)) e.key: e.value,
  };
}

/// [roster] with [role]'s people set to [people], sorted by [order], with
/// uids for the names that are members. Adds the duty if it is missing.
Roster withPeople(
  Roster roster,
  String role,
  List<String> people, {
  required Map<String, String> nameIds,
  required StaffOrder order,
}) {
  final cleaned = <String>[];
  for (final p in people) {
    final name = p.trim();
    if (name.isNotEmpty && !cleaned.contains(name)) cleaned.add(name);
  }
  final sorted = order.sort(role, cleaned);
  final duty = Duty(
    role: role,
    people: sorted,
    uids: {
      for (final name in sorted) name: ?nameIds[name],
    },
  );
  final exists = roster.duties.any((d) => d.role == role);
  return roster.copyWith(
    duties: exists ? [for (final d in roster.duties) d.role == role ? duty : d] : [...roster.duties, duty],
  );
}

Roster withoutDuty(Roster roster, String role) => roster.copyWith(
  duties: [
    for (final d in roster.duties)
      if (d.role != role) d,
  ],
);

/// The person in one duty on one day, a side of a swap.
class SwapSide {
  const SwapSide(this.roster, this.person);

  final Roster roster;

  /// Null for a day where nobody has the duty yet: the other person moves
  /// there.
  final String? person;
}

/// Swaps [a] and [b] in [role]. Both days are returned and must be written
/// together. People are re-sorted by [order], so the main person stays
/// first wherever they land (self-host swapped in place, which left them
/// second).
(Roster, Roster) swapPeople(
  String role,
  SwapSide a,
  SwapSide b, {
  required Map<String, String> nameIds,
  required StaffOrder order,
}) {
  List<String> replaced(Roster r, String? out, String? into) {
    final people = [
      for (final d in r.duties)
        if (d.role == role) ...d.people,
    ];
    final next = [
      for (final p in people)
        if (p != out) p,
    ];
    if (into != null && !next.contains(into)) next.add(into);
    return next;
  }

  final aNext = withPeople(
    a.roster,
    role,
    replaced(a.roster, a.person, b.person),
    nameIds: nameIds,
    order: order,
  );
  final bNext = withPeople(
    b.roster,
    role,
    replaced(b.roster, b.person, a.person),
    nameIds: nameIds,
    order: order,
  );
  return (aNext, bNext);
}

/// Swap targets for [person] in [role] on [from]: every other day's people
/// in that duty, plus days where the duty is empty. People already serving
/// [role] on [from] are left out (swapping with them changes nothing).
List<SwapSide> swapTargets(
  Iterable<Roster> days,
  Roster from,
  String role,
  String person,
) {
  final here = {
    for (final d in from.duties)
      if (d.role == role) ...d.people,
  };
  final result = <SwapSide>[];
  for (final r in days) {
    if (r.day == from.day) continue;
    final duty = r.duties.where((d) => d.role == role).firstOrNull;
    if (duty == null) continue;
    final others = [
      for (final p in duty.people)
        if (p != person && !here.contains(p)) p,
    ];
    if (duty.people.contains(person)) continue;
    if (duty.people.isEmpty) {
      result.add(SwapSide(r, null));
    } else {
      for (final p in others) {
        result.add(SwapSide(r, p));
      }
    }
  }
  return result;
}
